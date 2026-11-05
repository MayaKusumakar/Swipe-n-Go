package com.swipengo.app.data

import org.json.JSONException
import org.json.JSONObject
import java.time.OffsetDateTime
import java.time.format.DateTimeParseException

object EventJsonParser {

    /** Parses `{"events": [...], "count": n}`. Throws [EventsApiException.MalformedResponse]. */
    fun parseEventList(body: String): List<Event> = try {
        val events = JSONObject(body).getJSONArray("events")
        (0 until events.length()).map { parseEvent(events.getJSONObject(it)) }
    } catch (e: JSONException) {
        throw EventsApiException.MalformedResponse(e)
    } catch (e: DateTimeParseException) {
        throw EventsApiException.MalformedResponse(e)
    }

    /** Parses `{"error": {"code", "message"}}`, or null if the body isn't in that shape. */
    fun parseError(body: String): Pair<String, String>? = try {
        val error = JSONObject(body).getJSONObject("error")
        error.getString("code") to error.getString("message")
    } catch (e: JSONException) {
        null
    }

    private fun parseEvent(json: JSONObject) = Event(
        id = json.getString("id"),
        title = json.getString("title"),
        description = json.optString("description"),
        startTime = OffsetDateTime.parse(json.getString("start_time")),
        endTime = json.stringOrNull("end_time")?.let(OffsetDateTime::parse),
        locationName = json.optString("location_name"),
        latitude = json.doubleOrNull("latitude"),
        longitude = json.doubleOrNull("longitude"),
        category = json.optString("category"),
        imageUrl = json.stringOrNull("image_url"),
    )

    // optString() turns JSON null into the string "null", so check explicitly.
    private fun JSONObject.stringOrNull(name: String): String? =
        if (isNull(name)) null else getString(name)

    private fun JSONObject.doubleOrNull(name: String): Double? =
        if (isNull(name)) null else getDouble(name)
}
