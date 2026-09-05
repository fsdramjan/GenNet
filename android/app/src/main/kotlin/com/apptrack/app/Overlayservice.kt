package com.apptrack.app

import android.app.Service
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.TextView
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors

/**
 * Floating overlay showing the most recent captured flows on top of
 * whatever app is in the foreground -- a simple, always-visible plain
 * list (no bubble/collapse system), matching Reqable's minimal look.
 *
 * Requires the "Display over other apps" permission
 * (Settings.canDrawOverlays). MainActivity's method channel handles
 * checking/requesting that permission and starting/stopping this
 * service (including automatically when the app itself is backgrounded
 * while a VPN session is running); this class only owns the floating
 * window itself.
 */
class OverlayService : Service() {

    companion object {
        const val ACTION_START = "com.apptrack.app.action.START_OVERLAY"
        const val ACTION_STOP = "com.apptrack.app.action.STOP_OVERLAY"

        private const val TAG = "AppTrackOverlay"
        private const val MAX_LINES = 14
        private const val REFRESH_MS = 700L

        private const val COLOR_BG = "#DD000000"
        private const val COLOR_TEXT = "#F0F0F0"
        private const val COLOR_CLOSE_BG = "#33FFFFFF"
    }

    private var windowManager: WindowManager? = null
    private var rootView: View? = null
    private var bodyText: TextView? = null

    private val handler = Handler(Looper.getMainLooper())
    private var updateRunnable: Runnable? = null

    // IP -> company/ISP name cache, so we only look up each destination
    // once per session (ipwho.is is free/no-key, but still worth not
    // hammering repeatedly for the same handful of IPs every 700ms).
    private val ipOrgCache = ConcurrentHashMap<String, String>()
    private val ipLookupInFlight = ConcurrentHashMap.newKeySet<String>()
    private val lookupExecutor = Executors.newFixedThreadPool(3) { r ->
        Thread(r, "AppTrack-OverlayIpLookup").apply { isDaemon = true }
    }

