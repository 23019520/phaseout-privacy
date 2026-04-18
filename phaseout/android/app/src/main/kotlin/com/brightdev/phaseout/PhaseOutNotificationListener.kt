// ─────────────────────────────────────────────────────────────
//  android/app/src/main/kotlin/com/brightdev/phaseout/
//  PhaseOutNotificationListener.kt
//  PhaseOut — NotificationListenerService
//
//  Required for MediaSessionManager.getActiveSessions().
//  Lives in its own file so it can be referenced by both
//  MainActivity and PhaseOutService.
// ─────────────────────────────────────────────────────────────

package com.brightdev.phaseout

import android.service.notification.NotificationListenerService
import android.util.Log

class PhaseOutNotificationListener : NotificationListenerService() {

    override fun onListenerConnected() {
        super.onListenerConnected()
        Log.i("PhaseOut.NLS", "NotificationListener connected")
    }

    override fun onListenerDisconnected() {
        super.onListenerDisconnected()
        Log.w("PhaseOut.NLS", "NotificationListener disconnected")
    }
}