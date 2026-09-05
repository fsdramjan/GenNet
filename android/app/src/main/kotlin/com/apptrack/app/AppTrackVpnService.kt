package com.apptrack.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import android.util.Log
import androidx.core.app.NotificationCompat
import java.io.File
import java.util.concurrent.atomic.AtomicBoolean

class AppTrackVpnService : VpnService() {

    companion object {

        const val ACTION_START =
            "com.apptrack.app.action.START_VPN"

        const val ACTION_STOP =
            "com.apptrack.app.action.STOP_VPN"

        const val EXTRA_PACKAGES =
            "packages"

        private const val TAG =
            "AppTrackVPN"

        private const val CHANNEL_ID =
            "apptrack_vpn"

        private const val NOTIFICATION_ID =
            43

        // Matches PCAPdroid's proven-working value.
        private const val MTU =
            10000

        private const val VPN_IPV4 =
            "10.8.0.2"

        // /30 matches PCAPdroid's real, working configuration
        // (a proper point-to-point subnet, not a bare /32).
        private const val VPN_IPV4_PREFIX =
            30

        private const val SOCKS5_CONFIG_FILE =
            "apptrack-socks5.yml"

        private const val SOCKS5_LOG_FILE =
            "hev-socks5-server-debug.log"
    }

    private var vpnInterface:
        ParcelFileDescriptor? = null

    @Volatile
    private var vpnRunning =
        false

    @Volatile
    private var relayRunning =
        false

    @Volatile
    private var socks5Running =
        false

    @Volatile
    private var monitoredPackages:
        List<String> =
        emptyList()

    private var socks5ConfigFile:
        File? = null

    private val starting =
        AtomicBoolean(false)

    // ============================================================
    // CREATE
    // ============================================================

    override fun onCreate() {

        super.onCreate()

        Log.i(TAG, "========== AppTrackVpnService CREATED ==========")

        createNotificationChannel()

        startForeground(
            NOTIFICATION_ID,
            buildNotification()
        )
    }

    // ============================================================
    // START COMMAND
    // ============================================================

