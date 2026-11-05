package com.swipengo.app.ui.deck

import org.junit.Assert.assertEquals
import org.junit.Test
import java.time.OffsetDateTime
import java.time.ZoneId

class EventFormattingTest {

    private val davis = ZoneId.of("America/Los_Angeles")

    @Test
    fun convertsUtcToLocalTimeWithSameDayEnd() {
        assertEquals(
            "Fri, Nov 6 · 7:00 PM – 9:00 PM",
            formatEventTime(
                OffsetDateTime.parse("2026-11-07T03:00:00+00:00"),
                OffsetDateTime.parse("2026-11-07T05:00:00+00:00"),
                davis,
            ),
        )
    }

    @Test
    fun endOnLaterDayShowsDate() {
        assertEquals(
            "Fri, Nov 6 · 10:00 PM – Sat, Nov 7 · 1:00 AM",
            formatEventTime(
                OffsetDateTime.parse("2026-11-07T06:00:00+00:00"),
                OffsetDateTime.parse("2026-11-07T09:00:00+00:00"),
                davis,
            ),
        )
    }

    @Test
    fun noEndTime() {
        assertEquals(
            "Fri, Nov 6 · 7:00 PM",
            formatEventTime(OffsetDateTime.parse("2026-11-07T03:00:00+00:00"), null, davis),
        )
    }
}
