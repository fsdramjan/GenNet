package com.apptrack.app

import android.Manifest
import android.annotation.SuppressLint
import android.app.AppOpsManager
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.bluetooth.le.BluetoothLeScanner
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.location.LocationManager
import android.net.Uri
import android.net.VpnService
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.Settings
import android.telephony.*
import android.util.Log
import android.util.SparseArray
import android.widget.Toast
import androidx.appcompat.app.AlertDialog
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*
import java.io.BufferedReader
import java.io.File
import java.io.IOException
import java.io.InputStreamReader
import java.net.InetAddress
import java.net.Socket
import java.net.UnknownHostException
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.*
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.TimeUnit
import org.jsoup.Jsoup
import org.jsoup.nodes.Document

// ============================================================================
// AppTrack VPN/traffic-monitoring support classes.
// These live in their own package (com.apptrack.app) -- copy
// AppTrackVpnService.kt, TcpIpRelay.kt, Socks5ProcessService.kt,
// OverlayService.kt, FlowStore.kt and AppUsageStore.kt into
// android/app/src/main/kotlin/com/apptrack/app/ in THIS project
// (unchanged, keeping their own "package com.apptrack.app" line) so
// these imports resolve. See the checklist in the chat reply for the
// full list of files and the AndroidManifest.xml additions needed.
// ============================================================================
import com.apptrack.app.AppTrackVpnService
import com.apptrack.app.AppUsageStore
import com.apptrack.app.FlowStore
import com.apptrack.app.OverlayService

class MainActivity : FlutterActivity() {
    private val CHANNEL = "wifi.info.channel"
    private val TAG = "CombinedScanner"
    private val PERMISSION_REQUEST_CODE = 9999
    private val PERMISSION_REQUEST_CODE_LOCATION = 9998

    private lateinit var bluetoothManager: BluetoothManager
    private lateinit var bluetoothAdapter: BluetoothAdapter
    private var bluetoothLeScanner: BluetoothLeScanner? = null
    private val scannedBluetoothDevices = ConcurrentHashMap<String, ScannedBluetoothDevice>()
    private var isBleScanning = false
    private var pendingBluetoothScanResult: MethodChannel.Result? = null
    private var signalDbm: Int? = null

    // ========================================================================
    // APPTRACK: state
    // ========================================================================

    private val APPTRACK_TAG = "AppTrackNative"

    private val appTrackMethodChannelName = "apptrack/monitor"
    private val appTrackEventChannelName = "apptrack/monitor/events"

    private var appTrackEventSink: EventChannel.EventSink? = null

    private val appTrackSnapshotHandler = Handler(Looper.getMainLooper())
    private var appTrackSnapshotRunnable: Runnable? = null

    private var pendingVpnPackages: ArrayList<String>? = null

    private val VPN_PERMISSION_REQUEST = 7001

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.plugins.add(NetworkChannel())

        bluetoothManager = getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
        bluetoothAdapter = bluetoothManager.adapter
        bluetoothLeScanner = bluetoothAdapter.bluetoothLeScanner

        listenToSignalStrength()

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getWifiSignalInfo" -> getWifiSignalInfo(result)
                "getWifiEnabled" -> {
    getWifiEnabled(result)
}

"toggleWifi" -> {
    toggleWifi(result)
}
                "scanConnectedDevices" -> {
                    CoroutineScope(Dispatchers.IO).launch {
                        val devices = performActiveNetworkScan()
                        withContext(Dispatchers.Main) {
                            result.success(devices)
                        }
                    }
                }
                
                "startBleScan" -> {
                    pendingBluetoothScanResult = result
                    CoroutineScope(Dispatchers.IO).launch {
                        checkPermissionsAndStartScan()
                    }
                }
                "stopBleScan" -> {
                    stopBleScan()
                    result.success(true)
                }
                "getScannedBluetoothDevices" -> {
                    result.success(scannedBluetoothDevices.values.map { it.toMap() })
                }
                "getCellularSignalInfo" -> getCellularSignalInfo(result)
                "getDeviceInfo" -> result.success(getDeviceInfo())
                "getWifiFullDetails" -> {
                    CoroutineScope(Dispatchers.IO).launch {
                        getWifiFullDetails(result)
                    }
                }
                "getSerialNumber" -> result.success(getSerialNumber())
                "getEnhancedDeviceInfo" -> result.success(getEnhancedDeviceInfo())
"pingHost" -> {
    val host = call.argument<String>("host") ?: "8.8.8.8"
    val count = call.argument<Int>("count") ?: 4
    val timeoutSec = call.argument<Int>("timeoutSeconds") ?: 10
    CoroutineScope(Dispatchers.IO).launch {
        val pingResult = pingHost(host, count, timeoutSec)
        withContext(Dispatchers.Main) { result.success(pingResult) }
    }
}
                "scanPorts" -> {
                    val host = call.argument<String>("host") ?: "127.0.0.1"
                    val startPort = call.argument<Int>("startPort") ?: 1
                    val endPort = call.argument<Int>("endPort") ?: 1024
                    CoroutineScope(Dispatchers.IO).launch {
                        val openPorts = scanPorts(host, startPort, endPort)
                        withContext(Dispatchers.Main) {
                            result.success(openPorts)
                        }
                    }
                }
                "getManufacturerInfo" -> result.success(getManufacturerInfo())
                "getRouterInfo" -> {
                    CoroutineScope(Dispatchers.IO).launch {
                        getRouterInfo(result)
                    }
                }
                else -> result.notImplemented()
            }
        }

        // ====================================================================
        // APPTRACK: method channel (separate from wifi.info.channel above --
        // completely independent, so nothing here can break the existing
        // WifiMan features).
        // ====================================================================

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            appTrackMethodChannelName
        ).setMethodCallHandler { call, result ->

            when (call.method) {

                "listInstalledApps" -> {
                    Thread {
                        try {
                            val apps = appTrackListInstalledApps()
                            runOnUiThread { result.success(apps) }
                        } catch (e: Exception) {
                            runOnUiThread {
                                result.error(
                                    "APP_LIST_ERROR",
                                    e.message ?: "Failed to list installed apps",
                                    null
                                )
                            }
                        }
                    }.start()
                }

                "startSession" -> {
                    val packages = call.argument<List<String>>("packages") ?: emptyList()
                    result.success(appTrackStartSession(packages))
                }

                "stopSession" -> {
                    appTrackStopSession()
                    result.success(null)
                }

                "hasVpnPermission" -> {
                    result.success(appTrackHasVpnPermission())
                }

                "openVpnPermission" -> {
                    appTrackOpenVpnPermission()
                    result.success(null)
                }

                "hasUsageAccess" -> {
                    result.success(appTrackHasUsageAccess())
                }

                "openUsageAccessSettings" -> {
                    startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS))
                    result.success(null)
                }

                "getFlowSnapshot" -> {
                    Thread {
                        try {
                            val flows = appTrackReadFlows()
                            runOnUiThread { result.success(flows) }
                        } catch (e: Throwable) {
                            Log.e(APPTRACK_TAG, "Failed to get flow snapshot", e)
                            runOnUiThread {
                                result.error(
                                    "FLOW_ERROR",
                                    e.message ?: "Failed to read flows",
                                    null
                                )
                            }
                        }
                    }.start()
                }

                "getUniqueDestinationIps" -> {
                    try {
                        val ips = appTrackReadFlows()
                            .mapNotNull { it["destinationIp"] as? String }
                            .distinct()
                        result.success(ips)
                    } catch (e: Throwable) {
                        Log.e(APPTRACK_TAG, "Failed to get destination IPs", e)
                        result.error(
                            "FLOW_IP_ERROR",
                            e.message ?: "Failed to read destination IPs",
                            null
                        )
                    }
                }

                "getTunStats" -> {
                    try {
                        result.success(appTrackReadTunStats())
                    } catch (e: Throwable) {
                        Log.e(APPTRACK_TAG, "Failed to read tun stats", e)
                        result.error(
                            "TUN_STATS_ERROR",
                            e.message ?: "Failed to read /proc/net/dev",
                            null
                        )
                    }
                }

                "hasOverlayPermission" -> {
                    result.success(appTrackHasOverlayPermission())
                }

                "openOverlayPermission" -> {
                    appTrackOpenOverlayPermission()
                    result.success(null)
                }

                "startOverlay" -> {
                    if (!appTrackHasOverlayPermission()) {
                        result.error(
                            "OVERLAY_PERMISSION_REQUIRED",
                            "Draw-over-other-apps permission not granted",
                            null
                        )
                    } else {
                        try {
                            startService(
                                Intent(this, OverlayService::class.java).apply {
                                    action = OverlayService.ACTION_START
                                }
                            )
                            result.success(null)
                        } catch (e: Throwable) {
                            Log.e(APPTRACK_TAG, "Failed to start overlay", e)
                            result.error(
                                "OVERLAY_START_ERROR",
                                e.message ?: "Failed to start overlay",
                                null
                            )
                        }
                    }
                }

                "stopOverlay" -> {
                    try {
                        startService(
                            Intent(this, OverlayService::class.java).apply {
                                action = OverlayService.ACTION_STOP
                            }
                        )
                    } catch (e: Throwable) {
                        Log.w(APPTRACK_TAG, "Failed to stop overlay", e)
                    }
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            appTrackEventChannelName
        ).setStreamHandler(
            object : EventChannel.StreamHandler {

                override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
                    appTrackEventSink = sink
                    appTrackStartSnapshotLoop()
                    Log.d(APPTRACK_TAG, "AppTrack event stream attached")
                }

                override fun onCancel(arguments: Any?) {
                    appTrackEventSink = null
                    appTrackStopSnapshotLoop()
                    Log.d(APPTRACK_TAG, "AppTrack event stream detached")
                }
            }
        )
    }

    private fun listenToSignalStrength() {
        val telephonyManager = getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
        telephonyManager.listen(object : PhoneStateListener() {
            override fun onSignalStrengthsChanged(signalStrength: SignalStrength) {
                super.onSignalStrengthsChanged(signalStrength)
                signalDbm = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    signalStrength.cellSignalStrengths.firstOrNull()?.dbm
                } else null
            }
        }, PhoneStateListener.LISTEN_SIGNAL_STRENGTHS)
    }

    @SuppressLint("MissingPermission")