    override fun onStartCommand(
        intent: Intent?,
        flags: Int,
        startId: Int
    ): Int {

        when (intent?.action) {

            ACTION_START -> {

                val packages =
                    intent
                        .getStringArrayListExtra(EXTRA_PACKAGES)
                        .orEmpty()
                        .distinct()
                        .filter { it.isNotBlank() }
                        .filter { it != packageName }

                Log.i(TAG, "START packages=$packages")

                if (packages.isEmpty()) {
                    Log.e(TAG, "No packages selected")
                    return START_NOT_STICKY
                }

                if (
                    vpnRunning &&
                    relayRunning &&
                    socks5Running &&
                    monitoredPackages == packages
                ) {
                    Log.i(TAG, "========== VPN ALREADY RUNNING ==========")
                    return START_STICKY
                }

                if (!starting.compareAndSet(false, true)) {
                    Log.w(TAG, "VPN startup already in progress")
                    return START_STICKY
                }

                Thread(
                    {
                        try {
                            startVpn(packages)
                        } catch (e: Throwable) {
                            Log.e(TAG, "Background VPN startup failed", e)
                            stopVpn()
                        } finally {
                            starting.set(false)
                        }
                    },
                    "AppTrack-VPN-Start"
                ).start()

                return START_STICKY
            }

            ACTION_STOP -> {

                Log.i(TAG, "========== STOP REQUESTED ==========")

                Thread(
                    {
                        try {
                            stopVpn()
                        } finally {
                            try {
                                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                                    stopForeground(STOP_FOREGROUND_REMOVE)
                                } else {
                                    @Suppress("DEPRECATION")
                                    stopForeground(true)
                                }
                            } catch (e: Throwable) {
                                Log.w(TAG, "stopForeground failed", e)
                            }

                            stopSelf()
                            Log.i(TAG, "stopSelf() called")
                        }
                    },
                    "AppTrack-VPN-Stop"
                ).start()

                return START_NOT_STICKY
            }

            else -> {
                Log.w(TAG, "Unknown action=${intent?.action}")
                return START_NOT_STICKY
            }
        }
    }

    // ============================================================
    // START VPN
    // ============================================================

    private fun startVpn(
        packages: List<String>
    ) {

        Log.i(TAG, "========== STARTING VPN ==========")

        stopVpn()

        monitoredPackages = packages

        try {

            val builder =
                Builder()
                    .setSession("AppTrack Local Monitor")
                    .setMtu(MTU)
                    .setBlocking(false)

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                builder.setMetered(false)
            }

            builder.addAddress(VPN_IPV4, VPN_IPV4_PREFIX)

            // Split default route (PCAPdroid / WireGuard-Android pattern) --
            // a single addRoute("0.0.0.0", 0) can silently fail to install
            // as the per-UID default route on some Android builds.
            builder.addRoute("0.0.0.0", 1)
            builder.addRoute("128.0.0.0", 1)

            Log.i(TAG, "IPv4 route configured: 0.0.0.0/1 + 128.0.0.0/1")

            builder.addDnsServer("1.1.1.1")
            builder.addDnsServer("8.8.8.8")

            Log.i(TAG, "DNS configured: 1.1.1.1, 8.8.8.8")

            // Per-app filtering (real, production mode -- diagnostic
            // global-VPN bypass has been removed now that the real
            // fix -- our own TcpIpRelay -- is in place).
            var allowedCount = 0

            for (pkg in packages) {
                try {
                    builder.addAllowedApplication(pkg)
                    allowedCount++
                    Log.i(TAG, "Allowed app=$pkg")
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to allow app=$pkg", e)
                }
            }

            Log.i(TAG, "Allowed application count=$allowedCount")

            if (allowedCount == 0) {
                Log.e(TAG, "No valid allowed applications")
                monitoredPackages = emptyList()
                return
            }

            val tun = builder.establish()

            if (tun == null) {
                Log.e(TAG, "VPN establish returned NULL")
                monitoredPackages = emptyList()
                return
            }

            vpnInterface = tun
            vpnRunning = true

            FlowStore.clear()
            AppUsageStore.clear()

            Log.i(TAG, "========== VPN ESTABLISHED ==========")
            Log.i(TAG, "TUN fd=${tun.fd}")

            if (!startSocks5Server()) {
                Log.e(TAG, "SOCKS5 start failed")
                stopVpn()
                return
            }

            // Resolved once here and captured by the relay thread's
            // closure below -- passed explicitly into every handlePacket()
            // call rather than stored on a shared field, to avoid any
            // possible cross-thread visibility issue.
            val connectivityManager =
                getSystemService(android.net.ConnectivityManager::class.java)

            startRelay(tun, connectivityManager)

            if (!vpnRunning || !socks5Running || !relayRunning) {
                Log.e(TAG, "VPN components are not all running")
                stopVpn()
                return
            }

            Log.i(TAG, "========== AppTrack VPN READY ==========")
            Log.i(TAG, "Traffic path:")
            Log.i(TAG, "Selected App")
            Log.i(TAG, "    -> Android TUN")
            Log.i(TAG, "    -> TcpIpRelay (our own, in-process, resolves owning app per connection)")
            Log.i(TAG, "    -> local SOCKS5 127.0.0.1:1080")
            Log.i(TAG, "    -> Internet")

        } catch (e: Throwable) {
            Log.e(TAG, "========== VPN START FAILED ==========", e)
            stopVpn()
        }
    }

    // ============================================================
    // RELAY: real TUN <-> TcpIpRelay
    // ============================================================

    private fun startRelay(
        tun: ParcelFileDescriptor,
        connectivityManager: android.net.ConnectivityManager?
    ) {

        // TcpIpRelay writes response packets back through this callback.
        TcpIpRelay.writeToTun = { buf, len ->
            try {
                val out = java.io.FileOutputStream(tun.fileDescriptor)
                out.write(buf, 0, len)
            } catch (e: Throwable) {
                Log.w(TAG, "writeToTun failed", e)
            }
        }

        relayRunning = true

        Thread(
            {
                Log.i(TAG, "========== RELAY: TUN read loop started ==========")

                val input = java.io.FileInputStream(tun.fileDescriptor)
                val buffer = ByteArray(MTU + 64)
                var packets = 0L

                while (relayRunning) {

                    val n = try {
                        input.read(buffer)
                    } catch (e: java.io.IOException) {
                        -1
                    }

                    if (n > 0) {
                        packets++
                        TcpIpRelay.handlePacket(buffer.copyOf(n), n, connectivityManager)

                        if (packets % 200L == 0L) {
                            Log.i(TAG, "RELAY: TUN read packets=$packets")
                        }
                    } else {
                        Thread.sleep(1L)
                    }
                }

                Log.i(TAG, "========== RELAY: TUN read loop stopped, total=$packets ==========")
            },
            "AppTrack-Relay-TunRead"
        ).start()
    }

    private fun stopRelay() {
        relayRunning = false
        TcpIpRelay.writeToTun = null
        TcpIpRelay.reset()
    }

    // ============================================================
    // SOCKS5 SERVER
    // ============================================================

    private fun startSocks5Server(): Boolean {

        if (socks5Running) {
            Log.i(TAG, "SOCKS5 already running")
            return true
        }

        val configFile = File(cacheDir, SOCKS5_CONFIG_FILE)

        return try {

            if (isSocks5PortOpen()) {

                Log.i(TAG, "Previous SOCKS5 instance detected, stopping it first")

                try {
                    startService(
                        Intent(this, Socks5ProcessService::class.java)
                            .setAction(Socks5ProcessService.ACTION_STOP)
                    )
                } catch (e: Throwable) {
                    Log.w(TAG, "Previous SOCKS5 stop failed", e)
                }

                Thread.sleep(300L)
            }

            val config =
                """
main:
  workers: 16
  port: 1080
  listen-address: '127.0.0.1'
  listen-ipv6-only: false
  domain-address-type: unspec

misc:
  connect-timeout: 10000
  tcp-read-write-timeout: 300000
  log-file: '${cacheDir.absolutePath}/$SOCKS5_LOG_FILE'
  log-level: debug
  limit-nofile: 65535
                """.trimIndent()

            configFile.writeText(config)
            socks5ConfigFile = configFile

            Log.i(TAG, "========== SOCKS5 CONFIG (isolated process) ==========")
            Log.i(TAG, config)

            startService(
                Intent(this, Socks5ProcessService::class.java)
                    .setAction(Socks5ProcessService.ACTION_START)
                    .putExtra(Socks5ProcessService.EXTRA_CONFIG_PATH, configFile.absolutePath)
            )

            val deadline = System.currentTimeMillis() + 5000L

            while (System.currentTimeMillis() < deadline) {

                val open = isSocks5PortOpen()
                Log.i(TAG, "SOCKS5 port 1080 open=$open")

                if (open) {
                    socks5Running = true
                    Log.i(TAG, "========== SOCKS5 SERVER READY (isolated process) ==========")
                    return true
                }

                Thread.sleep(30L)
            }

            socks5Running = false
            Log.e(TAG, "========== SOCKS5 SERVER FAILED TO START ==========")
            false

        } catch (e: Throwable) {
            socks5Running = false
            Log.e(TAG, "Could not start SOCKS5", e)
            false
        }
    }

    private fun isSocks5PortOpen(): Boolean {
        return try {
            java.net.Socket().use { socket ->
                socket.connect(java.net.InetSocketAddress("127.0.0.1", 1080), 300)
            }
            true
        } catch (e: Throwable) {
            false
        }
    }

    private fun stopSocks5Server() {

        try {
            Log.i(TAG, "Stopping SOCKS5 (isolated process)")
            startService(
                Intent(this, Socks5ProcessService::class.java)
                    .setAction(Socks5ProcessService.ACTION_STOP)
            )
        } catch (e: Throwable) {
            Log.e(TAG, "SOCKS5 stop error", e)
        }

        socks5Running = false
    }

    // ============================================================
    // STOP VPN
    // ============================================================

    private fun stopVpn() {

        Log.i(TAG, "========== STOP VPN ==========")

        vpnRunning = false
        relayRunning = false
        socks5Running = false

        stopRelay()
        stopSocks5Server()

        val oldTun = vpnInterface
        vpnInterface = null

        try {
            oldTun?.close()
            Log.i(TAG, "TUN closed")
        } catch (e: Exception) {
            Log.w(TAG, "TUN close error", e)
        }

        try { socks5ConfigFile?.delete() } catch (_: Exception) {}
        socks5ConfigFile = null
        monitoredPackages = emptyList()

        FlowCollector.stop()
        FlowStore.clear()
        AppUsageStore.clear()

        Log.i(TAG, "VPN stopped")
    }

    // ============================================================
    // NOTIFICATION
    // ============================================================

    private fun buildNotification(): Notification {

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentTitle("AppTrack VPN monitor")
            .setContentText("Monitoring selected application traffic")
            .setOngoing(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    private fun createNotificationChannel() {

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {

            val manager = getSystemService(NotificationManager::class.java)

            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    "AppTrack VPN",
                    NotificationManager.IMPORTANCE_LOW
                )
            )
        }
    }

    // ============================================================
    // VPN REVOKED / DESTROY
    // ============================================================

    override fun onRevoke() {
        Log.i(TAG, "VPN permission revoked")
        stopVpn()
        super.onRevoke()
    }

    override fun onDestroy() {

        Log.i(TAG, "========== AppTrackVpnService DESTROYED ==========")

        stopVpn()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }

        super.onDestroy()
    }
}