package com.apptrack.app

import android.content.Context
import android.net.ConnectivityManager
import android.net.LinkProperties
import android.net.wifi.WifiInfo
import android.net.wifi.WifiManager
import android.os.Build
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.BufferedReader
import java.io.InputStreamReader
import java.util.concurrent.TimeUnit
import android.net.TrafficStats

class NetworkChannel : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var appContext: Context
    private val scope = CoroutineScope(Dispatchers.Main)

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "genhr.network/native")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getWifiInfo" -> result.success(getWifiInfoMap())
            "pingHost" -> {
                val host = call.argument<String>("host") ?: ""
                val timeoutSec = call.argument<Int>("timeoutSeconds") ?: 2
                scope.launch {
                    val res = withContext(Dispatchers.IO) { pingHost(host, timeoutSec) }
                    result.success(res)
                }
            }
            "getTrafficStats" -> {
    result.success(getTrafficStatsMap())
}
            else -> result.notImplemented()
        }
    }

    // ── WiFi + link info (no location perm needed for IP/gateway/DNS) ──
    private fun getWifiInfoMap(): Map<String, Any?> {
        val wifiManager = appContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        val connectivityManager =
            appContext.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager

        val wifiInfo: WifiInfo? = try { wifiManager.connectionInfo } catch (e: Exception) { null }
        val activeNetwork = connectivityManager.activeNetwork
        val linkProperties: LinkProperties? =
            activeNetwork?.let { connectivityManager.getLinkProperties(it) }

        var ipAddress: String? = null
        var subnetMask: String? = null
        linkProperties?.linkAddresses?.forEach { la ->
            val addr = la.address
            if (!addr.isLoopbackAddress && addr.hostAddress?.contains(":") == false) {
                ipAddress = addr.hostAddress
                subnetMask = prefixToMask(la.prefixLength)
            }
        }

        var gatewayIp: String? = null
        linkProperties?.routes?.forEach { r -> if (r.isDefaultRoute) gatewayIp = r.gateway?.hostAddress }

        val dnsServers = linkProperties?.dnsServers?.mapNotNull { it.hostAddress } ?: emptyList()

        // SSID / BSSID / RSSI / speed / frequency — needs location permission on API 27+
        var ssid: String? = null
        var bssid: String? = null
        var rssiDbm: Int? = null
        var linkSpeedMbps: Int? = null
        var frequencyMhz: Int? = null
        var wifiStandard: Int? = null
        var channelWidthMhz: Int? = null

        if (wifiInfo != null) {
            val rawSsid = wifiInfo.ssid?.replace("\"", "")
            ssid = if (rawSsid.isNullOrEmpty() || rawSsid == "<unknown ssid>") null else rawSsid
            bssid = if (wifiInfo.bssid == "02:00:00:00:00:00") null else wifiInfo.bssid
            rssiDbm = wifiInfo.rssi
            linkSpeedMbps = wifiInfo.linkSpeed
            frequencyMhz = wifiInfo.frequency
           if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
    wifiStandard = try {
        val method = WifiInfo::class.java.getMethod("getWifiStandard")
        method.invoke(wifiInfo) as? Int
    } catch (e: Exception) {
        null
    }
}
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
    channelWidthMhz = try {
        val method = WifiInfo::class.java.getMethod("getChannelWidth")
        when (method.invoke(wifiInfo) as? Int) {
            0 -> 20; 1 -> 40; 2 -> 80; 3 -> 160; 4 -> 80; else -> null
        }
    } catch (e: Exception) {
        null
    }
}
        }

        var dhcpLeaseSeconds: Int? = null
        try {
            @Suppress("DEPRECATION")
            val dhcp = wifiManager.dhcpInfo
            dhcpLeaseSeconds = dhcp?.leaseDuration
            if (gatewayIp == null && dhcp != null) gatewayIp = intToIp(dhcp.gateway)
        } catch (e: Exception) { /* ignore */ }

        val channel = frequencyMhz?.let { freqToChannel(it) }
        val band = frequencyMhz?.let {
            when {
                it in 2400..2500 -> "2.4 GHz"
                it in 4900..5900 -> "5 GHz"
                it in 5925..7125 -> "6 GHz"
                else -> null
            }
        }

        return mapOf(
            "ssid" to ssid, "bssid" to bssid, "ipAddress" to ipAddress,
            "subnetMask" to subnetMask, "gatewayIp" to gatewayIp, "dnsServers" to dnsServers,
            "rssiDbm" to rssiDbm, "linkSpeedMbps" to linkSpeedMbps, "frequencyMhz" to frequencyMhz,
            "channel" to channel, "band" to band, "channelWidthMhz" to channelWidthMhz,
            "wifiStandard" to wifiStandard, "dhcpLeaseSeconds" to dhcpLeaseSeconds
        )
    }

    private fun prefixToMask(prefixLength: Int): String {
        val mask = IntArray(4)
        var remaining = prefixLength
        for (i in 0 until 4) {
            val bits = minOf(8, maxOf(0, remaining))
            mask[i] = (0xFF shl (8 - bits)) and 0xFF
            remaining -= bits
        }
        return mask.joinToString(".")
    }

    private fun intToIp(addr: Int): String = String.format(
        "%d.%d.%d.%d", addr and 0xFF, addr shr 8 and 0xFF, addr shr 16 and 0xFF, addr shr 24 and 0xFF
    )

    private fun freqToChannel(freqMhz: Int): Int = when {
        freqMhz in 2412..2484 -> if (freqMhz == 2484) 14 else (freqMhz - 2412) / 5 + 1
        freqMhz in 5000..5900 -> (freqMhz - 5000) / 5
        freqMhz in 5925..7125 -> (freqMhz - 5950) / 5 + 1
        else -> -1
    }

    // ── Real ICMP ping via system ping binary (no root, standard technique) ──
    private fun pingHost(host: String, timeoutSec: Int): Map<String, Any?> {
        return try {
            val process = ProcessBuilder("/system/bin/ping", "-c", "1", "-W", "$timeoutSec", host)
                .redirectErrorStream(true).start()
            val output = BufferedReader(InputStreamReader(process.inputStream)).readText()
            val finished = process.waitFor(timeoutSec + 1L, TimeUnit.SECONDS)
            if (!finished) process.destroy()

            val match = Regex("time[=<]([\\d.]+)").find(output)
            val exitOk = try { process.exitValue() == 0 } catch (e: Exception) { false }

            if (exitOk && match != null) {
                mapOf("success" to true, "rttMs" to match.groupValues[1].toDouble())
            } else {
                mapOf("success" to false, "rttMs" to null)
            }
        } catch (e: Exception) {
            mapOf("success" to false, "rttMs" to null, "error" to e.message)
        }
    }

    private fun getTrafficStatsMap(): Map<String, Any?> {
    val uid = appContext.applicationInfo.uid
    // App-specific bytes (শুধু এই অ্যাপের ট্রাফিক)
    val appRx = TrafficStats.getUidRxBytes(uid)
    val appTx = TrafficStats.getUidTxBytes(uid)

    // পুরো ডিভাইসের (সব অ্যাপ মিলিয়ে) মোট ট্রাফিক — এটাই আপনার দরকার
    val totalRx = TrafficStats.getTotalRxBytes()
    val totalTx = TrafficStats.getTotalTxBytes()

    // Mobile-only বাদ দিয়ে সব ইন্টারফেস (WiFi সহ) ধরা হচ্ছে totalRx/totalTx দিয়ে
    return mapOf(
        "totalRxBytes" to totalRx,
        "totalTxBytes" to totalTx,
        "appRxBytes" to appRx,
        "appTxBytes" to appTx,
        "timestampMs" to System.currentTimeMillis()
    )
}
}