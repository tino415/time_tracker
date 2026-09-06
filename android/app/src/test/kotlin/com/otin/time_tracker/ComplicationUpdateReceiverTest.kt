package com.otin.time_tracker

import android.app.Application
import android.content.ComponentName
import android.content.Intent
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf

/**
 * The one push a complication data source is allowed to make. The service
 * cannot listen for the cache broadcast itself — the system builds it fresh per
 * request — so this receiver turns that broadcast into a request to re-bind it.
 */
@RunWith(RobolectricTestRunner::class)
class ComplicationUpdateReceiverTest {

    private lateinit var context: Application

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
    }

    private fun broadcastCount() = shadowOf(context).broadcastIntents.size

    @Test
    fun `an unrelated broadcast asks for nothing`() {
        val before = broadcastCount()

        ComplicationUpdateReceiver().onReceive(context, Intent("com.otin.time_tracker.SOMETHING_ELSE"))

        assertEquals(before, broadcastCount())
    }

    @Test
    fun `a cache change asks the system to re-read this app's complication`() {
        val before = broadcastCount()

        ComplicationUpdateReceiver().onReceive(context, Intent(CurrentStateCache.ACTION_CHANGED))

        // The requester talks to the system by broadcast whose extras name the
        // data source to re-bind — the request is only useful if it names ours.
        assertTrue("expected an update request to be sent", broadcastCount() > before)
        val request = shadowOf(context).broadcastIntents.last()
        @Suppress("DEPRECATION")
        val named = request.extras?.keySet().orEmpty().mapNotNull { request.extras?.get(it) as? ComponentName }
        assertTrue(
            "update request names $named, not the complication service",
            named.contains(ComponentName(context, CurrentActivityComplicationService::class.java)),
        )
    }
}