private fun getWifiEnabled(result: MethodChannel.Result) {
    try {
        val wifiManager =
            applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager

        result.success(wifiManager.isWifiEnabled)
    } catch (e: Exception) {
        Log.e(TAG, "getWifiEnabled error", e)
        result.error(
            "WIFI_STATUS_ERROR",
            e.message,
            null
        )
    }
}

@SuppressLint("MissingPermission")
private fun toggleWifi(result: MethodChannel.Result) {
    try {
        val wifiManager =
            applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {

            // Android 10+
            // Normal apps cannot directly enable/disable Wi-Fi.
            val intent = Intent(Settings.Panel.ACTION_INTERNET_CONNECTIVITY)
            startActivity(intent)

            result.success(
                mapOf(
                    "success" to true,
                    "directToggle" to false,
                    "wifiEnabled" to wifiManager.isWifiEnabled
                )
            )

        } else {

            // Android 9 and below
            @Suppress("DEPRECATION")
            val newState = !wifiManager.isWifiEnabled

            @Suppress("DEPRECATION")
            wifiManager.isWifiEnabled = newState

            result.success(
                mapOf(
                    "success" to true,
                    "directToggle" to true,
                    "wifiEnabled" to newState
                )
            )
        }

    } catch (e: Exception) {
        Log.e(TAG, "toggleWifi error", e)

        result.error(
            "WIFI_TOGGLE_ERROR",
            e.message,
            null
        )
    }
}

    private fun getDeviceInfo(): Map<String, Any?> {
        val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        val dhcpInfo = wifiManager.dhcpInfo
        val ipAddress = formatIP(wifiManager.connectionInfo.ipAddress)
        val gateway = formatIP(dhcpInfo.gateway)
        val dns1 = formatIP(dhcpInfo.dns1)
        val deviceName = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.JELLY_BEAN_MR1) {
            Settings.Global.getString(contentResolver, "device_name") ?: Build.MODEL
        } else {
            Build.MODEL
        }

        val uptimeMillis = SystemClock.elapsedRealtime()
        val uptimeDays = uptimeMillis / (1000 * 60 * 60 * 24)

        return mapOf(
            "deviceName" to deviceName,
            "model" to Build.MODEL,
            "manufacturer" to Build.MANUFACTURER,
            "deviceType" to "Phone",
            "firmwareVersion" to "Android ${Build.VERSION.RELEASE}",
            "uptime" to "$uptimeDays days",
            "ipAddress" to ipAddress,
            "gateway" to gateway,
            "dnsServer" to dns1,
            "signal" to (signalDbm?.toString() ?: "N/A")
        )
    }

    private fun formatIP(ip: Int): String {
        return try {
            val bytes = byteArrayOf(
                (ip and 0xff).toByte(),
                (ip shr 8 and 0xff).toByte(),
                (ip shr 16 and 0xff).toByte(),
                (ip shr 24 and 0xff).toByte()
            )
            InetAddress.getByAddress(bytes).hostAddress ?: "0.0.0.0"
        } catch (e: UnknownHostException) {
            "0.0.0.0"
        }
    }

    @SuppressLint("MissingPermission")
    private fun getWifiSignalInfo(result: MethodChannel.Result) {
        val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        val info = wifiManager.connectionInfo
        result.success(mapOf("signalStrength" to info.rssi, "linkSpeed" to info.linkSpeed))
    }

    @SuppressLint("MissingPermission")
    private fun performActiveNetworkScan(): List<String> {
        val list = mutableListOf<String>()
        val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        val dhcp = wifiManager.dhcpInfo
        val ip = dhcp.ipAddress
        if (ip == 0) return list

        val myIpBytes = ByteBuffer.allocate(4).order(ByteOrder.LITTLE_ENDIAN).putInt(ip).array()
        val subnetMaskBytes = ByteBuffer.allocate(4).order(ByteOrder.LITTLE_ENDIAN).putInt(dhcp.netmask).array()

        val startIp = ByteBuffer.wrap(myIpBytes).order(ByteOrder.BIG_ENDIAN).int and
                ByteBuffer.wrap(subnetMaskBytes).order(ByteOrder.BIG_ENDIAN).int
        val endIp = startIp or subnetMaskBytes.map { it.toInt().inv() and 0xFF }.reduce { acc, b -> acc shl 8 or b }

        for (i in (startIp + 1) until endIp) {
            val bytes = ByteBuffer.allocate(4).order(ByteOrder.BIG_ENDIAN).putInt(i).array()
            val target = InetAddress.getByAddress(bytes)
            try {
                if (target.isReachable(100)) list.add(target.hostAddress)
            } catch (_: Exception) { }
        }
        return list
    }

    @SuppressLint("MissingPermission")
    private fun getCellularSignalInfo(result: MethodChannel.Result) {
        val telephonyManager = getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
        var signal = "Unavailable"
        if (
            ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED ||
            ContextCompat.checkSelfPermission(this, Manifest.permission.READ_PHONE_STATE) == PackageManager.PERMISSION_GRANTED
        ) {
            val cells = telephonyManager.allCellInfo
            if (!cells.isNullOrEmpty()) {
                for (cell in cells) {
                    if (cell.isRegistered) {
                        signal = when (cell) {
                            is CellInfoLte -> "${cell.cellSignalStrength.dbm} dBm (LTE)"
                            is CellInfoGsm -> "${cell.cellSignalStrength.dbm} dBm (GSM)"
                            is CellInfoWcdma -> "${cell.cellSignalStrength.dbm} dBm (WCDMA)"
                            is CellInfoNr -> "${cell.cellSignalStrength.dbm} dBm (5G)"
                            else -> "Unknown"
                        }
                        break
                    }
                }
            }
        }
        result.success(signal)
    }

    private suspend fun checkPermissionsAndStartScan() {
        val requiredPermissions = mutableListOf<String>()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            requiredPermissions.add(Manifest.permission.BLUETOOTH_SCAN)
            requiredPermissions.add(Manifest.permission.BLUETOOTH_CONNECT)
        } else {
            requiredPermissions.add(Manifest.permission.BLUETOOTH)
            requiredPermissions.add(Manifest.permission.BLUETOOTH_ADMIN)
        }
        requiredPermissions.add(Manifest.permission.ACCESS_FINE_LOCATION)

        val missingPermissions = requiredPermissions.filter {
            ContextCompat.checkSelfPermission(this, it) != PackageManager.PERMISSION_GRANTED
        }

        if (missingPermissions.isNotEmpty()) {
            ActivityCompat.requestPermissions(this, missingPermissions.toTypedArray(), PERMISSION_REQUEST_CODE)
        } else {
            // Directly call ensureBluetoothAndLocationOn as checkLocationPermissionsAndServices is now handled internally
            ensureBluetoothAndLocationOn()
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        when (requestCode) {
            PERMISSION_REQUEST_CODE_LOCATION -> {
                if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                    // Permission granted, rely on Flutter to re-trigger data fetch.
                    // No direct action here to avoid double reply issues.
                } else {
                    // Permissions denied, do nothing and let Flutter handle the error on the next attempt.
                    showPermissionDeniedDialog()
                }
            }
            PERMISSION_REQUEST_CODE -> {
                // Handle Bluetooth permissions (existing logic)
                if (grantResults.all { it == PackageManager.PERMISSION_GRANTED }) {
                    // Permissions granted, rely on Flutter to re-trigger data fetch.
                    // No direct action here to avoid double reply issues.
                } else {
                    // Permissions denied, do nothing and let Flutter handle the error on the next attempt.
                    showPermissionDeniedDialog()
                }
            }
        }
    }

    private suspend fun ensureBluetoothAndLocationOn() {
        if (!bluetoothAdapter.isEnabled) {
            startActivityForResult(Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE), 1)
            Toast.makeText(this, "Please enable Bluetooth", Toast.LENGTH_LONG).show()
            pendingBluetoothScanResult?.error("BLUETOOTH_DISABLED", "Bluetooth is OFF. Please enable it.", null)
            return
        }

        if (checkLocationPermissionsAndServices()) {
            startBleScan()
        } else {
            pendingBluetoothScanResult?.error("LOCATION_DISABLED", "Location services are OFF or permissions denied. Please enable them.", null)
        }
    }

    @SuppressLint("MissingPermission")
    private suspend fun getWifiFullDetails(result: MethodChannel.Result) {
        if (!checkLocationPermissionsAndServices()) {
            result.error("LOCATION_PERMISSION_OR_SERVICE_DENIED", "Location permissions or services are not enabled.", null)
            return
        }

        val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        val wifiInfo = wifiManager.connectionInfo
        val dhcpInfo = wifiManager.dhcpInfo
        val wifiState = when (wifiManager.wifiState) {
            WifiManager.WIFI_STATE_DISABLED -> "Disabled"
            WifiManager.WIFI_STATE_DISABLING -> "Disabling"
            WifiManager.WIFI_STATE_ENABLED -> "Enabled"
            WifiManager.WIFI_STATE_ENABLING -> "Enabling"
            else -> "Unknown"
        }

        val ssid = wifiInfo.ssid ?: "Unavailable"
        val bssid = wifiInfo.bssid ?: "Unavailable"

        val channelWidthMhz = try {
    val method = wifiInfo.javaClass.getMethod("getChannelWidth")
    when (method.invoke(wifiInfo) as? Int) {
        0 -> 20; 1 -> 40; 2 -> 80; 3 -> 160; 4 -> 80; else -> null
    }
} catch (e: Exception) { null }

        val details = mapOf(
            "ssid" to ssid,
            "bssid" to bssid,
            "rssi" to wifiInfo.rssi,
            "linkSpeed" to wifiInfo.linkSpeed,
            "frequency" to wifiInfo.frequency,
            "ipAddress" to formatIP(wifiInfo.ipAddress),
            "gateway" to formatIP(dhcpInfo.gateway),
            "netmask" to formatIP(dhcpInfo.netmask),
            "serverAddress" to formatIP(dhcpInfo.serverAddress),
            "dns1" to formatIP(dhcpInfo.dns1),
            "macAddress" to wifiInfo.macAddress,
            "wifiState" to wifiState,
            "connectionType" to "WiFi",
            "isHiddenNetwork" to wifiInfo.hiddenSSID,
            "networkId" to wifiInfo.networkId,
            "channelWidth" to channelWidthMhz,
        )
        Log.d(TAG, "getWifiFullDetails: SSID = $ssid, BSSID = $bssid")
        result.success(details)
    }

    private fun getSerialNumber(): Map<String, Any?> {
        val serialNumber = try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Build.getSerial()
            } else {
                @Suppress("DEPRECATION")
                Build.SERIAL
            }
        } catch (e: SecurityException) {
            "Permission Denied"
        }

        return mapOf(
            "serialNumber" to serialNumber,
            "androidId" to Settings.Secure.getString(contentResolver, Settings.Secure.ANDROID_ID),
            "deviceId" to "${Build.MANUFACTURER}_${Build.MODEL}_${serialNumber}".replace("\\s".toRegex(), "_")
        )
    }

    private fun getEnhancedDeviceInfo(): Map<String, Any?> {
        val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        val dhcpInfo = wifiManager.dhcpInfo
        val ipAddress = formatIP(wifiManager.connectionInfo.ipAddress)
        val gateway = formatIP(dhcpInfo.gateway)
        val dns1 = formatIP(dhcpInfo.dns1)
        val dns2 = formatIP(dhcpInfo.dns2)
        val deviceName = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.JELLY_BEAN_MR1) {
            Settings.Global.getString(contentResolver, "device_name") ?: Build.MODEL
        } else {
            Build.MODEL
        }

        val uptimeMillis = SystemClock.elapsedRealtime()
        val uptimeDays = uptimeMillis / (1000 * 60 * 60 * 24)
        val uptimeHours = (uptimeMillis / (1000 * 60 * 60)) % 24
        val uptimeMinutes = (uptimeMillis / (1000 * 60)) % 60

        return mapOf(
            "deviceName" to deviceName,
            "model" to Build.MODEL,
            "manufacturer" to Build.MANUFACTURER,
            "brand" to Build.BRAND,
            "product" to Build.PRODUCT,
            "device" to Build.DEVICE,
            "hardware" to Build.HARDWARE,
            "board" to Build.BOARD,
            "bootloader" to Build.BOOTLOADER,
            "deviceType" to "Mobile",
            "osVersion" to "Android ${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT})",
            "firmwareVersion" to Build.VERSION.RELEASE,
            "buildNumber" to Build.VERSION.CODENAME,
            "securityPatch" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) Build.VERSION.SECURITY_PATCH else "N/A",
            "uptime" to "${uptimeDays}d ${uptimeHours}h ${uptimeMinutes}m",
            "ipAddress" to ipAddress,
            "gateway" to gateway,
            "dns1" to dns1,
            "dns2" to dns2,
            "subnetMask" to formatIP(dhcpInfo.netmask),
            "serverAddress" to formatIP(dhcpInfo.serverAddress),
            "leaseDuration" to dhcpInfo.leaseDuration,
            "wifiState" to when (wifiManager.wifiState) {
                WifiManager.WIFI_STATE_DISABLED -> "Disabled"
                WifiManager.WIFI_STATE_DISABLING -> "Disabling"
                WifiManager.WIFI_STATE_ENABLED -> "Enabled"
                WifiManager.WIFI_STATE_ENABLING -> "Enabling"
                else -> "Unknown"
            },
            "isWifiEnabled" to wifiManager.isWifiEnabled,
            "wifiMacAddress" to wifiManager.connectionInfo.macAddress,
            "wifiFrequency" to wifiManager.connectionInfo.frequency,
            "wifiLinkSpeed" to wifiManager.connectionInfo.linkSpeed,
            "wifiRssi" to wifiManager.connectionInfo.rssi,
            "wifiSupplicantState" to wifiManager.connectionInfo.supplicantState?.toString(),
            // "wifiDetailedState" to wifiManager.connectionInfo.detailedState?.toString(), // detailedState is deprecated or not available
            "networkId" to wifiManager.connectionInfo.networkId,
            "hiddenSSID" to wifiManager.connectionInfo.hiddenSSID,
            "signalStrength" to (signalDbm?.toString() ?: "N/A")
        )
    }

