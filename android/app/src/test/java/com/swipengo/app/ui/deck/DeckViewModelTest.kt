package com.swipengo.app.ui.deck

import com.swipengo.app.data.Event
import com.swipengo.app.data.EventsApi
import com.swipengo.app.data.EventsApiException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.io.IOException
import java.time.OffsetDateTime

@OptIn(ExperimentalCoroutinesApi::class)
class DeckViewModelTest {

    private val dispatcher = StandardTestDispatcher()

    private class FakeEventsApi : EventsApi {
        val results = ArrayDeque<Result<List<Event>>>()
        val requestedLimits = mutableListOf<Int>()

        override suspend fun listEvents(limit: Int): List<Event> {
            requestedLimits += limit
            return results.removeFirst().getOrThrow()
        }
    }

    private val api = FakeEventsApi()

    @Before
    fun setUp() = Dispatchers.setMain(dispatcher)

    @After
    fun tearDown() = Dispatchers.resetMain()

    @Test
    fun startsLoadingThenShowsDeck() = runTest(dispatcher) {
        api.results += Result.success(listOf(event("a"), event("b")))

        val viewModel = DeckViewModel(api)
        assertEquals(DeckUiState.Loading, viewModel.state.value)

        advanceUntilIdle()
        val deck = viewModel.state.value as DeckUiState.Deck
        assertEquals("a", deck.current?.id)
        assertEquals("b", deck.next?.id)
        assertEquals(listOf(DeckViewModel.PAGE_SIZE), api.requestedLimits)
    }

    @Test
    fun emptyResponseShowsEmptyState() = runTest(dispatcher) {
        api.results += Result.success(emptyList())

        val viewModel = DeckViewModel(api)
        advanceUntilIdle()

        assertEquals(DeckUiState.Empty, viewModel.state.value)
    }

    @Test
    fun failureShowsErrorWithMessage() = runTest(dispatcher) {
        api.results += Result.failure(EventsApiException.Server(503, "datastore_unavailable", "Events are temporarily unavailable"))

        val viewModel = DeckViewModel(api)
        advanceUntilIdle()

        assertEquals(DeckUiState.Error("Events are temporarily unavailable"), viewModel.state.value)
    }

    @Test
    fun retryAfterNetworkErrorLoadsEvents() = runTest(dispatcher) {
        api.results += Result.failure(EventsApiException.Network(IOException("connection refused")))
        api.results += Result.success(listOf(event("a")))

        val viewModel = DeckViewModel(api)
        advanceUntilIdle()
        assertTrue(viewModel.state.value is DeckUiState.Error)

        viewModel.load()
        assertEquals(DeckUiState.Loading, viewModel.state.value)
        advanceUntilIdle()
        assertEquals("a", (viewModel.state.value as DeckUiState.Deck).current?.id)
    }

    @Test
    fun swipingAdvancesAndRemembersInterest() = runTest(dispatcher) {
        api.results += Result.success(listOf(event("a"), event("b"), event("c")))
        val viewModel = DeckViewModel(api)
        advanceUntilIdle()

        viewModel.swipe(SwipeDirection.RIGHT)
        viewModel.swipe(SwipeDirection.LEFT)

        val deck = viewModel.state.value as DeckUiState.Deck
        assertEquals("c", deck.current?.id)
        assertEquals(setOf("a"), deck.interestedIds)
    }

    @Test
    fun swipingPastLastCardFinishesDeck() = runTest(dispatcher) {
        api.results += Result.success(listOf(event("a")))
        val viewModel = DeckViewModel(api)
        advanceUntilIdle()

        viewModel.swipe(SwipeDirection.RIGHT)
        viewModel.swipe(SwipeDirection.RIGHT) // extra swipe is ignored

        val deck = viewModel.state.value as DeckUiState.Deck
        assertTrue(deck.isFinished)
        assertEquals(1, deck.currentIndex)
        assertEquals(setOf("a"), deck.interestedIds)
    }

    @Test
    fun swipeWhileLoadingDoesNothing() = runTest(dispatcher) {
        api.results += Result.success(listOf(event("a")))
        val viewModel = DeckViewModel(api)

        viewModel.swipe(SwipeDirection.RIGHT)

        assertEquals(DeckUiState.Loading, viewModel.state.value)
    }

    private fun event(id: String) = Event(
        id = id,
        title = "Event $id",
        description = "",
        startTime = OffsetDateTime.parse("2026-11-06T19:00:00Z"),
        endTime = null,
        locationName = "Somewhere",
        latitude = null,
        longitude = null,
        category = "social",
        imageUrl = null,
    )
}
