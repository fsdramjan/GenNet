package com.apptrack.app

import android.util.Log
import java.io.File
import java.io.RandomAccessFile
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong

/**
 * Tails the local SOCKS5 server's own debug log to capture destination
 * IPs for the traffic screen. HEV (hev-socks5-tunnel) has been removed
 * entirely -- see TcpIpRelay.kt -- so there is no more native tunnel
 * stats call here.
 *
 *   [2026-08-31 13:10:11] [I] ... socks5 server tcp [1.1.1.1]:443
 *
 * This runs in the MAIN process and reads that log file directly off
 * disk (cacheDir is shared across the app's processes), so there is no
 * cross-process JNI/singleton issue -- just plain file tailing.
 */
object FlowCollector {

    private const val TAG = "AppTrackFlow"
    private const val PERIOD_MS = 500L

    // Matches: socks5 server tcp [1.1.1.1]:443   (also matches udp)
    private val CONNECT_REGEX =
        Regex("""socks5 server (tcp|udp) \[([^\]]+)\]:(\d+)""")

    private val running = AtomicBoolean(false)
    private var executor: ScheduledExecutorService? = null

    @Volatile
    private var socks5LogFile: File? = null

    @Volatile
    private var monitoredUid: Int = -1

    private val lastReadPosition = AtomicLong(0L)

    /**
     * @param socks5LogFilePath absolute path to hev-socks5-server-debug.log
     *   (the SAME path passed in the SOCKS5 config's `log-file` field).
     * @param monitoredUid the UID of the single monitored app, or -1 if
     *   multiple apps are selected (can't attribute per-flow in that case).
     */
    fun start(socks5LogFilePath: String, monitoredUid: Int = -1) {
        if (!running.compareAndSet(false, true)) {
            Log.i(TAG, "Flow collector already running")
            return
        }

        socks5LogFile = File(socks5LogFilePath)
        this.monitoredUid = monitoredUid

        // Skip any pre-existing content (from earlier sessions) so we
        // only parse genuinely NEW connections from this session.
        val startPosition = socks5LogFile?.takeIf { it.exists() }?.length() ?: 0L
        lastReadPosition.set(startPosition)

        Log.i(TAG, "========== FLOW COLLECTOR START ==========")
        Log.i(TAG, "Tailing SOCKS5 log: $socks5LogFilePath (starting at byte $startPosition, uid=$monitoredUid)")

        val service = Executors.newSingleThreadScheduledExecutor { runnable ->
            Thread(runnable, "AppTrack-FlowPoller").apply { isDaemon = true }
        }
        executor = service

        service.scheduleWithFixedDelay(
            { pollOnce() },
            0L,
            PERIOD_MS,
            TimeUnit.MILLISECONDS
        )
    }

    fun stop() {
        if (!running.compareAndSet(true, false)) {
            return
        }

        Log.i(TAG, "========== FLOW COLLECTOR STOP ==========")

        executor?.shutdownNow()
        executor = null
        socks5LogFile = null
        monitoredUid = -1
        lastReadPosition.set(0L)
    }

    private fun pollOnce() {
        if (!running.get()) return

        try {
            tailSocks5Log()

        } catch (t: Throwable) {
            Log.e(TAG, "Flow polling failed", t)
        }
    }

    private fun tailSocks5Log() {
        val file = socks5LogFile ?: return
        if (!file.exists()) return

        try {
            RandomAccessFile(file, "r").use { raf ->
                val length = raf.length()
                var pos = lastReadPosition.get()

                // Log file got rotated/recreated (new VPN session) -> restart.
                if (pos > length) pos = 0L

                if (pos == length) return

                raf.seek(pos)

                var newCount = 0

                while (true) {
                    val line = raf.readLine() ?: break
                    newCount++

                    val match = CONNECT_REGEX.find(line) ?: continue
                    val (proto, ip, portStr) = match.destructured
                    val port = portStr.toIntOrNull() ?: 0
                    val ipVersion = if (ip.contains(":")) 6 else 4

                    FlowStore.add(
                        destinationIp = ip,
                        destinationPort = port,
                        protocol = proto.uppercase(),
                        bytes = 1,
                        ipVersion = ipVersion,
                        uid = monitoredUid
                    )
                }

                lastReadPosition.set(raf.filePointer)

                if (newCount > 0) {
                    Log.i(
                        TAG,
                        "Parsed $newCount new SOCKS5 log line(s), " +
                            "FlowStore size=${FlowStore.size()}"
                    )
                }
            }
        } catch (t: Throwable) {
            Log.e(TAG, "Failed to tail SOCKS5 log", t)
        }
    }
}