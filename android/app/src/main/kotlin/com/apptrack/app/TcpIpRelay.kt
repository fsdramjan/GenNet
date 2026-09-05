package com.apptrack.app

import android.os.Build
import android.util.Log
import java.io.IOException
import java.net.InetAddress
import java.net.Socket
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import kotlin.random.Random

/**
 * Minimal userspace TCP/IP relay.
 *
 * WHY THIS EXISTS:
 *
 * hev-socks5-tunnel (the native tun2socks library) proved to never
 * actually process packets on this device, regardless of what fd it's
 * given (confirmed: our own relay successfully delivers packets to it
 * via a plain local socket, yet its internal stats stay at zero
 * forever). Rather than debug a closed, prebuilt native library further,
 * this replaces JUST that piece with a plain-Kotlin implementation.
 *
 * The local SOCKS5 server (hev-socks5-server, in Socks5ProcessService)
 * is NOT replaced -- it's proven to work correctly (self-tests always
 * passed, real CONNECT handshakes succeeded). This class's only job is:
 * parse raw IP packets read from the TUN, and for each new TCP
 * connection, open a socket to the local SOCKS5 server and relay bytes
 * both ways -- translating between "raw TCP segments on the wire" and
 * "a normal two-way byte stream" ourselves, by hand.
 *
 * V1 SCOPE:
 *  - TCP: yes (covers the vast majority of app/web traffic)
 *  - DNS (UDP port 53): yes, resolved directly via our own process's
 *    DNS resolver (this app is excluded from the VPN, so it already
 *    has normal internet access) and answered locally -- no real UDP
 *    relay needed for this common case.
 *  - Other UDP (QUIC/HTTP3, some video calls): NOT yet implemented.
 *  - No retransmission / congestion control -- fine on decent Wi-Fi,
 *    may stall some connections on lossy networks.
 */
object TcpIpRelay {

    private const val TAG = "AppTrackRelay"

    private const val SOCKS5_HOST = "127.0.0.1"
    private const val SOCKS5_PORT = 1080

    // Must match AppTrackVpnService's Builder.setMtu() value.
    private const val MTU = 10000

    // TCP flags
    private const val FIN = 0x01
    private const val SYN = 0x02
    private const val RST = 0x04
    private const val PSH = 0x08
    private const val ACK = 0x10

    private val executor =
        Executors.newCachedThreadPool { r ->
            Thread(r, "AppTrack-TcpConn").apply { isDaemon = true }
        }

    /** Callback the owner (AppTrackVpnService) provides to write a raw
     *  IP packet back out to the real TUN device. */
    @Volatile
    var writeToTun: ((ByteArray, Int) -> Unit)? = null

    private data class ConnKey(
        val srcIp: String,
        val srcPort: Int,
        val dstIp: String,
        val dstPort: Int
    )

    private enum class TcpState {
        SYN_RECEIVED, ESTABLISHED, CLOSING, CLOSED
    }

    private class Tcb(
        val key: ConnKey
    ) {
        @Volatile var state = TcpState.SYN_RECEIVED
        @Volatile var socket: Socket? = null

        // Sequence number WE use when sending TO the app.
        @Volatile var mySeq: Long = 0L
        // Next sequence number WE expect FROM the app (i.e. our ack value).
        @Volatile var theirNextSeq: Long = 0L

        @Volatile var closing = false
    }

    private val connections =
        ConcurrentHashMap<ConnKey, Tcb>()

    fun reset() {
        for (tcb in connections.values) {
            try { tcb.socket?.close() } catch (_: Throwable) {}
        }
        connections.clear()
    }

    // ================================================================
    // ENTRY POINT: one raw IP packet read from the TUN
    // ================================================================

    fun handlePacket(
        buf: ByteArray,
        len: Int,
        cm: android.net.ConnectivityManager?
    ) {

        try {

            if (len < 20) return

            val version = (buf[0].toInt() shr 4) and 0xF
            if (version != 4) return // IPv6 not handled in v1

            val ihl = (buf[0].toInt() and 0xF) * 4
            if (ihl < 20 || len < ihl) return

            val protocol = buf[9].toInt() and 0xFF
            val srcIp = ipToString(buf, 12)
            val dstIp = ipToString(buf, 16)

            when (protocol) {
                6 -> handleTcp(buf, len, ihl, srcIp, dstIp, cm)
                17 -> handleUdp(buf, len, ihl, srcIp, dstIp)
                else -> { /* ignore ICMP etc in v1 */ }
            }

        } catch (e: Throwable) {
            Log.e(TAG, "handlePacket failed", e)
        }
    }

