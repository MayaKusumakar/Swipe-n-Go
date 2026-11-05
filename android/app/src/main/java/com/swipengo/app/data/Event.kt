package com.swipengo.app.data

import java.time.OffsetDateTime

/** One event as returned by GET /api/events (see docs/API.llm.md). */
data class Event(
    val id: String,
    val title: String,
    val description: String,
    val startTime: OffsetDateTime,
    val endTime: OffsetDateTime?,
    val locationName: String,
    val latitude: Double?,
    val longitude: Double?,
    val category: String,
    val imageUrl: String?,
)
