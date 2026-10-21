package com.jackwallner.babydocs.ui.screens

import androidx.activity.compose.LocalActivity
import android.graphics.Bitmap
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.compose.foundation.Image
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.AddPhotoAlternate
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.Lock
import androidx.compose.material.icons.rounded.RadioButtonUnchecked
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.unit.dp
import androidx.fragment.app.FragmentActivity
import com.jackwallner.babydocs.AppGraph
import com.jackwallner.babydocs.Overlay
import com.jackwallner.babydocs.model.Child
import com.jackwallner.babydocs.model.DocumentItem
import com.jackwallner.babydocs.model.VaultDocument
import com.jackwallner.babydocs.model.VaultDocumentKind
import com.jackwallner.babydocs.rules.RequirementCatalog
import com.jackwallner.babydocs.ui.LocalGraph
import com.jackwallner.babydocs.ui.SearchListDialog
import com.jackwallner.babydocs.ui.theme.AppTheme
import com.jackwallner.babydocs.ui.theme.DialogTags
import com.jackwallner.babydocs.ui.theme.Card
import com.jackwallner.babydocs.ui.theme.Footnote
import com.jackwallner.babydocs.ui.theme.NavRow
import com.jackwallner.babydocs.ui.theme.Page
import com.jackwallner.babydocs.ui.theme.PrimaryButton
import com.jackwallner.babydocs.ui.theme.RowDivider
import com.jackwallner.babydocs.ui.theme.SectionHeader
import com.jackwallner.babydocs.ui.theme.Type
import java.util.UUID

/** Adding is free inside the first twelve weeks after a birth, the window the whole app is built around. */
fun Child.isWithinFreeVaultWindow(): Boolean = ageInDays() <= 84

/** One line of the gather list: the same document across every open task of one child. */
private data class Gather(val child: Child, val title: String, val items: List<DocumentItem>, val taskNames: List<String>) {
    val isOnHand: Boolean get() = items.all { it.isOnHand }
}

private fun gatherList(graph: AppGraph): List<Gather> {
    val data = graph.store.data
    return data.liveChildren.flatMap { child ->
        val open = data.liveTasks(child).filter { it.isOpen }
        open.flatMap { task -> data.liveDocuments(task).map { task to it } }
            .groupBy { it.second.title }
            .map { (title, pairs) ->
                Gather(
                    child, title, pairs.map { it.second },
                    pairs.map { (task, _) -> RequirementCatalog.rule(task.catalogKey)?.shortTitle ?: task.title }.distinct(),
                )
            }
    }
}

/** Unlocks the vault with the device's biometrics or screen lock, once per foreground session. */
fun AppGraph.unlockVault(activity: FragmentActivity?, then: () -> Unit) {
    if (navigator.vaultUnlocked || activity == null) {
        if (activity != null) then()
        return
    }
    val authenticators = BiometricManager.Authenticators.BIOMETRIC_WEAK or BiometricManager.Authenticators.DEVICE_CREDENTIAL
    if (BiometricManager.from(activity).canAuthenticate(authenticators) != BiometricManager.BIOMETRIC_SUCCESS) {
        // No screen lock on this device: there is nothing to unlock with, so the vault is as open as the phone.
        navigator.vaultUnlocked = true
        then()
        return
    }
    val prompt = BiometricPrompt(
        activity,
        object : BiometricPrompt.AuthenticationCallback() {
            override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) {
                navigator.vaultUnlocked = true
                then()
            }
        },
    )
    prompt.authenticate(
        BiometricPrompt.PromptInfo.Builder()
            .setTitle("Unlock the document vault")
            .setAllowedAuthenticators(authenticators)
            .build(),
    )
}

