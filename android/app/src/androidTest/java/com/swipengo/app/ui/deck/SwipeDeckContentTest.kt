package com.swipengo.app.ui.deck

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.swipengo.app.data.Event
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.time.OffsetDateTime

@RunWith(AndroidJUnit4::class)
class SwipeDeckContentTest {

    @get:Rule
    val compose = createComposeRule()

    @Test
    fun errorStateShowsMessageAndRetry() {
        var reloads = 0
        compose.setContent {
            SwipeDeckContent(DeckUiState.Error("Can't reach the server."), onSwipe = {}, onReload = { reloads++ })
        }

        compose.onNodeWithText("Couldn't load events").assertIsDisplayed()
        compose.onNodeWithText("Can't reach the server.").assertIsDisplayed()
        compose.onNodeWithText("Retry").performClick()
        assertEquals(1, reloads)
    }

    @Test
    fun emptyStateOffersRefresh() {
        compose.setContent { SwipeDeckContent(DeckUiState.Empty, onSwipe = {}, onReload = {}) }

        compose.onNodeWithText("No upcoming events yet").assertIsDisplayed()
        compose.onNodeWithText("Refresh").assertIsDisplayed()
    }

    @Test
    fun interestedButtonSwipesRight() {
        val swipes = mutableListOf<SwipeDirection>()
        compose.setContent {
            SwipeDeckContent(DeckUiState.Deck(listOf(event)), onSwipe = { swipes += it }, onReload = {})
        }

        compose.onNodeWithText("Trivia Night").assertIsDisplayed()
        compose.onNodeWithText("Memorial Union").assertIsDisplayed()
        compose.onNodeWithTag("interested_button").performClick()
        compose.waitForIdle()
        assertEquals(listOf(SwipeDirection.RIGHT), swipes)
    }

    private val event = Event(
        id = "seed-001",
        title = "Trivia Night",
        description = "Teams of up to 6.",
        startTime = OffsetDateTime.parse("2026-11-07T03:00:00Z"),
        endTime = null,
        locationName = "Memorial Union",
        latitude = null,
        longitude = null,
        category = "social",
        imageUrl = null,
    )
}
