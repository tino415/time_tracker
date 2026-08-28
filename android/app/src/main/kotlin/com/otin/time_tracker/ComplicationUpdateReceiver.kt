package com.otin.time_tracker

import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import androidx.wear.watchface.complications.datasource.ComplicationDataSourceUpdateRequester

/**
 * Bridges [CurrentStateCache.ACTION_CHANGED] to the one push a complication
 * data source is allowed to make: asking the system to re-invoke
 * [CurrentActivityComplicationService.onComplicationRequest]. The service
 * itself cannot listen for the broadcast — the system constructs it fresh for
 * each request/response round trip rather than keeping it alive.
 */
class ComplicationUpdateReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != CurrentStateCache.ACTION_CHANGED) return
        ComplicationDataSourceUpdateRequester.create(
            context,
            ComponentName(context, CurrentActivityComplicationService::class.java),
        ).requestUpdateAll()
    }
}
