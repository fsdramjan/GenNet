package com.apptrack.app

import android.app.AppOpsManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.app.usage.NetworkStats
import android.app.usage.NetworkStatsManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import java.util.concurrent.atomic.AtomicBoolean

class AppTrackUsageService : Service() {

    private val running = AtomicBoolean(false)

    private var worker: Thread? = null

    private var selectedPackages: List<String> = emptyList()

    private var sessionStartWallTime = 0L

override fun onCreate() {
    super.onCreate()

    Log.i(TAG, "========== AppTrackUsageService CREATED ==========")

    createNotificationChannel()
}

override fun onStartCommand(
    intent: Intent?,
    flags: Int,
    startId: Int
): Int {

    Log.i(
        TAG,
        "========== onStartCommand action=${intent?.action} =========="
    )

    when (intent?.action) {

        ACTION_STOP -> {
            Log.i(TAG, "ACTION_STOP received")

            stopMonitoring()
            stopSelf()

            return START_NOT_STICKY
        }

        ACTION_START -> {

            val packages =
                intent
                    .getStringArrayListExtra(EXTRA_PACKAGES)
                    .orEmpty()

            Log.i(
                TAG,
                "ACTION_START received packages=$packages"
            )

            startMonitoring(packages)
        }

        else -> {
            Log.w(
                TAG,
                "Unknown/null service action=${intent?.action}"
            )
        }
    }

    return START_STICKY
}

private fun startMonitoring(
    packages: List<String>
) {

    Log.i(
        TAG,
        "========== startMonitoring() packages=$packages =========="
    )

    stopMonitoring()

    selectedPackages =
        packages
            .distinct()
            .filter { it.isNotBlank() }
            .filter { it != packageName }

    Log.i(
        TAG,
        "selectedPackages=$selectedPackages"
    )

    if (selectedPackages.isEmpty()) {
        Log.w(TAG, "No packages selected")
        return
    }

    if (!hasUsageAccess()) {

        Log.e(
            TAG,
            "PACKAGE_USAGE_STATS permission is NOT granted"
        )

        return
    }

    Log.i(TAG, "Usage access is granted")

    startForeground(
        NOTIFICATION_ID,
        buildNotification()
    )

    Log.i(TAG, "Foreground service started")

    AppUsageStore.clear()

    sessionStartWallTime =
        System.currentTimeMillis()

    Log.i(
        TAG,
        "sessionStartWallTime=$sessionStartWallTime"
    )

    running.set(true)

    worker =
        Thread(
            {
                Log.i(
                    TAG,
                    "AppTrackUsageWorker thread STARTED"
                )

                monitorLoop()

                Log.i(
                    TAG,
                    "AppTrackUsageWorker thread STOPPED"
                )
            },
            "AppTrackUsageWorker"
        ).also {
            it.start()
        }

    Log.i(
        TAG,
        "App usage monitor started for packages=$selectedPackages"
    )
}
    private fun monitorLoop() {

        Log.i(
            TAG,
            "monitorLoop started"
        )

        while (running.get()) {

            try {

                updateUsage()

            } catch (e: SecurityException) {

                Log.e(
                    TAG,
                    "NetworkStats SecurityException",
                    e
                )

            } catch (e: Exception) {

                Log.e(
                    TAG,
                    "Usage monitor error",
                    e
                )
            }

            try {

                Thread.sleep(1000L)

            } catch (_: InterruptedException) {

                Log.i(
                    TAG,
                    "monitorLoop interrupted"
                )

                break
            }
        }

        Log.i(
            TAG,
            "monitorLoop stopped"
        )
    }

    private fun updateUsage() {

        val pm = packageManager

        Log.d(
            TAG,
            "Polling ${selectedPackages.size} package(s)"
        )

        for (pkg in selectedPackages) {

            try {

                val appInfo =
                    pm.getApplicationInfo(
                        pkg,
                        0
                    )

                val uid =
                    appInfo.uid

                val appName =
                    pm.getApplicationLabel(
                        appInfo
                    ).toString()

                Log.d(
                    TAG,
                    "Querying package=$pkg uid=$uid name=$appName"
                )

                val usage =
                    queryUidUsage(
                        uid
                    )

                val rxBytes =
                    usage.first

                val txBytes =
                    usage.second

                Log.i(
                    TAG,
                    "RESULT package=$pkg uid=$uid RX=$rxBytes TX=$txBytes"
                )

                AppUsageStore.update(
                    packageName = pkg,
                    appName = appName,
                    uid = uid,
                    rxBytes = rxBytes,
                    txBytes = txBytes
                )

            } catch (
                e: PackageManager.NameNotFoundException
            ) {

                Log.e(
                    TAG,
                    "Package not found: $pkg",
                    e
                )

            } catch (e: Exception) {

                Log.e(
                    TAG,
                    "Could not read usage for $pkg",
                    e
                )
            }
        }
    }

