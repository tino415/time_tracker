package com.otin.time_tracker

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import com.otin.time_tracker.support.bookmarksPayload
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import java.io.File

@RunWith(RobolectricTestRunner::class)
class CurrentStateCacheTest {

    @get:Rule
    val temporaryFolder = TemporaryFolder()

    private lateinit var context: Context

    private val cacheFile: File get() = File(temporaryFolder.root, CurrentStateCache.FILE_NAME)

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
    }

    private fun broadcasts() =
        shadowOf(context as android.app.Application).broadcastIntents
            .filter { it.action == CurrentStateCache.ACTION_CHANGED }

    @Test
    fun `what was written comes back out`() {
        CurrentStateCache.write(context, cacheFile, bookmarksPayload(name = "Reading", startedAt = 42L))

        // Field by field: write normalizes through JSONObject.toString(), which
        // makes no promise about key order.
        val current = CurrentStateCache.read(cacheFile)!!.getJSONObject("current")
        assertEquals(42L, current.getLong("startedAt"))
        assertEquals("Reading", current.getJSONObject("activity").getString("name"))
    }

    @Test
    fun `a later write replaces the whole cache rather than merging into it`() {
        CurrentStateCache.write(context, cacheFile, bookmarksPayload(name = "First"))
        CurrentStateCache.write(context, cacheFile, """{"current":null}""")

        val cached = CurrentStateCache.read(cacheFile)!!
        assertEquals(0, cached.optJSONArray("activities")?.length() ?: 0)
        assertNull(cached.optJSONObject("current"))
    }

    @Test
    fun `malformed json writes nothing`() {
        CurrentStateCache.write(context, cacheFile, "{ not json")

        assertFalse(cacheFile.exists())
    }

    @Test
    fun `malformed json also announces nothing - the early return leaves write entirely`() {
        CurrentStateCache.write(context, cacheFile, "{ not json")

        assertEquals(0, broadcasts().size)
    }

    @Test
    fun `a successful write announces itself exactly once`() {
        CurrentStateCache.write(context, cacheFile, bookmarksPayload())

        assertEquals(1, broadcasts().size)
    }

    @Test
    fun `the announcement is package-scoped, which is what makes it reach the watch process too`() {
        CurrentStateCache.write(context, cacheFile, bookmarksPayload())

        assertEquals(context.packageName, broadcasts().single().`package`)
    }

    @Test
    fun `a cache that was never written reads as absent`() {
        assertFalse(cacheFile.exists())

        assertNull(CurrentStateCache.read(cacheFile))
    }

    @Test
    fun `a corrupt cache reads as absent rather than throwing`() {
        cacheFile.writeText("""{"current":""")

        assertNull(CurrentStateCache.read(cacheFile))
    }

    @Test
    fun `an idle snapshot is stored, and its null current survives the round trip`() {
        CurrentStateCache.write(context, cacheFile, com.otin.time_tracker.support.idlePayload())

        val cached = CurrentStateCache.read(cacheFile)
        assertNotNull(cached)
        // Stored, but with nothing tracked — distinct from "no cache at all",
        // and both surfaces have to render it as the empty state.
        assertNull(cached!!.optJSONObject("current"))
    }
}
