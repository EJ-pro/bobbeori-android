package com.bobbeori.bobbeori_app

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.getValue
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.bobbeori.bobbeori_app.feature.home.ConnectionState
import com.bobbeori.bobbeori_app.feature.home.MainViewModel
import com.bobbeori.bobbeori_app.ui.theme.BobbeoriTheme

class MainActivity : ComponentActivity() {
    private var sharedText by mutableStateOf<String?>(null)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        sharedText = intent.sharedText()
        enableEdgeToEdge()
        setContent {
            BobbeoriTheme {
                val mainViewModel: MainViewModel = viewModel()
                val connectionState by mainViewModel.connectionState.collectAsState()
                Scaffold(modifier = Modifier.fillMaxSize()) { innerPadding ->
                    Column(
                        modifier = Modifier
                            .fillMaxSize()
                            .padding(innerPadding)
                            .padding(horizontal = 24.dp),
                        verticalArrangement = Arrangement.Center,
                        horizontalAlignment = Alignment.CenterHorizontally,
                    ) {
                        Text(
                            text = "밥벌이",
                            style = MaterialTheme.typography.headlineLarge,
                        )
                        Text(
                            modifier = Modifier.padding(top = 12.dp),
                            text = sharedText ?: "유튜브 요리 링크를 준비해 주세요.",
                            style = MaterialTheme.typography.bodyLarge,
                        )
                        when (val state = connectionState) {
                            ConnectionState.Loading -> CircularProgressIndicator(
                                modifier = Modifier.padding(top = 24.dp),
                            )

                            is ConnectionState.Connected -> Text(
                                modifier = Modifier.padding(top = 24.dp),
                                text = "Supabase 연결 완료 · ${if (state.profile.isAnonymous) "익명 사용자" else "회원"}",
                                color = MaterialTheme.colorScheme.primary,
                            )

                            is ConnectionState.Error -> {
                                Text(
                                    modifier = Modifier.padding(top = 24.dp),
                                    text = state.message,
                                    color = MaterialTheme.colorScheme.error,
                                )
                                Button(
                                    modifier = Modifier.padding(top = 8.dp),
                                    onClick = mainViewModel::connect,
                                ) {
                                    Text("다시 연결")
                                }
                            }
                        }
                        Button(
                            modifier = Modifier.padding(top = 24.dp),
                            onClick = { },
                        ) {
                            Text("링크 입력")
                        }
                    }
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        sharedText = intent.sharedText()
    }
}

private fun Intent.sharedText(): String? =
    takeIf { action == Intent.ACTION_SEND && type == "text/plain" }
        ?.getStringExtra(Intent.EXTRA_TEXT)
