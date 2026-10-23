package com.bobbeori.bobbeori_app.data.supabase

import com.bobbeori.bobbeori_app.BuildConfig
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.Auth
import io.github.jan.supabase.createSupabaseClient
import io.github.jan.supabase.postgrest.Postgrest

object SupabaseProvider {
    val client: SupabaseClient by lazy {
        check(BuildConfig.SUPABASE_URL.isNotBlank()) {
            "SUPABASE_URL이 설정되지 않았습니다. local.properties를 확인해 주세요."
        }
        check(BuildConfig.SUPABASE_PUBLISHABLE_KEY.isNotBlank()) {
            "SUPABASE_PUBLISHABLE_KEY가 설정되지 않았습니다. local.properties를 확인해 주세요."
        }

        createSupabaseClient(
            supabaseUrl = BuildConfig.SUPABASE_URL,
            supabaseKey = BuildConfig.SUPABASE_PUBLISHABLE_KEY,
        ) {
            install(Auth)
            install(Postgrest)
        }
    }
}
