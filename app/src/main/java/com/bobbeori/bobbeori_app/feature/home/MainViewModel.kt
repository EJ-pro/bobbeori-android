package com.bobbeori.bobbeori_app.feature.home

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bobbeori.bobbeori_app.data.auth.AuthRepository
import com.bobbeori.bobbeori_app.data.auth.Profile
import com.bobbeori.bobbeori_app.data.extraction.ExtractionJob
import com.bobbeori.bobbeori_app.data.extraction.ExtractionRepository
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.net.URI

sealed interface ConnectionState {
    data object Loading : ConnectionState
    data class Connected(val profile: Profile) : ConnectionState
    data class Error(val message: String) : ConnectionState
}

sealed interface SubmissionState {
    data object Idle : SubmissionState
    data object Submitting : SubmissionState
    data class Queued(val job: ExtractionJob) : SubmissionState
    data class Error(val message: String) : SubmissionState
}

data class HomeUiState(
    val connection: ConnectionState = ConnectionState.Loading,
    val videoUrl: String = "",
    val inputMethod: String = "PASTE",
    val urlError: String? = null,
    val submission: SubmissionState = SubmissionState.Idle,
)

class MainViewModel(
    private val authRepository: AuthRepository = AuthRepository(),
    private val extractionRepository: ExtractionRepository = ExtractionRepository(),
) : ViewModel() {
    private val _uiState = MutableStateFlow(HomeUiState())
    val uiState: StateFlow<HomeUiState> = _uiState.asStateFlow()

    init {
        connect()
    }

    fun connect() {
        _uiState.value = _uiState.value.copy(connection = ConnectionState.Loading)
        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(
                connection = runCatching { authRepository.connect() }
                    .fold(
                        onSuccess = ConnectionState::Connected,
                        onFailure = { ConnectionState.Error(it.message ?: "Supabase 연결에 실패했습니다.") },
                    ),
            )
        }
    }

    fun updateVideoUrl(value: String, fromShare: Boolean = false) {
        val normalizedValue = if (fromShare) extractYoutubeUrl(value) ?: value.trim() else value.trim()
        _uiState.value = _uiState.value.copy(
            videoUrl = normalizedValue,
            inputMethod = if (fromShare) "SHARE" else "PASTE",
            urlError = null,
            submission = SubmissionState.Idle,
        )
    }

    fun submit() {
        val state = _uiState.value
        if (state.connection !is ConnectionState.Connected || state.submission is SubmissionState.Submitting) return
        if (!isSupportedYoutubeUrl(state.videoUrl)) {
            _uiState.value = state.copy(urlError = "올바른 YouTube 영상 링크를 입력해 주세요.")
            return
        }

        _uiState.value = state.copy(urlError = null, submission = SubmissionState.Submitting)
        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(
                submission = runCatching {
                    extractionRepository.createJob(state.videoUrl, state.inputMethod)
                }.fold(
                    onSuccess = SubmissionState::Queued,
                    onFailure = { SubmissionState.Error(it.message ?: "분석 요청에 실패했습니다.") },
                ),
            )
        }
    }
}

internal fun isSupportedYoutubeUrl(value: String): Boolean = runCatching {
    val uri = URI(value.trim())
    val host = uri.host?.lowercase()?.removePrefix("www.") ?: return@runCatching false
    val path = uri.path.orEmpty()
    val isYoutubeHost = host == "youtube.com" || host.endsWith(".youtube.com")
    val isShortHost = host == "youtu.be"
    (isYoutubeHost && (path == "/watch" || path.startsWith("/shorts/") || path.startsWith("/live/"))) ||
        (isShortHost && path.length > 1)
}.getOrDefault(false)

internal fun extractYoutubeUrl(value: String): String? =
    Regex("https?://(?:www\\.)?(?:youtube\\.com|youtu\\.be)/[^\\s]+", RegexOption.IGNORE_CASE)
        .find(value)
        ?.value
