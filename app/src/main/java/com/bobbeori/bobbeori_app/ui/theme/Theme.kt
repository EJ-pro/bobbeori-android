package com.bobbeori.bobbeori_app.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable

private val LightColors = lightColorScheme(
    primary = BobbeoriBlue,
    primaryContainer = BobbeoriBlueContainer,
    onPrimaryContainer = BobbeoriInk,
    background = BobbeoriBackground,
    onBackground = BobbeoriInk,
)

private val DarkColors = darkColorScheme(
    primary = BobbeoriBlueContainer,
)

@Composable
fun BobbeoriTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit,
) {
    MaterialTheme(
        colorScheme = if (darkTheme) DarkColors else LightColors,
        typography = BobbeoriTypography,
        content = content,
    )
}
