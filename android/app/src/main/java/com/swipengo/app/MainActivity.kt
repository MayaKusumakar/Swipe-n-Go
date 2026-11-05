package com.swipengo.app

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Scaffold
import androidx.compose.ui.Modifier
import androidx.lifecycle.viewmodel.compose.viewModel
import com.swipengo.app.data.HttpEventsApi
import com.swipengo.app.ui.deck.DeckViewModel
import com.swipengo.app.ui.deck.SwipeDeckScreen
import com.swipengo.app.ui.theme.SwipeNGoTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        // Set with -PswipeNGo.apiBaseUrl=... (see gradle.properties).
        val api = HttpEventsApi(BuildConfig.API_BASE_URL)
        setContent {
            SwipeNGoTheme {
                Scaffold(modifier = Modifier.fillMaxSize()) { padding ->
                    val deckViewModel: DeckViewModel = viewModel(factory = DeckViewModel.factory(api))
                    SwipeDeckScreen(deckViewModel, Modifier.padding(padding))
                }
            }
        }
    }
}