@Composable
fun DocumentsScreen() {
    val graph = LocalGraph.current
    graph.store.revision
    val data = graph.store.data
    val nav = graph.navigator
    val c = AppTheme.colors
    val activity = LocalActivity.current as? FragmentActivity
    var mode by rememberSaveable { mutableStateOf(0) }
    val gather = gatherList(graph)
    val multipleChildren = data.liveChildren.size > 1

    Page("Documents") {
        item {
            SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                listOf("To bring", "Photos").forEachIndexed { i, label ->
                    SegmentedButton(
                        selected = mode == i, onClick = { mode = i },
                        shape = SegmentedButtonDefaults.itemShape(i, 2),
                        modifier = Modifier.testTag("documents-mode-$i"),
                    ) { Text(label) }
                }
            }
        }
        if (mode == 0) {
            val toFind = gather.filter { !it.isOnHand }
            val inHand = gather.filter { it.isOnHand }
            item {
                SectionHeader(
                    "Still to find",
                    blurb = if (multipleChildren) "What to take to each errand. Tick something and it ticks on every task that wants it for that child, and never for the other child."
                    else "What to take to each errand. Tick something and it ticks on every task that wants it.",
                )
            }
            if (toFind.isEmpty()) {
                item { Card { Text("Everything your open tasks ask for is gathered.", style = Type.body, color = c.secondary) } }
            } else {
                item { GatherCard(toFind, graph, multipleChildren) }
            }
            if (inHand.isNotEmpty()) {
                item {
                    SectionHeader("Already in hand · ${inHand.size}", blurb = "Ticked, and deliberately still here: the question at the counter is \"did I already deal with this one\", not only \"what is left\".")
                    GatherCard(inHand, graph, multipleChildren)
                }
            }
        } else {
            item { Footnote("Photographs of papers you already have. Nothing here is a task.") }
            data.liveChildren.forEach { child ->
                item(key = "vault-${child.id}") {
                    val docs = data.liveVault(child)
                    SectionHeader(if (multipleChildren) child.displayName else "Copies on this phone", blurb = "So you are not driving home for the certificate.")
                    Card(padding = PaddingValues(0.dp)) {
                        docs.forEach { doc ->
                            NavRow(
                                doc.displayTitle,
                                subtitle = "${doc.pageFileNames.size} ${if (doc.pageFileNames.size == 1) "page" else "pages"}",
                                icon = Icons.Rounded.Lock,
                                modifier = Modifier.testTag("vault-doc"),
                            ) { graph.unlockVault(activity) { nav.push(Overlay.VaultView(doc.id)) } }
                            RowDivider()
                        }
                        if (graph.subscriptions.isPro || child.isWithinFreeVaultWindow()) {
                            NavRow("Add a document", icon = Icons.Rounded.AddPhotoAlternate, modifier = Modifier.testTag("vault-add")) {
                                graph.unlockVault(activity) { nav.push(Overlay.VaultAdd(child.id)) }
                            }
                        } else {
                            NavRow("Add a document", value = "Plus", icon = Icons.Rounded.AddPhotoAlternate, modifier = Modifier.testTag("vault-add-locked")) {
                                nav.push(Overlay.Paywall("vault"))
                            }
                        }
                    }
                    Footnote("On this phone only. Not backed up, not uploaded. If you lose the phone these copies go with it, so keep the originals where you always kept them.")
                }
            }
        }
    }
}

