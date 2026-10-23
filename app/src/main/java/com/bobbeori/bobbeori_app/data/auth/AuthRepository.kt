package com.bobbeori.bobbeori_app.data.auth

import com.bobbeori.bobbeori_app.data.supabase.SupabaseProvider
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.postgrest.from

class AuthRepository {
    private val supabase = SupabaseProvider.client

    suspend fun connect(): Profile {
        if (supabase.auth.currentSessionOrNull() == null) {
            supabase.auth.signInAnonymously()
        }

        val userId = checkNotNull(supabase.auth.currentUserOrNull()?.id) {
            "익명 로그인 후 사용자 정보를 찾을 수 없습니다."
        }

        return supabase.from("profiles")
            .select {
                filter { eq("id", userId) }
            }
            .decodeSingle()
    }
}