    private val density get() = resources.displayMetrics.density
    private fun dp(v: Int) = (v * density).toInt()

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopSelf()
                return START_NOT_STICKY
            }
            else -> {
                if (rootView == null) {
                    try {
                        showOverlay()
                        startUpdating()
                    } catch (e: Throwable) {
                        Log.e(TAG, "Failed to show overlay", e)
                        stopSelf()
                    }
                }
                return START_STICKY
            }
        }
    }

    // ================================================================
    // BUILD VIEW
    // ================================================================

    private fun showOverlay() {

        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager

        val card = FrameLayout(this).apply {
            background = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = dp(6).toFloat()
                setColor(Color.parseColor(COLOR_BG))
            }
            setPadding(dp(10), dp(8), dp(10), dp(8))
            elevation = dp(4).toFloat()
        }

        val body = TextView(this).apply {
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.WRAP_CONTENT,
                FrameLayout.LayoutParams.WRAP_CONTENT
            ).apply {
                rightMargin = dp(18) // room for the close button
            }
            text = "Waiting for traffic..."
            setTextColor(Color.parseColor(COLOR_TEXT))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 10.5f)
            setLineSpacing(dp(2).toFloat(), 1f)
            minWidth = dp(180)
            maxWidth = dp(280)
        }
        bodyText = body

        // Small, always-present close button -- no separate collapsed
        // state to worry about, this is the only view.
        val closeSize = dp(16)
        val close = TextView(this).apply {
            layoutParams = FrameLayout.LayoutParams(closeSize, closeSize).apply {
                gravity = Gravity.TOP or Gravity.END
            }
            text = "\u00D7" // ×
            gravity = Gravity.CENTER
            setTextColor(Color.parseColor(COLOR_TEXT))
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Color.parseColor(COLOR_CLOSE_BG))
            }
            isClickable = true
            setOnClickListener { stopSelf() }
        }

        card.addView(body)
        card.addView(close)

        rootView = card

        val layoutType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }

        val lp = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            layoutType,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS or
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.END
            x = dp(6)
            y = dp(140)
        }

        makeDraggable(card, lp)

        windowManager?.addView(card, lp)
    }

    // ================================================================
    // DRAG TO MOVE
    // ================================================================

    private fun makeDraggable(root: View, lp: WindowManager.LayoutParams) {

        var initialX = 0
        var initialY = 0
        var initialTouchX = 0f
        var initialTouchY = 0f

        root.setOnTouchListener { _, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    initialX = lp.x
                    initialY = lp.y
                    initialTouchX = event.rawX
                    initialTouchY = event.rawY
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    lp.x = initialX - (event.rawX - initialTouchX).toInt()
                    lp.y = initialY + (event.rawY - initialTouchY).toInt()
                    try {
                        windowManager?.updateViewLayout(root, lp)
                    } catch (_: Throwable) {
                    }
                    true
                }
                else -> false
            }
        }
    }

    // ================================================================
    // IP -> ORGANIZATION / COMPANY LOOKUP
    // ================================================================

    /** Returns a display label for this IP: cached org/ISP name if we
     *  have it, "Local" for private/reserved IPs, or "..." while a
     *  lookup is still in flight (kicked off separately). */
    private fun resolveOrgLabel(ip: String): String {

        if (isPrivateOrLocalIp(ip)) {
            return "Local"
        }

        return ipOrgCache[ip] ?: "..."
    }

    private fun maybeLookupOrg(ip: String) {

        if (isPrivateOrLocalIp(ip)) return
        if (ipOrgCache.containsKey(ip)) return
        if (!ipLookupInFlight.add(ip)) return // already being looked up

        lookupExecutor.execute {
            try {
                val org = fetchOrgFromApi(ip)
                ipOrgCache[ip] = org ?: "Unknown"
            } catch (e: Throwable) {
                Log.w(TAG, "Overlay IP lookup failed for $ip", e)
                ipOrgCache[ip] = "Unknown"
            } finally {
                ipLookupInFlight.remove(ip)
            }
        }
    }

    /** Same free, no-API-key service the in-app Traffic screen uses. */
    private fun fetchOrgFromApi(ip: String): String? {

        val connection = URL("https://ipwho.is/$ip").openConnection() as HttpURLConnection

        return try {
            connection.connectTimeout = 6000
            connection.readTimeout = 6000
            connection.setRequestProperty("Accept", "application/json")

            val body = connection.inputStream.bufferedReader().use { it.readText() }
            val json = JSONObject(body)

            if (json.optBoolean("success", false)) {

                val conn = json.optJSONObject("connection")
                val isp = conn?.optString("isp").orEmpty()
                val org = conn?.optString("org").orEmpty()
                val country = json.optString("country").orEmpty()

                when {
                    isp.isNotBlank() -> isp
                    org.isNotBlank() -> org
                    country.isNotBlank() -> country
                    else -> null
                }

            } else {
                null
            }

        } finally {
            connection.disconnect()
        }
    }

    private fun isPrivateOrLocalIp(ip: String): Boolean {

        val parts = ip.split(".")

        if (parts.size == 4) {

            val numbers = parts.map { it.toIntOrNull() ?: return false }

            val a = numbers[0]
            val b = numbers[1]

            if (a == 10) return true
            if (a == 172 && b in 16..31) return true
            if (a == 192 && b == 168) return true
            if (a == 127) return true
            if (a == 169 && b == 254) return true
            if (a == 0) return true

            return false
        }

        val lower = ip.lowercase()

        return lower == "::1" || lower == "::" ||
            lower.startsWith("fe80:") ||
            lower.startsWith("fc") ||
            lower.startsWith("fd")
    }

    // ================================================================
    // LIVE UPDATE
    // ================================================================

    private fun startUpdating() {

        val runnable = object : Runnable {
            override fun run() {

                try {
                    val flows = FlowStore.snapshot()

                    val recentIps = mutableSetOf<String>()

                    val lines = flows
                        .takeLast(MAX_LINES)
                        .asReversed()
                        .joinToString("\n") { raw ->
                            val ip = raw["destinationIp"]?.toString() ?: "?"
                            val port = raw["destinationPort"]?.toString() ?: "?"
                            val proto = (raw["protocol"]?.toString() ?: "?").uppercase()
                            val scheme = if (proto == "UDP") "udp" else if (port == "443") "https" else "http"

                            recentIps.add(ip)

                            val org = resolveOrgLabel(ip)

                            "$scheme://$ip:$port  ($org)"
                        }

                    bodyText?.text = if (lines.isBlank()) {
                        "Waiting for traffic..."
                    } else {
                        lines
                    }

                    for (ip in recentIps) {
                        maybeLookupOrg(ip)
                    }

                } catch (e: Throwable) {
                    Log.w(TAG, "Overlay update failed", e)
                }

                handler.postDelayed(this, REFRESH_MS)
            }
        }

        updateRunnable = runnable
        handler.post(runnable)
    }

    // ================================================================
    // DESTROY
    // ================================================================

    override fun onDestroy() {

        updateRunnable?.let { handler.removeCallbacks(it) }
        updateRunnable = null

        try {
            lookupExecutor.shutdownNow()
        } catch (_: Throwable) {
        }

        rootView?.let {
            try {
                windowManager?.removeView(it)
            } catch (e: Throwable) {
                Log.w(TAG, "removeView failed", e)
            }
        }
        rootView = null

        super.onDestroy()
    }
}