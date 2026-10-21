package com.jackwallner.babydocs.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.jackwallner.babydocs.model.DeadlineKind

/**
 * `AppTheme.swift`: system grouped surfaces, one accent, and one colour system
 * that means one thing, how close a door is to closing. Categories are a grey
 * glyph; nothing else in the app is coloured. Light and dark, as on iOS.
 */
@Immutable
data class Palette(
    val page: Color,
    val surface: Color,
    val raised: Color,
    val label: Color,
    val secondary: Color,
    val tertiary: Color,
    val separator: Color,
    val accent: Color,
    val red: Color,
    val orange: Color,
    val green: Color,
)

val LightPalette = Palette(
    page = Color(0xFFF2F2F7),
    surface = Color.White,
    raised = Color(0xFFF2F2F7),
    label = Color(0xFF000000),
    secondary = Color(0x993C3C43),
    tertiary = Color(0x4D3C3C43),
    separator = Color(0x4A3C3C43),
    accent = Color(0xFF3378D9),
    red = Color(0xFFFF3B30),
    orange = Color(0xFFC75F00),
    green = Color(0xFF248A3D),
)

val DarkPalette = Palette(
    page = Color(0xFF000000),
    surface = Color(0xFF1C1C1E),
    raised = Color(0xFF2C2C2E),
    label = Color.White,
    secondary = Color(0x99EBEBF5),
    tertiary = Color(0x4DEBEBF5),
    separator = Color(0x99545458),
    accent = Color(0xFF5A9DEE),
    red = Color(0xFFFF453A),
    orange = Color(0xFFFF9F0A),
    green = Color(0xFF30D158),
)

val LocalPalette = staticCompositionLocalOf { LightPalette }

object AppTheme {
    /** The only horizontal inset. */
    val margin = 20.dp
    val hairSpacing = 4.dp
    val tightSpacing = 8.dp
    val spacing = 12.dp
    val looseSpacing = 20.dp
    val cardRadius = 14.dp
    val minTouch = 48.dp

    val colors: Palette
        @Composable get() = LocalPalette.current

    /** Urgency owns colour: red inside a week of a hard window, orange for a suggestion, grey otherwise. */
    @Composable
    fun urgency(kind: DeadlineKind, daysRemaining: Int?): Color {
        val c = colors
        return when (kind) {
            DeadlineKind.HARD -> if (daysRemaining == null || daysRemaining <= 7) c.red else c.orange
            DeadlineKind.RECOMMENDED -> c.orange
            DeadlineKind.NONE -> c.secondary
        }
    }

    val childColors = listOf(
        Color(0xFF5C8CDB), Color(0xFFE0878C), Color(0xFF5CAD8C),
        Color(0xFFA880D1), Color(0xFFEBAD52), Color(0xFF52A8B8),
    )

    fun childColor(index: Int): Color = childColors[((index % childColors.size) + childColors.size) % childColors.size]
}

/** iOS Dynamic Type at the default size. */
object Type {
    val largeTitle = TextStyle(fontSize = 32.sp, fontWeight = FontWeight.Bold, lineHeight = 38.sp)
    val title = TextStyle(fontSize = 26.sp, fontWeight = FontWeight.Bold, lineHeight = 32.sp)
    val title2 = TextStyle(fontSize = 22.sp, fontWeight = FontWeight.SemiBold, lineHeight = 28.sp)
    val title3 = TextStyle(fontSize = 20.sp, fontWeight = FontWeight.SemiBold, lineHeight = 25.sp)
    val headline = TextStyle(fontSize = 17.sp, fontWeight = FontWeight.SemiBold, lineHeight = 22.sp)
    val body = TextStyle(fontSize = 17.sp, lineHeight = 23.sp)
    val callout = TextStyle(fontSize = 16.sp, lineHeight = 21.sp)
    val subheadline = TextStyle(fontSize = 15.sp, lineHeight = 20.sp)
    val footnote = TextStyle(fontSize = 13.sp, lineHeight = 18.sp)
    val caption = TextStyle(fontSize = 12.sp, lineHeight = 16.sp)
    val sectionHeader = TextStyle(fontSize = 13.sp, fontWeight = FontWeight.Medium, letterSpacing = 0.3.sp)
}

@Composable
fun BabyDocsTheme(content: @Composable () -> Unit) {
    val dark = isSystemInDarkTheme()
    val palette = if (dark) DarkPalette else LightPalette
    val scheme = if (dark) {
        darkColorScheme(
            primary = palette.accent, onPrimary = Color.White, background = palette.page, surface = palette.surface,
            onSurface = palette.label, onBackground = palette.label, surfaceVariant = palette.raised,
            onSurfaceVariant = palette.secondary, outline = palette.separator, error = palette.red,
            surfaceContainerHigh = palette.surface, surfaceContainer = palette.surface,
        )
    } else {
        lightColorScheme(
            primary = palette.accent, onPrimary = Color.White, background = palette.page, surface = palette.surface,
            onSurface = palette.label, onBackground = palette.label, surfaceVariant = palette.raised,
            onSurfaceVariant = palette.secondary, outline = palette.separator, error = palette.red,
            surfaceContainerHigh = palette.surface, surfaceContainer = palette.surface,
        )
    }
    CompositionLocalProvider(LocalPalette provides palette) {
        MaterialTheme(colorScheme = scheme, content = content)
    }
}
