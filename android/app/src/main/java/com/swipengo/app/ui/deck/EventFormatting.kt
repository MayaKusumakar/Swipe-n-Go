package com.swipengo.app.ui.deck

import java.time.OffsetDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

private val dayFormat = DateTimeFormatter.ofPattern("EEE, MMM d", Locale.US)
private val timeFormat = DateTimeFormatter.ofPattern("h:mm a", Locale.US)

/** "Thu, Nov 6 · 7:00 PM – 9:00 PM", shown in [zone] (the device's zone by default). */
fun formatEventTime(
    start: OffsetDateTime,
    end: OffsetDateTime?,
    zone: ZoneId = ZoneId.systemDefault(),
): String {
    val localStart = start.atZoneSameInstant(zone)
    val startText = "${localStart.format(dayFormat)} · ${localStart.format(timeFormat)}"
    if (end == null) return startText

    val localEnd = end.atZoneSameInstant(zone)
    val endText = if (localEnd.toLocalDate() == localStart.toLocalDate()) {
        localEnd.format(timeFormat)
    } else {
        "${localEnd.format(dayFormat)} · ${localEnd.format(timeFormat)}"
    }
    return "$startText – $endText"
}
