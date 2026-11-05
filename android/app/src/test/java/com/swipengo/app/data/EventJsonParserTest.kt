package com.swipengo.app.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.OffsetDateTime

class EventJsonParserTest {

    @Test
    fun parsesEventsFromServerResponse() {
        val events = EventJsonParser.parseEventList(SAMPLE_RESPONSE)

        assertEquals(2, events.size)
        val first = events[0]
        assertEquals("seed-001", first.id)
        assertEquals("Trivia Night", first.title)
        assertEquals("Teams of up to 6.", first.description)
        assertEquals(OffsetDateTime.parse("2026-11-06T19:00:00+00:00"), first.startTime)
        assertEquals(OffsetDateTime.parse("2026-11-06T21:00:00+00:00"), first.endTime)
        assertEquals("Memorial Union", first.locationName)
        assertEquals(38.5424, first.latitude!!, 1e-9)
        assertEquals(-121.7494, first.longitude!!, 1e-9)
        assertEquals("social", first.category)
        assertNull(first.imageUrl)
    }

    @Test
    fun jsonNullsBecomeKotlinNulls() {
        val second = EventJsonParser.parseEventList(SAMPLE_RESPONSE)[1]

        assertNull(second.endTime)
        assertNull(second.latitude)
        assertNull(second.longitude)
        assertNull(second.imageUrl)
    }

    @Test
    fun emptyEventList() {
        assertTrue(EventJsonParser.parseEventList("""{"events": [], "count": 0}""").isEmpty())
    }

    @Test
    fun malformedBodiesThrowMalformedResponse() {
        listOf(
            "not json",
            "{}",
            """{"events": [{"title": "missing id"}]}""",
            """{"events": [{"id": "x", "title": "t", "start_time": "tomorrow"}]}""",
        ).forEach { body ->
            assertThrows(body, EventsApiException.MalformedResponse::class.java) {
                EventJsonParser.parseEventList(body)
            }
        }
    }

    @Test
    fun parsesErrorBody() {
        val error = EventJsonParser.parseError(
            """{"error": {"code": "datastore_unavailable", "message": "Events are temporarily unavailable"}}""",
        )
        assertEquals("datastore_unavailable" to "Events are temporarily unavailable", error)
    }

    @Test
    fun nonErrorBodyGivesNull() {
        assertNull(EventJsonParser.parseError("<html>502 Bad Gateway</html>"))
    }

    companion object {
        val SAMPLE_RESPONSE = """
            {
              "events": [
                {
                  "id": "seed-001", "title": "Trivia Night", "description": "Teams of up to 6.",
                  "start_time": "2026-11-06T19:00:00+00:00", "end_time": "2026-11-06T21:00:00+00:00",
                  "location_name": "Memorial Union", "latitude": 38.5424, "longitude": -121.7494,
                  "category": "social", "image_url": null
                },
                {
                  "id": "seed-002", "title": "Pickup Soccer", "description": "",
                  "start_time": "2026-11-07T00:00:00+00:00", "end_time": null,
                  "location_name": "ARC Fields", "latitude": null, "longitude": null,
                  "category": "sports", "image_url": null
                }
              ],
              "count": 2
            }
        """.trimIndent()
    }
}
