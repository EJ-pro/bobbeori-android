package com.bobbeori.bobbeori_app.data.extraction

import com.bobbeori.bobbeori_app.data.supabase.SupabaseProvider
import io.github.jan.supabase.functions.functions
import io.ktor.client.call.body
import io.ktor.client.plugins.ClientRequestException
import io.ktor.http.Headers
import java.util.UUID

class ExtractionRepository {
    private val supabase = SupabaseProvider.client

    suspend fun createJob(url: String, inputMethod: String): ExtractionJob {
        val validated = invoke<ValidateVideoRequest, ValidatedVideo>(
            function = "validate-video",
            body = ValidateVideoRequest(url = url, inputMethod = inputMethod),
        )
        return invoke<CreateExtractionRequest, ExtractionJob>(
            function = "create-extraction",
            body = CreateExtractionRequest(sourceVideoId = validated.sourceVideoId),
            headers = mapOf("Idempotency-Key" to UUID.randomUUID().toString()),
        )
    }

    private suspend inline fun <reified Request : Any, reified Response : Any> invoke(
        function: String,
        body: Request,
        headers: Map<String, String> = emptyMap(),
    ): Response = try {
        val requestHeaders = Headers.build {
            headers.forEach { (name, value) -> append(name, value) }
        }
        supabase.functions.invoke(function = function, body = body, headers = requestHeaders)
            .body<ApiEnvelope<Response>>()
            .data
    } catch (exception: ClientRequestException) {
        val apiError = runCatching { exception.response.body<ApiErrorEnvelope>() }.getOrNull()
        throw ExtractionException(
            code = apiError?.error?.code ?: "NETWORK_REQUIRED",
            message = apiError?.error?.message ?: "요청을 처리하지 못했습니다. 잠시 후 다시 시도해 주세요.",
        )
    }
}

class ExtractionException(
    val code: String,
    override val message: String,
) : IllegalStateException(message)
