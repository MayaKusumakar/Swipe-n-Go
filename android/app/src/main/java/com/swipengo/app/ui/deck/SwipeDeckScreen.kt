package com.swipengo.app.ui.deck

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import com.swipengo.app.data.Event
import kotlinx.coroutines.launch
import kotlin.math.abs
import kotlin.math.absoluteValue
import kotlin.math.roundToInt

/** Fraction of the card width a drag must pass to count as a swipe. */
private const val SWIPE_THRESHOLD = 0.3f

@Composable
fun SwipeDeckScreen(viewModel: DeckViewModel, modifier: Modifier = Modifier) {
    val state by viewModel.state.collectAsState()
    SwipeDeckContent(
        state = state,
        onSwipe = viewModel::swipe,
        onReload = viewModel::load,
        modifier = modifier,
    )
}

/** Stateless so it can be previewed and UI-tested without a ViewModel. */
@Composable
fun SwipeDeckContent(
    state: DeckUiState,
    onSwipe: (SwipeDirection) -> Unit,
    onReload: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Box(modifier.fillMaxSize().padding(16.dp), contentAlignment = Alignment.Center) {
        when (state) {
            DeckUiState.Loading -> Column(horizontalAlignment = Alignment.CenterHorizontally) {
                CircularProgressIndicator()
                Spacer(Modifier.height(12.dp))
                Text("Loading events…")
            }
            DeckUiState.Empty -> StatusMessage(
                title = "No upcoming events yet",
                body = "Check back soon.",
                actionLabel = "Refresh",
                onAction = onReload,
            )
            is DeckUiState.Error -> StatusMessage(
                title = "Couldn't load events",
                body = state.message,
                actionLabel = "Retry",
                onAction = onReload,
            )
            is DeckUiState.Deck -> {
                val current = state.current
                if (current == null) {
                    StatusMessage(
                        title = "You're all caught up",
                        body = "You were interested in ${state.interestedIds.size} of ${state.events.size} events.",
                        actionLabel = "Start over",
                        onAction = onReload,
                    )
                } else {
                    Deck(current = current, next = state.next, onSwipe = onSwipe)
                }
            }
        }
    }
}

@Composable
private fun Deck(current: Event, next: Event?, onSwipe: (SwipeDirection) -> Unit) {
    // Keyed by event so each new top card starts centered.
    val cardState = remember(current.id) { SwipeCardState() }
    val scope = rememberCoroutineScope()
    val swipeWithAnimation: (SwipeDirection) -> Unit = { direction ->
        if (!cardState.isFlinging) {
            scope.launch {
                cardState.fling(direction)
                onSwipe(direction)
            }
        }
    }

    Column(Modifier.fillMaxSize()) {
        Box(Modifier.weight(1f).fillMaxWidth()) {
            if (next != null) {
                // Peek at the next card underneath.
                EventCard(next, expanded = false, modifier = Modifier.scale(0.95f))
            }
            SwipeableEventCard(current, cardState, onSwiped = onSwipe)
        }
        Spacer(Modifier.height(16.dp))
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(16.dp)) {
            OutlinedButton(
                onClick = { swipeWithAnimation(SwipeDirection.LEFT) },
                modifier = Modifier.weight(1f).testTag("skip_button"),
            ) { Text("Skip") }
            Button(
                onClick = { swipeWithAnimation(SwipeDirection.RIGHT) },
                modifier = Modifier.weight(1f).testTag("interested_button"),
            ) { Text("Interested") }
        }
    }
}

/** Horizontal position of the top card. Lives outside the card so the buttons can fling it too. */
private class SwipeCardState {
    val offsetX = Animatable(0f)
    var widthPx by mutableFloatStateOf(1f)
    var isFlinging by mutableStateOf(false)
        private set

    val progress: Float get() = (offsetX.value / (widthPx * SWIPE_THRESHOLD)).coerceIn(-1f, 1f)

    suspend fun fling(direction: SwipeDirection) {
        isFlinging = true
        val target = if (direction == SwipeDirection.RIGHT) widthPx * 1.5f else -widthPx * 1.5f
        offsetX.animateTo(target, tween(durationMillis = 250))
    }

