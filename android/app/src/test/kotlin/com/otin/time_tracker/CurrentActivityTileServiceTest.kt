package com.otin.time_tracker

import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ResolveInfo
import android.icu.util.ULocale
import androidx.wear.protolayout.ActionBuilders.LaunchAction
import androidx.wear.protolayout.DeviceParametersBuilders
import androidx.wear.protolayout.DeviceParametersBuilders.DeviceParameters
import androidx.wear.protolayout.LayoutElementBuilders.Box
import androidx.wear.protolayout.LayoutElementBuilders.Column
import androidx.wear.protolayout.LayoutElementBuilders.LayoutElement
import androidx.wear.protolayout.LayoutElementBuilders.Row
import androidx.wear.protolayout.LayoutElementBuilders.Text
import androidx.wear.protolayout.ModifiersBuilders.Modifiers
import androidx.wear.protolayout.expression.DynamicBuilders.DynamicString
import androidx.wear.protolayout.expression.pipeline.DynamicTypeBindingRequest
import androidx.wear.protolayout.expression.pipeline.DynamicTypeEvaluator
import androidx.wear.protolayout.expression.pipeline.DynamicTypeValueReceiver
import androidx.wear.protolayout.expression.pipeline.PlatformTimeUpdateNotifier
import androidx.wear.protolayout.material3.ColorScheme
import androidx.wear.protolayout.material3.createMaterialScope
import androidx.wear.tiles.RequestBuilders.TileRequest
import androidx.wear.tiles.TileBuilders.Tile
import androidx.wear.tiles.TileService
import com.otin.time_tracker.support.bookmarksPayload
import com.otin.time_tracker.support.idlePayload
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import java.io.File
import java.time.Instant
import java.util.concurrent.Executor

/**
 * The tile shows what the complication shows, for faces that take no
 * third-party complication. Like the complication's service, the system builds
 * this one per request, so the cache file is the only state.
 */
@RunWith(RobolectricTestRunner::class)
class CurrentActivityTileServiceTest {

    private lateinit var service: CurrentActivityTileService

    private val cacheFile: File get() = File(service.filesDir, CurrentStateCache.FILE_NAME)

    @Before
    fun setUp() {
        service = Robolectric.buildService(CurrentActivityTileService::class.java).create().get()
        cacheFile.delete()
    }

    private fun cache(payloadJson: String) = CurrentStateCache.write(service, cacheFile, payloadJson)

    /** One request/response round trip, in the material scope Material3TileService builds from the request. */
    private fun tile(): Tile = runBlocking {
        with(service) {
            createMaterialScope(service, roundWatch(), allowDynamicTheme = false, defaultColorScheme = ColorScheme())
                .tileResponse(TileRequest.Builder().setDeviceConfiguration(roundWatch()).build())
        }
    }

    private fun roundWatch(): DeviceParameters = DeviceParameters.Builder()
        .setScreenWidthDp(192)
        .setScreenHeightDp(192)
        .setScreenDensity(2f)
        .setScreenShape(DeviceParametersBuilders.SCREEN_SHAPE_ROUND)
        .build()

    private fun Tile.elements(): List<LayoutElement> =
        tileTimeline!!.timelineEntries.single().layout!!.root!!.withDescendants().toList()

    private fun LayoutElement.withDescendants(): Sequence<LayoutElement> = sequence {
        yield(this@withDescendants)
        val children = when (this@withDescendants) {
            is Box -> contents
            is Column -> contents
            is Row -> contents
            else -> emptyList()
        }
        children.forEach { yieldAll(it.withDescendants()) }
    }

    private fun Tile.texts(): List<Text> = elements().filterIsInstance<Text>()

    private fun Tile.shownTexts(): List<String> = texts().map { it.text!!.value }

    private fun Tile.elapsedText(): Text = texts().single { it.text!!.dynamicValue != null }

    private fun LayoutElement.modifiers(): Modifiers? = when (this) {
        is Box -> modifiers
        is Column -> modifiers
        is Row -> modifiers
        is Text -> modifiers
        else -> null
    }

    private fun Tile.launchedActivities(): List<String> = elements()
        .mapNotNull { it.modifiers()?.clickable?.onClick as? LaunchAction }
        .map { it.androidActivity!!.packageName + "/" + it.androidActivity!!.className }