    // ================================================================
    // UDP (only DNS is actually answered in v1)
    // ================================================================

    private fun handleUdp(
        buf: ByteArray, len: Int, ihl: Int, srcIp: String, dstIp: String
    ) {
        if (len < ihl + 8) return

        val srcPort = readU16(buf, ihl)
        val dstPort = readU16(buf, ihl + 2)
        val udpLen = readU16(buf, ihl + 4)
        val payloadOff = ihl + 8
        val payloadLen = (udpLen - 8).coerceAtMost(len - payloadOff)

        if (dstPort != 53 || payloadLen <= 0) return // only DNS handled

        executor.execute {
            try {
                val response = resolveDns(buf, payloadOff, payloadLen)
                if (response != null) {
                    sendUdpReply(
                        srcIp, srcPort, dstIp, dstPort, response
                    )
                }
            } catch (e: Throwable) {
                Log.w(TAG, "DNS resolve failed", e)
            }
        }
    }

    /**
     * Extremely small DNS responder: parses just enough of the query to
     * get the hostname + query type, resolves it using this process's
     * own (non-VPN) network access, and builds a minimal A/AAAA answer.
     * Falls back to returning null (no answer) on anything it can't
     * confidently parse -- the app will just retry or fail that lookup,
     * same as a dropped UDP packet would.
     */
    private fun resolveDns(buf: ByteArray, off: Int, len: Int): ByteArray? {

        if (len < 12) return null

        val id0 = buf[off]
        val id1 = buf[off + 1]
        val flagsQr = buf[off + 2].toInt() and 0xFF
        if ((flagsQr and 0x80) != 0) return null // not a query

        val qdCount = readU16(buf, off + 4)
        if (qdCount != 1) return null // only handle the common single-question case

        var pos = off + 12
        val nameStart = pos
        val nameBuilder = StringBuilder()

        while (pos < off + len) {
            val labelLen = buf[pos].toInt() and 0xFF
            if (labelLen == 0) { pos++; break }
            pos++
            if (pos + labelLen > off + len) return null
            if (nameBuilder.isNotEmpty()) nameBuilder.append('.')
            nameBuilder.append(String(buf, pos, labelLen, Charsets.US_ASCII))
            pos += labelLen
        }

        if (pos + 4 > off + len) return null
        val qtype = readU16(buf, pos)
        val qclass = readU16(buf, pos + 2)
        val questionEnd = pos + 4

        if (qclass != 1) return null // only IN class
        if (qtype != 1 && qtype != 28) return null // only A / AAAA

        val hostname = nameBuilder.toString()
        if (hostname.isBlank()) return null

        val addresses = try {
            InetAddress.getAllByName(hostname)
        } catch (e: Throwable) {
            null
        } ?: return buildDnsResponse(buf, off, nameStart, questionEnd - nameStart, id0, id1, qtype, emptyList())

        val matching = addresses.filter {
            (qtype == 1 && it.address.size == 4) ||
                (qtype == 28 && it.address.size == 16)
        }

        return buildDnsResponse(
            buf, off, nameStart, questionEnd - nameStart, id0, id1, qtype, matching
        )
    }