    suspend fun settle(): SwipeDirection? {
        val threshold = widthPx * SWIPE_THRESHOLD
        return when {
            offsetX.value > threshold -> SwipeDirection.RIGHT.also { fling(it) }
            offsetX.value < -threshold -> SwipeDirection.LEFT.also { fling(it) }
            else -> {
                offsetX.animateTo(0f, spring())
                null
            }
        }
    }
}

@Composable
private fun SwipeableEventCard(event: Event, cardState: SwipeCardState, onSwiped: (SwipeDirection) -> Unit) {
    val scope = rememberCoroutineScope()
    val currentOnSwiped by rememberUpdatedState(onSwiped)
    var expanded by remember(event.id) { mutableStateOf(false) }

    Box(
        Modifier
            .fillMaxSize()
            .testTag("event_card")
            .onSizeChanged { cardState.widthPx = it.width.toFloat().coerceAtLeast(1f) }
            .offset { IntOffset(cardState.offsetX.value.roundToInt(), 0) }
            .graphicsLayer { rotationZ = cardState.progress * 8f }
            .pointerInput(event.id) {
                detectHorizontalDragGestures(
                    onDragEnd = {
                        scope.launch { cardState.settle()?.let(currentOnSwiped) }
                    },
                    onDragCancel = {
                        scope.launch { cardState.offsetX.animateTo(0f, spring()) }
                    },
                    onHorizontalDrag = { change, dragAmount ->
                        change.consume()
                        scope.launch { cardState.offsetX.snapTo(cardState.offsetX.value + dragAmount) }
                    },
                )
            }
            .clickable { expanded = !expanded },
    ) {
        EventCard(event, expanded)
        SwipeLabel(progress = cardState.progress)
    }
}

@Composable
private fun SwipeLabel(progress: Float) {
    if (progress == 0f) return
    val interested = progress > 0
    Box(Modifier.fillMaxSize().padding(24.dp), contentAlignment = if (interested) Alignment.TopStart else Alignment.TopEnd) {
        Text(
            text = if (interested) "INTERESTED" else "SKIP",
            color = Color.White,
            fontWeight = FontWeight.Bold,
            modifier = Modifier
                .graphicsLayer { alpha = abs(progress) }
                .background(if (interested) Color(0xFF2E7D32) else Color(0xFFC62828), RoundedCornerShape(8.dp))
                .padding(horizontal = 12.dp, vertical = 6.dp),
        )
    }
}

@Composable
private fun EventCard(event: Event, expanded: Boolean, modifier: Modifier = Modifier) {
    Card(
        modifier = modifier.fillMaxSize(),
        elevation = CardDefaults.cardElevation(defaultElevation = 4.dp),
    ) {
        Column(Modifier.verticalScroll(rememberScrollState(), enabled = expanded)) {
            // Image placeholder until events have images (image_url is null for now).
            Box(
                Modifier.fillMaxWidth().height(160.dp).background(categoryColor(event.category)),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    event.category.uppercase().ifEmpty { "EVENT" },
                    color = Color.White,
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold,
                )
            }
            Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(event.title, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
                Text(formatEventTime(event.startTime, event.endTime), style = MaterialTheme.typography.bodyLarge)
                Text(event.locationName, style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.primary)
                Text(
                    event.description,
                    style = MaterialTheme.typography.bodyMedium,
                    maxLines = if (expanded) Int.MAX_VALUE else 3,
                    overflow = TextOverflow.Ellipsis,
                )
                Text(
                    if (expanded) "Tap to show less" else "Tap for details",
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

@Composable
private fun StatusMessage(title: String, body: String, actionLabel: String, onAction: () -> Unit) {
    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(title, style = MaterialTheme.typography.titleLarge, textAlign = TextAlign.Center)
        Text(body, style = MaterialTheme.typography.bodyMedium, textAlign = TextAlign.Center)
        Button(onClick = onAction, modifier = Modifier.testTag("status_action")) { Text(actionLabel) }
    }
}

private val categoryColors = listOf(
    Color(0xFF00695C), Color(0xFF1565C0), Color(0xFF6A1B9A),
    Color(0xFFAD1457), Color(0xFFEF6C00), Color(0xFF2E7D32),
)

private fun categoryColor(category: String) =
    categoryColors[category.hashCode().absoluteValue % categoryColors.size]
