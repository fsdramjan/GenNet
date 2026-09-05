package com.apptrack.app

import android.app.AppOpsManager
import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Log
import hev.htproxy.TProxyService
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {

    private val methodChannelName =
        "apptrack/monitor"

    private val eventChannelName =
        "apptrack/monitor/events"

    private var eventSink:
        EventChannel.EventSink? = null

    private val snapshotHandler =
        Handler(
            Looper.getMainLooper()
        )

    private var snapshotRunnable:
        Runnable? = null

    private var pendingVpnPackages:
        ArrayList<String>? = null

    override fun configureFlutterEngine(
        flutterEngine: FlutterEngine
    ) {

        super.configureFlutterEngine(
            flutterEngine
        )

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            methodChannelName
        ).setMethodCallHandler { call, result ->

            when (call.method) {

                // ---------------------------------------------------------
                // INSTALLED APPS
                // ---------------------------------------------------------

                "listInstalledApps" -> {

                    Thread {

                        try {

                            val apps =
                                listInstalledApps()

                            runOnUiThread {

                                result.success(
                                    apps
                                )
                            }

                        } catch (e: Exception) {

                            runOnUiThread {

                                result.error(
                                    "APP_LIST_ERROR",
                                    e.message
                                        ?: "Failed to list installed apps",
                                    null
                                )
                            }
                        }

                    }.start()
                }

                // ---------------------------------------------------------
                // START SESSION
                // ---------------------------------------------------------

                "startSession" -> {

                    val packages =
                        call.argument<List<String>>(
                            "packages"
                        ) ?: emptyList()

                    result.success(
                        startSession(
                            packages
                        )
                    )
                }

                // ---------------------------------------------------------
                // STOP SESSION
                // ---------------------------------------------------------

                "stopSession" -> {

                    stopSession()

                    result.success(
                        null
                    )
                }

                // ---------------------------------------------------------
                // VPN PERMISSION
                // ---------------------------------------------------------

                "hasVpnPermission" -> {

                    result.success(
                        hasVpnPermission()
                    )
                }

                "openVpnPermission" -> {

                    openVpnPermission()

                    result.success(
                        null
                    )
                }

                // ---------------------------------------------------------
                // USAGE ACCESS
                // ---------------------------------------------------------

                "hasUsageAccess" -> {

                    result.success(
                        hasUsageAccess()
                    )
                }

                "openUsageAccessSettings" -> {

                    startActivity(
                        Intent(
                            Settings.ACTION_USAGE_ACCESS_SETTINGS
                        )
                    )

                    result.success(
                        null
                    )
                }

                // ---------------------------------------------------------
                // FLOW SNAPSHOT
                // ---------------------------------------------------------

                "getFlowSnapshot" -> {

                    Thread {

                        try {

                            val flows =
                                readHevFlows()

                            runOnUiThread {

                                result.success(
                                    flows
                                )
                            }

                        } catch (e: Throwable) {

                            Log.e(
                                TAG,
                                "Failed to get flow snapshot",
                                e
                            )

                            runOnUiThread {

                                result.error(
                                    "FLOW_ERROR",
                                    e.message
                                        ?: "Failed to read flows",
                                    null
                                )
                            }
                        }

                    }.start()
                }

                // ---------------------------------------------------------
                // UNIQUE DESTINATION IPS
                // ---------------------------------------------------------

                "getUniqueDestinationIps" -> {

                    try {

                        val ips =
                            readHevFlows()
                                .mapNotNull {

                                    it[
                                        "destinationIp"
                                    ] as? String
                                }
                                .distinct()

                        result.success(
                            ips
                        )

                    } catch (e: Throwable) {

                        Log.e(
                            TAG,
                            "Failed to get destination IPs",
                            e
                        )

                        result.error(
                            "FLOW_IP_ERROR",
                            e.message
                                ?: "Failed to read destination IPs",
                            null
                        )
                    }
                }

                // ---------------------------------------------------------
                // DIAGNOSTIC: TUN INTERFACE STATS (from /proc/net/dev)
                // ---------------------------------------------------------
                //
                // Reads the same information as `adb shell cat /proc/net/dev`
                // directly on-device, so RX/TX packet counts for the tun
                // interface can be checked without a PC/adb connection.
                // No special permission needed -- /proc/net/dev is
                // world-readable.

                "getTunStats" -> {

                    try {

                        result.success(
                            readTunStats()
                        )

                    } catch (e: Throwable) {

                        Log.e(
                            TAG,
                            "Failed to read tun stats",
                            e
                        )

                        result.error(
                            "TUN_STATS_ERROR",
                            e.message
                                ?: "Failed to read /proc/net/dev",
                            null
                        )
                    }
                }

                // ---------------------------------------------------------
                // FLOATING OVERLAY (PIP-style live traffic panel)
                // ---------------------------------------------------------

                "hasOverlayPermission" -> {

                    result.success(
                        hasOverlayPermission()
                    )
                }

                "openOverlayPermission" -> {

                    openOverlayPermission()

                    result.success(
                        null
                    )
                }

                "startOverlay" -> {

                    if (!hasOverlayPermission()) {

                        result.error(
                            "OVERLAY_PERMISSION_REQUIRED",
                            "Draw-over-other-apps permission not granted",
                            null
                        )

                    } else {

                        try {

                            startService(
                                Intent(
                                    this,
                                    OverlayService::class.java
                                ).apply {
                                    action = OverlayService.ACTION_START
                                }
                            )

                            result.success(
                                null
                            )

                        } catch (e: Throwable) {

                            Log.e(
                                TAG,
                                "Failed to start overlay",
                                e
                            )

                            result.error(
                                "OVERLAY_START_ERROR",
                                e.message
                                    ?: "Failed to start overlay",
                                null
                            )
                        }
                    }
                }

                "stopOverlay" -> {

                    try {

                        startService(
                            Intent(
                                this,
                                OverlayService::class.java
                            ).apply {
                                action = OverlayService.ACTION_STOP
                            }
                        )

                    } catch (e: Throwable) {

                        Log.w(
                            TAG,
                            "Failed to stop overlay",
                            e
                        )
                    }

                    result.success(
                        null
                    )
                }

                // ---------------------------------------------------------
                // UNKNOWN METHOD
                // ---------------------------------------------------------

                else -> {

                    result.notImplemented()
                }
            }
        }

        // -------------------------------------------------------------
        // EVENT CHANNEL
        // -------------------------------------------------------------

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            eventChannelName
        ).setStreamHandler(
            object :
                EventChannel.StreamHandler {

                override fun onListen(
                    arguments: Any?,
                    sink: EventChannel.EventSink?
                ) {

                    eventSink =
                        sink

                    startSnapshotLoop()

                    Log.d(
                        TAG,
                        "AppTrack event stream attached"
                    )
                }

                override fun onCancel(
                    arguments: Any?
                ) {

                    eventSink =
                        null

                    stopSnapshotLoop()

                    Log.d(
                        TAG,
                        "AppTrack event stream detached"
                    )
                }
            }
        )
    }

    // =====================================================================
    // DIAGNOSTIC: TUN STATS
    // =====================================================================

    /**
     * Parses /proc/net/dev and returns every interface whose name starts
     * with "tun" (there can be more than one across the device's history,
     * e.g. tun0, tun1 -- Android increments the number each time a NEW
     * VPN interface is created, it does not reuse tun0).
     *
     * Returns a list of maps: [{"name": "tun1", "rxBytes": ..,
     * "rxPackets": .., "txBytes": .., "txPackets": ..}, ...]
     */
    private fun readTunStats(): List<Map<String, Any>> {

        val results = mutableListOf<Map<String, Any>>()

        val file = File("/proc/net/dev")

        if (!file.exists()) {
            return results
        }

        file.forEachLine { rawLine ->

            val line = rawLine.trim()

            val colonIndex = line.indexOf(':')
            if (colonIndex <= 0) return@forEachLine

            val name = line.substring(0, colonIndex).trim()
            if (!name.startsWith("tun")) return@forEachLine

            val fields = line.substring(colonIndex + 1)
                .trim()
                .split(Regex("\\s+"))

            // /proc/net/dev columns (Receive then Transmit):
            // bytes packets errs drop fifo frame compressed multicast |
            // bytes packets errs drop fifo colls carrier compressed
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

    // =====================================================================
    // VPN SESSION
    // =====================================================================

    private fun startSession(
        packages: List<String>
    ): String {

        val filtered =
            packages
                .distinct()
                .filter {
                    it.isNotBlank()
                }
                .filter {
                    it != packageName
                }

        if (filtered.isEmpty()) {

            return "empty"
        }

        val prepareIntent =
            VpnService.prepare(
                this
            )

        if (prepareIntent != null) {

            pendingVpnPackages =
                ArrayList(
                    filtered
                )

            Log.i(
                TAG,
                "VPN permission required"
            )

            startActivityForResult(
                prepareIntent,
                VPN_PERMISSION_REQUEST
            )

            return "vpn_permission_required"
        }

        startVpnService(
            filtered
        )

        return "started"
    }

    private fun openVpnPermission() {

        val intent =
            VpnService.prepare(
                this
            )

        if (intent != null) {

            startActivityForResult(
                intent,
                VPN_PERMISSION_REQUEST
            )

        } else {

            Log.i(
                TAG,
                "VPN permission already granted"
            )
        }
    }

    private fun startVpnService(
        packages: List<String>
    ) {

        if (packages.isEmpty()) {

            return
        }

        val intent =
            Intent(
                this,
                AppTrackVpnService::class.java
            ).apply {

                action =
                    AppTrackVpnService.ACTION_START

                putStringArrayListExtra(
                    AppTrackVpnService.EXTRA_PACKAGES,
                    ArrayList(
                        packages
                    )
                )
            }

        try {

            if (
                Build.VERSION.SDK_INT >=
                Build.VERSION_CODES.O
            ) {

                startForegroundService(
                    intent
                )

            } else {

                startService(
                    intent
                )
            }

            Log.i(
                TAG,
                "VPN service start requested packages=$packages"
            )

        } catch (e: Exception) {

            Log.e(
                TAG,
                "Failed to start VPN service",
                e
            )
        }
    }

    private fun stopSession() {

        pendingVpnPackages =
            null

        val intent =
            Intent(
                this,
                AppTrackVpnService::class.java
            ).apply {

                action =
                    AppTrackVpnService.ACTION_STOP
            }

        try {

            startService(
                intent
            )

        } catch (e: Exception) {

            Log.e(
                TAG,
                "Failed to stop VPN service",
                e
            )
        }

        try {

            startService(
                Intent(
                    this,
                    OverlayService::class.java
                ).apply {
                    action = OverlayService.ACTION_STOP
                }
            )

        } catch (e: Throwable) {

            Log.w(
                TAG,
                "Failed to stop overlay",
                e
            )
        }

        FlowStore.clear()

        AppUsageStore.clear()
    }

    // =====================================================================
    // VPN PERMISSION
    // =====================================================================

    private fun hasVpnPermission():
        Boolean {

        return try {

            VpnService.prepare(
                this
            ) == null

        } catch (e: Exception) {

            Log.e(
                TAG,
                "VPN permission check failed",
                e
            )

            false
        }
    }

    // =====================================================================
    // ACTIVITY RESULT
    // =====================================================================

    @Deprecated(
        "Deprecated in Java"
    )
    override fun onActivityResult(
        requestCode: Int,
        resultCode: Int,
        data: Intent?
    ) {

        super.onActivityResult(
            requestCode,
            resultCode,
            data
        )

        if (
            requestCode !=
            VPN_PERMISSION_REQUEST
        ) {

            return
        }

        val packages =
            pendingVpnPackages

        pendingVpnPackages =
            null

        if (
            resultCode ==
            RESULT_OK
        ) {

            Log.i(
                TAG,
                "VPN permission granted"
            )

            if (
                packages != null &&
                packages.isNotEmpty()
            ) {

                startVpnService(
                    packages
                )
            }

        } else {

            Log.w(
                TAG,
                "VPN permission denied"
            )
        }
    }

    // =====================================================================
    // LIVE SNAPSHOT LOOP
    // =====================================================================

    private fun startSnapshotLoop() {

        stopSnapshotLoop()

        val runnable =
            object :
                Runnable {

                override fun run() {

                    val sink =
                        eventSink

                    if (sink != null) {

                        try {

                            val flows =
                                readHevFlows()

                            sink.success(
                                flows
                            )

                        } catch (e: Throwable) {

                            Log.e(
                                TAG,
                                "HEV flow read failed",
                                e
                            )
                        }
                    }

                    snapshotHandler.postDelayed(
                        this,
                        500L
                    )
                }
            }

        snapshotRunnable =
            runnable

        snapshotHandler.post(
            runnable
        )
    }

    private fun stopSnapshotLoop() {

        snapshotRunnable?.let {

            snapshotHandler.removeCallbacks(
                it
            )
        }

        snapshotRunnable =
            null
    }

    // =====================================================================
    // HEV FLOWS
    // =====================================================================

    private fun readHevFlows(): List<Map<String, Any>> {
        val rawFlows = FlowStore.snapshot()

        val flows = rawFlows.mapNotNull { raw ->
            parseFlow(raw)
        }

        Log.i(
            TAG,
            "FlowStore raw=${rawFlows.size}, parsed=${flows.size}"
        )

        return flows
    }

    private fun valueFor(
        raw: Map<String, Any>,
        vararg names: String
    ): Any? {
        for (name in names) {
            raw[name]?.let { return it }
        }

        val normalized = raw.entries.associate {
            normalizeKey(it.key) to it.value
        }

        for (name in names) {
            normalized[normalizeKey(name)]?.let { return it }
        }

        return null
    }

    private fun normalizeKey(value: String): String {
        return value
            .trim()
            .lowercase()
            .replace("_", "")
            .replace("-", "")
    }

    private fun parseFlow(raw: Map<String, Any>): Map<String, Any>? {
        val ip = valueFor(
            raw,
            "destinationIp",
            "dstIp",
            "dst_ip",
            "destination_ip",
            "remoteIp",
            "remote_ip",
            "ip",
            "destination",
            "dst",
            "targetIp",
            "target_ip"
        )?.toString()?.trim().orEmpty()

        if (ip.isBlank()) {
            Log.w(TAG, "FLOW DROPPED: no destination IP. raw=$raw")
            return null
        }

        val port = when (val value = valueFor(
            raw,
            "destinationPort",
            "dstPort",
            "dst_port",
            "destination_port",
            "remotePort",
            "remote_port",
            "port",
            "targetPort",
            "target_port"
        )) {
            is Number -> value.toInt()
            else -> value?.toString()?.toIntOrNull() ?: 0
        }

        val protocolValue = valueFor(raw, "protocol", "proto", "transport", "type")
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

        val bytes = when (val value = valueFor(
            raw,
            "bytes",
            "byteCount",
            "byte_count",
            "size",
            "length",
            "rxBytes",
            "txBytes",
            "totalBytes",
            "total_bytes"
        )) {
            is Number -> value.toLong().coerceAtMost(Int.MAX_VALUE.toLong()).toInt()
            else -> value?.toString()?.toLongOrNull()
                ?.coerceAtMost(Int.MAX_VALUE.toLong())
                ?.toInt() ?: 0
        }

        val ipVersion = when (val value = valueFor(
            raw,
            "ipVersion",
            "ip_version",
            "version",
            "family"
        )) {
            is Number -> value.toInt()
            is String -> value.toIntOrNull() ?: if (ip.contains(":")) 6 else 4
            else -> if (ip.contains(":")) 6 else 4
        }

        val uid = when (val value = valueFor(raw, "uid", "userId", "user_id")) {
            is Number -> value.toInt()
            else -> value?.toString()?.toIntOrNull() ?: -1
        }

        val packetCount = when (val value = valueFor(
            raw,
            "packetCount",
            "packet_count",
            "packets"
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

    // =====================================================================
    // OVERLAY PERMISSION (draw over other apps)
    // =====================================================================

    private fun hasOverlayPermission(): Boolean {

        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {

            Settings.canDrawOverlays(this)

        } else {

            true
        }
    }

    private fun openOverlayPermission() {

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {

            startActivity(
                Intent(
                    Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                    android.net.Uri.parse(
                        "package:$packageName"
                    )
                )
            )
        }
    }

    // =====================================================================
    // USAGE ACCESS
    // =====================================================================

    private fun hasUsageAccess():
        Boolean {

        val appOps =
            getSystemService(
                Context.APP_OPS_SERVICE
            ) as AppOpsManager

        val mode =
            if (
                Build.VERSION.SDK_INT >=
                Build.VERSION_CODES.Q
            ) {

                appOps.unsafeCheckOpNoThrow(
                    AppOpsManager.OPSTR_GET_USAGE_STATS,
                    android.os.Process.myUid(),
                    packageName
                )

            } else {

                @Suppress(
                    "DEPRECATION"
                )
                appOps.checkOpNoThrow(
                    AppOpsManager.OPSTR_GET_USAGE_STATS,
                    android.os.Process.myUid(),
                    packageName
                )
            }

        return mode ==
            AppOpsManager.MODE_ALLOWED
    }

    // =====================================================================
    // INSTALLED APPS
    // =====================================================================

    private fun listInstalledApps():
        List<Map<String, Any>> {

        val pm =
            packageManager

        val launcherIntent =
            Intent(
                Intent.ACTION_MAIN
            ).addCategory(
                Intent.CATEGORY_LAUNCHER
            )

        val resolved =
            pm.queryIntentActivities(
                launcherIntent,
                0
            )

        val seen =
            LinkedHashSet<String>()

        val result =
            mutableListOf<Map<String, Any>>()

        for (
            info in resolved
        ) {

            val appInfo =
                info.activityInfo
                    .applicationInfo

            val pkg =
                appInfo.packageName

            if (
                pkg == packageName ||
                !seen.add(pkg)
            ) {

                continue
            }

            val label =
                try {

                    pm.getApplicationLabel(
                        appInfo
                    ).toString()

                } catch (
                    _: Exception
                ) {

                    pkg
                }

            // ---------------------------------------------------------
            // APP ICON
            // ---------------------------------------------------------

            val iconBytes =
                try {

                    val drawable =
                        pm.getApplicationIcon(
                            appInfo
                        )

                    val bitmap =
                        android.graphics.Bitmap.createBitmap(
                            96,
                            96,
                            android.graphics.Bitmap.Config.ARGB_8888
                        )

                    val canvas =
                        android.graphics.Canvas(
                            bitmap
                        )

                    drawable.setBounds(
                        0,
                        0,
                        96,
                        96
                    )

                    drawable.draw(
                        canvas
                    )

                    val stream =
                        java.io.ByteArrayOutputStream()

                    bitmap.compress(
                        android.graphics.Bitmap.CompressFormat.PNG,
                        100,
                        stream
                    )

                    bitmap.recycle()

                    stream.toByteArray()

                } catch (
                    e: Exception
                ) {

                    Log.w(
                        TAG,
                        "Icon failed for $pkg",
                        e
                    )

                    null
                }

            // ---------------------------------------------------------
            // APP DATA
            // ---------------------------------------------------------

            val app =
                mutableMapOf<String, Any>(

                    "packageName" to
                        pkg,

                    "appName" to
                        label,

                    "uid" to
                        appInfo.uid
                )

            if (
                iconBytes != null
            ) {

                app["icon"] =
                    iconBytes
            }

            result.add(
                app
            )
        }

        return result.sortedBy {

            (
                it["appName"]
                    as String
            ).lowercase()
        }
    }

    // =====================================================================
    // DESTROY
    // =====================================================================

    override fun onDestroy() {

        stopSnapshotLoop()

        eventSink =
            null

        pendingVpnPackages =
            null

        super.onDestroy()
    }

    // =====================================================================
    // AUTO-SHOW OVERLAY ON BACKGROUND
    // =====================================================================
    //
    // While a VPN monitoring session is running, show the floating panel
    // automatically the moment this app leaves the foreground (so the
    // user can immediately see live traffic while switching to the game/
    // app being monitored), and hide it again once they come back to
    // AppTrack itself (the in-app Traffic screen is the better view then).

    override fun onPause() {
        super.onPause()

        if (AppTrackVpnService.isRunning && hasOverlayPermission()) {

            try {
                startService(
                    Intent(
                        this,
                        OverlayService::class.java
                    ).apply {
                        action = OverlayService.ACTION_START
                    }
                )
            } catch (e: Throwable) {
                Log.w(TAG, "Auto-start overlay failed", e)
            }
        }
    }

    override fun onResume() {
        super.onResume()
        // The overlay is intentionally left running here -- it now has
        // its own close button, so it stays visible until the user
        // explicitly closes it (or the VPN session stops), rather than
        // disappearing just because AppTrack came back to the foreground.
    }

    // =====================================================================
    // CONSTANTS
    // =====================================================================

    companion object {

        private const val TAG =
            "AppTrackNative"

        private const val VPN_PERMISSION_REQUEST =
            7001
    }
}