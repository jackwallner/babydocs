package com.jackwallner.babydocs.ui.theme

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.automirrored.rounded.KeyboardArrowRight
import androidx.compose.material.icons.rounded.AccountBalance
import androidx.compose.material.icons.rounded.Badge
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.Flight
import androidx.compose.material.icons.rounded.FamilyRestroom
import androidx.compose.material.icons.rounded.Home
import androidx.compose.material.icons.rounded.MedicalServices
import androidx.compose.material.icons.rounded.RadioButtonUnchecked
import androidx.compose.material.icons.rounded.Work
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.jackwallner.babydocs.model.RequirementCategory

/** Dialogs are their own window, so test tags must be exposed again inside each one. */
@OptIn(androidx.compose.ui.ExperimentalComposeUiApi::class)
val DialogTags: Modifier = Modifier.semantics { testTagsAsResourceId = true }

val RequirementCategory.icon: ImageVector
    get() = when (this) {
        RequirementCategory.IDENTITY -> Icons.Rounded.Badge
        RequirementCategory.INSURANCE -> Icons.Rounded.MedicalServices
        RequirementCategory.PARENTAGE -> Icons.Rounded.FamilyRestroom
        RequirementCategory.MONEY -> Icons.Rounded.AccountBalance
        RequirementCategory.TRAVEL -> Icons.Rounded.Flight
        RequirementCategory.WORK -> Icons.Rounded.Work
        RequirementCategory.HOUSEHOLD -> Icons.Rounded.Home
    }

/**
 * A tab page or pushed screen: grouped background, large title, one scrolling list.
 * Records are plain mutable objects behind `BabyStore.revision`, so every lazy
 * item reads that revision itself: strong skipping would otherwise keep an item
 * whose captured record is the same instance and draw it stale after a commit.
 */
@Composable
fun Page(
    title: String,
    modifier: Modifier = Modifier,
    onBack: (() -> Unit)? = null,
    actions: @Composable RowScope.() -> Unit = {},
    bottomInset: Boolean = false,
    content: LazyListScope.() -> Unit,
) {
    val c = AppTheme.colors
    Column(modifier.fillMaxSize().background(c.page).windowInsetsPadding(WindowInsets.statusBars)) {
        Row(
            Modifier.fillMaxWidth().heightIn(min = 52.dp).padding(horizontal = if (onBack != null) 4.dp else AppTheme.margin),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            if (onBack != null) {
                IconButton(onClick = onBack, modifier = Modifier.testTag("back")) {
                    Icon(Icons.AutoMirrored.Rounded.ArrowBack, contentDescription = "Back", tint = c.accent)
                }
                Text(title, style = Type.headline, color = c.label, maxLines = 1, modifier = Modifier.weight(1f).semantics { heading() })
            } else {
                Text(title, style = Type.largeTitle, color = c.label, modifier = Modifier.weight(1f).padding(top = 8.dp).semantics { heading() })
            }
            actions()
        }
        LazyColumn(
            Modifier.fillMaxSize(),
            contentPadding = PaddingValues(start = AppTheme.margin, end = AppTheme.margin, top = 8.dp, bottom = if (bottomInset) 24.dp else 32.dp),
            verticalArrangement = Arrangement.spacedBy(AppTheme.tightSpacing),
            content = content,
        )
    }
}

@Composable
fun Card(modifier: Modifier = Modifier, padding: PaddingValues = PaddingValues(AppTheme.spacing), content: @Composable ColumnScope.() -> Unit) {
    Column(
        modifier.fillMaxWidth().clip(RoundedCornerShape(AppTheme.cardRadius)).background(AppTheme.colors.surface).padding(padding),
        content = content,
    )
}

@Composable
fun SectionHeader(text: String, modifier: Modifier = Modifier, blurb: String = "") {
    Column(modifier.padding(top = AppTheme.spacing, bottom = 2.dp, start = 4.dp)) {
        Text(text.uppercase(), style = Type.sectionHeader, color = AppTheme.colors.secondary, modifier = Modifier.semantics { heading() })
        if (blurb.isNotEmpty()) Text(blurb, style = Type.footnote, color = AppTheme.colors.secondary)
    }
}

@Composable
fun Footnote(text: String, modifier: Modifier = Modifier) {
    Text(text, style = Type.footnote, color = AppTheme.colors.secondary, modifier = modifier.padding(horizontal = 4.dp))
}

