package com.otin.time_tracker

import android.app.Application
import android.os.Looper
import androidx.test.core.app.ApplicationProvider
import com.google.android.gms.tasks.Tasks
import com.google.android.gms.wearable.CapabilityClient
import com.google.android.gms.wearable.CapabilityInfo
import com.google.android.gms.wearable.MessageClient
import com.google.android.gms.wearable.Node
import com.otin.time_tracker.support.FakeBinaryMessenger
import com.otin.time_tracker.support.FakeMessageEvent
import com.otin.time_tracker.support.RecordingResult
import com.otin.time_tracker.support.RecordingSink
import com.otin.time_tracker.support.envelope
import com.otin.time_tracker.support.envelopeBytes
import io.mockk.every
import io.mockk.mockk
import io.mockk.slot
import io.flutter.plugin.common.MethodCall
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.setMain
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import java.io.File

/**
 * The Data Layer transport. The Play Services clients are handed in rather than
 * looked up, which is the only reason any of this is reachable without a paired
 * device and a live GMS.
 */
@RunWith(RobolectricTestRunner::class)
class WearBridgeTest {

    private lateinit var context: Application
    private lateinit var messageClient: MessageClient
    private lateinit var capabilityClient: CapabilityClient
    private lateinit var bridge: WearBridge
    private lateinit var sink: RecordingSink

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        // The bridge's scope is Dispatchers.Main; unconfined makes each launch
        // run inline so a test reads as a straight line.
        Dispatchers.setMain(UnconfinedTestDispatcher())
        messageClient = mockk(relaxed = true)
        capabilityClient = mockk(relaxed = true)
        bridge = WearBridge(context, FakeBinaryMessenger(), messageClient, capabilityClient)
        sink = RecordingSink()
        File(context.filesDir, WearQueue.FILE_NAME).delete()
        File(context.filesDir, CurrentStateCache.FILE_NAME).delete()
    }

    @After
    fun tearDown() {
        Dispatchers.resetMain()
        WearBridge.isEngineListening = false
    }

    // --- harness -----------------------------------------------------------

    /** Play Services answers its Tasks on the main looper, which Robolectric pauses. */
    private fun settle() {
        repeat(3) { shadowOf(Looper.getMainLooper()).idle() }
    }

    private fun node(id: String, nearby: Boolean = true): Node = mockk {
        every { this@mockk.id } returns id
        every { isNearby } returns nearby
    }

    // Stubbed per filter, never with any(): send asks for FILTER_REACHABLE and
    // reachability for FILTER_ALL, and swapping them changes what a paired but
    // out-of-range watch reports. A test using the wrong helper gets an
    // unstubbed lookup, not a false pass.

    private fun capabilityInfo(vararg nodes: Node): CapabilityInfo {
        val info = mockk<CapabilityInfo>()
        every { info.nodes } returns nodes.toSet()
        return info
    }

    private fun reachablePeersAre(vararg nodes: Node) {
        every {
            capabilityClient.getCapability(WearBridge.CAPABILITY, CapabilityClient.FILTER_REACHABLE)
        } returns Tasks.forResult(capabilityInfo(*nodes))
    }

    private fun allPeersAre(vararg nodes: Node) {
        every {
            capabilityClient.getCapability(WearBridge.CAPABILITY, CapabilityClient.FILTER_ALL)
        } returns Tasks.forResult(capabilityInfo(*nodes))
    }

    private fun peerLookupFails() {
        every { capabilityClient.getCapability(WearBridge.CAPABILITY, any()) } returns
            Tasks.forException(RuntimeException("no play services"))
    }

    private fun send(type: String? = "switch", payload: Map<String, Any?>? = mapOf("n" to 1)): RecordingResult {
        val arguments = mutableMapOf<String, Any?>()
        type?.let { arguments["type"] = it }
        payload?.let { arguments["payload"] = it }
        val result = RecordingResult()
        bridge.onMethodCall(MethodCall("send", arguments), result)
        settle()
        return result.awaitAnswer()
    }

    private fun call(method: String, arguments: Any? = null): RecordingResult {
        val result = RecordingResult()
        bridge.onMethodCall(MethodCall(method, arguments), result)
        settle()
        return result.awaitAnswer()
    }

    // --- send: the silent-drop regression ----------------------------------

    /**
     * Reporting success with nothing reachable would mark the state delivered,
     * and Dart dedupes every later identical push against what it believes was
     * delivered — so a false success here loses the message permanently.
     */
    @Test
    fun `with no peer reachable the send fails - it must never report delivery`() {
        reachablePeersAre()

        val result = send()

        assertEquals("no_peer", result.errorCode)
    }

    @Test
    fun `a single reachable peer takes the message`() {
        reachablePeersAre(node("n1"))
        every { messageClient.sendMessage(any(), any(), any()) } returns Tasks.forResult(1)

        assertNull(send().errorCode)
    }

    @Test
    fun `one unreachable node among several is not fatal`() {
        reachablePeersAre(node("n1"), node("n2"))
        every { messageClient.sendMessage("n1", any(), any()) } returns Tasks.forException(RuntimeException("gone"))
        every { messageClient.sendMessage("n2", any(), any()) } returns Tasks.forResult(1)

        assertNull(send().errorCode)
    }

    @Test
    fun `when no node accepts it, the send fails`() {
        reachablePeersAre(node("n1"), node("n2"))
        every { messageClient.sendMessage(any(), any(), any()) } returns Tasks.forException(RuntimeException("gone"))

        assertEquals("send_failed", send().errorCode)
    }

    @Test
    fun `a peer lookup that throws fails the send rather than passing silently`() {
        peerLookupFails()

        assertEquals("send_failed", send().errorCode)
    }

    @Test
    fun `the wire carries a type-and-payload envelope on the agreed path`() {
        reachablePeersAre(node("n1"))
        val bytes = slot<ByteArray>()
        val path = slot<String>()
        every { messageClient.sendMessage(eq("n1"), capture(path), capture(bytes)) } returns Tasks.forResult(1)

        send(type = "switch", payload = mapOf("activityId" to "a1"))

        assertEquals(WearBridge.PATH, path.captured)
        val sent = JSONObject(String(bytes.captured, Charsets.UTF_8))
        assertEquals("switch", sent.getString("type"))
        assertEquals("a1", sent.getJSONObject("payload").getString("activityId"))
    }

    @Test
    fun `a send with no type is rejected before any peer is looked up`() {
        assertEquals("invalid_args", send(type = null).errorCode)
    }

    @Test
    fun `a send with no payload is rejected too`() {
        assertEquals("invalid_args", send(payload = null).errorCode)
    }

    // --- inbound -----------------------------------------------------------

    @Test
    fun `an inbound message reaches Dart as type and payload`() {
        bridge.onListen(null, sink)

        bridge.onMessageReceived(FakeMessageEvent(WearBridge.PATH, envelopeBytes("switch", """{"activityId":"a1"}""")))
        settle()

        val message = sink.messagesExcludingReachability().single()
        assertEquals("switch", message["type"])
        assertEquals(mapOf("activityId" to "a1"), message["payload"])
    }

    @Test
    fun `a message on another path is not ours`() {
        bridge.onListen(null, sink)

        bridge.onMessageReceived(FakeMessageEvent("/other/path", envelopeBytes("switch")))
        settle()

        assertEquals(emptyList<Map<String, Any?>>(), sink.messagesExcludingReachability())
    }

    @Test
    fun `an unparseable inbound message is dropped, not forwarded`() {
        bridge.onListen(null, sink)

        bridge.onMessageReceived(FakeMessageEvent(WearBridge.PATH, "not json".toByteArray()))
        settle()

        assertEquals(emptyList<Map<String, Any?>>(), sink.messagesExcludingReachability())
    }

    // --- reachability ------------------------------------------------------

    private fun reachabilityWith(vararg nodes: Node): Any? {
        allPeersAre(*nodes)
        bridge.onListen(null, sink)
        settle()
        return sink.reachabilityStates().last()
    }

    @Test
    fun `no nodes at all means nothing is paired`() {
        assertEquals("notPaired", reachabilityWith())
    }

    @Test
    fun `a known node that is not nearby is paired but out of reach`() {
        assertEquals("pairedButNotReachable", reachabilityWith(node("n1", nearby = false)))
    }

    @Test
    fun `a nearby node is reachable`() {
        assertEquals("reachable", reachabilityWith(node("n1", nearby = true)))
    }

    @Test
    fun `if the lookup throws we report not paired rather than guessing`() {
        peerLookupFails()
        bridge.onListen(null, sink)
        settle()

        assertEquals("notPaired", sink.reachabilityStates().last())
    }

    // --- the isEngineListening handshake -----------------------------------

    @Test
    fun `attaching alone does not claim inbound messages`() {
        allPeersAre()

        bridge.attach()

        // Anything arriving between engine construction and onListen belongs to
        // the listener service's queue, not to a sink that does not exist yet.
        assertFalse(WearBridge.isEngineListening)
    }

    @Test
    fun `a listening engine claims them`() {
        allPeersAre()

        bridge.onListen(null, sink)

        assertTrue(WearBridge.isEngineListening)
    }

    @Test
    fun `cancelling the stream hands them back`() {
        allPeersAre()
        bridge.onListen(null, sink)

        bridge.onCancel(null)

        assertFalse(WearBridge.isEngineListening)
    }

    /**
     * setStreamHandler(null) drops the handler *without* calling onCancel, so
     * detach must clear the flag itself: stuck true, it makes the listener
     * service skip queueing every later message — the drop the queue exists
     * to prevent.
     */
    @Test
    fun `detaching hands them back too, without waiting for an onCancel that never comes`() {
        allPeersAre()
        bridge.attach()
        bridge.onListen(null, sink)

        bridge.detach()

        assertFalse(WearBridge.isEngineListening)
    }

    // --- the disk-backed methods -------------------------------------------

    @Test
    fun `drainPending hands over what the listener service parked`() {
        WearQueue.append(File(context.filesDir, WearQueue.FILE_NAME), envelope("switch", """{"n":1}"""))

        @Suppress("UNCHECKED_CAST")
        val drained = call("drainPending").successValue as List<Map<String, Any?>>

        assertEquals(listOf("switch"), drained.map { it["type"] })
    }

    @Test
    fun `draining twice yields nothing the second time`() {
        WearQueue.append(File(context.filesDir, WearQueue.FILE_NAME), envelope("switch"))
        call("drainPending")

        @Suppress("UNCHECKED_CAST")
        val second = call("drainPending").successValue as List<Map<String, Any?>>

        assertEquals(emptyList<Map<String, Any?>>(), second)
    }

    @Test
    fun `cacheCurrent puts the payload where the engineless surfaces read it`() {
        call("cacheCurrent", mapOf("payload" to mapOf("current" to null, "credentialVersion" to 1)))

        val cached = CurrentStateCache.read(File(context.filesDir, CurrentStateCache.FILE_NAME))
        assertEquals(1, cached!!.getInt("credentialVersion"))
    }

    @Test
    fun `cacheCurrent without a payload is rejected`() {
        assertEquals("invalid_args", call("cacheCurrent", mapOf<String, Any?>()).errorCode)
    }

    @Test
    fun `an unknown method is reported as not implemented, not as a failure`() {
        assertTrue(call("someMethodDartDoesNotHave").notImplemented)
    }
}
