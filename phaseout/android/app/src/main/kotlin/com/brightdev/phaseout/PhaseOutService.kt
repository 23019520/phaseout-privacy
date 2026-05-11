// ─────────────────────────────────────────────────────────────
//  PhaseOutService.kt  — v8
//
//  Refactor: Allowlist → Blacklist architecture
//  - EXTRA_ALLOWLIST     → EXTRA_BLOCKED_APPS
//  - KEY_FOCUS_ALLOWLIST → KEY_FOCUS_BLOCKED_APPS
//  - focusAllowlist      → focusBlockedApps
//  - checkFocusAndBlock: block if fg IS in focusBlockedApps
//    (previously blocked if fg was NOT in focusAllowlist)
// ─────────────────────────────────────────────────────────────

package com.brightdev.phaseout

import android.app.*
import android.app.usage.UsageStatsManager
import android.content.*
import android.media.AudioManager
import android.media.RingtoneManager
import android.media.session.MediaSessionManager
import android.os.*
import android.provider.Settings
import android.util.Log
import androidx.core.app.NotificationCompat
import java.util.Calendar
import kotlin.math.abs

class PhaseOutService : Service() {

    companion object {
        private const val TAG = "PhaseOut.Service"

        // ── Actions ────────────────────────────────────────────
        const val ACTION_STOP_MEDIA           = "com.brightdev.phaseout.STOP_MEDIA"
        const val ACTION_START_FOCUS          = "com.brightdev.phaseout.START_FOCUS"
        const val ACTION_STOP_FOCUS           = "com.brightdev.phaseout.STOP_FOCUS"
        const val ACTION_SET_TIMER            = "com.brightdev.phaseout.SET_TIMER"
        const val ACTION_CANCEL_TIMER         = "com.brightdev.phaseout.CANCEL_TIMER"
        const val ACTION_STOP_SERVICE         = "com.brightdev.phaseout.STOP_SERVICE"
        const val ACTION_MORNING_RESTORE      = "com.brightdev.phaseout.MORNING_RESTORE"
        const val ACTION_DIM_BRIGHTNESS       = "com.brightdev.phaseout.DIM_BRIGHTNESS"
        const val ACTION_RESTORE_BRIGHTNESS   = "com.brightdev.phaseout.RESTORE_BRIGHTNESS"
        const val ACTION_ENABLE_DND           = "com.brightdev.phaseout.ENABLE_DND"
        const val ACTION_DISABLE_DND          = "com.brightdev.phaseout.DISABLE_DND"
        const val ACTION_SEND_CHARGE_REMINDER = "com.brightdev.phaseout.SEND_CHARGE_REMINDER"

        // ── Extras ─────────────────────────────────────────────
        const val EXTRA_BRIGHTNESS_LEVEL = "brightness_level"
        const val EXTRA_EXPIRY_MS        = "extra_expiry_ms"
        const val EXTRA_BLOCKED_APPS     = "extra_blocked_apps"   // was: EXTRA_ALLOWLIST

        // ── Notification channels ──────────────────────────────
        private const val NOTIF_CHANNEL_ID  = "phaseout_native_service"
        private const val ALERT_CHANNEL_ID  = "phaseout_alerts"
        private const val CHARGE_CHANNEL_ID = "phaseout_charge"
        private const val NOTIF_ID          = 101
        private const val NOTIF_ID_CHARGE   = 50
        private const val TICK_MS           = 60_000L
        private const val FOCUS_POLL_MS     = 700L                // was: 1_000L

        // ── SharedPreferences ──────────────────────────────────
        private const val PREFS_NAME              = "FlutterSharedPreferences"
        private const val KEY_DND_PREV_FILTER     = "phaseout.prev_dnd_filter"
        private const val KEY_BRIGHTNESS_PREV     = "phaseout.prev_brightness"
        private const val KEY_FOCUS_ACTIVE        = "flutter.focus_session_active"
        private const val KEY_FOCUS_BLOCKED_APPS  = "flutter.focus_blocked_apps"  // was: KEY_FOCUS_ALLOWLIST

        // Packages that can never be blocked regardless of user selection.
        // Minimal set — blacklist model makes most guards unnecessary,
        // but self-protection and emergency dialer are non-negotiable.
        private val NEVER_BLOCK = setOf(
            "com.brightdev.phaseout",
            "com.android.launcher", "com.android.launcher2", "com.android.launcher3",
            "com.samsung.android.launcher",
            "com.google.android.apps.nexuslauncher",
            "com.miui.home", "com.huawei.android.launcher",
            "com.oneplus.launcher", "com.oppo.launcher", "com.vivo.launcher",
            "com.tcl.launcher", "com.sec.android.app.launcher",
            "com.android.dialer", "com.samsung.android.dialer", "com.google.android.dialer",
            "com.android.mms", "com.samsung.android.messaging", "com.google.android.apps.messaging",
        )
    }

