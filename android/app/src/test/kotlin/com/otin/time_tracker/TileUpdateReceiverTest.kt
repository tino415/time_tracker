package com.otin.time_tracker

import android.app.Application
import android.content.ComponentName
import android.content.Context
import android.content.ContextWrapper
import android.content.Intent
import android.content.ReceiverCallNotAllowedException
import android.content.ServiceConnection
import android.content.pm.ResolveInfo
import android.content.pm.ServiceInfo
import android.os.Looper
import androidx.test.core.app.ApplicationProvider
import androidx.wear.tiles.TileUpdateRequestData
import androidx.wear.tiles.TileUpdateRequesterService
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf

/**
 * The tile's twin of [ComplicationUpdateReceiverTest]: the cache broadcast
 * becomes a request for the watch's system UI to ask the tile for a new layout.
 */
@RunWith(RobolectricTestRunner::class)
class TileUpdateReceiverTest {

    private lateinit var context: Application

    private val systemUi = RecordingUpdateRequester()

    private val systemUiComponent = ComponentName("com.google.android.wearable.app", "UpdateRequester")

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        installSystemUi()
    }

    /** What a watch has and Robolectric does not: system UI exporting the tile update requester. */
    private fun installSystemUi() {
        shadowOf(context.packageManager).addResolveInfoForIntent(
            Intent("androidx.wear.tiles.action.BIND_UPDATE_REQUESTER").setPackage(systemUiComponent.packageName),
            ResolveInfo().apply {
                serviceInfo = ServiceInfo().apply {
                    packageName = systemUiComponent.packageName
                    name = systemUiComponent.className
                }
            },
        )
        shadowOf(context).setComponentNameAndServiceForBindService(systemUiComponent, systemUi)
    }

    private fun receive(action: String) {
        TileUpdateReceiver().onReceive(ReceiverContext(context), Intent(action))
        shadowOf(Looper.getMainLooper()).idle()
    }

    @Test
    fun `an unrelated broadcast asks for nothing`() {
        receive("com.otin.time_tracker.SOMETHING_ELSE")

        assertEquals(emptyList<ComponentName>(), systemUi.requested)
    }

    @Test
    fun `a cache change asks the system to re-read this app's tile`() {
        receive(CurrentStateCache.ACTION_CHANGED)

        assertEquals(listOf(ComponentName(context, CurrentActivityTileService::class.java)), systemUi.requested)
    }

    /** What Android hands a manifest receiver: unlike its application, it refuses to bind. */
    private class ReceiverContext(base: Context) : ContextWrapper(base) {
        override fun bindService(service: Intent, conn: ServiceConnection, flags: Int): Boolean =
            throw ReceiverCallNotAllowedException("BroadcastReceiver components are not allowed to bind to services")
    }

    private class RecordingUpdateRequester : TileUpdateRequesterService.Stub() {
        val requested = mutableListOf<ComponentName>()

        override fun getApiVersion(): Int = TileUpdateRequesterService.API_VERSION

        override fun requestUpdate(component: ComponentName, updateData: TileUpdateRequestData) {
            requested.add(component)
        }
    }
}
