package com.otin.time_tracker

import android.util.Log
import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.Wearable
import com.google.android.gms.wearable.WearableListenerService
import org.json.JSONObject
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
 * Deliberately thin: park the bytes and return, or — for a `snapshot_request` —
 * answer straight from [CurrentStateCache]. Either way there is no Flutter
 * engine to hand the message to and no Drift connection to apply it with, and
 * every decision that could live in Dart does.
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

        val raw = String(event.data, Charsets.UTF_8)
        val type = try {
            JSONObject(raw).optString("type")
        } catch (_: Throwable) {
            null
        }

        // A `snapshot_request` is answered rather than queued: WearQueue already
        // refuses to hold one (a fresh request supersedes it the moment the
        // watch asks again), and queuing it here would gain nothing — nobody is
        // running to drain the queue and build a fresh snapshot. Answering from
        // whatever CurrentStateCache last saw a running engine write lets the
        // watch draw its tiles now instead of sitting blank until the phone app
        // is next opened; a snapshot that is merely stale is still a real one,
        // which is why replaying it beats the silence a plain drop would leave.
        // Everything else — `switch`, `assign`, `retime`, a `bookmarks` push
        // from the other side — has no cache to answer from and is still
        // queued, same as before.
        if (type == "snapshot_request") {
            val cached = CurrentStateCache.read(File(filesDir, CurrentStateCache.FILE_NAME))
            if (cached != null) replyWithCachedSnapshot(event.sourceNodeId, cached)
            return
        }

        try {
            WearQueue.append(File(filesDir, WearQueue.FILE_NAME), raw)
            Log.d(TAG, "queued inbound ${event.path} for next app start")
        } catch (t: Throwable) {
            Log.w(TAG, "queueing inbound wear message failed: ${t.message}")
        }
    }

    private fun replyWithCachedSnapshot(sourceNodeId: String, payload: JSONObject) {
        val envelope = JSONObject().put("type", "bookmarks").put("payload", payload)
        val bytes = envelope.toString().toByteArray(Charsets.UTF_8)
        Wearable.getMessageClient(this).sendMessage(sourceNodeId, WearBridge.PATH, bytes)
            .addOnFailureListener { t ->
                Log.d(TAG, "answering snapshot_request from cache failed: ${t.message}")
            }
    }

    companion object {
        private const val TAG = "WearListenerService"
    }
}