@Composable
private fun GatherCard(rows: List<Gather>, graph: AppGraph, showChild: Boolean) {
    val c = AppTheme.colors
    Card(padding = PaddingValues(0.dp)) {
        rows.forEachIndexed { i, row ->
            if (i > 0) RowDivider(inset = true)
            Row(
                Modifier.fillMaxWidth().heightIn(min = AppTheme.minTouch)
                    .clickable(role = Role.Checkbox) {
                        val now = System.currentTimeMillis()
                        val target = !row.isOnHand
                        graph.store.commit(reconcile = false) {
                            row.items.forEach { item ->
                                item.isOnHand = target
                                item.markedOnHandAt = if (target) now else null
                                item.updatedAt = now
                            }
                        }
                    }
                    .semantics { stateDescription = if (row.isOnHand) "Gathered" else "Still to find" }
                    .padding(AppTheme.spacing).testTag("gather-row"),
            ) {
                Icon(if (row.isOnHand) Icons.Rounded.CheckCircle else Icons.Rounded.RadioButtonUnchecked, contentDescription = null, tint = if (row.isOnHand) c.accent else c.tertiary)
                Spacer(Modifier.width(AppTheme.spacing))
                Column(Modifier.weight(1f)) {
                    Text(row.title, style = Type.body, color = if (row.isOnHand) c.secondary else c.label, textDecoration = if (row.isOnHand) TextDecoration.LineThrough else null)
                    val forLine = (if (showChild) "${row.child.displayName} · " else "") + "For " + row.taskNames.joinToString(", ")
                    Text(forLine, style = Type.caption, color = c.secondary)
                }
            }
        }
    }
}

@Composable
fun VaultAddScreen(childID: UUID) {
    val graph = LocalGraph.current
    val nav = graph.navigator
    val c = AppTheme.colors
    var kind by rememberSaveable { mutableStateOf(VaultDocumentKind.BIRTH_CERTIFICATE) }
    var customTitle by rememberSaveable { mutableStateOf("") }
    val pages = remember { mutableStateListOf<String>() }
    var choosingKind by remember { mutableStateOf(false) }
    var sensitiveNote by remember { mutableStateOf(false) }
    var acknowledged by rememberSaveable { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var saved by remember { mutableStateOf(false) }
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.PickMultipleVisualMedia(8)) { uris: List<Uri> ->
        val names = uris.mapNotNull(graph.vault::importImage)
        if (names.size < uris.size) error = "One photo could not be loaded. Choose it again before saving."
        pages += names
    }
    // Pages imported but never saved are deleted, never left orphaned on disk.
    androidx.compose.runtime.DisposableEffect(Unit) { onDispose { if (!saved) graph.vault.delete(pages.toList()) } }

    fun pick() {
        if (kind.isSensitive && !acknowledged) { sensitiveNote = true; return }
        picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
    }

    Page("Add a document", onBack = { nav.pop() }) {
        item {
            SectionHeader("What is it")
            Card(padding = PaddingValues(0.dp)) {
                NavRow("Document type", value = kind.label, modifier = Modifier.testTag("vault-kind")) { choosingKind = true }
                if (kind == VaultDocumentKind.OTHER) {
                    OutlinedTextField(customTitle, { customTitle = it }, label = { Text("Name it") }, singleLine = true, modifier = Modifier.fillMaxWidth().padding(AppTheme.spacing))
                }
            }
        }
        item {
            SectionHeader("Photos")
            Card(padding = PaddingValues(0.dp)) {
                pages.forEachIndexed { i, name ->
                    Row(Modifier.fillMaxWidth().padding(AppTheme.spacing), verticalAlignment = Alignment.CenterVertically) {
                        val bitmap = remember(name) { graph.vault.loadImage(name, 240) }
                        bitmap?.let { Image(it.asImageBitmap(), contentDescription = "Page ${i + 1}", modifier = Modifier.size(56.dp), contentScale = ContentScale.Crop) }
                        Spacer(Modifier.width(AppTheme.spacing))
                        Text("Page ${i + 1}", style = Type.body, color = c.label, modifier = Modifier.weight(1f))
                        TextButton(onClick = { graph.vault.delete(listOf(name)); pages.remove(name) }) { Text("Remove", color = c.red) }
                    }
                    RowDivider()
                }
                NavRow(if (pages.isEmpty()) "Choose photos" else "Add more pages", icon = Icons.Rounded.AddPhotoAlternate, modifier = Modifier.testTag("vault-pick")) { pick() }
            }
            Footnote("Both sides, or every page. The photo is scaled down and saved as a copy; the one in your gallery is untouched, and you may want to delete that one.")
        }
        item {
            Spacer(Modifier.padding(top = AppTheme.spacing))
            PrimaryButton("Save", enabled = pages.isNotEmpty(), tag = "vault-save") {
                val ok = graph.store.commit(reconcile = false) {
                    it.vault += VaultDocument(childId = childID, kind = kind, customTitle = customTitle.trim(), pageFileNames = pages.toList())
                }
                if (ok) {
                    saved = true
                    nav.pop()
                } else {
                    error = "The document could not be saved. Nothing was kept. Try again after freeing some space."
                }
            }
            Footnote("They stay on this phone: not backed up, not uploaded, and Baby Docs has no server to put them on.")
        }
    }

    if (choosingKind) {
        SearchListDialog(
            "Document type", VaultDocumentKind.entries.sortedBy { it.sortWeight }.map { it.raw to it.label },
            onDismiss = { choosingKind = false },
            onPick = { raw -> kind = VaultDocumentKind.of(raw); choosingKind = false },
        )
    }
    if (sensitiveNote) {
        AlertDialog(
            modifier = DialogTags,
            onDismissRequest = { sensitiveNote = false },
            text = { Text("This copy stays on this phone. It is not backed up and never leaves the device, so if you lose the phone the copy is gone. The card itself is still the record: keep it somewhere safe.") },
            confirmButton = { TextButton(onClick = { sensitiveNote = false; acknowledged = true; pick() }) { Text("I understand") } },
            dismissButton = { TextButton(onClick = { sensitiveNote = false }) { Text("Not now") } },
        )
    }
    error?.let { message ->
        AlertDialog(modifier = DialogTags, onDismissRequest = { error = null }, text = { Text(message) }, confirmButton = { TextButton(onClick = { error = null }) { Text("OK") } })
    }
}

