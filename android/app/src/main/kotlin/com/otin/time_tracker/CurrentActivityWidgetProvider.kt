package com.otin.time_tracker

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.os.SystemClock
import android.view.View
import android.widget.RemoteViews
import org.json.JSONObject
import java.io.File

/**
 * Home-screen widget showing what is currently tracked, without opening the app.
 *
 * Refreshed by [CurrentStateCache.ACTION_CHANGED] rather than the info XML's
 * `updatePeriodMillis` — that floor is 30 minutes, useless for something meant
 * to track live. The elapsed time is a running [android.widget.Chronometer],
 * not a string this class recomputes: `setChronometer` gives it a start instant
 * and the widget host ticks it on its own, the same reason the complication
 * side renders elapsed time from an instant instead of a pushed duration.
 */
class CurrentActivityWidgetProvider : AppWidgetProvider() {

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action != CurrentStateCache.ACTION_CHANGED) return
        val manager = AppWidgetManager.getInstance(context)
        val ids = manager.getAppWidgetIds(ComponentName(context, CurrentActivityWidgetProvider::class.java))
        onUpdate(context, manager, ids)
    }

    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        val cached = CurrentStateCache.read(File(context.filesDir, CurrentStateCache.FILE_NAME))
        val views = buildViews(context, cached)
        for (id in ids) {
            manager.updateAppWidget(id, views)
        }
    }

    private fun buildViews(context: Context, cached: JSONObject?): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.current_activity_widget)
        views.setOnClickPendingIntent(R.id.widget_root, openAppPendingIntent(context))

        val current = cached?.optJSONObject("current")
        val activity = current?.optJSONObject("activity")

        // Null covers both "nothing tracked" and the multi-activity block the
        // wire protocol itself declines to resolve to one — see
        // CurrentStateCache. Either way this shows the empty state, not a guess.
        if (activity == null) {
            views.setViewVisibility(R.id.widget_name, View.GONE)
            views.setViewVisibility(R.id.widget_timer, View.GONE)
            views.setViewVisibility(R.id.widget_empty, View.VISIBLE)
            return views
        }

        views.setViewVisibility(R.id.widget_name, View.VISIBLE)
        views.setViewVisibility(R.id.widget_timer, View.VISIBLE)
        views.setViewVisibility(R.id.widget_empty, View.GONE)

        views.setTextViewText(R.id.widget_name, activity.optString("name"))
        try {
            views.setInt(R.id.widget_name, "setTextColor", Color.parseColor(activity.optString("color")))
        } catch (_: Throwable) {
            // A malformed color falls back to the layout's default rather than
            // failing the whole update.
        }

        // Chronometer counts from elapsedRealtime(), the cache stores a
        // wall-clock epoch millis — convert once here rather than push a
        // recomputed duration on every tick.
        val startedAt = current.optLong("startedAt")
        val base = SystemClock.elapsedRealtime() - (System.currentTimeMillis() - startedAt)
        views.setChronometer(R.id.widget_timer, base, null, true)

        return views
    }

    private fun openAppPendingIntent(context: Context): PendingIntent =
        PendingIntent.getActivity(
            context,
            0,
            Intent(context, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
}