    /** What the watch's renderer would show for [expression] with its clock at [at]. */
    private fun render(expression: DynamicString, at: Instant): String {
        var shown: String? = null
        val evaluator = DynamicTypeEvaluator(
            DynamicTypeEvaluator.Config.Builder()
                .setClock { at }
                .setPlatformTimeUpdateNotifier(TickOnce)
                .build(),
        )
        val receiver = object : DynamicTypeValueReceiver<String> {
            override fun onData(newData: String) {
                shown = newData
            }

            override fun onInvalidated() = Unit
        }
        evaluator.bind(DynamicTypeBindingRequest.forDynamicString(expression, ULocale.ENGLISH, Executor { it.run() }, receiver))
            .use { it.startEvaluation() }
        return checkNotNull(shown) { "the expression produced no value" }
    }

    private object TickOnce : PlatformTimeUpdateNotifier {
        override fun setReceiver(executor: Executor, tick: Runnable) = executor.execute(tick)

        override fun clearReceiver() = Unit
    }

    private fun pickerEntry(): ResolveInfo? = service.packageManager
        .queryIntentServices(
            Intent(TileService.ACTION_BIND_TILE_PROVIDER).setPackage(service.packageName),
            PackageManager.GET_META_DATA,
        )
        .singleOrNull { it.serviceInfo.name == CurrentActivityTileService::class.java.name }

    @Test
    fun `the tile names what is being tracked`() {
        cache(bookmarksPayload(name = "Deep work"))

        assertTrue(tile().shownTexts().contains("Deep work"))
    }

    @Test
    fun `with nothing cached the tile says so rather than staying blank`() {
        assertEquals(listOf("Nothing tracked"), tile().shownTexts())
    }

    @Test
    fun `a snapshot with nothing tracked, or a block of several activities, reads the same as no snapshot`() {
        cache(idlePayload())

        assertEquals(listOf("Nothing tracked"), tile().shownTexts())
    }

    @Test
    fun `elapsed time counts up from the start on the watch, not from a value we push`() {
        val startedAt = Instant.ofEpochMilli(1_700_000_000_000L)
        cache(bookmarksPayload(startedAt = startedAt.toEpochMilli()))

        val elapsed = tile().elapsedText().text!!.dynamicValue!!

        assertEquals("2:05", render(elapsed, startedAt.plusSeconds(2 * 3600 + 5 * 60 + 30)))
        assertNotEquals(render(elapsed, startedAt.plusSeconds(60)), render(elapsed, startedAt.plusSeconds(600)))
    }

    @Test
    fun `a renderer without dynamic text shows the elapsed time as of the request`() {
        val startedAt = Instant.now().minusSeconds(90 * 60 + 10)
        cache(bookmarksPayload(startedAt = startedAt.toEpochMilli()))

        assertEquals("1:30", tile().elapsedText().text!!.value)
    }

    @Test
    fun `the elapsed text reserves room for two-digit hours`() {
        cache(bookmarksPayload())

        assertEquals("00:00", tile().elapsedText().layoutConstraintsForDynamicText!!.patternForLayout)
    }

    @Test
    fun `tapping the tile opens the app`() {
        cache(bookmarksPayload())

        assertEquals(listOf("${service.packageName}/${MainActivity::class.java.name}"), tile().launchedActivities())
    }

    @Test
    fun `tapping the empty tile opens the app too`() {
        assertEquals(listOf("${service.packageName}/${MainActivity::class.java.name}"), tile().launchedActivities())
    }

    @Test
    fun `the tile picker finds the service under the action it binds`() {
        assertEquals(
            "com.google.android.wearable.permission.BIND_TILE_PROVIDER",
            pickerEntry()!!.serviceInfo.permission,
        )
    }

    @Test
    fun `the tile picker lists it by what it shows, with an icon and a preview`() {
        val info = pickerEntry()!!.serviceInfo

        assertEquals("Current activity", info.loadLabel(service.packageManager).toString())
        assertNotEquals(0, info.iconResource)
        assertNotEquals(0, info.metaData.getInt(TileService.METADATA_PREVIEW_KEY))
        assertNotNull(service.getDrawable(info.metaData.getInt(TileService.METADATA_PREVIEW_KEY)))
    }
}
