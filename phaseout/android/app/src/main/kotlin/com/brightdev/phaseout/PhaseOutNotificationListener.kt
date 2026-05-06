// ─────────────────────────────────────────────────────────────
//  PhaseOutNotificationListener.kt
//  PhaseOut — NotificationListenerService
//
//  Required for MediaSessionManager.getActiveSessions().
//
//  No structural changes from your original.
//  Added: companion object so PhaseOutService can reference
//  the ComponentName cleanly without hardcoding strings.
// ─────────────────────────────────────────────────────────────

package com.brightdev.phaseout

import android.content.ComponentName
import android.content.Context
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

    companion object {
        /** Use this when calling MediaSessionManager.getActiveSessions(). */
        fun componentName(context: Context) = ComponentName(
            context.packageName,
            PhaseOutNotificationListener::class.java.name
        )
    }
}