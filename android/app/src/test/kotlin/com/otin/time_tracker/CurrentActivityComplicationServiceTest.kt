package com.otin.time_tracker

import androidx.wear.watchface.complications.data.ComplicationData
import androidx.wear.watchface.complications.data.ComplicationType
import androidx.wear.watchface.complications.data.LongTextComplicationData
import androidx.wear.watchface.complications.data.ShortTextComplicationData
import androidx.wear.watchface.complications.data.TimeDifferenceComplicationText
import androidx.wear.watchface.complications.datasource.ComplicationDataSourceService
import androidx.wear.watchface.complications.datasource.ComplicationRequest
import com.otin.time_tracker.support.bookmarksPayload
import com.otin.time_tracker.support.idlePayload
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import java.io.File
import java.time.Instant

/**
 * The watch-face side of "what is running, without opening anything". The
 * service is built fresh by the system for each request, so there is no state
 * here beyond the cache file it reads.
 */
@RunWith(RobolectricTestRunner::class)
class CurrentActivityComplicationServiceTest {

    private lateinit var service: CurrentActivityComplicationService

    private val cacheFile: File get() = File(service.filesDir, CurrentStateCache.FILE_NAME)

    @Before
    fun setUp() {
        service = Robolectric.buildService(CurrentActivityComplicationService::class.java).create().get()
        cacheFile.delete()
    }

    private fun cache(payloadJson: String) = CurrentStateCache.write(service, cacheFile, payloadJson)

    /** Drives one request/response round trip, the way the system does. */
    private fun complicationFor(type: ComplicationType): ComplicationData? {
        var received: ComplicationData? = null
        service.onComplicationRequest(
            ComplicationRequest(1, type, false),
            object : ComplicationDataSourceService.ComplicationRequestListener {
                override fun onComplicationData(complicationData: ComplicationData?) {
                    received = complicationData
                }
            },
        )
        return received
    }

    private fun ComplicationData.mainText(at: Instant = Instant.now()): String = when (this) {
        is ShortTextComplicationData -> text.getTextAt(service.resources, at).toString()
        is LongTextComplicationData -> text.getTextAt(service.resources, at).toString()
        else -> error("no text on $this")
    }

    private fun ComplicationData.titleText(at: Instant): String = when (this) {
        is ShortTextComplicationData -> title!!.getTextAt(service.resources, at).toString()
        is LongTextComplicationData -> title!!.getTextAt(service.resources, at).toString()
        else -> error("no title on $this")
    }

    @Test
    fun `a short text slot is a handful of characters, so the name is cut rather than left to the face`() {
        cache(bookmarksPayload(name = "Deep work"))

        assertEquals("Deep wo", complicationFor(ComplicationType.SHORT_TEXT)!!.mainText())
    }

    @Test
    fun `a name that already fits is left alone`() {
        cache(bookmarksPayload(name = "Email"))

        assertEquals("Email", complicationFor(ComplicationType.SHORT_TEXT)!!.mainText())
    }

    @Test
    fun `a long text slot gets the whole name`() {
        cache(bookmarksPayload(name = "Deep work"))

        assertEquals("Deep work", complicationFor(ComplicationType.LONG_TEXT)!!.mainText())
    }

    @Test
    fun `with nothing cached the face is told so rather than left blank`() {
        assertEquals("Nothing tracked", complicationFor(ComplicationType.SHORT_TEXT)!!.mainText())
    }

    @Test
    fun `a snapshot with nothing tracked reads the same as no snapshot`() {
        cache(idlePayload())

        assertEquals("Nothing tracked", complicationFor(ComplicationType.LONG_TEXT)!!.mainText())
    }

    @Test
    fun `only the two declared slot types are answered`() {
        cache(bookmarksPayload())

        assertNull(complicationFor(ComplicationType.RANGED_VALUE))
        assertNull(complicationFor(ComplicationType.MONOCHROMATIC_IMAGE))
    }

    @Test
    fun `elapsed time is anchored on the start instant, not a duration we recompute`() {
        val startedAt = 1_700_000_000_000L
        cache(bookmarksPayload(startedAt = startedAt))

        val data = complicationFor(ComplicationType.SHORT_TEXT)!!

        // A watch face redraws on the order of minutes in ambient mode, so a
        // pushed duration would be stale by the next frame; the face renders
        // this itself from the anchor.
        assertTrue(data is ShortTextComplicationData && data.title is TimeDifferenceComplicationText)
        assertTrue(data.titleText(Instant.ofEpochMilli(startedAt + 90_000L)).contains("1:30"))
    }

    @Test
    fun `the elapsed text keeps counting up as time passes`() {
        val startedAt = 1_700_000_000_000L
        cache(bookmarksPayload(startedAt = startedAt))

        val data = complicationFor(ComplicationType.LONG_TEXT)!!

        val early = data.titleText(Instant.ofEpochMilli(startedAt + 60_000L))
        val later = data.titleText(Instant.ofEpochMilli(startedAt + 600_000L))
        assertTrue("expected $early and $later to differ", early != later)
    }

    @Test
    fun `the picker gets preview data, without which the complication is not selectable`() {
        assertNotNull(service.getPreviewData(ComplicationType.SHORT_TEXT))
        assertNotNull(service.getPreviewData(ComplicationType.LONG_TEXT))
    }

    @Test
    fun `preview data shows a plausible in-progress block rather than the empty state`() {
        val preview = service.getPreviewData(ComplicationType.LONG_TEXT)!!

        assertEquals("Deep work", preview.mainText())
    }

    @Test
    fun `unsupported slot types have no preview either`() {
        assertNull(service.getPreviewData(ComplicationType.RANGED_VALUE))
    }
}
