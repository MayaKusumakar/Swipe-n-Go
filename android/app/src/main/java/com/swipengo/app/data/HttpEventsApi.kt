package com.swipengo.app.data

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL

/** [EventsApi] over plain HTTP. [baseUrl] is e.g. "http://10.0.2.2:8080". */
class HttpEventsApi(
    private val baseUrl: String,
    private val timeoutMillis: Int = 10_000,
) : EventsApi {

    override suspend fun listEvents(limit: Int): List<Event> = withContext(Dispatchers.IO) {
        val body = get("/api/events?limit=$limit")
        EventJsonParser.parseEventList(body)
    }

    /** Returns the body of a 2xx response; throws [EventsApiException] otherwise. */
    private fun get(path: String): String {
        val connection = try {
            URL(baseUrl.trimEnd('/') + path).openConnection() as HttpURLConnection
        } catch (e: IOException) {
            throw EventsApiException.Network(e)
        }
        try {
            connection.connectTimeout = timeoutMillis
            connection.readTimeout = timeoutMillis
            connection.setRequestProperty("Accept", "application/json")

            val status = connection.responseCode
            val stream = if (status in 200..299) connection.inputStream else connection.errorStream
            val body = stream?.bufferedReader()?.use { it.readText() }.orEmpty()

            if (status !in 200..299) {
                val error = EventJsonParser.parseError(body)
                throw EventsApiException.Server(
                    status = status,
                    code = error?.first,
                    message = error?.second ?: "Server error ($status). Try again later.",
                )
            }
            return body
        } catch (e: IOException) {
            throw EventsApiException.Network(e)
        } finally {
            connection.disconnect()
        }
    }
}