/** A tappable row in a card, with an optional leading glyph and trailing value. */
@Composable
fun NavRow(
    title: String,
    modifier: Modifier = Modifier,
    subtitle: String = "",
    value: String = "",
    icon: ImageVector? = null,
    titleColor: Color = Color.Unspecified,
    onClick: () -> Unit,
) {
    val c = AppTheme.colors
    Row(
        modifier.fillMaxWidth().heightIn(min = AppTheme.minTouch).clickable(role = Role.Button, onClick = onClick).padding(horizontal = AppTheme.spacing, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (icon != null) {
            Icon(icon, contentDescription = null, tint = c.secondary, modifier = Modifier.size(22.dp))
            Spacer(Modifier.width(AppTheme.spacing))
        }
        Column(Modifier.weight(1f)) {
            Text(title, style = Type.body, color = if (titleColor == Color.Unspecified) c.label else titleColor)
            if (subtitle.isNotEmpty()) Text(subtitle, style = Type.footnote, color = c.secondary)
        }
        if (value.isNotEmpty()) Text(value, style = Type.body, color = c.secondary, modifier = Modifier.padding(start = 8.dp))
        Icon(Icons.AutoMirrored.Rounded.KeyboardArrowRight, contentDescription = null, tint = c.tertiary)
    }
}

@Composable
fun ToggleRow(title: String, checked: Boolean, modifier: Modifier = Modifier, subtitle: String = "", enabled: Boolean = true, onChange: (Boolean) -> Unit) {
    val c = AppTheme.colors
    Row(
        modifier.fillMaxWidth().heightIn(min = AppTheme.minTouch)
            .toggleable(value = checked, enabled = enabled, role = Role.Switch, onValueChange = onChange)
            .padding(horizontal = AppTheme.spacing, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f)) {
            Text(title, style = Type.body, color = if (enabled) c.label else c.tertiary)
            if (subtitle.isNotEmpty()) Text(subtitle, style = Type.footnote, color = c.secondary)
        }
        Switch(checked = checked, onCheckedChange = null, enabled = enabled)
    }
}

/** One choice in a single-select list, drawn as a radio row. */
@Composable
fun ChoiceRow(title: String, selected: Boolean, modifier: Modifier = Modifier, subtitle: String = "", onSelect: () -> Unit) {
    val c = AppTheme.colors
    Row(
        modifier.fillMaxWidth().heightIn(min = AppTheme.minTouch)
            .selectable(selected = selected, role = Role.RadioButton, onClick = onSelect)
            .padding(horizontal = AppTheme.spacing, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f)) {
            Text(title, style = Type.body, color = c.label)
            if (subtitle.isNotEmpty()) Text(subtitle, style = Type.footnote, color = c.secondary)
        }
        Icon(
            if (selected) Icons.Rounded.CheckCircle else Icons.Rounded.RadioButtonUnchecked,
            contentDescription = null,
            tint = if (selected) c.accent else c.tertiary,
        )
    }
}

@Composable
fun RowDivider(inset: Boolean = false) {
    HorizontalDivider(Modifier.padding(start = if (inset) 46.dp else AppTheme.spacing), thickness = 0.5.dp, color = AppTheme.colors.separator)
}

@Composable
fun PrimaryButton(title: String, modifier: Modifier = Modifier, enabled: Boolean = true, tag: String = "", onClick: () -> Unit) {
    Button(
        onClick = onClick,
        enabled = enabled,
        shape = RoundedCornerShape(AppTheme.cardRadius),
        colors = ButtonDefaults.buttonColors(containerColor = AppTheme.colors.accent, contentColor = Color.White),
        modifier = modifier.fillMaxWidth().heightIn(min = 52.dp).then(if (tag.isNotEmpty()) Modifier.testTag(tag) else Modifier),
    ) {
        Text(title, style = Type.headline, textAlign = TextAlign.Center)
    }
}

@Composable
fun SecondaryButton(title: String, modifier: Modifier = Modifier, tag: String = "", onClick: () -> Unit) {
    TextButton(
        onClick = onClick,
        modifier = modifier.fillMaxWidth().heightIn(min = AppTheme.minTouch).then(if (tag.isNotEmpty()) Modifier.testTag(tag) else Modifier),
    ) {
        Text(title, style = Type.body, color = AppTheme.colors.accent, textAlign = TextAlign.Center)
    }
}

/** The due-date pill: urgency colour plus words, never colour alone. */
@Composable
fun DuePill(text: String, color: Color, modifier: Modifier = Modifier) {
    Box(modifier.clip(RoundedCornerShape(50)).background(color.copy(alpha = 0.14f)).padding(horizontal = 8.dp, vertical = 3.dp)) {
        Text(text, style = Type.caption.copy(fontWeight = FontWeight.SemiBold), color = color)
    }
}

@Composable
fun Avatar(initials: String, color: Color, modifier: Modifier = Modifier) {
    Box(modifier.size(36.dp).clip(CircleShape).background(color), contentAlignment = Alignment.Center) {
        Text(initials, style = Type.footnote.copy(fontWeight = FontWeight.Bold), color = Color.White)
    }
}

@Composable
fun Hero(icon: ImageVector, title: String, subtitle: String, modifier: Modifier = Modifier) {
    val c = AppTheme.colors
    Column(modifier.fillMaxWidth().padding(vertical = AppTheme.spacing), horizontalAlignment = Alignment.Start) {
        Icon(icon, contentDescription = null, tint = c.accent, modifier = Modifier.size(36.dp))
        Spacer(Modifier.heightIn(min = AppTheme.spacing))
        Text(title, style = Type.title, color = c.label, modifier = Modifier.semantics { heading() })
        Spacer(Modifier.heightIn(min = 6.dp))
        Text(subtitle, style = Type.callout, color = c.secondary)
    }
}
