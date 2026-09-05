package com.apptrack.app

/**
 * Current app network usage.
 *
 * Kept for compatibility with the existing UsageService and Flutter code.
 */
data class NativeAppUsage(
    val packageName: String,
    val appName: String,
    val uid: Int,
    val rxBytes: Long,
    val txBytes: Long
)

/**
 * Thread-safe app usage store.
 */
object AppUsageStore {

    private val lock = Any()

    private val usage =
        LinkedHashMap<String, NativeAppUsage>()

    fun clear() {
        synchronized(lock) {
            usage.clear()
        }
    }

    fun update(
        packageName: String,
        appName: String,
        uid: Int,
        rxBytes: Long,
        txBytes: Long
    ) {
        synchronized(lock) {

            usage[packageName] =
                NativeAppUsage(
                    packageName = packageName,
                    appName = appName,
                    uid = uid,
                    rxBytes = rxBytes,
                    txBytes = txBytes
                )
        }
    }

    fun snapshot(): List<Map<String, Any>> {
        synchronized(lock) {

            return usage.values.map { app ->

                mapOf(
                    "packageName" to app.packageName,
                    "appName" to app.appName,
                    "uid" to app.uid,
                    "rxBytes" to app.rxBytes,
                    "txBytes" to app.txBytes
                )
            }
        }
    }
}