package com.otin.time_tracker

import com.google.android.gms.tasks.Tasks
import com.google.android.gms.wearable.MessageClient
import com.otin.time_tracker.support.FakeMessageEvent
import com.otin.time_tracker.support.bookmarksPayload
import com.otin.time_tracker.support.envelopeBytes
import io.mockk.every
import io.mockk.mockk
import io.mockk.slot
import io.mockk.verify
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import java.io.File

/**
 * The service that answers when no Flutter engine is running. Everything here
 * is about what it *declines* to do — a message that arrives correctly and is
 * then thrown away fails silently in production.
 */
@RunWith(RobolectricTestRunner::class)
class WearListenerServiceTest {

    /**
     * Robolectric constructs services through the no-arg path, so the mock
     * client travels through a file-level holder instead of the constructor
     * call. Nothing is overridden — the real reply body runs.
     */
    class InjectedListenerService : WearListenerService({ injectedMessageClient })

    private lateinit var service: InjectedListenerService
    private lateinit var messageClient: MessageClient

    private val queueFile: File get() = File(service.filesDir, WearQueue.FILE_NAME)
    private val cacheFile: File get() = File(service.filesDir, CurrentStateCache.FILE_NAME)

    @Before
    fun setUp() {
        messageClient = mockk {
            every { sendMessage(any(), any(), any()) } returns Tasks.forResult(1)
        }
        injectedMessageClient = messageClient
        service = Robolectric.buildService(InjectedListenerService::class.java).create().get()
        queueFile.delete()
        cacheFile.delete()
        WearBridge.isEngineListening = false
    }

    @After
    fun tearDown() {
        // A @Volatile global: left set, it silently disables queueing in every
        // test that runs after this one.
        WearBridge.isEngineListening = false
    }

    private fun queuedTypes() = WearQueue.drain(queueFile).map { it["type"] }

    private fun assertNothingSent() = verify(exactly = 0) { messageClient.sendMessage(any(), any(), any()) }

    @Test
    fun `a message on another path is not ours and is ignored`() {
        service.onMessageReceived(FakeMessageEvent("/something/else", envelopeBytes("switch")))

        assertEquals(emptyList<String>(), queuedTypes())
    }

    @Test
    fun `nothing is queued while an engine is listening - its own listener already has it`() {
        WearBridge.isEngineListening = true

        service.onMessageReceived(FakeMessageEvent(WearBridge.PATH, envelopeBytes("switch")))

        assertEquals(emptyList<String>(), queuedTypes())
    }

    @Test
    fun `a switch arriving with no engine is parked for the next start`() {
        service.onMessageReceived(FakeMessageEvent(WearBridge.PATH, envelopeBytes("switch", """{"n":1}""")))

        assertEquals(listOf("switch"), queuedTypes())
    }

    @Test
    fun `a bookmarks push is parked too - only snapshot_request is special`() {
        service.onMessageReceived(FakeMessageEvent(WearBridge.PATH, envelopeBytes("bookmarks", bookmarksPayload())))

        assertEquals(listOf("bookmarks"), queuedTypes())
    }

    @Test
    fun `an unparseable envelope is dropped rather than parked`() {
        service.onMessageReceived(FakeMessageEvent(WearBridge.PATH, "not json".toByteArray()))

        assertEquals(emptyList<String>(), queuedTypes())
    }

    /**
     * The watch asks while the phone app is dead; answering from the cache is
     * what keeps it from sitting blank until the phone is next opened. The real
     * reply body runs here, so the wire shape is pinned, not just the intent.
     */
    @Test
    fun `a snapshot request is answered from the cache with no engine running`() {
        CurrentStateCache.write(service, cacheFile, bookmarksPayload(name = "Reading"))

        service.onMessageReceived(
            FakeMessageEvent(WearBridge.PATH, envelopeBytes("snapshot_request"), sourceNodeId = "watch-7"),
        )

        val bytes = slot<ByteArray>()
        verify { messageClient.sendMessage("watch-7", WearBridge.PATH, capture(bytes)) }
        val envelope = JSONObject(String(bytes.captured, Charsets.UTF_8))
        assertEquals("bookmarks", envelope.getString("type"))
        assertEquals(
            "Reading",
            envelope.getJSONObject("payload").getJSONObject("current")
                .getJSONObject("activity").getString("name"),
        )
    }

    @Test
    fun `answering a snapshot request queues nothing - it is replied to, not replayed`() {
        CurrentStateCache.write(service, cacheFile, bookmarksPayload())

        service.onMessageReceived(FakeMessageEvent(WearBridge.PATH, envelopeBytes("snapshot_request")))

        assertEquals(emptyList<String>(), queuedTypes())
    }

    @Test
    fun `with nothing cached a snapshot request goes unanswered - silence beats a made-up reply`() {
        service.onMessageReceived(FakeMessageEvent(WearBridge.PATH, envelopeBytes("snapshot_request")))

        assertNothingSent()
        assertEquals(emptyList<String>(), queuedTypes())
    }

    @Test
    fun `a snapshot request is never answered while an engine is running`() {
        CurrentStateCache.write(service, cacheFile, bookmarksPayload())
        WearBridge.isEngineListening = true

        service.onMessageReceived(FakeMessageEvent(WearBridge.PATH, envelopeBytes("snapshot_request")))

        assertNothingSent()
    }

    private companion object {
        lateinit var injectedMessageClient: MessageClient
    }
}