    private fun queryUidUsage(
        uid: Int
    ): Pair<Long, Long> {

        val manager =
            getSystemService(
                Context.NETWORK_STATS_SERVICE
            ) as NetworkStatsManager

        var rx = 0L
        var tx = 0L

        val now =
            System.currentTimeMillis()

        Log.d(
            TAG,
            "NetworkStats query uid=$uid from=$sessionStartWallTime to=$now"
        )

        /*
         * Wi-Fi
         */
        try {

            Log.d(
                TAG,
                "Query WIFI uid=$uid"
            )

            val stats =
                manager.queryDetailsForUid(
                    ConnectivityManager.TYPE_WIFI,
                    null,
                    sessionStartWallTime,
                    now,
                    uid
                )

            val result =
                readStats(
                    stats,
                    "WIFI",
                    uid
                )

            rx += result.first
            tx += result.second

        } catch (e: SecurityException) {

            Log.e(
                TAG,
                "WIFI SecurityException uid=$uid",
                e
            )

        } catch (e: Exception) {

            Log.e(
                TAG,
                "WIFI query failed uid=$uid: ${e.message}",
                e
            )
        }

        /*
         * Mobile
         */
        try {

            Log.d(
                TAG,
                "Query MOBILE uid=$uid"
            )

            val stats =
                manager.queryDetailsForUid(
                    ConnectivityManager.TYPE_MOBILE,
                    null,
                    sessionStartWallTime,
                    now,
                    uid
                )

            val result =
                readStats(
                    stats,
                    "MOBILE",
                    uid
                )

            rx += result.first
            tx += result.second

        } catch (e: SecurityException) {

            Log.e(
                TAG,
                "MOBILE SecurityException uid=$uid",
                e
            )

        } catch (e: Exception) {

            Log.e(
                TAG,
                "MOBILE query failed uid=$uid: ${e.message}",
                e
            )
        }

        Log.d(
            TAG,
            "TOTAL uid=$uid RX=$rx TX=$tx"
        )

        return Pair(
            rx,
            tx
        )
    }

    private fun readStats(
        stats: NetworkStats,
        type: String,
        uid: Int
    ): Pair<Long, Long> {

        var rx = 0L
        var tx = 0L
        var bucketCount = 0

        val bucket =
            NetworkStats.Bucket()

        try {

            while (
                stats.hasNextBucket()
            ) {

                stats.getNextBucket(
                    bucket
                )

                bucketCount++

                rx += bucket.rxBytes
                tx += bucket.txBytes

                Log.d(
                    TAG,
                    "$type bucket uid=$uid " +
                        "uid=${bucket.uid} " +
                        "rx=${bucket.rxBytes} " +
                        "tx=${bucket.txBytes}"
                )
            }

        } finally {

            try {
                stats.close()
            } catch (_: Exception) {
            }
        }

        Log.d(
            TAG,
            "$type finished uid=$uid buckets=$bucketCount rx=$rx tx=$tx"
        )

        return Pair(
            rx,
            tx
        )
    }

    private fun hasUsageAccess(): Boolean {

        val appOps =
            getSystemService(
                Context.APP_OPS_SERVICE
            ) as AppOpsManager

        val mode =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {

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

        Log.i(
            TAG,
            "hasUsageAccess mode=$mode"
        )

        return mode ==
            AppOpsManager.MODE_ALLOWED
    }

    private fun buildNotification() =
        NotificationCompat.Builder(
            this,
            CHANNEL_ID
        )
            .setSmallIcon(
                android.R.drawable.stat_sys_download
            )
            .setContentTitle(
                "AppTrack is monitoring"
            )
            .setContentText(
                "Monitoring selected app network usage"
            )
            .setOngoing(true)
            .setCategory(
                NotificationCompat.CATEGORY_SERVICE
            )
            .build()

    private fun createNotificationChannel() {

        if (
            Build.VERSION.SDK_INT >=
            Build.VERSION_CODES.O
        ) {

            val manager =
                getSystemService(
                    NotificationManager::class.java
                )

            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    "AppTrack monitor",
                    NotificationManager.IMPORTANCE_LOW
                )
            )
        }
    }

    private fun stopMonitoring() {

        running.set(false)

        worker?.interrupt()
        worker = null

        AppUsageStore.clear()

        if (
            Build.VERSION.SDK_INT >=
            Build.VERSION_CODES.N
        ) {

            stopForeground(
                STOP_FOREGROUND_REMOVE
            )

        } else {

            @Suppress("DEPRECATION")
            stopForeground(true)
        }

        Log.i(
            TAG,
            "App usage monitor stopped"
        )
    }

    override fun onDestroy() {

        Log.i(
            TAG,
            "AppTrackUsageService destroyed"
        )

        stopMonitoring()

        super.onDestroy()
    }

    override fun onBind(
        intent: Intent?
    ): IBinder? = null

    companion object {

        const val ACTION_START =
            "com.apptrack.app.action.START_USAGE"

        const val ACTION_STOP =
            "com.apptrack.app.action.STOP_USAGE"

        const val EXTRA_PACKAGES =
            "packages"

        private const val CHANNEL_ID =
            "apptrack_usage"

        private const val NOTIFICATION_ID =
            42

        private const val TAG =
            "AppTrackUsage"
    }
}