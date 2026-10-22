package com.otin.time_tracker

import android.content.ComponentName
import androidx.wear.protolayout.ActionBuilders.launchAction
import androidx.wear.protolayout.LayoutElementBuilders.LayoutElement
import androidx.wear.protolayout.TimelineBuilders.Timeline
import androidx.wear.protolayout.TypeBuilders.StringLayoutConstraint
import androidx.wear.protolayout.expression.DynamicBuilders.DynamicInstant
import androidx.wear.protolayout.expression.DynamicBuilders.DynamicInt32.IntFormatter
import androidx.wear.protolayout.expression.DynamicBuilders.DynamicString
import androidx.wear.protolayout.material3.MaterialScope
import androidx.wear.protolayout.material3.Typography
import androidx.wear.protolayout.material3.primaryLayout
import androidx.wear.protolayout.material3.text
import androidx.wear.protolayout.modifiers.clickable
import androidx.wear.protolayout.types.LayoutString
import androidx.wear.tiles.Material3TileService
import androidx.wear.tiles.RequestBuilders.TileRequest
import androidx.wear.tiles.TileBuilders.Tile
import org.json.JSONObject
import java.io.File
import java.time.Duration
import java.time.Instant

/**
 * The tile counterpart of [CurrentActivityComplicationService], for watch faces
 * that take no third-party complication. Same source, same rules: what
 * [CurrentStateCache] last saw, and "Nothing tracked" when there is no block or
 * the block holds more than one activity.
 *
 * Elapsed time is a dynamic expression the renderer counts up from `startedAt`,
 * like the complication's TimeDifferenceComplicationText, so nothing has to be
 * pushed every minute. Refreshing on [CurrentStateCache.ACTION_CHANGED] is
 * [TileUpdateReceiver]'s job.
 */
class CurrentActivityTileService : Material3TileService() {

    public override suspend fun MaterialScope.tileResponse(requestParams: TileRequest): Tile {
        val cached = CurrentStateCache.read(File(filesDir, CurrentStateCache.FILE_NAME))
        return Tile.Builder()
            .setTileTimeline(Timeline.fromLayoutElement(layout(cached, Instant.now())))
            .build()
    }

    private fun MaterialScope.layout(cached: JSONObject?, now: Instant): LayoutElement {
        val current = cached?.optJSONObject("current")
        val activity = current?.optJSONObject("activity")
        return if (activity == null) {
            nothingTracked()
        } else {
            tracking(activity.optString("name"), Instant.ofEpochMilli(current.optLong("startedAt")), now)
        }
    }

    private fun MaterialScope.nothingTracked(): LayoutElement = primaryLayout(
        mainSlot = { text(LayoutString(getString(R.string.widget_nothing_tracked)), typography = Typography.TITLE_MEDIUM) },
        onClick = openApp(),
    )

    private fun MaterialScope.tracking(name: String, startedAt: Instant, now: Instant): LayoutElement = primaryLayout(
        titleSlot = { text(LayoutString(name)) },
        mainSlot = { text(elapsedSince(startedAt, now), typography = Typography.NUMERAL_MEDIUM) },
        onClick = openApp(),
    )

    private fun openApp() = clickable(launchAction(ComponentName(this, MainActivity::class.java)), id = OPEN_APP_ID)

    // The static value is what a renderer without dynamic expressions shows as
    // is; one that has them replaces it and keeps counting.
    private fun elapsedSince(startedAt: Instant, now: Instant): LayoutString = LayoutString(
        formatHoursAndMinutes(Duration.between(startedAt, now)),
        countingUpFrom(startedAt),
        StringLayoutConstraint.Builder(ELAPSED_WIDEST).build(),
    )

    private fun countingUpFrom(startedAt: Instant): DynamicString {
        val elapsed = DynamicInstant.withSecondsPrecision(startedAt)
            .durationUntil(DynamicInstant.platformTimeWithSecondsPrecision())
        return elapsed.toIntHours().format()
            .concat(DynamicString.constant(":"))
            .concat(elapsed.minutesPart.format(IntFormatter.Builder().setMinIntegerDigits(2).build()))
    }

    // Duration.toMinutesPart is API 31; minSdk is 26.
    private fun formatHoursAndMinutes(elapsed: Duration): String =
        "%d:%02d".format(elapsed.toHours(), elapsed.toMinutes() % 60)

    companion object {
        private const val OPEN_APP_ID = "open_app"
        private const val ELAPSED_WIDEST = "00:00"
    }
}
