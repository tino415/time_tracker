package com.otin.time_tracker

import com.otin.time_tracker.support.envelope
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import java.io.File

/**
 * Robolectric rather than a plain JVM test only because org.json on the unit
 * test classpath is the android.jar stub, which throws from every method.
 * Nothing here touches a Context.
 */
@RunWith(RobolectricTestRunner::class)
class WearQueueTest {

    @get:Rule
    val temporaryFolder = TemporaryFolder()

    private val queueFile: File get() = File(temporaryFolder.root, WearQueue.FILE_NAME)

    private fun drainTypes() = WearQueue.drain(queueFile).map { it["type"] }

    // --- append ------------------------------------------------------------

    @Test
    fun `an unparseable envelope is dropped rather than stored`() {
        WearQueue.append(queueFile, "not json at all")

        assertEquals(emptyList<Map<String, Any?>>(), WearQueue.drain(queueFile))
    }

    @Test
    fun `an envelope with no type is dropped`() {
        WearQueue.append(queueFile, """{"payload":{"a":1}}""")

        assertEquals(emptyList<Map<String, Any?>>(), WearQueue.drain(queueFile))
    }

    @Test
    fun `a snapshot request is never queued`() {
        WearQueue.append(queueFile, envelope("snapshot_request"))

        assertEquals(emptyList<Map<String, Any?>>(), WearQueue.drain(queueFile))
    }

    @Test
    fun `a newer bookmarks snapshot replaces the one already parked`() {
        WearQueue.append(queueFile, envelope("bookmarks", """{"generation":1}"""))
        WearQueue.append(queueFile, envelope("bookmarks", """{"generation":2}"""))

        val entries = WearQueue.drain(queueFile)

        assertEquals(1, entries.size)
        @Suppress("UNCHECKED_CAST")
        val payload = entries.single()["payload"] as Map<String, Any?>
        assertEquals(2, payload["generation"])
    }

    @Test
    fun `collapsing bookmarks leaves other types in place`() {
        WearQueue.append(queueFile, envelope("switch", """{"n":1}"""))
        WearQueue.append(queueFile, envelope("bookmarks", """{"generation":1}"""))
        WearQueue.append(queueFile, envelope("switch", """{"n":2}"""))
        WearQueue.append(queueFile, envelope("bookmarks", """{"generation":2}"""))

        assertEquals(listOf("switch", "switch", "bookmarks"), drainTypes())
    }

    @Test
    fun `every switch is kept - it is an event, not a snapshot`() {
        repeat(5) { WearQueue.append(queueFile, envelope("switch", """{"n":$it}""")) }

        assertEquals(List(5) { "switch" }, drainTypes())
    }

    @Test
    fun `over the cap the newest entries survive, not the oldest`() {
        repeat(205) { WearQueue.append(queueFile, envelope("switch", """{"n":$it}""")) }

        val entries = WearQueue.drain(queueFile)

        assertEquals(200, entries.size)
        @Suppress("UNCHECKED_CAST")
        fun nAt(index: Int) = (entries[index]["payload"] as Map<String, Any?>)["n"]
        assertEquals(5, nAt(0))
        assertEquals(204, nAt(199))
    }

    @Test
    fun `a payload containing a newline cannot split the line it is stored on`() {
        WearQueue.append(queueFile, envelope("switch", """{"note":"first\nsecond"}"""))
        WearQueue.append(queueFile, envelope("switch", """{"note":"third"}"""))

        val entries = WearQueue.drain(queueFile)

        assertEquals(2, entries.size)
        @Suppress("UNCHECKED_CAST")
        val payload = entries.first()["payload"] as Map<String, Any?>
        assertEquals("first\nsecond", payload["note"])
    }

    // --- drain -------------------------------------------------------------

    @Test
    fun `draining a file that was never written is empty, not an error`() {
        assertFalse(queueFile.exists())

        assertEquals(emptyList<Map<String, Any?>>(), WearQueue.drain(queueFile))
    }

    @Test
    fun `draining clears the file, so nothing is replayed twice`() {
        WearQueue.append(queueFile, envelope("switch"))

        assertEquals(1, WearQueue.drain(queueFile).size)
        assertEquals(emptyList<Map<String, Any?>>(), WearQueue.drain(queueFile))
    }

    @Test
    fun `a torn line is skipped and its neighbours still arrive`() {
        queueFile.writeText(
            listOf(envelope("switch", """{"n":1}"""), """{"type":"swi""", envelope("switch", """{"n":2}"""))
                .joinToString("\n"),
        )

        assertEquals(listOf("switch", "switch"), drainTypes())
    }

    @Test
    fun `an entry with no payload drains as an empty map`() {
        queueFile.writeText("""{"type":"switch"}""")

        assertEquals(emptyMap<String, Any?>(), WearQueue.drain(queueFile).single()["payload"])
    }

    // --- jsonObjectToMap: the Flutter standard codec contract ---------------

    @Test
    fun `json null becomes kotlin null`() {
        val map = WearQueue.jsonObjectToMap(JSONObject("""{"activity":null}"""))

        assertTrue(map.containsKey("activity"))
        assertNull(map["activity"])
    }

    @Test
    fun `nested objects and arrays become maps and lists`() {
        val map = WearQueue.jsonObjectToMap(
            JSONObject("""{"current":{"startedAt":7},"activities":[{"name":"a"},{"name":"b"}]}"""),
        )

        assertEquals(mapOf("startedAt" to 7), map["current"])
        assertEquals(listOf(mapOf("name" to "a"), mapOf("name" to "b")), map["activities"])
    }

    @Test
    fun `scalars pass through with their types intact`() {
        val map = WearQueue.jsonObjectToMap(
            JSONObject("""{"name":"deep work","version":3,"startedAt":1756400000000,"nearby":true}"""),
        )

        assertEquals("deep work", map["name"])
        assertEquals(3, map["version"])
        assertEquals(1756400000000L, map["startedAt"])
        assertEquals(true, map["nearby"])
    }
}
