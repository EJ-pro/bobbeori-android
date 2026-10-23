package com.bobbeori.bobbeori_app.data.extraction

import kotlinx.serialization.Serializable

@Serializable
data class ValidateVideoRequest(val url: String, val inputMethod: String)

@Serializable
data class ValidatedVideo(
    val sourceVideoId: String,
    val canonicalUrl: String,
    val platformVideoId: String,
    val title: String? = null,
    val channelName: String? = null,
    val thumbnailUrl: String? = null,
    val availability: String,
    val analysisSupport: String,
)

@Serializable
data class CreateExtractionRequest(
    val sourceVideoId: String,
    val allowLimitedAnalysis: Boolean = false,
)

@Serializable
data class ProcessExtractionRequest(val jobId: String)

@Serializable
data class ExtractionJob(
    val jobId: String,
    val status: String,
    val cacheHit: Boolean,
    val recipeSourceId: String? = null,
)

@Serializable
data class ApiEnvelope<T>(val data: T, val requestId: String)

@Serializable
data class ApiErrorEnvelope(val error: ApiError, val requestId: String? = null)

@Serializable
data class ApiError(val code: String, val message: String, val retryable: Boolean)
