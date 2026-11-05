package com.swipengo.app.data

import com.sun.net.httpserver.HttpServer
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Before
import org.junit.Test
import java.net.InetSocketAddress
import java.net.ServerSocket

/** Runs HttpEventsApi against a real local HTTP server (the JDK's built-in one). */
class HttpEventsApiTest {

    private lateinit var server: HttpServer
    private var responseStatus = 200
    private var responseBody = ""
    private var requestedUri: String? = null

    @Before
    fun startServer() {
        server = HttpServer.create(InetSocketAddress("127.0.0.1", 0), 0)
        server.createContext("/") { exchange ->
            requestedUri = exchange.requestURI.toString()
            val bytes = responseBody.toByteArray()
            exchange.responseHeaders.add("Content-Type", "application/json")
            exchange.sendResponseHeaders(responseStatus, bytes.size.toLong().takeIf { it > 0 } ?: -1)
            exchange.responseBody.use { it.write(bytes) }
        }
        server.start()
    }

    @After
    fun stopServer() {
        server.stop(0)
    }

    private fun api() = HttpEventsApi("http://127.0.0.1:${server.address.port}/")

    @Test
    fun successfulResponseIsParsed() = runTest {
        responseBody = EventJsonParserTest.SAMPLE_RESPONSE

        val events = api().listEvents(limit = 20)

        assertEquals("/api/events?limit=20", requestedUri)
        assertEquals(listOf("seed-001", "seed-002"), events.map { it.id })
    }

    @Test
    fun serverErrorCarriesCodeAndMessage() = runTest {
        responseStatus = 503
        responseBody = """{"error": {"code": "datastore_unavailable", "message": "Events are temporarily unavailable"}}"""

        val error = expect<EventsApiException.Server> { api().listEvents(20) }

        assertEquals(503, error.status)
        assertEquals("datastore_unavailable", error.code)
        assertEquals("Events are temporarily unavailable", error.message)
    }

    @Test
    fun serverErrorWithoutJsonBodyGetsGenericMessage() = runTest {
        responseStatus = 500
        responseBody = "Internal Server Error"

        val error = expect<EventsApiException.Server> { api().listEvents(20) }

        assertEquals(500, error.status)
        assertEquals(null, error.code)
        assertTrue(error.message!!.contains("500"))
    }

    @Test
    fun malformedSuccessBody() = runTest {
        responseBody = "<html>not json</html>"

        expect<EventsApiException.MalformedResponse> { api().listEvents(20) }
    }

    @Test
    fun unreachableServerIsNetworkError() = runTest {
        // Grab a free port, then close it so nothing is listening there.
        val closedPort = ServerSocket(0).use { it.localPort }

        expect<EventsApiException.Network> {
            HttpEventsApi("http://127.0.0.1:$closedPort", timeoutMillis = 2_000).listEvents(20)
        }
    }

    private suspend inline fun <reified T : EventsApiException> expect(block: suspend () -> Unit): T {
        try {
            block()
        } catch (e: EventsApiException) {
            if (e is T) return e
            fail("Expected ${T::class.simpleName} but got ${e::class.simpleName}")
        }
        fail("Expected ${T::class.simpleName} but nothing was thrown")
        throw AssertionError()
    }
}
