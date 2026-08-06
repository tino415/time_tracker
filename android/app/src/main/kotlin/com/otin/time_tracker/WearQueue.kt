package com.otin.time_tracker

import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/**
 * Inbound envelopes parked on disk while no Flutter engine is running.
 *
 * [WearListenerService] appends here when Android wakes the app for a message
 * it would otherwise drop; [WearBridge]'s `drainPending` hands the backlog to
 * Dart at the next start. Deliberately the only piece of native state in the
 * app: Kotlin cannot write Drift, and passing the backlog over the channel we
 * already own beats teaching Dart where `filesDir` is.
 *
 * Storage is JSON lines — one re-serialized envelope per line, so a payload
 * containing newlines cannot corrupt the file. Both entry points take the whole
 * file under [lock], which is the entire concurrency story: the service and the
 * bridge share a process.
 */
object WearQueue {
    const val FILE_NAME = "wear_queue.jsonl"

    /**
     * Types carrying a *full* snapshot, where only the newest is worth keeping.
     * Collapsing them bounds the queue semantically rather than by an arbitrary
     * cap: a watch left in a drawer for a week parks one bookmark set, not a
     * week of them.
     */
    private val SNAPSHOT_TYPES = setOf("bookmarks")

    /**
     * Never queued — replaying it is meaningless, because the watch sends a
     * fresh one the moment it starts.
     */
    private const val SNAPSHOT_REQUEST = "snapshot_request"

    /**
     * Backstop for what cannot be collapsed: a `switch` is a distinct event each
     * time, not a snapshot. Oldest go first; losing one is no worse than the
     * drop this queue exists to prevent.
     */
    private const val MAX_ENTRIES = 200

    private val lock = Any()

    /**
     * Park one raw wire envelope. Unparseable input and [SNAPSHOT_REQUEST] are
     * dropped rather than stored — a corrupt line would only fail again later.
     */
    fun append(file: File, envelope: String) {
        synchronized(lock) {
            val parsed = try {
                JSONObject(envelope)
            } catch (_: Throwable) {
                return
            }
            val type = parsed.optString("type")
            if (type.isEmpty() || type == SNAPSHOT_REQUEST) return

            val kept = read(file).filterNot { it.optString("type") == type && type in SNAPSHOT_TYPES }
            val all = (kept + parsed).takeLast(MAX_ENTRIES)
            file.writeText(all.joinToString("\n") { it.toString() })
        }
    }

    /** Hand over everything parked and clear the file. */
    fun drain(file: File): List<Map<String, Any?>> {
        synchronized(lock) {
            val entries = read(file)
            if (file.exists()) file.delete()
            return entries.map {
                mapOf(
                    "type" to it.optString("type"),
                    "payload" to jsonObjectToMap(it.optJSONObject("payload") ?: JSONObject()),
                )
            }
        }
    }

    private fun read(file: File): List<JSONObject> {
        if (!file.exists()) return emptyList()
        return file.readLines()
            .filter { it.isNotBlank() }
            .mapNotNull {
                try {
                    JSONObject(it)
                } catch (_: Throwable) {
                    null // a torn line is skipped, not fatal
                }
            }
    }

    /** org.json types are not what the Flutter codec expects; convert. */
    fun jsonObjectToMap(json: JSONObject): Map<String, Any?> {
        val out = mutableMapOf<String, Any?>()
        for (key in json.keys()) {
            out[key] = unwrap(json.get(key))
        }
        return out
    }

    private fun jsonArrayToList(json: JSONArray): List<Any?> =
        (0 until json.length()).map { unwrap(json.get(it)) }

    private fun unwrap(value: Any?): Any? = when (value) {
        JSONObject.NULL -> null
        is JSONObject -> jsonObjectToMap(value)
        is JSONArray -> jsonArrayToList(value)
        else -> value
    }
}
