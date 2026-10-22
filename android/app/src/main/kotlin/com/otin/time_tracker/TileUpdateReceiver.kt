package com.otin.time_tracker

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import androidx.wear.tiles.TileService

/**
 * Bridges [CurrentStateCache.ACTION_CHANGED] to a request for the system to
 * call [CurrentActivityTileService.onTileRequest] again, the tile's twin of
 * [ComplicationUpdateReceiver].
 */
class TileUpdateReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != CurrentStateCache.ACTION_CHANGED) return
        TileService.getUpdater(context.applicationContext).requestUpdate(CurrentActivityTileService::class.java)
    }
}
