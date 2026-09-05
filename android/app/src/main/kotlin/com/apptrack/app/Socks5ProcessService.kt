package com.apptrack.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import hev.socks5.Socks5Service

/**
 * Runs the local SOCKS5 relay (hev-socks5-server) in an ISOLATED process.
 *
 * WHY THIS EXISTS
 * ----------------
 * hev-socks5-server.so and hev-socks5-tunnel.so both statically link
 * their own copy of the same internal coroutine runtime (hev-task-system).
 * When both .so files are loaded into the SAME process/linker namespace,
 * their global symbols/state collide -- whichever one initializes SECOND
 * reliably kills the other's native worker thread within ~100-300ms.
 * This was confirmed by logs: TProxyIsRunning() flips true -> false right
 * as the other library's native init runs, regardless of start order.
 *
 * Running the SOCKS5 relay in its own process (declared with
 * android:process=":socks5" in AndroidManifest.xml) gives it a fully
 * separate address space, so there's no possibility of collision with
 * the tunnel running in AppTrackVpnService's process. The two components
 * still talk to each other exactly as before -- plain TCP loopback on
 * 127.0.0.1:1080 -- so nothing about the protocol changes.
 *
 * IMPORTANT: because this runs in a different OS process, AppTrackVpnService
 * can no longer call Socks5Service.isRunning() directly and get a meaningful
 * answer (that would just query a separate, never-started copy of the
 * native library in ITS OWN process). Readiness must be checked externally,
 * e.g. by attempting a TCP connect to 127.0.0.1:1080 from AppTrackVpnService.
 */
class Socks5ProcessService : Service() {

    companion object {

        const val ACTION_START =
            "com.apptrack.app.action.SOCKS5_START"

        const val ACTION_STOP =
            "com.apptrack.app.action.SOCKS5_STOP"

        const val EXTRA_CONFIG_PATH =
            "config_path"

        private const val TAG = "AppTrackSocks5Proc"

        private const val CHANNEL_ID = "apptrack_socks5"

        private const val NOTIFICATION_ID = 44
    }

    override fun onCreate() {
        super.onCreate()

        Log.i(TAG, "========== Socks5ProcessService CREATED (isolated process) ==========")

        createNotificationChannel()

        startForeground(
            NOTIFICATION_ID,
            buildNotification()
        )
    }

    override fun onStartCommand(
        intent: Intent?,
        flags: Int,
        startId: Int
    ): Int {

        when (intent?.action) {

            ACTION_START -> {

                val configPath =
                    intent.getStringExtra(EXTRA_CONFIG_PATH)

                if (configPath.isNullOrBlank()) {
                    Log.e(TAG, "No config path provided")
                    return START_NOT_STICKY
                }

                Thread(
                    {
                        try {

                            Log.i(TAG, "========== SOCKS5 (isolated process) START ==========")

                            try {
                                Socks5Service.stop()
                            } catch (e: Throwable) {
                                Log.w(TAG, "Previous SOCKS5 stop failed", e)
                            }

                            val result =
                                Socks5Service.start(configPath)

                            Log.i(TAG, "Socks5Service.start() returned=$result")

                            // Give the caller a moment, then log real state
                            // for debugging (isRunning() is meaningful HERE,
                            // inside this process).
                            Thread.sleep(200L)

                            Log.i(TAG, "Socks5Service.isRunning()=${Socks5Service.isRunning()}")

                        } catch (e: Throwable) {
                            Log.e(TAG, "SOCKS5 native error", e)
                        }
                    },
                    "AppTrack-Socks5Proc-Start"
                ).start()

                return START_STICKY
            }

            ACTION_STOP -> {

                Thread(
                    {
                        try {

                            /*
                             * Guard against a stale/redundant STOP
                             * landing right after a fresh START (race
                             * seen in logs: START -> STOPPED -> DESTROYED
                             * within ~20ms). If nothing is actually
                             * running, don't tear the service down --
                             * a START may be in flight or just completed.
                             */
                            if (!Socks5Service.isRunning()) {
                                Log.i(
                                    TAG,
                                    "ACTION_STOP: nothing running, ignoring (avoids killing a fresh start)"
                                )
                                return@Thread
                            }

                            Socks5Service.stop()

                            Log.i(TAG, "========== SOCKS5 (isolated process) STOPPED ==========")

                            stopForeground(true)
                            stopSelf()

                        } catch (e: Throwable) {

                            Log.e(TAG, "SOCKS5 stop error", e)
                        }
                    },
                    "AppTrack-Socks5Proc-Stop"
                ).start()

                return START_NOT_STICKY
            }

            else -> {
                return START_NOT_STICKY
            }
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun buildNotification(): Notification {

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentTitle("AppTrack relay")
            .setContentText("Local traffic relay running")
            .setOngoing(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    private fun createNotificationChannel() {

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {

            val manager =
                getSystemService(NotificationManager::class.java)

            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    "AppTrack relay",
                    NotificationManager.IMPORTANCE_LOW
                )
            )
        }
    }

    override fun onDestroy() {

        Log.i(TAG, "========== Socks5ProcessService DESTROYED ==========")

        try {
            Socks5Service.stop()
        } catch (_: Throwable) {
        }

        super.onDestroy()
    }
}