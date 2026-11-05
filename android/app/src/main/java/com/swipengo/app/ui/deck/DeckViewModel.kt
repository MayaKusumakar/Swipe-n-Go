package com.swipengo.app.ui.deck

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.swipengo.app.data.Event
import com.swipengo.app.data.EventsApi
import com.swipengo.app.data.EventsApiException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

enum class SwipeDirection { LEFT, RIGHT }

sealed interface DeckUiState {
    data object Loading : DeckUiState

    /** The server returned no upcoming events. */
    data object Empty : DeckUiState

    data class Error(val message: String) : DeckUiState

    /**
     * Cards from [currentIndex] onward haven't been swiped yet.
     * [interestedIds] is local-only for Milestone 0 (not sent to the server).
     */
    data class Deck(
        val events: List<Event>,
        val currentIndex: Int = 0,
        val interestedIds: Set<String> = emptySet(),
    ) : DeckUiState {
        val current: Event? get() = events.getOrNull(currentIndex)
        val next: Event? get() = events.getOrNull(currentIndex + 1)
        val isFinished: Boolean get() = currentIndex >= events.size
    }
}

class DeckViewModel(private val api: EventsApi) : ViewModel() {

    private val _state = MutableStateFlow<DeckUiState>(DeckUiState.Loading)
    val state: StateFlow<DeckUiState> = _state.asStateFlow()

    init {
        load()
    }

    fun load() {
        _state.value = DeckUiState.Loading
        viewModelScope.launch {
            _state.value = try {
                val events = api.listEvents(PAGE_SIZE)
                if (events.isEmpty()) DeckUiState.Empty else DeckUiState.Deck(events)
            } catch (e: EventsApiException) {
                DeckUiState.Error(e.message ?: "Something went wrong.")
            }
        }
    }

    fun swipe(direction: SwipeDirection) {
        val deck = _state.value as? DeckUiState.Deck ?: return
        val event = deck.current ?: return
        _state.value = deck.copy(
            currentIndex = deck.currentIndex + 1,
            interestedIds = if (direction == SwipeDirection.RIGHT) deck.interestedIds + event.id else deck.interestedIds,
        )
    }

    companion object {
        const val PAGE_SIZE = 20

        fun factory(api: EventsApi) = viewModelFactory {
            initializer { DeckViewModel(api) }
        }
    }
}