@Composable
fun VaultViewScreen(documentID: UUID) {
    val graph = LocalGraph.current
    val nav = graph.navigator
    val c = AppTheme.colors
    graph.store.revision
    val doc = graph.store.data.vault.firstOrNull { it.id == documentID && it.deletedAt == null }
    if (doc == null || !nav.vaultUnlocked) {
        LaunchedEffect(Unit) { nav.pop() }
        return
    }
    var confirmDelete by remember { mutableStateOf(false) }
    val images: List<Bitmap?> = remember(doc.pageFileNames) { doc.pageFileNames.map { graph.vault.loadImage(it) } }

    Page(doc.displayTitle, onBack = { nav.pop() }) {
        if (images.any { it == null }) item { Footnote("Some pages are unavailable. The copies on this phone may be incomplete.") }
        items(images.withIndex().toList()) { (i, bitmap) ->
            bitmap?.let {
                Image(
                    it.asImageBitmap(), contentDescription = "Document photo ${i + 1} of ${images.size}",
                    modifier = Modifier.fillMaxWidth(), contentScale = ContentScale.FillWidth,
                )
            }
        }
        item {
            TextButton(onClick = { confirmDelete = true }, modifier = Modifier.fillMaxWidth().testTag("vault-delete")) { Text("Delete the photos", color = c.red) }
        }
    }
    if (confirmDelete) {
        AlertDialog(
            modifier = DialogTags,
            onDismissRequest = { confirmDelete = false },
            title = { Text("Delete the photos?") },
            text = { Text("The photos are removed from this phone now and cannot be recovered: they are not backed up anywhere. The document itself is unaffected.") },
            confirmButton = {
                TextButton(onClick = {
                    confirmDelete = false
                    // The one hard delete in the app: image files go immediately.
                    graph.vault.delete(doc.pageFileNames)
                    graph.store.commit(reconcile = false) { d -> d.vault.removeAll { it.id == doc.id } }
                    nav.pop()
                }) { Text("Delete the photos", color = c.red) }
            },
            dismissButton = { TextButton(onClick = { confirmDelete = false }) { Text("Keep them") } },
        )
    }
}
