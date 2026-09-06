package com.otin.time_tracker

import android.app.Application
import android.content.ComponentName
import android.content.Intent
import android.net.Uri
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/**
 * Facts that live in three files at once — a Kotlin constant, a resource, and
 * the manifest — with nothing but this test linking them. Each one breaks
 * quietly: the app still builds, still installs, and simply stops talking to
 * the other device.
 */
@RunWith(RobolectricTestRunner::class)
class WearContractTest {

    private lateinit var context: Application

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
    }

    @Test
    fun `the advertised capability is the one the bridge looks for`() {
        val advertised = context.resources.getStringArray(R.array.android_wear_capabilities)

        // Drift here and capability discovery finds nothing, so every send fails
        // with no_peer while both devices sit there perfectly paired.
        assertTrue(
            "wear.xml advertises ${advertised.toList()}, bridge looks for ${WearBridge.CAPABILITY}",
            advertised.contains(WearBridge.CAPABILITY),
        )
    }

    @Test
    fun `the path the bridge sends on is one the manifest filter accepts`() {
        // Matched against the merged manifest itself, not a copy of its
        // pathPrefix: the filter matches on a prefix while the code compares
        // the whole path, and a path outside the prefix never wakes the app.
        assertTrue(
            "no manifest filter accepts ${WearBridge.PATH}",
            listenerServicesAcceptingPath(WearBridge.PATH).isNotEmpty(),
        )
        // Proof the filter has teeth — an unrelated path must not match.
        assertTrue(listenerServicesAcceptingPath("/some_other_app/sync").isEmpty())
    }

    private fun listenerServicesAcceptingPath(path: String): List<String> {
        val probe = Intent("com.google.android.gms.wearable.MESSAGE_RECEIVED")
            .setPackage(context.packageName)
            .setData(Uri.Builder().scheme("wear").authority("node0").path(path).build())
        @Suppress("DEPRECATION")
        return context.packageManager
            .queryIntentServices(probe, android.content.pm.PackageManager.GET_RESOLVED_FILTER)
            .mapNotNull { it.serviceInfo?.name }
            .filter { it == WearListenerService::class.java.name }
    }

    @Test
    fun `the listener service keeps the no-arg constructor the framework instantiates it with`() {
        // Kotlin emits it only while every constructor parameter stays
        // defaulted — and without it, message delivery crashes the moment the
        // system wakes the app.
        WearListenerService::class.java.getDeclaredConstructor()
    }

    @Test
    fun `the listener service is exported, or the other device cannot wake it`() {
        val info = context.packageManager.getServiceInfo(
            ComponentName(context, WearListenerService::class.java),
            0,
        )

        assertTrue(info.exported)
    }

    @Test
    fun `the complication service is exported and behind the system permission`() {
        val info = context.packageManager.getServiceInfo(
            ComponentName(context, CurrentActivityComplicationService::class.java),
            0,
        )

        assertTrue(info.exported)
        assertEquals("com.google.android.wearable.permission.BIND_COMPLICATION_PROVIDER", info.permission)
    }

    @Test
    fun `the complication update receiver stays private to this package`() {
        val info = context.packageManager.getReceiverInfo(
            ComponentName(context, ComplicationUpdateReceiver::class.java),
            0,
        )

        // CurrentStateCache scopes the broadcast to this package, so nothing
        // outside it has any business reaching this receiver.
        assertFalse(info.exported)
    }

}
