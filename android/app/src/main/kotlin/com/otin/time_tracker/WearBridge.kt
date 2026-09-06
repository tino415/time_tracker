package com.otin.time_tracker

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.google.android.gms.wearable.CapabilityClient
import com.google.android.gms.wearable.CapabilityInfo
import com.google.android.gms.wearable.MessageClient
import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.Wearable
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.File

/**
 * Wear Data Layer transport for the Dart side.
 *
 * One APK serves both form factors, so this is the same class on the phone and
 * on the watch — only the message types differ. It is deliberately dumb: it
 * moves JSON envelopes and reports reachability. Every decision about what a
 * message *means* lives in Dart, where the database is.
 */
class WearBridge(
    context: Context,
    binaryMessenger: BinaryMessenger,
    // Defaulted rather than constructed below so a test can hand in doubles:
    // both are Play Services statics that need a live GMS to answer.
    private val messageClient: MessageClient = Wearable.getMessageClient(context.applicationContext),
    private val capabilityClient: CapabilityClient = Wearable.getCapabilityClient(context.applicationContext),
) : MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler,
    MessageClient.OnMessageReceivedListener,
    CapabilityClient.OnCapabilityChangedListener {

    private val appContext = context.applicationContext
    private val methodChannel = MethodChannel(binaryMessenger, METHOD_CHANNEL)
    private val eventChannel = EventChannel(binaryMessenger, EVENT_CHANNEL)
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private val mainHandler = Handler(Looper.getMainLooper())
    private var sink: EventChannel.EventSink? = null

    fun attach() {
        // Not listening until Dart subscribes: anything arriving between engine
        // construction and onListen belongs to WearListenerService's queue, not
        // to a sink that does not exist yet.
        isEngineListening = false
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
        messageClient.addListener(this)
        capabilityClient.addListener(this, CAPABILITY)
    }

    fun detach() {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        // setStreamHandler(null) drops the handler *without* calling onCancel, so
        // clearing the flag only there would leave it stuck true after teardown —
        // and the listener service would then skip queueing every later message,
        // which is exactly the drop this mechanism exists to prevent.
        sink = null
        isEngineListening = false
        messageClient.removeListener(this)
        capabilityClient.removeListener(this)
        scope.cancel()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "send" -> {
                val type = call.argument<String>("type")
                @Suppress("UNCHECKED_CAST")
                val payload = call.argument<Map<String, Any?>>("payload")
                if (type == null || payload == null) {
                    result.error("invalid_args", "send requires type + payload", null)
                    return
                }
                send(type, payload, result)
            }
            "drainPending" -> {
                scope.launch {
                    val events = withContext(Dispatchers.IO) {
                        try {
                            WearQueue.drain(File(appContext.filesDir, WearQueue.FILE_NAME))
                        } catch (t: Throwable) {
                            Log.w(TAG, "draining the wear queue failed: ${t.message}")
                            emptyList()
                        }
                    }
                    result.success(events)
                }
            }
            "cacheCurrent" -> {
                @Suppress("UNCHECKED_CAST")
                val payload = call.argument<Map<String, Any?>>("payload")
                if (payload == null) {
                    result.error("invalid_args", "cacheCurrent requires payload", null)
                    return
                }
                scope.launch {
                    withContext(Dispatchers.IO) {
                        try {
                            CurrentStateCache.write(
                                appContext,
                                File(appContext.filesDir, CurrentStateCache.FILE_NAME),
                                JSONObject(payload).toString(),
                            )
                        } catch (t: Throwable) {
                            Log.w(TAG, "caching current state failed: ${t.message}")
                        }
                    }
                    result.success(null)
                }
            }
            "refreshReachability" -> {
                emitReachability()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun send(type: String, payload: Map<String, Any?>, result: MethodChannel.Result) {
        val envelope = JSONObject().apply {
            put("type", type)
            put("payload", JSONObject(payload))
        }
        val bytes = envelope.toString().toByteArray(Charsets.UTF_8)
        scope.launch {
            try {
                val nodes = capabilityClient
                    .getCapability(CAPABILITY, CapabilityClient.FILTER_REACHABLE)
                    .await()
                    .nodes
                // Reporting success for an empty node set is how a message gets
                // silently dropped: the sender marks the state as delivered and
                // never sends it again. Nothing reachable is a failure.
                if (nodes.isEmpty()) {
                    Log.d(TAG, "send($type): no reachable peer")
                    result.error("no_peer", "no reachable peer", null)
                    return@launch
                }
                var delivered = 0
                for (node in nodes) {
                    try {
                        messageClient.sendMessage(node.id, PATH, bytes).await()
                        delivered++
                    } catch (t: Throwable) {
                        // One unreachable node among several is not fatal.
                        Log.d(TAG, "send($type) to ${node.id} failed: ${t.message}")
                    }
                }
                if (delivered > 0) {
                    result.success(null)
                } else {
                    result.error("send_failed", "no node accepted the message", null)
                }
            } catch (t: Throwable) {
                Log.w(TAG, "send($type) failed: ${t.message}")
                result.error("send_failed", t.message ?: "send failed", null)
            }
        }
    }

    override fun onMessageReceived(event: MessageEvent) {
        if (event.path != PATH) return
        val parsed = try {
            JSONObject(String(event.data, Charsets.UTF_8))
        } catch (_: Throwable) {
            return
        }
        val map = mapOf(
            "type" to parsed.optString("type"),
            "payload" to WearQueue.jsonObjectToMap(parsed.optJSONObject("payload") ?: JSONObject()),
        )
        mainHandler.post { sink?.success(map) }
    }

    override fun onCapabilityChanged(info: CapabilityInfo) = emitReachability()

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        sink = events
        isEngineListening = true
        emitReachability()
    }

    override fun onCancel(arguments: Any?) {
        sink = null
        isEngineListening = false
    }

    private fun emitReachability() {
        scope.launch {
            val state = try {
                val info = capabilityClient
                    .getCapability(CAPABILITY, CapabilityClient.FILTER_ALL)
                    .await()
                when {
                    info.nodes.isEmpty() -> "notPaired"
                    info.nodes.none { it.isNearby } -> "pairedButNotReachable"
                    else -> "reachable"
                }
            } catch (_: Throwable) {
                "notPaired"
            }
            mainHandler.post {
                sink?.success(mapOf("type" to TYPE_REACHABILITY, "payload" to mapOf("state" to state)))
            }
        }
    }

    companion object {
        private const val TAG = "WearBridge"
        private const val METHOD_CHANNEL = "time_tracker/wear/method"
        private const val EVENT_CHANNEL = "time_tracker/wear/events"

        /**
         * Advertised in res/values/wear.xml. Both form factors declare it, so
         * either can discover the other — the phone does not need to know it is
         * "the phone" to answer a snapshot request.
         */
        const val CAPABILITY = "time_tracker_sync"

        /** Data Layer path this bridge and the listener service both serve. */
        const val PATH = "/time_tracker/sync"

        /**
         * Reserved event type this bridge emits itself; never a wire message.
         * The Dart side matches it by the same literal in wear_bridge.dart.
         */
        const val TYPE_REACHABILITY = "_reachability"

        /**
         * True while a Flutter engine holds the inbound sink, i.e. this bridge
         * will deliver a message itself. [WearListenerService] reads it to decide
         * whether an inbound message needs parking on disk. See [detach] for why
         * clearing it in onCancel alone is not enough.
         */
        @Volatile
        var isEngineListening: Boolean = false
    }
}
