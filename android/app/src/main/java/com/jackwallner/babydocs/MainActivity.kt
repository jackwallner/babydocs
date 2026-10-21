package com.jackwallner.babydocs

import android.Manifest
import android.content.Intent
import android.os.Build
import android.os.Bundle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Box
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.fragment.app.FragmentActivity
import androidx.lifecycle.lifecycleScope
import com.jackwallner.babydocs.data.DeadlineReminders
import com.jackwallner.babydocs.ui.LocalGraph
import com.jackwallner.babydocs.ui.RootScreen
import com.jackwallner.babydocs.ui.theme.BabyDocsTheme
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.launch
import java.util.UUID

@OptIn(ExperimentalComposeUiApi::class)
class MainActivity : FragmentActivity() {
    private val graph: AppGraph get() = (application as BabyDocsApplication).graph
    private var permissionAnswer: CompletableDeferred<Boolean>? = null

    private val notificationPermission = registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        permissionAnswer?.complete(granted)
        permissionAnswer = null
    }

    /** The one prompt for notification permission, asked from the intake's last page. */
    suspend fun requestNotificationPermission(): Boolean {
        if (Build.VERSION.SDK_INT < 33 || DeadlineReminders.hasPermission(this)) return true
        val answer = CompletableDeferred<Boolean>()
        permissionAnswer = answer
        notificationPermission.launch(Manifest.permission.POST_NOTIFICATIONS)
        return answer.await()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val graph = graph
        if (savedInstanceState == null) {
            DebugLaunchOptions.apply(graph, intent)
            graph.diagnostics.recordAppOpen()
            graph.review.recordAppLaunch()
            route(intent)
        }
        enableEdgeToEdge()
        lifecycleScope.launch {
            graph.subscriptions.start()
            graph.rescheduleReminders()
        }
        setContent {
            CompositionLocalProvider(LocalGraph provides graph) {
                BabyDocsTheme {
                    // Test tags double as resource ids so UI Automator and capture scripts can find controls.
                    Box(Modifier.semantics { testTagsAsResourceId = true }) {
                        RootScreen(this@MainActivity)
                    }
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        route(intent)
    }

    /** A notification opens its task; a shared plan link offers to import. */
    private fun route(intent: Intent?) {
        intent ?: return
        intent.getStringExtra(DeadlineReminders.EXTRA_TASK)
            ?.let { runCatching { UUID.fromString(it) }.getOrNull() }
            ?.takeIf { graph.store.data.task(it)?.deletedAt == null }
            ?.let { graph.navigator.openTask(it) }
        intent.dataString?.takeIf { intent.action == Intent.ACTION_VIEW }?.let { graph.navigator.push(Overlay.ImportPlan(it)) }
    }

    override fun onResume() {
        super.onResume()
        // Renewals, restores and late grants flip the app promptly.
        lifecycleScope.launch {
            graph.subscriptions.refreshCustomerInfo()
            graph.rescheduleReminders()
        }
    }

    override fun onStop() {
        super.onStop()
        graph.subscriptions.syncConversionAttributes()
        // The vault locks again whenever the app leaves the screen.
        if (!isChangingConfigurations) graph.navigator.vaultUnlocked = false
    }
}
