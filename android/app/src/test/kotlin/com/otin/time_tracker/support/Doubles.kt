package com.otin.time_tracker.support

import com.google.android.gms.wearable.MessageEvent
import com.otin.time_tracker.WearBridge
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.nio.ByteBuffer
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * The Kotlin counterpart to test/support/ on the Dart side: the doubles every
 * suite here shares, so no test has to describe the channel plumbing again.
 */

/**
 * Captures what a [MethodChannel.MethodCallHandler] answered.
 *
 * `drainPending` and `cacheCurrent` finish on [kotlinx.coroutines.Dispatchers.IO],
 * which the bridge does not take as a parameter, so the answer arrives on
 * another thread — hence the latch rather than a plain field read.
 */
class RecordingResult : MethodChannel.Result {
    private val answered = CountDownLatch(1)

    var successValue: Any? = null
        private set
    var errorCode: String? = null
        private set
    var errorMessage: String? = null
        private set
    var notImplemented: Boolean = false
        private set

    override fun success(result: Any?) {
        successValue = result
        answered.countDown()
    }

    override fun error(code: String, message: String?, details: Any?) {
        errorCode = code
        errorMessage = message
        answered.countDown()
    }

    override fun notImplemented() {
        notImplemented = true
        answered.countDown()
    }

    /** Fails the calling test rather than hanging it if nothing ever answers. */
    fun awaitAnswer(): RecordingResult {
        check(answered.await(5, TimeUnit.SECONDS)) { "the method call was never answered" }
        return this
    }
}

/** Collects everything the bridge pushes at the Dart event channel. */
class RecordingSink : EventChannel.EventSink {
    val events = mutableListOf<Any?>()
    var endOfStreamCount = 0
        private set

    override fun success(event: Any?) {
        events.add(event)
    }

    override fun error(code: String, message: String?, details: Any?) = Unit

    override fun endOfStream() {
        endOfStreamCount++
    }

    /** Reachability rides the same channel under a reserved type; usually noise. */
    @Suppress("UNCHECKED_CAST")
    fun messagesExcludingReachability(): List<Map<String, Any?>> =
        events.filterIsInstance<Map<String, Any?>>()
            .filterNot { it["type"] == WearBridge.TYPE_REACHABILITY }

    @Suppress("UNCHECKED_CAST")
    fun reachabilityStates(): List<Any?> =
        events.filterIsInstance<Map<String, Any?>>()
            .filter { it["type"] == WearBridge.TYPE_REACHABILITY }
            .map { (it["payload"] as Map<String, Any?>)["state"] }
}

/**
 * Enough of a messenger to let MethodChannel and EventChannel be constructed.
 * Nothing here is asserted on — the bridge is driven through its handler
 * interfaces directly, which is also how the real engine reaches it.
 */
class FakeBinaryMessenger : BinaryMessenger {
    override fun send(channel: String, message: ByteBuffer?) = Unit

    override fun send(channel: String, message: ByteBuffer?, callback: BinaryMessenger.BinaryReply?) = Unit

    override fun setMessageHandler(channel: String, handler: BinaryMessenger.BinaryMessageHandler?) = Unit
}

/** MessageEvent is an interface, so the real Data Layer is not needed to build one. */
class FakeMessageEvent(
    private val path: String,
    private val data: ByteArray,
    private val sourceNodeId: String = "node-1",
) : MessageEvent {
    override fun getRequestId(): Int = 1

    override fun getPath(): String = path

    override fun getData(): ByteArray = data

    override fun getSourceNodeId(): String = sourceNodeId
}

/** A wire envelope, the shape both sides actually exchange. */
fun envelope(type: String, payloadJson: String = "{}"): String = """{"type":"$type","payload":$payloadJson}"""

fun envelopeBytes(type: String, payloadJson: String = "{}"): ByteArray =
    envelope(type, payloadJson).toByteArray(Charsets.UTF_8)

/**
 * A cache payload shaped like BookmarkSnapshot.toPayload() in Dart, which is
 * what actually reaches CurrentStateCache. The widget and the complication read
 * only current.startedAt and current.activity, but fixtures carry the whole
 * thing so they stay honest about what is on the wire.
 */
fun bookmarksPayload(
    name: String = "Deep work",
    color: String = "#4C6EF5",
    startedAt: Long = 1_756_400_000_000L,
): String = """
    {
      "activities":[{"syncId":"a1","name":"$name","color":"$color"}],
      "current":{
        "changeId":"c1",
        "startedAt":$startedAt,
        "activity":{"syncId":"a1","name":"$name","color":"$color"},
        "version":1
      },
      "credentialVersion":1
    }
""".trimIndent()

/** The same snapshot with nothing being tracked — the empty state both surfaces render. */
fun idlePayload(): String = """
    {
      "activities":[{"syncId":"a1","name":"Deep work","color":"#4C6EF5"}],
      "current":null,
      "credentialVersion":1
    }
""".trimIndent()