    private val handler          = Handler(Looper.getMainLooper())
    private var focusBlockedApps = mutableListOf<String>()   // was: focusAllowlist
    private var focusActive      = false

    private var timerRunnable: Runnable? = null

    private val tickRunnable = object : Runnable {
        override fun run() {
            tick()
            handler.postDelayed(this, TICK_MS)
        }
    }

    private val focusRunnable = object : Runnable {
        override fun run() {
            if (focusActive) {
                checkFocusAndBlock()
                handler.postDelayed(this, FOCUS_POLL_MS)
            }
        }
    }

    // ─────────────────────────────────────────────────────────
    //  LIFECYCLE
    // ─────────────────────────────────────────────────────────

    override fun onCreate() {
        super.onCreate()
        createNotificationChannels()
        startForegroundCompat()
        Log.i(TAG, "Service v8 started")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {

            ACTION_STOP_MEDIA -> stopAllMedia()

            ACTION_SET_TIMER -> {
                val expiryMs = intent.getLongExtra(EXTRA_EXPIRY_MS, 0L)
                if (expiryMs > 0) scheduleAudioTimer(expiryMs)
            }

            ACTION_CANCEL_TIMER -> cancelAudioTimer()

            ACTION_START_FOCUS -> {
                val blockedApps = intent.getStringArrayListExtra(EXTRA_BLOCKED_APPS) ?: arrayListOf()
                focusBlockedApps = blockedApps.toMutableList()
                focusActive      = true
                getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).edit()
                    .putBoolean(KEY_FOCUS_ACTIVE, true)
                    .putString(KEY_FOCUS_BLOCKED_APPS, blockedApps.joinToString(","))
                    .apply()
                handler.post(focusRunnable)
                Log.i(TAG, "Focus started — blockedApps: $blockedApps")
            }

            ACTION_STOP_FOCUS -> {
                focusActive = false
                handler.removeCallbacks(focusRunnable)
                PhaseOutWindowOverlay.dismiss()
                getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).edit()
                    .putBoolean(KEY_FOCUS_ACTIVE, false)
                    .apply()
                Log.i(TAG, "Focus stopped")
            }

            ACTION_DIM_BRIGHTNESS -> {
                val level = intent.getIntExtra(EXTRA_BRIGHTNESS_LEVEL, 30)
                dimBrightness(level)
            }

            ACTION_RESTORE_BRIGHTNESS -> restoreBrightness()

            ACTION_ENABLE_DND  -> enableDoNotDisturb()
            ACTION_DISABLE_DND -> disableDoNotDisturb()

            ACTION_SEND_CHARGE_REMINDER -> sendChargeReminder()

            ACTION_STOP_SERVICE -> {
                stopSelf()
                return START_NOT_STICKY
            }

