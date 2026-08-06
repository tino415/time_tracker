package com.otin.time_tracker

import android.util.Log
import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.WearableListenerService
import java.io.File

/**
 * Wakes the app for messages that arrive while it is not running.
 *
 * [WearBridge]'s listener is attached from `configureFlutterEngine`, so without
 * this service a switch relayed while the phone app is killed would be dropped —
 * and the phone would then be tracking the wrong thing until the user noticed.
 * Declared once and unflavoured: one APK serves both form factors, so the watch
 * gets background delivery of bookmark snapshots too.
 *
 * Deliberately thin: park the bytes and return. There is no Flutter engine to
 * hand them to and no Drift connection to apply them with, and every decision
 * that could live in Dart does.
 */
class WearListenerService : WearableListenerService() {

    override fun onMessageReceived(event: MessageEvent) {
        if (event.path != WearBridge.PATH) return

        // A live engine's own listener already has this one. Queueing it anyway
        // would replay it at the next start; that is harmless for a `switch`
        // (applying it is idempotent on its syncId) but pointless, and for a
        // `bookmarks` snapshot it would re-apply a stale set over a newer one.
        // Losing the race — the engine dying right here — just drops the
        // message, which is the behaviour without this service at all.
        if (WearBridge.isEngineListening) return

        try {
            WearQueue.append(
                File(filesDir, WearQueue.FILE_NAME),
                String(event.data, Charsets.UTF_8),
            )
            Log.d(TAG, "queued inbound ${event.path} for next app start")
        } catch (t: Throwable) {
            Log.w(TAG, "queueing inbound wear message failed: ${t.message}")
        }
    }

    companion object {
        private const val TAG = "WearListenerService"
    }
}
