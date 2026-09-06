package com.otin.time_tracker

import android.app.Application
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.os.SystemClock
import android.view.View
import android.widget.Chronometer
import android.widget.TextView
import androidx.test.core.app.ApplicationProvider
import com.otin.time_tracker.support.bookmarksPayload
import com.otin.time_tracker.support.idlePayload
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import java.io.File

@RunWith(RobolectricTestRunner::class)
class CurrentActivityWidgetProviderTest {

    private lateinit var context: Application

    private val cacheFile: File get() = File(context.filesDir, CurrentStateCache.FILE_NAME)

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        cacheFile.delete()
    }

    private fun cache(payloadJson: String) = CurrentStateCache.write(context, cacheFile, payloadJson)

    /** Binds a widget, which renders it from whatever the cache holds right now. */
    private fun bindWidget(): Int {
        val manager = AppWidgetManager.getInstance(context)
        return shadowOf(manager).createWidget(
            CurrentActivityWidgetProvider::class.java,
            R.layout.current_activity_widget,
        )
    }

    private fun viewOf(widgetId: Int): View =
        shadowOf(AppWidgetManager.getInstance(context)).getViewFor(widgetId)

    private fun broadcastChanged() =
        CurrentActivityWidgetProvider().onReceive(context, Intent(CurrentStateCache.ACTION_CHANGED))

    /**
     * The CURRENT_CHANGED broadcast is package-scoped, so on one unflavoured
     * APK it also lands in the watch process — which has no app-widget host and
     * hands out no AppWidgetManager. An exception out of onReceive takes the
     * whole app down with it, and the cache is written on the first stream
     * tick, so surviving here is what keeps the watch alive past launch.
     */
    @Test
    fun `on a device with no app-widget host the broadcast is survived, not thrown out of`() {
        cache(bookmarksPayload())
        shadowOf(context).removeSystemService(Context.APPWIDGET_SERVICE)

        broadcastChanged()
        // Reaching here is the assertion: onReceive returned instead of throwing
        // into a process that has nothing to catch it.
    }

    @Test
    fun `with nothing cached the widget says so`() {
        val view = viewOf(bindWidget())

        assertEquals(View.VISIBLE, view.findViewById<TextView>(R.id.widget_empty).visibility)
        assertEquals(View.GONE, view.findViewById<TextView>(R.id.widget_name).visibility)
        assertEquals(View.GONE, view.findViewById<Chronometer>(R.id.widget_timer).visibility)
    }

    @Test
    fun `a snapshot with nothing tracked renders the same empty state as no snapshot at all`() {
        cache(idlePayload())

        val view = viewOf(bindWidget())

        // current == null covers both "nothing tracked" and the multi-activity
        // block the wire protocol declines to resolve to one activity.
        assertEquals(View.VISIBLE, view.findViewById<TextView>(R.id.widget_empty).visibility)
        assertEquals(View.GONE, view.findViewById<TextView>(R.id.widget_name).visibility)
    }

    @Test
    fun `what is being tracked is shown by name`() {
        cache(bookmarksPayload(name = "Reading"))

        val view = viewOf(bindWidget())

        val name = view.findViewById<TextView>(R.id.widget_name)
        assertEquals(View.VISIBLE, name.visibility)
        assertEquals("Reading", name.text.toString())
        assertEquals(View.GONE, view.findViewById<TextView>(R.id.widget_empty).visibility)
    }

    @Test
    fun `the activity colour is applied to the name`() {
        cache(bookmarksPayload(color = "#FF8800"))

        val view = viewOf(bindWidget())

        assertEquals(Color.parseColor("#FF8800"), view.findViewById<TextView>(R.id.widget_name).currentTextColor)
    }

    @Test
    fun `a malformed colour costs the colour, not the update`() {
        cache(bookmarksPayload(name = "Reading", color = "rebeccapurple-ish"))

        val view = viewOf(bindWidget())

        assertEquals("Reading", view.findViewById<TextView>(R.id.widget_name).text.toString())
        assertEquals(View.VISIBLE, view.findViewById<TextView>(R.id.widget_name).visibility)
    }

    @Test
    fun `the timer is handed a start instant so the host ticks it, not us`() {
        val startedAt = System.currentTimeMillis() - 90_000L
        cache(bookmarksPayload(startedAt = startedAt))

        val view = viewOf(bindWidget())

        // The cache stores wall-clock epoch millis; a Chronometer counts from
        // elapsedRealtime(), so the provider converts between the two.
        val expected = SystemClock.elapsedRealtime() - (System.currentTimeMillis() - startedAt)
        val actual = view.findViewById<Chronometer>(R.id.widget_timer).base
        assertTrue("base was $actual, expected about $expected", Math.abs(actual - expected) < 2_000L)
    }

    @Test
    fun `a CURRENT_CHANGED broadcast redraws the widget`() {
        val widgetId = bindWidget()
        assertEquals(View.VISIBLE, viewOf(widgetId).findViewById<TextView>(R.id.widget_empty).visibility)

        cache(bookmarksPayload(name = "Reading"))
        broadcastChanged()

        assertEquals("Reading", viewOf(widgetId).findViewById<TextView>(R.id.widget_name).text.toString())
    }

    @Test
    fun `an unrelated broadcast redraws nothing`() {
        val widgetId = bindWidget()
        cache(bookmarksPayload(name = "Reading"))

        CurrentActivityWidgetProvider().onReceive(context, Intent("com.otin.time_tracker.SOMETHING_ELSE"))

        // Still the empty state it was bound with: the new cache was not read.
        assertEquals(View.VISIBLE, viewOf(widgetId).findViewById<TextView>(R.id.widget_empty).visibility)
    }
}
