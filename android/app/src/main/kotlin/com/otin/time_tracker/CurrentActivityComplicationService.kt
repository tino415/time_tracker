package com.otin.time_tracker

import android.app.PendingIntent
import android.content.Intent
import androidx.wear.watchface.complications.data.ComplicationData
import androidx.wear.watchface.complications.data.ComplicationType
import androidx.wear.watchface.complications.data.CountUpTimeReference
import androidx.wear.watchface.complications.data.LongTextComplicationData
import androidx.wear.watchface.complications.data.PlainComplicationText
import androidx.wear.watchface.complications.data.ShortTextComplicationData
import androidx.wear.watchface.complications.data.TimeDifferenceComplicationText
import androidx.wear.watchface.complications.data.TimeDifferenceStyle
import androidx.wear.watchface.complications.datasource.ComplicationDataSourceService
import androidx.wear.watchface.complications.datasource.ComplicationRequest
import org.json.JSONObject
import java.io.File
import java.time.Instant

/**
 * Watch-face complication mirroring the phone widget: what is being tracked,
 * without opening the app.
 *
 * Elapsed time is [TimeDifferenceComplicationText] anchored on `startedAt`, not
 * a string this service recomputes — a watch face redraws in ambient mode on
 * the order of minutes, so a pushed duration would already be stale by the
 * next frame. RANGED_VALUE was left out for the same shape of reason: it wants
 * a min/max to bound the value, and an open-ended elapsed time has no natural
 * one to give it.
 *
 * There is no engine and no listener kept alive here — the system constructs
 * this service for one request/response round trip and drops it. Refreshing on
 * [CurrentStateCache.ACTION_CHANGED] is [ComplicationUpdateReceiver]'s job, the
 * one push a complication data source is allowed to initiate.
 */
class CurrentActivityComplicationService : ComplicationDataSourceService() {

    override fun onComplicationRequest(
        request: ComplicationRequest,
        listener: ComplicationRequestListener,
    ) {
        val cached = CurrentStateCache.read(File(filesDir, CurrentStateCache.FILE_NAME))
        listener.onComplicationData(buildData(request.complicationType, cached))
    }

    override fun getPreviewData(type: ComplicationType): ComplicationData? = buildData(type, previewState())

    private fun buildData(type: ComplicationType, cached: JSONObject?): ComplicationData? {
        val current = cached?.optJSONObject("current")
        val activity = current?.optJSONObject("activity")
        val tapAction = openAppPendingIntent()

        // Null covers both "nothing tracked" and the multi-activity block the
        // wire protocol itself declines to resolve to one — see
        // CurrentStateCache. Either way this is the empty state, not a guess.
        if (activity == null) {
            val empty = PlainComplicationText.Builder(getString(R.string.widget_nothing_tracked)).build()
            return when (type) {
                ComplicationType.SHORT_TEXT ->
                    ShortTextComplicationData.Builder(empty, empty).setTapAction(tapAction).build()
                ComplicationType.LONG_TEXT ->
                    LongTextComplicationData.Builder(empty, empty).setTapAction(tapAction).build()
                else -> null
            }
        }

        val name = activity.optString("name")
        val contentDescription = PlainComplicationText.Builder(name).build()
        val elapsed = TimeDifferenceComplicationText.Builder(
            TimeDifferenceStyle.STOPWATCH,
            CountUpTimeReference(Instant.ofEpochMilli(current.optLong("startedAt"))),
        ).build()

        return when (type) {
            // SHORT_TEXT's text slot is a handful of characters on most faces —
            // truncate rather than let the face do it mid-word.
            ComplicationType.SHORT_TEXT ->
                ShortTextComplicationData.Builder(PlainComplicationText.Builder(abbreviate(name)).build(), contentDescription)
                    .setTitle(elapsed)
                    .setTapAction(tapAction)
                    .build()
            ComplicationType.LONG_TEXT ->
                LongTextComplicationData.Builder(PlainComplicationText.Builder(name).build(), contentDescription)
                    .setTitle(elapsed)
                    .setTapAction(tapAction)
                    .build()
            else -> null
        }
    }

    private fun abbreviate(name: String): String = if (name.length <= SHORT_TEXT_MAX_CHARS) name else name.take(SHORT_TEXT_MAX_CHARS)

    private fun openAppPendingIntent(): PendingIntent =
        PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

    // What the watch-face picker renders for this complication before the user
    // has ever tracked anything on this device — without it the complication
    // has nothing to show and is not selectable. Started a few minutes before
    // "now" rather than at the epoch, so the stopwatch text reads like a real
    // in-progress block instead of decades of elapsed time.
    private fun previewState(): JSONObject {
        val startedAt = System.currentTimeMillis() - PREVIEW_ELAPSED_MILLIS
        return JSONObject(
            """{"current":{"startedAt":$startedAt,"activity":{"syncId":"preview","name":"Deep work","color":"#4C6EF5"}}}""",
        )
    }

    companion object {
        private const val SHORT_TEXT_MAX_CHARS = 7
        private const val PREVIEW_ELAPSED_MILLIS = 12 * 60 * 1000L
    }
}
