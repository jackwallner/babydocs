package com.jackwallner.babydocs

import android.content.Intent

/** Release and QA builds: launch extras never change anything. */
object DebugLaunchOptions {
    @Suppress("UNUSED_PARAMETER")
    fun apply(graph: AppGraph, intent: Intent?) = Unit
}
