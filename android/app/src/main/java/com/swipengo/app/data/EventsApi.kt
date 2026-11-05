package com.swipengo.app.data

/** Backend calls for events. The UI depends on this, not on HTTP details. */
interface EventsApi {
    /** Upcoming events, soonest first. Throws [EventsApiException] on failure. */
    suspend fun listEvents(limit: Int): List<Event>
}

sealed class EventsApiException(message: String, cause: Throwable? = null) : Exception(message, cause) {
    /** Couldn't connect, or the connection dropped. */
    class Network(cause: Throwable) :
        EventsApiException("Can't reach the server. Check your connection and try again.", cause)

    /** Server answered with a non-2xx status. [code] comes from the JSON error body when present. */
    class Server(val status: Int, val code: String?, message: String) : EventsApiException(message)

    /** Server answered 2xx but the body wasn't what the API contract says. */
    class MalformedResponse(cause: Throwable) :
        EventsApiException("Got an unexpected response from the server.", cause)
}
