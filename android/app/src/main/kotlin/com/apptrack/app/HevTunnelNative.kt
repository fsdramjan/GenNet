package com.apptrack.app

import android.util.Log

object HevTunnelNative {

    private const val TAG = "AppTrackHev"

    init {
        System.loadLibrary("apptrack_native")
    }

    external fun start(
        config: String,
        tunFd: Int
    ): Int

    external fun stop()

    fun startAsync(
        config: String,
        tunFd: Int
    ) {

        Thread(
            {
                try {

                    val result =
                        start(
                            config,
                            tunFd
                        )

                    Log.i(
                        TAG,
                        "HEV start result=$result"
                    )

                } catch (e: Throwable) {

                    Log.e(
                        TAG,
                        "HEV tunnel failed",
                        e
                    )
                }
            },
            "AppTrackHevTunnel"
        ).start()
    }

    fun stopTunnel() {

        try {
            stop()
        } catch (e: Throwable) {
            Log.e(
                TAG,
                "HEV stop failed",
                e
            )
        }
    }
}