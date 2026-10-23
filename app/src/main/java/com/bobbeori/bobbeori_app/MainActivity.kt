package com.bobbeori.bobbeori_app

import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.getValue
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.bobbeori.bobbeori_app.feature.home.ConnectionState
import com.bobbeori.bobbeori_app.feature.home.MainViewModel
import com.bobbeori.bobbeori_app.feature.home.SubmissionState
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
                val uiState by mainViewModel.uiState.collectAsState()
                LaunchedEffect(sharedText) {
                    sharedText?.let { mainViewModel.updateVideoUrl(it, fromShare = true) }
                }
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
                            text = "유튜브 요리 영상 링크를 넣으면 레시피 분석을 시작해요.",
                            style = MaterialTheme.typography.bodyLarge,
                        )
                        when (val state = uiState.connection) {
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
                        OutlinedTextField(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(top = 24.dp),
                            value = uiState.videoUrl,
                            onValueChange = mainViewModel::updateVideoUrl,
                            label = { Text("YouTube 링크") },
                            placeholder = { Text("https://youtu.be/...") },
                            singleLine = true,
                            isError = uiState.urlError != null,
                            supportingText = uiState.urlError?.let { message ->
                                { Text(message) }
                            },
                            enabled = uiState.submission !is SubmissionState.Submitting,
                        )
                        Button(
                            modifier = Modifier.padding(top = 24.dp),
                            onClick = mainViewModel::submit,
                            enabled = uiState.connection is ConnectionState.Connected &&
                                uiState.submission !is SubmissionState.Submitting,
                        ) {
                            Text(
                                if (uiState.submission is SubmissionState.Submitting) {
                                    "요청 중..."
                                } else {
                                    "레시피 분석 시작"
                                },
                            )
                        }
                        when (val submission = uiState.submission) {
                            SubmissionState.Idle, SubmissionState.Submitting -> Unit
                            is SubmissionState.Queued -> Text(
                                modifier = Modifier.padding(top = 16.dp),
                                text = when (submission.job.status) {
                                    "COMPLETED" -> "레시피 분석이 완료됐어요."
                                    "NEEDS_REVIEW" -> "분석 완료 · 확인이 필요한 정보가 있어요."
                                    else -> "분석 요청이 등록됐어요. · ${submission.job.status}"
                                },
                                color = MaterialTheme.colorScheme.primary,
                            )
                            is SubmissionState.Error -> Text(
                                modifier = Modifier.padding(top = 16.dp),
                                text = submission.message,
                                color = MaterialTheme.colorScheme.error,
                            )
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