    private fun buildDnsResponse(
        query: ByteArray,
        queryOff: Int,
        nameStart: Int,
        questionLen: Int,
        id0: Byte,
        id1: Byte,
        qtype: Int,
        answers: List<InetAddress>
    ): ByteArray {

        val out = java.io.ByteArrayOutputStream()

        out.write(id0.toInt()); out.write(id1.toInt())
        out.write(0x81); out.write(0x80) // standard response, recursion available
        out.write(0x00); out.write(0x01) // QDCOUNT=1
        val ancount = answers.size
        out.write((ancount shr 8) and 0xFF); out.write(ancount and 0xFF)
        out.write(0x00); out.write(0x00) // NSCOUNT
        out.write(0x00); out.write(0x00) // ARCOUNT

        // Echo back the original question section verbatim.
        out.write(query, nameStart, questionLen)

        for (addr in answers) {
            // Name: pointer back to the question's name (offset 12 in the message).
            out.write(0xC0); out.write(0x0C)
            out.write(0x00); out.write(qtype)
            out.write(0x00); out.write(0x01) // IN
            out.write(0x00); out.write(0x00); out.write(0x00); out.write(0x3C) // TTL=60
            val addrBytes = addr.address
            out.write((addrBytes.size shr 8) and 0xFF); out.write(addrBytes.size and 0xFF)
            out.write(addrBytes)
        }

        return out.toByteArray()
    }

    private fun sendUdpReply(
        srcIp: String, srcPort: Int,
        dstIp: String, dstPort: Int,
        payload: ByteArray
    ) {
        // Note: "srcIp/srcPort" here are the ORIGINAL query's source
        // (the app) -- our reply must come FROM dstIp:dstPort (the
        // resolver the app asked) and go TO srcIp:srcPort.
        val packet = buildUdpPacket(
            fromIp = dstIp, fromPort = dstPort,
            toIp = srcIp, toPort = srcPort,
            payload = payload
        )
        writeToTun?.invoke(packet, packet.size)
    }

    private fun buildUdpPacket(
        fromIp: String, fromPort: Int,
        toIp: String, toPort: Int,
        payload: ByteArray
    ): ByteArray {

        val udpLen = 8 + payload.size
        val totalLen = 20 + udpLen
        val buf = ByteArray(totalLen)

        // IPv4 header
        buf[0] = 0x45
        buf[1] = 0
        writeU16(buf, 2, totalLen)
        writeU16(buf, 4, 0) // identification
        writeU16(buf, 6, 0) // flags/fragment
        buf[8] = 64 // TTL
        buf[9] = 17 // UDP
        writeU16(buf, 10, 0) // checksum placeholder
        writeIp(buf, 12, fromIp)
        writeIp(buf, 16, toIp)
        val ipChecksum = checksum(buf, 0, 20)
        writeU16(buf, 10, ipChecksum)

        // UDP header
        writeU16(buf, 20, fromPort)
        writeU16(buf, 22, toPort)
        writeU16(buf, 24, udpLen)
        writeU16(buf, 26, 0) // checksum (0 = not computed, valid for IPv4 UDP)

        System.arraycopy(payload, 0, buf, 28, payload.size)

        return buf
    }

    // ================================================================
    // TCP
    // ================================================================

    private fun handleTcp(
        buf: ByteArray, len: Int, ihl: Int, srcIp: String, dstIp: String,
        cm: android.net.ConnectivityManager?
    ) {
        if (len < ihl + 20) return

        val srcPort = readU16(buf, ihl)
        val dstPort = readU16(buf, ihl + 2)
        val seq = readU32(buf, ihl + 4)
        val ack = readU32(buf, ihl + 8)
        val dataOffset = ((buf[ihl + 12].toInt() shr 4) and 0xF) * 4
        val flags = buf[ihl + 13].toInt() and 0xFF
        val payloadOff = ihl + dataOffset
        val payloadLen = (len - payloadOff).coerceAtLeast(0)

        val key = ConnKey(srcIp, srcPort, dstIp, dstPort)

        if ((flags and SYN) != 0 && (flags and ACK) == 0) {
            openConnection(key, seq, cm)
            return
        }

        val tcb = connections[key] ?: run {
            // Unknown connection and not a SYN -- politely refuse.
            if ((flags and RST) == 0) {
                sendRst(key, ack)
            }
            return
        }

        if ((flags and RST) != 0) {
            closeConnection(tcb, alsoSendFin = false)
            return
        }

        if ((flags and FIN) != 0) {
            tcb.theirNextSeq = seq + 1
            sendAck(tcb)
            closeConnection(tcb, alsoSendFin = true)
            return
        }

        if (payloadLen > 0) {
            val socket = tcb.socket
            if (socket != null && tcb.state == TcpState.ESTABLISHED) {
                try {
                    socket.getOutputStream().write(buf, payloadOff, payloadLen)
                    tcb.theirNextSeq = seq + payloadLen
                    sendAck(tcb)
                } catch (e: IOException) {
                    closeConnection(tcb, alsoSendFin = true)
                }
            }
        }
    }