private fun pingHost(host: String, count: Int = 4, timeoutSec: Int = 10): Map<String, Any?> {
    return try {
        val process = Runtime.getRuntime().exec("/system/bin/ping -c $count -w $timeoutSec $host")
        val reader = BufferedReader(InputStreamReader(process.inputStream))
        val errorReader = BufferedReader(InputStreamReader(process.errorStream))

        val output = StringBuilder()
        val errorOutput = StringBuilder()
        var line: String?
        while (reader.readLine().also { line = it } != null) output.append(line).append("\n")
        while (errorReader.readLine().also { line = it } != null) errorOutput.append(line).append("\n")

        val exitCode = process.waitFor()
        val outputStr = output.toString()

        val times = Regex("time[=<]([\\d.]+)\\s*ms").findAll(outputStr)
            .map { it.groupValues[1].toDouble() }.toList()

        val summaryMatch = Regex("=\\s*([\\d.]+)/([\\d.]+)/([\\d.]+)/([\\d.]+)\\s*ms").find(outputStr)
        val avgMs = summaryMatch?.groupValues?.get(2)?.toDoubleOrNull()
            ?: (if (times.isNotEmpty()) times.average() else null)

        val lossMatch = Regex("(\\d+)%\\s*packet loss").find(outputStr)
        val packetLossPercent = lossMatch?.groupValues?.get(1)?.toIntOrNull()
        val success = exitCode == 0 && avgMs != null

        mapOf(
            "success" to success, "avgMs" to avgMs, "rtts" to times,
            "packetLossPercent" to packetLossPercent, "output" to outputStr,
            "error" to errorOutput.toString(), "exitCode" to exitCode, "host" to host
        )
    } catch (e: IOException) {
        mapOf(
            "success" to false, "avgMs" to null, "rtts" to emptyList<Double>(),
            "packetLossPercent" to null, "output" to "", "error" to e.message,
            "exitCode" to -1, "host" to host
        )
    }
}

    private fun scanPorts(host: String, startPort: Int, endPort: Int): List<Map<String, Any>> {
        val openPorts = mutableListOf<Map<String, Any>>()
        
        for (port in startPort..endPort) {
            try {
                val socket = Socket(host, port)
                socket.close()
                openPorts.add(mapOf(
                    "port" to port,
                    "status" to "open",
                    "service" to getServiceName(port)
                ))
            } catch (e: Exception) {
                // Port is closed or filtered
                openPorts.add(mapOf(
                    "port" to port,
                    "status" to "closed",
                    "service" to getServiceName(port)
                ))
            }
        }
        
        return openPorts
    }

    private fun getServiceName(port: Int): String {
        val commonPorts = mapOf(
            20 to "FTP Data", 21 to "FTP Control", 22 to "SSH", 23 to "Telnet",
            25 to "SMTP", 53 to "DNS", 80 to "HTTP", 110 to "POP3",
            143 to "IMAP", 443 to "HTTPS", 993 to "IMAPS", 995 to "POP3S",
            3389 to "RDP", 8080 to "HTTP Proxy", 8443 to "HTTPS Proxy"
        )
        return commonPorts[port] ?: "Unknown"
    }

    private fun getManufacturerInfo(): Map<String, Any?> {
        val manufacturer = Build.MANUFACTURER.lowercase()
        
        val manufacturerUrls = mapOf(
            "samsung" to "https://www.samsung.com",
            "google" to "https://www.google.com",
            "oneplus" to "https://www.oneplus.com",
            "xiaomi" to "https://www.mi.com",
            "huawei" to "https://www.huawei.com",
            "oppo" to "https://www.oppo.com",
            "vivo" to "https://www.vivo.com",
            "apple" to "https://www.apple.com",
            "sony" to "https://www.sony.com",
            "lg" to "https://www.lg.com",
            "motorola" to "https://www.motorola.com",
            "lenovo" to "https://www.lenovo.com",
            "asus" to "https://www.asus.com",
            "acer" to "https://www.acer.com",
            "dell" to "https://www.dell.com",
            "hp" to "https://www.hp.com"
        )
        
        val productUrls = mapOf(
            "pixel" to "https://store.google.com/product/pixel",
            "galaxy" to "https://www.samsung.com/us/mobile/galaxy",
            "iphone" to "https://www.apple.com/iphone",
            "oneplus" to "https://www.oneplus.com",
            "mi" to "https://www.mi.com",
            "redmi" to "https://www.mi.com/redmi",
            "huawei" to "https://consumer.huawei.com/en/phones/mate",
            "mate" to "https://consumer.huawei.com/en/phones/mate",
            "porsche" to "https://www.porsche.com",
            "design" to "https://www.huawei.com"
        )
        
        val manufacturerSite = manufacturerUrls[manufacturer] ?: "https://www.${manufacturer}.com"
        val productSite = productUrls.entries.find { Build.PRODUCT.contains(it.key, ignoreCase = true) }?.value ?: manufacturerSite
        
        return mapOf(
            "manufacturer" to Build.MANUFACTURER,
            "manufacturerSite" to manufacturerSite,
            "product" to Build.PRODUCT,
            "productSite" to productSite,
            "brand" to Build.BRAND,
            "model" to Build.MODEL
        )
    }

    private suspend fun getRouterInfo(result: MethodChannel.Result) {
        // pendingLocationPermissionResult = result // Removed
        val data = mutableMapOf<String, Any?>("routerModel" to "Unknown", "routerManufacturer" to "Unknown", "routerName" to "<unknown ssid>")

        if (!checkLocationPermissionsAndServices()) {
            result.error("LOCATION_PERMISSION_OR_SERVICE_DENIED", "Location permissions or services are not enabled.", null)
            return
        }

        val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        val wifiInfo = wifiManager.connectionInfo
        val dhcpInfo = wifiManager.dhcpInfo

        val ssid = wifiInfo.ssid ?: "Unavailable"
        val bssid = wifiInfo.bssid ?: "Unavailable"

        val gatewayIp = formatIP(dhcpInfo.gateway)
        val subnetMask = formatIP(dhcpInfo.netmask)
        val dns1 = formatIP(dhcpInfo.dns1)
        val dns2 = formatIP(dhcpInfo.dns2)
        val serverAddress = formatIP(dhcpInfo.serverAddress)

        val networkRange = calculateNetworkRange(gatewayIp, subnetMask)

        val routerMac = bssid
        val routerManufacturer = getRouterManufacturer(routerMac)

        val capabilities = estimateRouterCapabilities(dhcpInfo, wifiInfo)

        // Attempt to get router model from web interface
        val routerModelFromWeb = CoroutineScope(Dispatchers.IO).async {
            getRouterModelFromWeb(gatewayIp)
        }.await()

        data.putAll(mapOf(
            "routerIp" to gatewayIp,
            "routerMac" to routerMac,
            "routerManufacturer" to routerManufacturer,
            "routerModel" to routerModelFromWeb, // Use the model obtained from web
            "subnetMask" to subnetMask,
            "networkRange" to networkRange,
            "dnsServers" to listOf(dns1, dns2).filter { it != "0.0.0.0" },
            "dhcpServer" to serverAddress,
            "leaseDuration" to dhcpInfo.leaseDuration,
            "wifiFrequency" to "${wifiInfo.frequency} MHz",
            "wifiChannel" to getWifiChannel(wifiInfo.frequency),
            "maxWifiSpeed" to "${wifiInfo.linkSpeed} Mbps",
            "capabilities" to capabilities,
            "connectedDevices" to performActiveNetworkScan().size,
            "networkType" to if (wifiInfo.frequency < 3000) "2.4 GHz" else "5 GHz",
            "securityType" to "WPA2/WPA3", // Default assumption
            "signalQuality" to getSignalQuality(wifiInfo.rssi),
            "connectionType" to "WiFi",
            "isHiddenNetwork" to wifiInfo.hiddenSSID,
            "networkId" to wifiInfo.networkId,
            "routerName" to ssid
        ))
        Log.d(TAG, "getRouterInfo: Data collected - $data")
        result.success(data)
        // pendingLocationPermissionResult = null // Removed
    }

    private fun calculateNetworkRange(gateway: String, subnetMask: String): String {
        val gatewayBytes = gateway.split(".").map { it.toInt() }.toIntArray()
        val subnetMaskBytes = subnetMask.split(".").map { it.toInt() }.toIntArray()

        val networkAddress = IntArray(4)
        for (i in 0..3) {
            networkAddress[i] = gatewayBytes[i] and subnetMaskBytes[i]
        }

        val broadcastAddress = IntArray(4)
        for (i in 0..3) {
            broadcastAddress[i] = networkAddress[i] or (subnetMaskBytes[i].inv() and 0xFF)
        }

        return "${formatIP(networkAddress[0])}.${formatIP(networkAddress[1])}.${formatIP(networkAddress[2])}.${formatIP(networkAddress[3])}, ${formatIP(broadcastAddress[0])}.${formatIP(broadcastAddress[1])}.${formatIP(broadcastAddress[2])}.${formatIP(broadcastAddress[3])}"
    }

    private suspend fun getRouterManufacturer(macAddress: String): String {
        return try {
            val oui = macAddress.substring(0, 8).replace(":", "").uppercase()
            // This is an illustrative, simplified list. For a comprehensive lookup,
            // a regularly updated external database or API would be required.
            val routerManufacturers = mapOf(
                "000C29" to "VMware",
                "001310" to "Technicolor",
                "0023CD" to "TP-LINK",
                "0024A4" to "ARRIS",
                "008EF2" to "Netgear",
                "00B555" to "Huawei",
                "00D4C8" to "Apple",
                "00C0A8" to "GVC",
                "00D016" to "Actiontec Electronics",
                "0024A5" to "NETGEAR",
                "00405A" to "TP-LINK Technologies CO.,LTD.",
                "647002" to "HUAWEI TECHNOLOGIES CO.,LTD",
                "CC46D6" to "Tenda",
                "44D6E5" to "D-Link",
                "F832E5" to "Cisco",
                "FCF136" to "ASUS",
                "14EBB6" to "TP-Link Corporation Limited",
                "1C3BF3" to "TP-LINK TECHNOLOGIES CO., LTD." // Updated with correct manufacturer
            )
            val prefix = oui.substring(0, 6)
            val localLookup = routerManufacturers[prefix]
            return if (localLookup != null && localLookup != "Unknown") {
                localLookup
            } else {
                getManufacturerFromOUIOnline(prefix) // Direct call now that getRouterManufacturer is suspend
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error getting router manufacturer: ${e.message}")
            return "Unknown"
        }
    }

    private suspend fun getManufacturerFromOUIOnline(oui: String): String {
        return withContext(Dispatchers.IO) {
            try {
                val url = java.net.URL("https://api.macvendors.com/$oui")
                val connection = url.openConnection() as java.net.HttpURLConnection
                connection.requestMethod = "GET"
                connection.connectTimeout = 5000 // 5 seconds
                connection.readTimeout = 5000 // 5 seconds

                if (connection.responseCode == java.net.HttpURLConnection.HTTP_OK) {
                    BufferedReader(InputStreamReader(connection.inputStream)).use { reader ->
                        reader.readText().trim()
                    }
                } else {
                    Log.e(TAG, "Online OUI lookup failed with response code: ${connection.responseCode}")
                    "Unknown"
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error during online OUI lookup: ${e.message}")
                "Unknown"
            }
        }
    }

    @SuppressLint("MissingPermission")
    private fun startBleScan() {
        if (isBleScanning) {
            pendingBluetoothScanResult?.success(true)
            return
        }

        bluetoothLeScanner = bluetoothAdapter.bluetoothLeScanner
        if (bluetoothLeScanner == null) {
            pendingBluetoothScanResult?.error("BLE_NOT_AVAILABLE", "BLE scanner not available", null)
            return
        }

        scannedBluetoothDevices.clear()
        isBleScanning = true
        bluetoothLeScanner?.startScan(listOf(), createScanSettings(), bleScanCallback)
        pendingBluetoothScanResult?.success(true)
        pendingBluetoothScanResult = null

        CoroutineScope(Dispatchers.Main).launch {
            delay(5000L)
            stopBleScan()
        }
    }

    @SuppressLint("MissingPermission")
    private fun stopBleScan() {
        if (isBleScanning) {
            bluetoothLeScanner?.stopScan(bleScanCallback)
            isBleScanning = false
        }
    }

    private fun createScanSettings(): ScanSettings {
        return ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
            .build()
    }

    private val bleScanCallback = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult) {
            val address = result.device.address ?: return
            val name = result.device.name ?: result.scanRecord?.deviceName ?: "Unknown"
            val rssi = result.rssi
            val manufacturer = ManufacturerLookup.getManufacturer(result.scanRecord?.manufacturerSpecificData)
            val serviceUuids = result.scanRecord?.serviceUuids?.joinToString(", ") ?: ""
            val type = ManufacturerLookup.inferDeviceType(name, manufacturer, serviceUuids)

            scannedBluetoothDevices[address] = ScannedBluetoothDevice(
                address, name, rssi, manufacturer, type, serviceUuids
            )
        }
    }

    private fun showPermissionDeniedDialog() {
        AlertDialog.Builder(this)
            .setTitle("Permission Required")
            .setMessage("Please enable all required permissions in settings.")
            .setPositiveButton("Settings") { _, _ ->
                startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                    data = Uri.fromParts("package", packageName, null)
                })
            }
            .setNegativeButton("Cancel", null)
            .show()
    }

    private fun getWifiChannel(frequency: Int): Int {
        if (frequency == 0) return 0 // Not connected

        if (frequency >= 2412 && frequency <= 2484) {
            // 2.4 GHz band
            return (frequency - 2412) / 5 + 1
        } else if (frequency >= 5170 && frequency <= 5825) {
            // 5 GHz band
            return (frequency - 5170) / 5 + 34
        }
        return 0 // Unknown or other band
    }

    private fun estimateRouterCapabilities(dhcpInfo: android.net.DhcpInfo, wifiInfo: android.net.wifi.WifiInfo): List<String> {
        val capabilities = mutableListOf<String>()

        // Based on frequency
        if (wifiInfo.frequency >= 5000) {
            capabilities.add("5GHz WiFi")
        } else if (wifiInfo.frequency >= 2400) {
            capabilities.add("2.4GHz WiFi")
        }

        // Based on typical router features (simplified)
        if (dhcpInfo.dns1 != 0 || dhcpInfo.dns2 != 0) {
            capabilities.add("DNS Server")
        }
        if (dhcpInfo.gateway != 0) {
            capabilities.add("Gateway")
        }
        if (dhcpInfo.leaseDuration > 0) {
            capabilities.add("DHCP Server")
        }
        
        // Assuming basic features based on modern routers
        capabilities.add("Firewall")
        capabilities.add("NAT")
        capabilities.add("Port Forwarding")
        capabilities.add("VPN Passthrough")

        return capabilities.distinct().toList()
    }

    private fun getSignalQuality(rssi: Int): String {
        return when {
            rssi > -50 -> "Excellent"
            rssi > -60 -> "Good"
            rssi > -70 -> "Fair"
            else -> "Weak"
        }
    }

    private suspend fun getRouterModelFromWeb(gatewayIp: String): String {
        return withContext(Dispatchers.IO) {
            try {
                val url = "http://$gatewayIp"
                val connection = java.net.URL(url).openConnection() as java.net.HttpURLConnection
                connection.requestMethod = "GET"
                connection.connectTimeout = 5000 // 5 seconds
                connection.readTimeout = 5000 // 5 seconds

                if (connection.responseCode == java.net.HttpURLConnection.HTTP_OK) {
                    BufferedReader(InputStreamReader(connection.inputStream)).use { reader ->
                        val response = reader.readText()
                        extractModelFromHtml(response)
                    }
                } else {
                    Log.e(TAG, "HTTP GET to router failed with response code: ${connection.responseCode}")
                    "Unknown"
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error fetching router web interface: ${e.message}")
                "Unknown"
            }
        }
    }

    private fun extractModelFromHtml(html: String): String {
        try {
            val document = Jsoup.parse(html)

            // Attempt to extract modelName directly from the entire HTML using regex (highest priority)
            val directModelNameRegex = """var\s+modelName\s*=\s*['"]([^'"]+)['"]""".toRegex(RegexOption.IGNORE_CASE)
            val directMatch = directModelNameRegex.findAll(html).lastOrNull()
            if (directMatch != null) {
                val extractedModel = cleanAndValidateModel(directMatch.groupValues[1].trim())
                if (extractedModel.isNotBlank() && extractedModel.length > 2) {
                    Log.d(TAG, "Direct regex extraction found model: $extractedModel")
                    return extractedModel
                }
            }

            // Jsoup based extraction (lower priority after direct regex)
            val selectors = listOf(
                // Removed: "script:contains(var modelName=)" - now handled by direct regex
                "title", // Often contains brand and model
                "h1:contains(Model)", "h2:contains(Model)", "h3:contains(Model)",
                "div[class*=model]", "span[class*=model]", "p[class*=model]",
                "div[id*=model]", "span[id*=model]", "p[id*=model]",
                "b:contains(Model)", "strong:contains(Model)",
                "td:contains(Model) + td", // Common in tables
                "dt:contains(Model) + dd", // Common in definition lists
                "meta[name=model]", "meta[name=product]", "meta[property=og:title]"
            )

            for (selector in selectors) {
                val elements = document.select(selector)
                for (element in elements) {
                    var extracted = ""
                    // Removed: Script content parsing is now handled by direct regex at the beginning
                    if (selector.startsWith("meta")) {
                        extracted = element.attr("content").trim() // For meta tags, get content attribute
                    } else {
                        extracted = element.text().trim()
                    }

                    // Aggressive cleanup and validation
                    extracted = cleanAndValidateModel(extracted)
                    if (extracted.isNotBlank() && extracted.length > 2) {
                        // Further refine for TP-Link specific patterns if brand is known
                        if (extracted.contains(Regex("TP-Link", RegexOption.IGNORE_CASE))) {
                            val tpLinkMatch = Regex("TP-Link\\s*(?:Model)?\\s*(TL-WR(?:\\d{3,4})N|Archer\\s*[A-Z]\\d{2,4}|TD-W(?:\\d{3,4})ND?|MR(?:\\d{3,4}))", RegexOption.IGNORE_CASE).find(extracted)
                            if (tpLinkMatch != null) {
                                return tpLinkMatch.groupValues.last()
                            }
                        }
                        return extracted
                    }
                }
            }

            // Fallback to simplified regex patterns if Jsoup doesn't find anything
            val fallbackPatterns = listOf(
                """var\s+(?:router)?Model\s*=\s*['\"]([^'\"]+)['\"]""".toRegex(RegexOption.IGNORE_CASE),
                """deviceModel:\s*['\"]([^'\"]+)['\"]""".toRegex(RegexOption.IGNORE_CASE),
                """productModel:\s*['\"]([^'\"]+)['\"]""".toRegex(RegexOption.IGNORE_CASE),
                """Model[:\s-]*([a-zA-Z0-9\-]{2,})""".toRegex(RegexOption.IGNORE_CASE),
                """([A-Z0-9]{2,4}[-][A-Z0-9]{2,4}(?:[A-Z0-9])?)""".toRegex(RegexOption.IGNORE_CASE)
            )

            for (pattern in fallbackPatterns) {
                val match = pattern.find(html)
                if (match != null) {
                    val extracted = cleanAndValidateModel(match.groupValues.last().trim())
                    if (extracted.isNotBlank() && extracted.length > 2) {
                        return extracted
                    }
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error during HTML parsing for router model: ${e.message}")
        }
        return "Unknown"
    }

    private fun cleanAndValidateModel(input: String): String {
        var cleaned = input
            .replace(Regex("Admin|Router|Management|Interface|Page|Settings|Version|Hardware|Firmware|Home|Login", RegexOption.IGNORE_CASE), "")
            .replace(Regex("<[^>]+>", RegexOption.IGNORE_CASE), "")
            .replace(Regex("\\s+", RegexOption.IGNORE_CASE), " ")
            .trim()

        // Additional check for common HTML attributes or non-model strings
        if (cleaned.contains(Regex("^(http|https|www|html|body|head|meta|link|script|style|charset|content|type|name|property|value|text)", RegexOption.IGNORE_CASE)) ||
            cleaned.length < 3 || // Too short to be a model
            !cleaned.contains(Regex("[A-Z0-9]", RegexOption.IGNORE_CASE))) { // Doesn't contain alphanumeric characters
            return ""
        }
        return cleaned
    }

    private suspend fun checkLocationPermissionsAndServices(): Boolean {
        val fineLocationPermission = Manifest.permission.ACCESS_FINE_LOCATION

        if (ContextCompat.checkSelfPermission(this, fineLocationPermission) != PackageManager.PERMISSION_GRANTED) {
            ActivityCompat.requestPermissions(this, arrayOf(fineLocationPermission), PERMISSION_REQUEST_CODE_LOCATION)
            return false // Permission not granted yet, will re-evaluate after permission callback
        } else {
            val locationManager = getSystemService(Context.LOCATION_SERVICE) as LocationManager
            val isLocationEnabled = locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER) ||
                                    locationManager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)
            
            if (isLocationEnabled) {
                return true
            } else {
                showLocationServiceRequiredDialog()
                return false
            }
        }
    }

    private fun showLocationServiceRequiredDialog() {
        AlertDialog.Builder(this)
            .setTitle("Location Services Required")
            .setMessage("Please enable location services to get accurate Wi-Fi and router information.")
            .setPositiveButton("Settings") { _, _ ->
                startActivity(Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS))
            }
            .setNegativeButton("Cancel", null)
            .show()
    }

    // ========================================================================
    // APPTRACK: VPN session control
    // ========================================================================

    private fun appTrackStartSession(packages: List<String>): String {

        val filtered = packages
            .distinct()
            .filter { it.isNotBlank() }
            .filter { it != packageName }

        if (filtered.isEmpty()) {
            return "empty"
        }

        val prepareIntent = VpnService.prepare(this)

        if (prepareIntent != null) {
            pendingVpnPackages = ArrayList(filtered)
            Log.i(APPTRACK_TAG, "VPN permission required")
            startActivityForResult(prepareIntent, VPN_PERMISSION_REQUEST)
            return "vpn_permission_required"
        }

        appTrackStartVpnService(filtered)
        return "started"
    }

    private fun appTrackOpenVpnPermission() {
        val intent = VpnService.prepare(this)
        if (intent != null) {
            startActivityForResult(intent, VPN_PERMISSION_REQUEST)
        } else {
            Log.i(APPTRACK_TAG, "VPN permission already granted")
        }
    }

    private fun appTrackStartVpnService(packages: List<String>) {
        if (packages.isEmpty()) return

        val intent = Intent(this, AppTrackVpnService::class.java).apply {
            action = AppTrackVpnService.ACTION_START
            putStringArrayListExtra(AppTrackVpnService.EXTRA_PACKAGES, ArrayList(packages))
        }

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }
            Log.i(APPTRACK_TAG, "VPN service start requested packages=$packages")
        } catch (e: Exception) {
            Log.e(APPTRACK_TAG, "Failed to start VPN service", e)
        }
    }

    private fun appTrackStopSession() {
        pendingVpnPackages = null

        val intent = Intent(this, AppTrackVpnService::class.java).apply {
            action = AppTrackVpnService.ACTION_STOP
        }

        try {
            startService(intent)
        } catch (e: Exception) {
            Log.e(APPTRACK_TAG, "Failed to stop VPN service", e)
        }

        try {
            startService(
                Intent(this, OverlayService::class.java).apply {
                    action = OverlayService.ACTION_STOP
                }
            )
        } catch (e: Throwable) {
            Log.w(APPTRACK_TAG, "Failed to stop overlay", e)
        }

        FlowStore.clear()
        AppUsageStore.clear()
    }

    private fun appTrackHasVpnPermission(): Boolean {
        return try {
            VpnService.prepare(this) == null
        } catch (e: Exception) {
            Log.e(APPTRACK_TAG, "VPN permission check failed", e)
            false
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)

        if (requestCode != VPN_PERMISSION_REQUEST) {
            // Not ours (e.g. the Bluetooth-enable request code 1 from
            // ensureBluetoothAndLocationOn) -- leave it alone.
            return
        }

        val packages = pendingVpnPackages
        pendingVpnPackages = null

        if (resultCode == RESULT_OK) {
            Log.i(APPTRACK_TAG, "VPN permission granted")
            if (packages != null && packages.isNotEmpty()) {
                appTrackStartVpnService(packages)
            }
        } else {
            Log.w(APPTRACK_TAG, "VPN permission denied")
        }
    }

    // ========================================================================
    // APPTRACK: overlay permission
    // ========================================================================

    private fun appTrackHasOverlayPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            Settings.canDrawOverlays(this)
        } else {
            true
        }
    }

    private fun appTrackOpenOverlayPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            startActivity(
                Intent(
                    Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                    Uri.parse("package:$packageName")
                )
            )
        }
    }

    // ========================================================================
    // APPTRACK: auto-show overlay on background
    // ========================================================================

    override fun onPause() {
        super.onPause()

        if (AppTrackVpnService.isRunning && appTrackHasOverlayPermission()) {
            try {
                startService(
                    Intent(this, OverlayService::class.java).apply {
                        action = OverlayService.ACTION_START
                    }
                )
            } catch (e: Throwable) {
                Log.w(APPTRACK_TAG, "Auto-start overlay failed", e)
            }
        }
    }

    override fun onResume() {
        super.onResume()
        // Overlay has its own close button -- left running here on
        // purpose so it stays visible until explicitly closed or the
        // VPN session stops.
    }

    // ========================================================================
    // APPTRACK: usage access
    // ========================================================================

    private fun appTrackHasUsageAccess(): Boolean {
        val appOps = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager

        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            appOps.unsafeCheckOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                android.os.Process.myUid(),
                packageName
            )
        } else {
            @Suppress("DEPRECATION")
            appOps.checkOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                android.os.Process.myUid(),
                packageName
            )
        }

        return mode == AppOpsManager.MODE_ALLOWED
    }

    // ========================================================================
    // APPTRACK: installed apps
    // ========================================================================

    private fun appTrackListInstalledApps(): List<Map<String, Any>> {

        val pm = packageManager

        val launcherIntent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        val resolved = pm.queryIntentActivities(launcherIntent, 0)

        val seen = LinkedHashSet<String>()
        val result = mutableListOf<Map<String, Any>>()

        for (info in resolved) {
            val appInfo = info.activityInfo.applicationInfo
            val pkg = appInfo.packageName

            if (pkg == packageName || !seen.add(pkg)) continue

            val label = try {
                pm.getApplicationLabel(appInfo).toString()
            } catch (_: Exception) {
                pkg
            }

            val iconBytes = try {
                val drawable = pm.getApplicationIcon(appInfo)
                val bitmap = android.graphics.Bitmap.createBitmap(
                    96, 96, android.graphics.Bitmap.Config.ARGB_8888
                )
                val canvas = android.graphics.Canvas(bitmap)
                drawable.setBounds(0, 0, 96, 96)
                drawable.draw(canvas)

                val stream = java.io.ByteArrayOutputStream()
                bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, stream)
                bitmap.recycle()
                stream.toByteArray()
            } catch (e: Exception) {
                Log.w(APPTRACK_TAG, "Icon failed for $pkg", e)
                null
            }

            val app = mutableMapOf<String, Any>(
                "packageName" to pkg,
                "appName" to label,
                "uid" to appInfo.uid
            )

            if (iconBytes != null) {
                app["icon"] = iconBytes
            }

            result.add(app)
        }

        return result.sortedBy { (it["appName"] as String).lowercase() }
    }

    // ========================================================================
    // APPTRACK: live snapshot loop (drives the EventChannel)
    // ========================================================================

    private fun appTrackStartSnapshotLoop() {
        appTrackStopSnapshotLoop()

        val runnable = object : Runnable {
            override fun run() {
                val sink = appTrackEventSink
                if (sink != null) {
                    try {
                        sink.success(appTrackReadFlows())
                    } catch (e: Throwable) {
                        Log.e(APPTRACK_TAG, "HEV flow read failed", e)
                    }
                }
                appTrackSnapshotHandler.postDelayed(this, 500L)
            }
        }

        appTrackSnapshotRunnable = runnable
        appTrackSnapshotHandler.post(runnable)
    }

    private fun appTrackStopSnapshotLoop() {
        appTrackSnapshotRunnable?.let { appTrackSnapshotHandler.removeCallbacks(it) }
        appTrackSnapshotRunnable = null
    }

    // ========================================================================
    // APPTRACK: flow parsing
    // ========================================================================

    private fun appTrackReadFlows(): List<Map<String, Any>> {
        val rawFlows = FlowStore.snapshot()
        val flows = rawFlows.mapNotNull { raw -> appTrackParseFlow(raw) }
        Log.i(APPTRACK_TAG, "FlowStore raw=${rawFlows.size}, parsed=${flows.size}")
        return flows
    }

    private fun appTrackValueFor(raw: Map<String, Any>, vararg names: String): Any? {
        for (name in names) {
            raw[name]?.let { return it }
        }
        val normalized = raw.entries.associate { appTrackNormalizeKey(it.key) to it.value }
        for (name in names) {
            normalized[appTrackNormalizeKey(name)]?.let { return it }
        }
        return null
    }

    private fun appTrackNormalizeKey(value: String): String {
        return value.trim().lowercase().replace("_", "").replace("-", "")
    }

    private fun appTrackParseFlow(raw: Map<String, Any>): Map<String, Any>? {
        val ip = appTrackValueFor(
            raw,
            "destinationIp", "dstIp", "dst_ip", "destination_ip",
            "remoteIp", "remote_ip", "ip", "destination", "dst",
            "targetIp", "target_ip"
        )?.toString()?.trim().orEmpty()

        if (ip.isBlank()) {
            Log.w(APPTRACK_TAG, "FLOW DROPPED: no destination IP. raw=$raw")
            return null
        }

        val port = when (val value = appTrackValueFor(
            raw,
            "destinationPort", "dstPort", "dst_port", "destination_port",
            "remotePort", "remote_port", "port", "targetPort", "target_port"
        )) {
            is Number -> value.toInt()
            else -> value?.toString()?.toIntOrNull() ?: 0
        }

        val protocolValue = appTrackValueFor(raw, "protocol", "proto", "transport", "type")
        val protocol = when (protocolValue) {
            is String -> protocolValue.uppercase()
            is Number -> when (protocolValue.toInt()) {
                6 -> "TCP"
                17 -> "UDP"
                1 -> "ICMP"
                58 -> "ICMPv6"
                else -> "IP"
            }
            else -> "IP"
        }

        val bytes = when (val value = appTrackValueFor(
            raw,
            "bytes", "byteCount", "byte_count", "size", "length",
            "rxBytes", "txBytes", "totalBytes", "total_bytes"
        )) {
            is Number -> value.toLong().coerceAtMost(Int.MAX_VALUE.toLong()).toInt()
            else -> value?.toString()?.toLongOrNull()
                ?.coerceAtMost(Int.MAX_VALUE.toLong())?.toInt() ?: 0
        }

        val ipVersion = when (val value = appTrackValueFor(
            raw, "ipVersion", "ip_version", "version", "family"
        )) {
            is Number -> value.toInt()
            is String -> value.toIntOrNull() ?: if (ip.contains(":")) 6 else 4
            else -> if (ip.contains(":")) 6 else 4
        }

        val uid = when (val value = appTrackValueFor(raw, "uid", "userId", "user_id")) {
            is Number -> value.toInt()
            else -> value?.toString()?.toIntOrNull() ?: -1
        }

        val packetCount = when (val value = appTrackValueFor(
            raw, "packetCount", "packet_count", "packets"
        )) {
            is Number -> value.toLong()
            else -> value?.toString()?.toLongOrNull() ?: 0L
        }

        return mapOf(
            "destinationIp" to ip,
            "destinationPort" to port,
            "protocol" to protocol,
            "bytes" to bytes,
            "ipVersion" to ipVersion,
            "uid" to uid,
            "packetCount" to packetCount
        )
    }

    // ========================================================================
    // APPTRACK: TUN interface stats (/proc/net/dev)
    // ========================================================================

    private fun appTrackReadTunStats(): List<Map<String, Any>> {

        val results = mutableListOf<Map<String, Any>>()
        val file = File("/proc/net/dev")

        if (!file.exists()) return results

        file.forEachLine { rawLine ->
            val line = rawLine.trim()
            val colonIndex = line.indexOf(':')
            if (colonIndex <= 0) return@forEachLine

            val name = line.substring(0, colonIndex).trim()
            if (!name.startsWith("tun")) return@forEachLine

            val fields = line.substring(colonIndex + 1).trim().split(Regex("\\s+"))
            if (fields.size < 16) return@forEachLine

            val rxBytes = fields[0].toLongOrNull() ?: 0L
            val rxPackets = fields[1].toLongOrNull() ?: 0L
            val txBytes = fields[8].toLongOrNull() ?: 0L
            val txPackets = fields[9].toLongOrNull() ?: 0L

            results.add(
                mapOf(
                    "name" to name,
                    "rxBytes" to rxBytes,
                    "rxPackets" to rxPackets,
                    "txBytes" to txBytes,
                    "txPackets" to txPackets
                )
            )
        }

        return results
    }

    override fun onDestroy() {
        appTrackStopSnapshotLoop()
        appTrackEventSink = null
        pendingVpnPackages = null
        super.onDestroy()
    }
}


