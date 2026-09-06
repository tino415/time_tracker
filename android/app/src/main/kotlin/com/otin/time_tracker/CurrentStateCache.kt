package com.otin.time_tracker

import android.content.Context
import android.content.Intent
import org.json.JSONObject
import java.io.File

/**
 * The most recent `bookmarks` payload this device has seen, kept on disk so
 * [WearListenerService] can answer a `snapshot_request` with something even
 * when no Flutter engine is running to build one.
 *
 * Modelled on [WearQueue]: an object owning one file, a single lock guarding
 * every entry point, org.json for parsing, and failure treated as absence
 * rather than thrown — a cache that cannot be read is exactly like a cache
 * that was never written.
 */
object CurrentStateCache {
    const val FILE_NAME = "current_state.json"

    /**
     * Broadcast after a successful [write], package-scoped.
     * [CurrentActivityWidgetProvider] and [ComplicationUpdateReceiver] both
     * listen for it. Package-scoped rather than targeted, so on one unflavoured
     * APK it reaches both of them on either form factor — which is why the
     * widget receiver has to survive a watch that has no AppWidgetManager.
     */
    const val ACTION_CHANGED = "com.otin.time_tracker.CURRENT_CHANGED"

    private val lock = Any()

    /** Overwrite the cache with [payloadJson], the wire payload of a `bookmarks` message. */
    fun write(context: Context, file: File, payloadJson: String) {
        synchronized(lock) {
            val parsed = try {
                JSONObject(payloadJson)
            } catch (_: Throwable) {
                return
            }
            file.writeText(parsed.toString())
        }
        context.applicationContext.sendBroadcast(
            Intent(ACTION_CHANGED).setPackage(context.packageName),
        )
    }

    /** The last cached `bookmarks` payload, or null if nothing was ever written or it is unreadable. */
    fun read(file: File): JSONObject? {
        synchronized(lock) {
            if (!file.exists()) return null
            return try {
                JSONObject(file.readText())
            } catch (_: Throwable) {
                null
            }
        }
    }
}
