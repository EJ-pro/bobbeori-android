package com.bobbeori.bobbeori_app.data.auth

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class Profile(
    val id: String,
    val locale: String,
    val timezone: String,
    @SerialName("is_anonymous_snapshot")
    val isAnonymous: Boolean,
)
