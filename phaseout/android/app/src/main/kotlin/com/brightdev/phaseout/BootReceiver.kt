// ─────────────────────────────────────────────────────────────
//  android/app/src/main/kotlin/com/brightdev/phaseout/BootReceiver.kt
//  PhaseOut — Restarts PhaseOutService after device reboot
// ─────────────────────────────────────────────────────────────

package com.brightdev.phaseout

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

class BootReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED &&
            intent.action != Intent.ACTION_MY_PACKAGE_REPLACED) return

        Log.i("PhaseOut.Boot", "Boot/update received — starting PhaseOutService")

        val serviceIntent = Intent(context, PhaseOutService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(serviceIntent)
        } else {
            context.startService(serviceIntent)
        }
    }
}