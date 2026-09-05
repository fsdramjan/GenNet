package com.apptrack.app

object FlowStore {

    private const val MAX_FLOWS = 2000

    private val lock = Any()

    private val flows =
        LinkedHashMap<FlowKey, FlowData>()

    fun add(
        destinationIp: String,
        destinationPort: Int,
        protocol: String,
        bytes: Int,
        ipVersion: Int,
        uid: Int
    ) {

        if (destinationIp.isBlank()) {
            return
        }

        if (bytes <= 0) {
            return
        }

        val normalizedProtocol =
            protocol.uppercase()

        val key =
            FlowKey(
                destinationIp =
                    destinationIp,

                destinationPort =
                    destinationPort,

                protocol =
                    normalizedProtocol,

                ipVersion =
                    ipVersion,

                uid =
                    uid
            )

        synchronized(lock) {

            val existing =
                flows[key]

            if (existing != null) {

                existing.bytes +=
                    bytes.toLong()

                existing.packetCount++

                existing.lastSeen =
                    System.currentTimeMillis()

                return
            }

            if (
                flows.size >=
                MAX_FLOWS
            ) {
                removeOldest()
            }

            flows[key] =
                FlowData(
                    destinationIp =
                        destinationIp,

                    destinationPort =
                        destinationPort,

                    protocol =
                        normalizedProtocol,

                    bytes =
                        bytes.toLong(),

                    ipVersion =
                        ipVersion,

                    uid =
                        uid,

                    packetCount =
                        1L,

                    lastSeen =
                        System.currentTimeMillis()
                )
        }
    }

    fun replaceSnapshot(
        newFlows: List<Map<String, Any>>
    ) {
        synchronized(lock) {
            flows.clear()

            val now = System.currentTimeMillis()

            for (raw in newFlows) {
                val ip = raw["destinationIp"]?.toString()?.trim().orEmpty()
                if (ip.isBlank()) continue

                val port = when (val v = raw["destinationPort"]) {
                    is Number -> v.toInt()
                    else -> v?.toString()?.toIntOrNull() ?: 0
                }

                val protocol = raw["protocol"]?.toString()?.uppercase() ?: "IP"
                val bytes = when (val v = raw["bytes"]) {
                    is Number -> v.toLong()
                    else -> v?.toString()?.toLongOrNull() ?: 0L
                }.coerceAtLeast(0L)

                val ipVersion = when (val v = raw["ipVersion"]) {
                    is Number -> v.toInt()
                    else -> v?.toString()?.toIntOrNull() ?: 4
                }

                val uid = when (val v = raw["uid"]) {
                    is Number -> v.toInt()
                    else -> v?.toString()?.toIntOrNull() ?: -1
                }

                val packetCount = when (val v = raw["packetCount"]) {
                    is Number -> v.toLong()
                    else -> v?.toString()?.toLongOrNull() ?: 0L
                }

                val key = FlowKey(ip, port, protocol, ipVersion, uid)
                flows[key] = FlowData(
                    destinationIp = ip,
                    destinationPort = port,
                    protocol = protocol,
                    bytes = bytes,
                    ipVersion = ipVersion,
                    uid = uid,
                    packetCount = packetCount,
                    lastSeen = now
                )

                if (flows.size >= MAX_FLOWS) break
            }
        }
    }

    fun snapshot():
        List<Map<String, Any>> {

        synchronized(lock) {

            return flows.values
                .sortedByDescending {
                    it.lastSeen
                }
                .map { flow ->

                    mapOf(
                        "destinationIp"
                            to flow.destinationIp,

                        "destinationPort"
                            to flow.destinationPort,

                        "protocol"
                            to flow.protocol,

                        "bytes"
                            to clampToInt(
                                flow.bytes
                            ),

                        "ipVersion"
                            to flow.ipVersion,

                        "uid"
                            to flow.uid,

                        "packetCount"
                            to flow.packetCount
                    )
                }
        }
    }

    fun uniqueDestinationIps():
        List<String> {

        synchronized(lock) {

            return flows.values
                .asSequence()
                .map {
                    it.destinationIp
                }
                .filter {
                    it.isNotBlank()
                }
                .distinct()
                .sorted()
                .toList()
        }
    }

    fun uniqueDestinationEndpoints():
        List<String> {

        synchronized(lock) {

            return flows.values
                .asSequence()
                .map { flow ->

                    if (
                        flow.destinationPort > 0
                    ) {

                        "${flow.destinationIp}:${flow.destinationPort}"

                    } else {

                        flow.destinationIp
                    }
                }
                .filter {
                    it.isNotBlank()
                }
                .distinct()
                .sorted()
                .toList()
        }
    }

    fun totalBytes(): Long {

        synchronized(lock) {

            return flows.values.sumOf {
                it.bytes
            }
        }
    }

    fun size(): Int {

        synchronized(lock) {
            return flows.size
        }
    }

    fun clear() {

        synchronized(lock) {
            flows.clear()
        }
    }

    private fun removeOldest() {

        val oldest =
            flows.entries
                .minByOrNull {
                    it.value.lastSeen
                }

        if (oldest != null) {

            flows.remove(
                oldest.key
            )
        }
    }

    private fun clampToInt(
        value: Long
    ): Int {

        return when {

            value <= 0L ->
                0

            value >=
                Int.MAX_VALUE.toLong() ->
                Int.MAX_VALUE

            else ->
                value.toInt()
        }
    }

    private data class FlowKey(
        val destinationIp: String,
        val destinationPort: Int,
        val protocol: String,
        val ipVersion: Int,
        val uid: Int
    )

    private data class FlowData(
        val destinationIp: String,
        val destinationPort: Int,
        val protocol: String,
        var bytes: Long,
        val ipVersion: Int,
        val uid: Int,
        var packetCount: Long,
        var lastSeen: Long
    )
}