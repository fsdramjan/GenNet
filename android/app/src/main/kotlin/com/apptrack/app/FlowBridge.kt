package com.apptrack.app

object FlowBridge {

    @JvmStatic
    fun onFlow(
        destinationIp: String,
        destinationPort: Int,
        protocol: String,
        bytes: Int,
        ipVersion: Int
    ) {

        if (destinationIp.isBlank()) {
            return
        }

        if (bytes <= 0) {
            return
        }

        FlowStore.add(
            destinationIp = destinationIp,
            destinationPort = destinationPort,
            protocol = protocol,
            bytes = bytes,
            ipVersion = ipVersion,
            uid = -1
        )
    }
}