// Data class for Bluetooth device info
data class ScannedBluetoothDevice(
    val address: String,
    var name: String?,
    var rssi: Int,
    var manufacturer: String?,
    var deviceType: String?,
    val serviceUuids: String?
) {
    fun toMap(): Map<String, Any?> = mapOf(
        "address" to address,
        "name" to name,
        "rssi" to rssi,
        "manufacturer" to manufacturer,
        "deviceType" to deviceType,
        "serviceUuids" to serviceUuids
    )
}

object ManufacturerLookup {
    private val manufacturerMap = mapOf(76 to "Apple", 117 to "Samsung", 315 to "Google", 300 to "Xiaomi", 311 to "OnePlus", 312 to "Lenovo", 313 to "Sony", 65535 to "Unknown")
    fun getManufacturer(data: SparseArray<ByteArray>?): String? {
        if (data != null && data.size() > 0) {
            val id = data.keyAt(0)
            return manufacturerMap[id] ?: "0x${id.toString(16)}"
        }
        return null
    }

    fun inferDeviceType(name: String?, m: String?, uuids: String?): String {
        val n = name?.lowercase(Locale.ROOT) ?: ""
        val manuf = m?.lowercase(Locale.ROOT) ?: ""
        return when {
            "iphone" in n || "mac" in n || "apple" in manuf -> "Apple"
            "samsung" in n || "android" in n -> "Android"
            "tv" in n || "roku" in n || "tv" in uuids.orEmpty().lowercase() -> "TV"
            "watch" in n || "band" in n -> "Wearable"
            else -> m ?: "Unknown"
        }
    }
}