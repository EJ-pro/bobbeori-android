package com.bobbeori.bobbeori_app.feature.home

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.bobbeori.bobbeori_app.data.auth.AuthRepository
import com.bobbeori.bobbeori_app.data.auth.Profile
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

sealed interface ConnectionState {
    data object Loading : ConnectionState
    data class Connected(val profile: Profile) : ConnectionState
    data class Error(val message: String) : ConnectionState
}

class MainViewModel(
    private val authRepository: AuthRepository = AuthRepository(),
) : ViewModel() {
    private val _connectionState = MutableStateFlow<ConnectionState>(ConnectionState.Loading)
    val connectionState: StateFlow<ConnectionState> = _connectionState.asStateFlow()

    init {
        connect()
    }

    fun connect() {
        _connectionState.value = ConnectionState.Loading
        viewModelScope.launch {
            _connectionState.value = runCatching { authRepository.connect() }
                .fold(
                    onSuccess = ConnectionState::Connected,
                    onFailure = { ConnectionState.Error(it.message ?: "Supabase 연결에 실패했습니다.") },
                )
        }
    }
}
