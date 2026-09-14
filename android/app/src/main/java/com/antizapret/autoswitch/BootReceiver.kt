package com.antizapret.autoswitch

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return
        val prefs = Prefs(context)
        if (prefs.autoStartOnBoot && prefs.tunnelNames().isNotEmpty() && prefs.remoteKey.isNotBlank()) {
            AutoSwitchService.start(context)
        }
    }
}