    /**
     * Resolves which app (UID) actually owns this TCP connection, using
     * Android's official per-app-VPN attribution API. Falls back to -1
     * (unknown) on older Android versions or if the lookup fails for
     * any reason -- capture still works, just without the app icon/name
     * for that entry.
     */
    private fun resolveOwnerUid(key: ConnKey, cm: android.net.ConnectivityManager?): Int {

        if (cm == null) {
            Log.w(TAG, "resolveOwnerUid: connectivityManager param is null")
            return -1
        }

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            Log.w(TAG, "resolveOwnerUid: SDK ${Build.VERSION.SDK_INT} < Q, unsupported")
            return -1
        }

        return try {

            val local =
                java.net.InetSocketAddress(key.srcIp, key.srcPort)

            val remote =
                java.net.InetSocketAddress(key.dstIp, key.dstPort)

            val uid =
                cm.getConnectionOwnerUid(
                    android.system.OsConstants.IPPROTO_TCP,
                    local,
                    remote
                )

            Log.i(TAG, "resolveOwnerUid: $key -> uid=$uid (INVALID_UID=${android.os.Process.INVALID_UID})")

            if (uid == android.os.Process.INVALID_UID) -1 else uid

        } catch (e: Throwable) {
            Log.w(TAG, "getConnectionOwnerUid failed for $key", e)
            -1
        }
    }

    private fun openConnection(
        key: ConnKey,
        clientIsn: Long,
        cm: android.net.ConnectivityManager?
    ) {

        if (connections.containsKey(key)) return

        val tcb = Tcb(key)
        tcb.theirNextSeq = clientIsn + 1
        tcb.mySeq = Random.nextLong(0, 0xFFFFFFFFL)
        connections[key] = tcb

        // Attribute this connection to the actual app that opened it,
        // and record it for the capture UI -- works correctly even with
        // multiple apps selected, since we resolve the REAL owner per
        // connection instead of assuming a single monitored app.
        val ownerUid = resolveOwnerUid(key, cm)

        FlowStore.add(
            destinationIp = key.dstIp,
            destinationPort = key.dstPort,
            protocol = "TCP",
            bytes = 1,
            ipVersion = 4,
            uid = ownerUid
        )

        executor.execute {
            try {

                val socket = Socket()
                socket.tcpNoDelay = true
                socket.receiveBufferSize = 65536
                socket.sendBufferSize = 65536
                socket.connect(
                    java.net.InetSocketAddress(SOCKS5_HOST, SOCKS5_PORT), 8000
                )
                socks5Connect(socket, key.dstIp, key.dstPort)

                tcb.socket = socket
                tcb.state = TcpState.ESTABLISHED

                // SYN-ACK to the app.
                sendSynAck(tcb)

                Log.i(TAG, "TCP open: ${key.srcIp}:${key.srcPort} -> ${key.dstIp}:${key.dstPort}")

                val input = socket.getInputStream()
                val buf = ByteArray(65536)

                // Must not exceed the TUN's MTU per packet -- IP(20) +
                // TCP(20) header overhead subtracted, with a small margin.
                val maxSegment = MTU - 64

                while (!tcb.closing) {
                    val n = try { input.read(buf) } catch (e: IOException) { -1 }
                    if (n <= 0) break

                    var offset = 0
                    while (offset < n) {
                        val chunk = minOf(maxSegment, n - offset)
                        sendData(tcb, buf, offset, chunk)
                        offset += chunk
                    }
                }

            } catch (e: Throwable) {
                Log.w(TAG, "TCP connect failed for $key", e)
                sendRst(key, tcb.theirNextSeq)
                connections.remove(key)
                return@execute
            }

            closeConnection(tcb, alsoSendFin = true)
        }
    }

    private fun socks5Connect(socket: Socket, destIp: String, destPort: Int) {
        val out = socket.getOutputStream()
        val input = socket.getInputStream()

        out.write(byteArrayOf(0x05, 0x01, 0x00))
        out.flush()
        val greet = ByteArray(2)
        if (input.read(greet) != 2 || greet[1] != 0x00.toByte()) {
            throw IOException("SOCKS5 greeting failed")
        }

        val destBytes = InetAddress.getByName(destIp).address
        val req = ByteArray(4 + destBytes.size + 2)
        req[0] = 0x05; req[1] = 0x01; req[2] = 0x00
        req[3] = if (destBytes.size == 4) 0x01 else 0x04
        System.arraycopy(destBytes, 0, req, 4, destBytes.size)
        req[req.size - 2] = ((destPort shr 8) and 0xFF).toByte()
        req[req.size - 1] = (destPort and 0xFF).toByte()
        out.write(req)
        out.flush()

        val resp = ByteArray(4)
        if (input.read(resp) != 4 || resp[1] != 0x00.toByte()) {
            throw IOException("SOCKS5 connect rejected: rep=${resp.getOrNull(1)}")
        }
        // Consume the rest of the bound address (variable length) before relaying.
        val addrType = resp[3].toInt() and 0xFF
        val skip = when (addrType) {
            1 -> 4
            4 -> 16
            3 -> (input.read().and(0xFF))
            else -> 0
        } + 2
        var remaining = skip
        val discard = ByteArray(32)
        while (remaining > 0) {
            val r = input.read(discard, 0, minOf(remaining, discard.size))
            if (r <= 0) break
            remaining -= r
        }
    }

    private fun closeConnection(tcb: Tcb, alsoSendFin: Boolean) {
        if (tcb.closing) return
        tcb.closing = true
        try { tcb.socket?.close() } catch (_: Throwable) {}
        if (alsoSendFin) {
            try { sendFin(tcb) } catch (_: Throwable) {}
        }
        connections.remove(tcb.key)
    }

    // ---- packet builders (TCP) ----

    private fun sendSynAck(tcb: Tcb) =
        sendTcpSegment(tcb, SYN or ACK, ByteArray(0), advanceMySeq = 1)

    private fun sendAck(tcb: Tcb) =
        sendTcpSegment(tcb, ACK, ByteArray(0), advanceMySeq = 0)

    private fun sendFin(tcb: Tcb) =
        sendTcpSegment(tcb, FIN or ACK, ByteArray(0), advanceMySeq = 1)

    private fun sendData(tcb: Tcb, data: ByteArray, offset: Int, len: Int) =
        sendTcpSegment(tcb, PSH or ACK, data.copyOfRange(offset, offset + len), advanceMySeq = len)

    private fun sendRst(key: ConnKey, seq: Long) {
        val buf = buildTcpPacket(
            fromIp = key.dstIp, fromPort = key.dstPort,
            toIp = key.srcIp, toPort = key.srcPort,
            seq = seq, ack = 0, flags = RST, payload = ByteArray(0)
        )
        writeToTun?.invoke(buf, buf.size)
    }

    private fun sendTcpSegment(
        tcb: Tcb, flags: Int, payload: ByteArray, advanceMySeq: Int
    ) {
        val buf = buildTcpPacket(
            fromIp = tcb.key.dstIp, fromPort = tcb.key.dstPort,
            toIp = tcb.key.srcIp, toPort = tcb.key.srcPort,
            seq = tcb.mySeq, ack = tcb.theirNextSeq,
            flags = flags, payload = payload
        )
        writeToTun?.invoke(buf, buf.size)
        tcb.mySeq += advanceMySeq
    }

    private fun buildTcpPacket(
        fromIp: String, fromPort: Int,
        toIp: String, toPort: Int,
        seq: Long, ack: Long,
        flags: Int, payload: ByteArray
    ): ByteArray {

        val tcpLen = 20 + payload.size
        val totalLen = 20 + tcpLen
        val buf = ByteArray(totalLen)

        // IPv4 header
        buf[0] = 0x45
        buf[1] = 0
        writeU16(buf, 2, totalLen)
        writeU16(buf, 4, 0)
        writeU16(buf, 6, 0x4000) // don't fragment
        buf[8] = 64
        buf[9] = 6 // TCP
        writeU16(buf, 10, 0)
        writeIp(buf, 12, fromIp)
        writeIp(buf, 16, toIp)
        writeU16(buf, 10, checksum(buf, 0, 20))

        // TCP header
        writeU16(buf, 20, fromPort)
        writeU16(buf, 22, toPort)
        writeU32(buf, 24, seq)
        writeU32(buf, 28, ack)
        buf[32] = (5 shl 4).toByte() // data offset = 5 (no options)
        buf[33] = flags.toByte()
        writeU16(buf, 34, 65535) // window
        writeU16(buf, 36, 0) // checksum placeholder
        writeU16(buf, 38, 0) // urgent pointer

        System.arraycopy(payload, 0, buf, 40, payload.size)

        val tcpChecksum = tcpChecksum(buf, fromIp, toIp, 20, tcpLen)
        writeU16(buf, 36, tcpChecksum)

        return buf
    }

    // ================================================================
    // Low-level helpers
    // ================================================================

    private fun ipToString(buf: ByteArray, off: Int): String {
        return "${buf[off].toInt() and 0xFF}.${buf[off + 1].toInt() and 0xFF}." +
            "${buf[off + 2].toInt() and 0xFF}.${buf[off + 3].toInt() and 0xFF}"
    }

    private fun writeIp(buf: ByteArray, off: Int, ip: String) {
        val parts = ip.split(".")
        for (i in 0 until 4) {
            buf[off + i] = (parts[i].toInt() and 0xFF).toByte()
        }
    }

    private fun readU16(buf: ByteArray, off: Int): Int =
        ((buf[off].toInt() and 0xFF) shl 8) or (buf[off + 1].toInt() and 0xFF)

    private fun writeU16(buf: ByteArray, off: Int, value: Int) {
        buf[off] = ((value shr 8) and 0xFF).toByte()
        buf[off + 1] = (value and 0xFF).toByte()
    }

    private fun readU32(buf: ByteArray, off: Int): Long {
        return ((buf[off].toLong() and 0xFF) shl 24) or
            ((buf[off + 1].toLong() and 0xFF) shl 16) or
            ((buf[off + 2].toLong() and 0xFF) shl 8) or
            (buf[off + 3].toLong() and 0xFF)
    }

    private fun writeU32(buf: ByteArray, off: Int, value: Long) {
        buf[off] = ((value shr 24) and 0xFF).toByte()
        buf[off + 1] = ((value shr 16) and 0xFF).toByte()
        buf[off + 2] = ((value shr 8) and 0xFF).toByte()
        buf[off + 3] = (value and 0xFF).toByte()
    }

    private fun checksum(buf: ByteArray, off: Int, len: Int): Int {
        var sum = 0L
        var i = off
        val end = off + len
        while (i + 1 < end) {
            sum += readU16(buf, i)
            i += 2
        }
        if (i < end) {
            sum += (buf[i].toInt() and 0xFF) shl 8
        }
        while (sum shr 16 != 0L) {
            sum = (sum and 0xFFFF) + (sum shr 16)
        }
        return (sum.inv() and 0xFFFF).toInt()
    }

    private fun tcpChecksum(
        buf: ByteArray, fromIp: String, toIp: String, tcpOff: Int, tcpLen: Int
    ): Int {
        // Pseudo-header + TCP segment, summed together.
        var sum = 0L

        val src = fromIp.split(".").map { it.toInt() and 0xFF }
        val dst = toIp.split(".").map { it.toInt() and 0xFF }

        sum += (src[0] shl 8) or src[1]
        sum += (src[2] shl 8) or src[3]
        sum += (dst[0] shl 8) or dst[1]
        sum += (dst[2] shl 8) or dst[3]
        sum += 6 // protocol = TCP
        sum += tcpLen

        var i = tcpOff
        val end = tcpOff + tcpLen
        while (i + 1 < end) {
            sum += readU16(buf, i)
            i += 2
        }
        if (i < end) {
            sum += (buf[i].toInt() and 0xFF) shl 8
        }

        while (sum shr 16 != 0L) {
            sum = (sum and 0xFFFF) + (sum shr 16)
        }

        return (sum.inv() and 0xFFFF).toInt()
    }
}