            null -> {
                handler.removeCallbacks(tickRunnable)
                handler.post(tickRunnable)
                restoreFocusIfActive()
            }
        }
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        handler.removeCallbacks(tickRunnable)
        handler.removeCallbacks(focusRunnable)
        cancelAudioTimer()
        super.onDestroy()
    }

    // ─────────────────────────────────────────────────────────
    //  MAIN TICK  (~60 s)
    // ─────────────────────────────────────────────────────────

    private fun tick() {
        Log.d(TAG, "Tick")
        checkAndFireSchedules()
        checkRestoreSchedules()
    }

    // ─────────────────────────────────────────────────────────
    //  FIRE SCHEDULES
    // ─────────────────────────────────────────────────────────

    private fun checkAndFireSchedules() {
        val schedules = PhaseOutDatabase.getEnabledSchedules(this)
        if (schedules.isEmpty()) return

        val now   = Calendar.getInstance()
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

        val todayDow = when (now.get(Calendar.DAY_OF_WEEK)) {
            Calendar.MONDAY    -> 1
            Calendar.TUESDAY   -> 2
            Calendar.WEDNESDAY -> 3
            Calendar.THURSDAY  -> 4
            Calendar.FRIDAY    -> 5
            Calendar.SATURDAY  -> 6
            Calendar.SUNDAY    -> 7
            else               -> 1
        }

        val todayKey = todayDateKey(now)

        for (s in schedules) {
            if (!s.daysOfWeek.contains(todayDow)) continue

            val triggerCal = Calendar.getInstance().apply {
                set(Calendar.HOUR_OF_DAY, s.triggerHour)
                set(Calendar.MINUTE, s.triggerMin)
                set(Calendar.SECOND, 0)
            }
            if (abs(now.timeInMillis - triggerCal.timeInMillis) > 90_000) continue

            val firedKey = "phaseout.fired_${s.id}_$todayKey"
            if (prefs.getBoolean(firedKey, false)) continue

            val skipKey = "flutter.phaseout.skip_${s.id}"
            if (prefs.getString(skipKey, null) == todayKey) {
                Log.i(TAG, "Schedule '${s.name}' skipped today")
                continue
            }

            val snoozeKey   = "flutter.phaseout.snooze_until_${s.id}"
            val snoozeUntil = prefs.getLong(snoozeKey, 0L)
            if (snoozeUntil > now.timeInMillis) {
                Log.i(TAG, "Schedule '${s.name}' snoozed until $snoozeUntil")
                continue
            }
            if (snoozeUntil > 0) prefs.edit().remove(snoozeKey).apply()

            Log.i(TAG, "Firing '${s.name}' actions=${s.actions}")
            prefs.edit().putBoolean(firedKey, true).apply()
            fireActions(s.actions)
        }
    }

    private fun fireActions(actions: List<String>) {
        for (action in actions) {
            when (action) {
                "stop_media"        -> stopAllMedia()
                "do_not_disturb"    -> enableDoNotDisturb()
                "dim_brightness"    -> dimBrightness(30)
                "go_home"           -> goHome()
                "send_notification" -> sendChargeReminder()
                else                -> Log.w(TAG, "Unknown action: $action")
            }
        }
    }

    // ─────────────────────────────────────────────────────────
    //  RESTORE SCHEDULES
    // ─────────────────────────────────────────────────────────

    private fun checkRestoreSchedules() {
        val schedules = PhaseOutDatabase.getEnabledSchedules(this)
        if (schedules.isEmpty()) return

        val now   = Calendar.getInstance()
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

        for (s in schedules) {
            val wakeHour = s.wakeHour   ?: continue
            val wakeMin  = s.wakeMinute ?: continue

            val restoreCal = Calendar.getInstance().apply {
                set(Calendar.HOUR_OF_DAY, wakeHour)
                set(Calendar.MINUTE, wakeMin)
                set(Calendar.SECOND, 0)
            }
            if (abs(now.timeInMillis - restoreCal.timeInMillis) > 90_000) continue

            val todayKey = todayDateKey(now)
            val doneKey  = "phaseout.restored_${s.id}_$todayKey"
            if (prefs.getBoolean(doneKey, false)) continue

            val actions  = s.actions.toSet()
            var restored = false
            if (actions.contains("do_not_disturb")) { disableDoNotDisturb(); restored = true }
            if (actions.contains("dim_brightness"))  { restoreBrightness();   restored = true }

            if (restored) {
                prefs.edit().putBoolean(doneKey, true).apply()
                Log.i(TAG, "Restored '${s.name}'")
            }
        }
    }

    // ─────────────────────────────────────────────────────────
    //  AUDIO TIMER
    // ─────────────────────────────────────────────────────────

    private fun scheduleAudioTimer(expiryMs: Long) {
        cancelAudioTimer()
        val delay = expiryMs - System.currentTimeMillis()
        if (delay <= 0) { stopAllMedia(); return }

        val r = Runnable {
            Log.i(TAG, "Audio timer expired — stopping media")
            stopAllMedia()
            timerRunnable = null
        }
        timerRunnable = r
        handler.postDelayed(r, delay)
        Log.i(TAG, "Audio timer set, fires in ${delay / 1000}s")
    }

    private fun cancelAudioTimer() {
        timerRunnable?.let { handler.removeCallbacks(it) }
        timerRunnable = null
    }

    // ─────────────────────────────────────────────────────────
    //  FOCUS BLOCKING  (every 700 ms)
    //
    //  Blacklist model:
    //    - If fg is in NEVER_BLOCK  → dismiss overlay, return
    //    - If fg is NOT in focusBlockedApps → dismiss overlay, return
    //    - Otherwise → show overlay
    //
    //  This is the core inversion from v7. System UI, launchers,
    //  OEM overlays, and permission dialogs are never in
    //  focusBlockedApps so they pass through automatically.
    // ─────────────────────────────────────────────────────────

    private fun checkFocusAndBlock() {
        if (!focusActive) return
        try {
            val now   = System.currentTimeMillis()
            val usm   = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
            val stats = usm.queryUsageStats(UsageStatsManager.INTERVAL_BEST, now - 2000L, now)
                ?: return
            val fg = stats
                .filter { it.totalTimeInForeground > 0 }
                .maxByOrNull { it.lastTimeUsed }
                ?.packageName ?: return

            // Step 1: permanent safe list (self + launchers + emergency)
            if (NEVER_BLOCK.contains(fg)) {
                PhaseOutWindowOverlay.dismiss()
                return
            }

            // Step 2: blacklist check — only block explicitly selected apps
            if (!focusBlockedApps.contains(fg)) {
                PhaseOutWindowOverlay.dismiss()
                return
            }

            // Step 3: show overlay if not already visible
            if (!PhaseOutWindowOverlay.isShowing()) {
                Log.i(TAG, "Blocking: $fg")
                PhaseOutWindowOverlay.show(this, fg)
            }
        } catch (e: Exception) {
            Log.e(TAG, "checkFocusAndBlock: ${e.message}")
        }
    }

    // ─────────────────────────────────────────────────────────
    //  RESTORE FOCUS SESSION AFTER SERVICE RESTART
    // ─────────────────────────────────────────────────────────

    private fun restoreFocusIfActive() {
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        if (!prefs.getBoolean(KEY_FOCUS_ACTIVE, false)) return
        val saved = prefs.getString(KEY_FOCUS_BLOCKED_APPS, "") ?: ""
        focusBlockedApps = if (saved.isEmpty()) mutableListOf()
                           else saved.split(",").toMutableList()
        focusActive = true
        handler.post(focusRunnable)
        Log.i(TAG, "Focus session restored — blockedApps: $focusBlockedApps")
    }

    // ─────────────────────────────────────────────────────────
    //  SYSTEM ACTIONS
    // ─────────────────────────────────────────────────────────

    private fun dimBrightness(level: Int) {
        if (!Settings.System.canWrite(this)) {
            Log.w(TAG, "dimBrightness: WRITE_SETTINGS not granted"); return
        }
        val cr    = contentResolver
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val current = Settings.System.getInt(cr, Settings.System.SCREEN_BRIGHTNESS, 128)
        prefs.edit().putInt(KEY_BRIGHTNESS_PREV, current).apply()
        Settings.System.putInt(cr, Settings.System.SCREEN_BRIGHTNESS_MODE,
            Settings.System.SCREEN_BRIGHTNESS_MODE_MANUAL)
        Settings.System.putInt(cr, Settings.System.SCREEN_BRIGHTNESS, level.coerceIn(1, 255))
        Log.i(TAG, "Brightness dimmed to $level (was $current)")
    }

    private fun restoreBrightness() {
        if (!Settings.System.canWrite(this)) {
            Log.w(TAG, "restoreBrightness: WRITE_SETTINGS not granted"); return
        }
        val saved = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getInt(KEY_BRIGHTNESS_PREV, -1)
        if (saved < 0) { Log.w(TAG, "restoreBrightness: nothing saved"); return }
        Settings.System.putInt(contentResolver, Settings.System.SCREEN_BRIGHTNESS, saved)
        Log.i(TAG, "Brightness restored to $saved")
    }

    private fun enableDoNotDisturb() {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (!nm.isNotificationPolicyAccessGranted) {
            Log.w(TAG, "enableDnd: access not granted"); return
        }
        getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).edit()
            .putInt(KEY_DND_PREV_FILTER, nm.currentInterruptionFilter).apply()
        nm.setInterruptionFilter(NotificationManager.INTERRUPTION_FILTER_NONE)
        Log.i(TAG, "DND enabled")
    }

    private fun disableDoNotDisturb() {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (!nm.isNotificationPolicyAccessGranted) {
            Log.w(TAG, "disableDnd: access not granted"); return
        }
        val prev = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getInt(KEY_DND_PREV_FILTER, NotificationManager.INTERRUPTION_FILTER_ALL)
        nm.setInterruptionFilter(prev)
        Log.i(TAG, "DND disabled, restored filter=$prev")
    }

    private fun sendChargeReminder() {
        val nm  = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
        nm.notify(NOTIF_ID_CHARGE,
            NotificationCompat.Builder(this, CHARGE_CHANNEL_ID)
                .setSmallIcon(android.R.drawable.ic_dialog_info)
                .setContentTitle("Time to charge")
                .setContentText("Plug in your phone before you sleep.")
                .setSound(uri)
                .setAutoCancel(true)
                .build())
        Log.i(TAG, "Charge reminder sent")
    }

    private fun stopAllMedia(): Boolean {
        return try {
            val msm = getSystemService(Context.MEDIA_SESSION_SERVICE) as MediaSessionManager
            val sessions = msm.getActiveSessions(
                PhaseOutNotificationListener.componentName(this)
            )
            sessions.forEach { s ->
                try {
                    s.transportControls.pause()
                    s.transportControls.stop()
                } catch (_: Exception) {}
            }
            Log.i(TAG, "stopAllMedia: paused ${sessions.size} session(s)")
            true
        } catch (e: Exception) {
            Log.e(TAG, "stopAllMedia failed: ${e.message}")
            try {
                (getSystemService(Context.AUDIO_SERVICE) as AudioManager)
                    .abandonAudioFocus(null)
            } catch (_: Exception) {}
            false
        }
    }

    private fun goHome() {
        try {
            startActivity(Intent(Intent.ACTION_MAIN).apply {
                addCategory(Intent.CATEGORY_HOME)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            })
        } catch (e: Exception) {
            Log.e(TAG, "goHome: ${e.message}")
        }
    }

    // ─────────────────────────────────────────────────────────
    //  FOREGROUND + CHANNELS
    // ─────────────────────────────────────────────────────────

    private fun startForegroundCompat() {
        val notif = NotificationCompat.Builder(this, NOTIF_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle("PhaseOut active")
            .setContentText("Monitoring schedules")
            .setOngoing(true)
            .build()
        startForeground(NOTIF_ID, notif)
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.createNotificationChannel(
            NotificationChannel(NOTIF_CHANNEL_ID, "Service", NotificationManager.IMPORTANCE_LOW))
        nm.createNotificationChannel(
            NotificationChannel(ALERT_CHANNEL_ID, "Alerts", NotificationManager.IMPORTANCE_HIGH))
        nm.createNotificationChannel(
            NotificationChannel(CHARGE_CHANNEL_ID, "Charge reminder", NotificationManager.IMPORTANCE_DEFAULT))
    }

    // ─────────────────────────────────────────────────────────
    //  UTILITIES
    // ─────────────────────────────────────────────────────────

    private fun todayDateKey(cal: Calendar): String {
        val y = cal.get(Calendar.YEAR)
        val m = (cal.get(Calendar.MONTH) + 1).toString().padStart(2, '0')
        val d = cal.get(Calendar.DAY_OF_MONTH).toString().padStart(2, '0')
        return "$y-$m-$d"
    }
}