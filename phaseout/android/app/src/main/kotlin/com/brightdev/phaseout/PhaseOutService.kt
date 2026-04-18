// ─────────────────────────────────────────────────────────────
//  PhaseOutService.kt  — v4
//  Sound: IMPORTANCE_HIGH + AudioAttributes + default ringtone
//  Snooze/Skip: pre-action notification 30s before firing
// ─────────────────────────────────────────────────────────────

package com.brightdev.phaseout

import android.app.*
import android.app.usage.UsageStatsManager
import android.content.*
import android.content.pm.ServiceInfo
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.RingtoneManager
import android.media.session.MediaSessionManager
import android.os.*
import android.provider.Settings
import android.util.Log
import androidx.core.app.NotificationCompat
import java.util.*

class PhaseOutService : Service() {

    companion object {
        private const val TAG = "PhaseOut.Service"

        const val ACTION_STOP_MEDIA      = "com.brightdev.phaseout.STOP_MEDIA"
        const val ACTION_START_FOCUS     = "com.brightdev.phaseout.START_FOCUS"
        const val ACTION_STOP_FOCUS      = "com.brightdev.phaseout.STOP_FOCUS"
        const val ACTION_SET_TIMER       = "com.brightdev.phaseout.SET_TIMER"
        const val ACTION_CANCEL_TIMER    = "com.brightdev.phaseout.CANCEL_TIMER"
        const val ACTION_STOP_SERVICE    = "com.brightdev.phaseout.STOP_SERVICE"
        const val ACTION_MORNING_RESTORE = "com.brightdev.phaseout.MORNING_RESTORE"
        const val ACTION_SNOOZE_15       = "com.brightdev.phaseout.SNOOZE_15"
        const val ACTION_SNOOZE_30       = "com.brightdev.phaseout.SNOOZE_30"
        const val ACTION_SKIP_TODAY      = "com.brightdev.phaseout.SKIP_TODAY"
        const val ACTION_FIRE_NOW        = "com.brightdev.phaseout.FIRE_NOW"
        const val EXTRA_SCHEDULE_ID      = "schedule_id"
        const val EXTRA_EXPIRY_MS        = "expiry_ms"
        const val EXTRA_ALLOWLIST        = "allowlist"

        private const val NOTIF_CHANNEL_ID  = "phaseout_native_service"
        private const val ALERT_CHANNEL_ID  = "phaseout_alerts"
        private const val PREACTION_CHANNEL = "phaseout_preaction"
        private const val NOTIF_ID          = 101
        private const val TICK_MS           = 60_000L

        private const val PREFS_NAME          = "FlutterSharedPreferences"
        private const val KEY_TIMER_EXPIRY    = "flutter.audio_timer_expiry_ms"
        private const val KEY_TIMER_ACTIVE    = "flutter.audio_timer_active"
        private const val KEY_FOCUS_ACTIVE    = "flutter.focus_session_active"
        private const val KEY_FOCUS_ALLOWLIST = "flutter.focus_session_allowlist"
        private const val KEY_DND_PREV_FILTER = "phaseout.prev_dnd_filter"
        private const val KEY_BRIGHTNESS_PREV = "phaseout.prev_brightness"
        private const val KEY_BEDTIME_ACTIVE  = "phaseout.bedtime_active"

        private fun snoozeKey(id: Int) = "phaseout.snooze_until_$id"
        private fun skipKey(id: Int)   = "phaseout.skip_$id"
        private fun todayKey(): String {
            val c = Calendar.getInstance()
            return "${c.get(Calendar.YEAR)}-${c.get(Calendar.MONTH)}-${c.get(Calendar.DAY_OF_MONTH)}"
        }

        private val lastFired     = mutableMapOf<Int, String>()
        private val preNotifFired = mutableSetOf<String>()
        private val pendingFire   = mutableMapOf<Int, Long>()
        private var lastFocusBlock = 0L
    }

    private val handler = Handler(Looper.getMainLooper())
    private val tickRunnable = object : Runnable {
        override fun run() { tick(); handler.postDelayed(this, TICK_MS) }
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannels()
        startForegroundCompat()
        Log.i(TAG, "PhaseOutService v4 created")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val schedId = intent?.getIntExtra(EXTRA_SCHEDULE_ID, -1) ?: -1
        when (intent?.action) {
            ACTION_STOP_MEDIA    -> stopAllMedia()
            ACTION_START_FOCUS   -> {
                val al = intent.getStringArrayListExtra(EXTRA_ALLOWLIST) ?: arrayListOf()
                saveFocusState(true, al)
            }
            ACTION_STOP_FOCUS    -> { saveFocusState(false, arrayListOf()); PhaseOutWindowOverlay.dismiss() }
            ACTION_SET_TIMER     -> {
                val ms = intent.getLongExtra(EXTRA_EXPIRY_MS, 0L)
                if (ms > 0) saveTimerState(true, ms)
            }
            ACTION_CANCEL_TIMER  -> saveTimerState(false, 0L)
            ACTION_STOP_SERVICE  -> stopSelf()
            ACTION_MORNING_RESTORE -> performMorningRestore()
            ACTION_SNOOZE_15     -> if (schedId >= 0) setSnooze(schedId, 15)
            ACTION_SNOOZE_30     -> if (schedId >= 0) setSnooze(schedId, 30)
            ACTION_SKIP_TODAY    -> if (schedId >= 0) setSkipToday(schedId)
            ACTION_FIRE_NOW      -> {
                if (schedId >= 0) {
                    pendingFire.remove(schedId)
                    val s = PhaseOutDatabase.getEnabledSchedules(this).firstOrNull { it.id == schedId }
                    s?.let { for (a in it.actions) executeAction(a, it) }
                }
            }
            null -> {
                Log.i(TAG, "Service started — tick loop")
                handler.removeCallbacks(tickRunnable)
                handler.post(tickRunnable)
            }
        }
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        handler.removeCallbacks(tickRunnable)
        PhaseOutWindowOverlay.dismiss()
        super.onDestroy()
    }

    private fun tick() {
        Log.d(TAG, "Tick")
        checkSchedules()
        checkPendingFires()
        checkAudioTimer()
        checkFocusSession()
    }

    private fun checkSchedules() {
        val schedules = PhaseOutDatabase.getEnabledSchedules(this)
        if (schedules.isEmpty()) return

        val cal     = Calendar.getInstance()
        val nowH    = cal.get(Calendar.HOUR_OF_DAY)
        val nowM    = cal.get(Calendar.MINUTE)
        val javaDow = cal.get(Calendar.DAY_OF_WEEK)
        val dartDow = if (javaDow == Calendar.SUNDAY) 7 else javaDow - 1
        val todayStr = "${cal.get(Calendar.YEAR)}-${cal.get(Calendar.MONTH)}-${cal.get(Calendar.DAY_OF_MONTH)}"
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

        for (s in schedules) {
            val minuteKey = "$todayStr-$nowH-$nowM"
            if (s.actions.contains("send_notification")) checkPreNotif(s, cal, nowH, nowM)
            if (lastFired[s.id] == minuteKey) continue
            if (!s.daysOfWeek.contains(dartDow)) continue
            if (s.triggerHour != nowH || s.triggerMin != nowM) continue

            if (prefs.getString(skipKey(s.id), "") == todayKey()) {
                Log.i(TAG, "'${s.name}' skipped today"); lastFired[s.id] = minuteKey; continue
            }
            val snoozeUntil = prefs.getLong(snoozeKey(s.id), 0L)
            if (snoozeUntil > System.currentTimeMillis()) {
                Log.i(TAG, "'${s.name}' snoozed"); lastFired[s.id] = minuteKey; continue
            }

            Log.i(TAG, "*** SCHEDULE READY '${s.name}'")
            lastFired[s.id] = minuteKey
            sendPreActionNotification(s)
            pendingFire[s.id] = System.currentTimeMillis() + 30_000L
        }
    }

    private fun checkPendingFires() {
        val now   = System.currentTimeMillis()
        val toFire = pendingFire.filter { it.value <= now }
        for ((id, _) in toFire) {
            pendingFire.remove(id)
            val s = PhaseOutDatabase.getEnabledSchedules(this).firstOrNull { it.id == id } ?: continue
            Log.i(TAG, "Auto-firing '${s.name}'")
            for (a in s.actions) executeAction(a, s)
        }
    }

    private fun sendPreActionNotification(s: ScheduleRow) {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        fun pi(action: String) = PendingIntent.getService(this,
            s.id * 10 + action.hashCode(),
            Intent(this, PhaseOutService::class.java).apply {
                this.action = action; putExtra(EXTRA_SCHEDULE_ID, s.id) },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)

        val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
        nm.notify(s.id + 1000,
            NotificationCompat.Builder(this, PREACTION_CHANNEL)
                .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
                .setContentTitle("${s.name} starts in 30 seconds")
                .setContentText("Tap to snooze or skip — otherwise it runs automatically.")
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setDefaults(NotificationCompat.DEFAULT_ALL)
                .setSound(uri)
                .setAutoCancel(true)
                .setTimeoutAfter(35_000)
                .addAction(android.R.drawable.ic_media_next, "Snooze 15m", pi(ACTION_SNOOZE_15))
                .addAction(android.R.drawable.ic_media_next, "Snooze 30m", pi(ACTION_SNOOZE_30))
                .addAction(android.R.drawable.ic_delete,     "Skip today", pi(ACTION_SKIP_TODAY))
                .addAction(android.R.drawable.ic_media_play, "Run now",    pi(ACTION_FIRE_NOW))
                .build())
    }

    private fun checkPreNotif(s: ScheduleRow, cal: Calendar, nowH: Int, nowM: Int) {
        val diff = (s.triggerHour * 60 + s.triggerMin) - (nowH * 60 + nowM)
        if (diff !in 28..32) return
        val key = "${s.id}-${cal.get(Calendar.YEAR)}-${cal.get(Calendar.DAY_OF_YEAR)}"
        if (preNotifFired.contains(key)) return
        sendAlert("Bedtime reminder ⏰", "'${s.name}' starts in $diff minutes.")
        preNotifFired.add(key)
    }

    private fun executeAction(action: String, s: ScheduleRow) {
        when (action) {
            "stop_media"        -> stopAllMedia()
            "send_notification" -> sendAlert("Wind-down time 🌙", "'${s.name}' has started.")
            "go_home"           -> goHome()
            "do_not_disturb"    -> enableDoNotDisturb()
            "dim_brightness"    -> dimBrightness()
            "set_morning_alarm" -> setMorningAlarm(s.wakeHour ?: 7, s.wakeMinute ?: 0)
        }
    }

    private fun setSnooze(id: Int, minutes: Int) {
        val until = System.currentTimeMillis() + (minutes * 60_000L)
        getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).edit()
            .putLong(snoozeKey(id), until).apply()
        pendingFire.remove(id)
        sendAlert("Snoozed ⏰", "Schedule snoozed for $minutes minutes.")
        Log.i(TAG, "Schedule $id snoozed $minutes min")
    }

    private fun setSkipToday(id: Int) {
        getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).edit()
            .putString(skipKey(id), todayKey()).apply()
        pendingFire.remove(id)
        sendAlert("Skipped", "Schedule skipped for today.")
        Log.i(TAG, "Schedule $id skipped")
    }

    private fun checkAudioTimer() {
        val prefs    = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val active   = prefs.getBoolean(KEY_TIMER_ACTIVE, false); if (!active) return
        val expiryMs = prefs.getLong(KEY_TIMER_EXPIRY, 0L); if (expiryMs == 0L) return
        val remaining = expiryMs - System.currentTimeMillis()
        if (remaining > 0) { Log.d(TAG, "Timer: ${(remaining/60000).toInt()+1}m left"); return }
        Log.i(TAG, "Audio timer expired")
        stopAllMedia(); goHome()
        sendAlert("Sleep timer ended 🌙", "Audio stopped. Good night.")
        prefs.edit().remove(KEY_TIMER_EXPIRY).putBoolean(KEY_TIMER_ACTIVE, false).apply()
    }

    private fun checkFocusSession() {
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        if (!prefs.getBoolean(KEY_FOCUS_ACTIVE, false)) return
        val al = try {
            val arr = org.json.JSONArray(prefs.getString(KEY_FOCUS_ALLOWLIST,"[]")?:"[]")
            (0 until arr.length()).map { arr.getString(it) }
        } catch (e: Exception) { emptyList() }
        val fg = getForegroundApp() ?: return
        if (al.contains(fg)) { if (PhaseOutWindowOverlay.isShowing()) handler.post { PhaseOutWindowOverlay.dismiss() }; return }
        val now = System.currentTimeMillis()
        if (now - lastFocusBlock < 30_000L) return
        lastFocusBlock = now
        if (PhaseOutWindowOverlay.canDraw(this))
            handler.post { PhaseOutWindowOverlay.dismiss(); PhaseOutWindowOverlay.show(this, fg) }
        else sendAlert("Focus mode active", "$fg is blocked.")
    }

    private fun stopAllMedia(): Boolean {
        return try {
            if (isNotificationListenerEnabled()) {
                val msm = getSystemService(Context.MEDIA_SESSION_SERVICE) as MediaSessionManager
                val cn  = ComponentName(this, PhaseOutNotificationListener::class.java)
                try {
                    val sessions = msm.getActiveSessions(cn)
                    Log.d(TAG, "Active sessions: ${sessions.size}")
                    for (s in sessions) { try { s.transportControls.pause(); s.transportControls.stop() } catch (_: Exception) {} }
                } catch (e: SecurityException) { Log.w(TAG, "getActiveSessions denied") }
            }
            releaseAudioFocus(); true
        } catch (e: Exception) { false }
    }

    private fun releaseAudioFocus() {
        val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            am.abandonAudioFocusRequest(android.media.AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN).build())
        else @Suppress("DEPRECATION") am.abandonAudioFocus(null)
    }

    private fun goHome() {
        try { startActivity(Intent(Intent.ACTION_MAIN).apply {
            addCategory(Intent.CATEGORY_HOME); addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) })
        } catch (e: Exception) { Log.e(TAG, "goHome: ${e.message}") }
    }

    private fun enableDoNotDisturb() {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (!nm.isNotificationPolicyAccessGranted) return
        getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).edit()
            .putInt(KEY_DND_PREV_FILTER, nm.currentInterruptionFilter)
            .putBoolean(KEY_BEDTIME_ACTIVE, true).apply()
        nm.setInterruptionFilter(NotificationManager.INTERRUPTION_FILTER_NONE)
    }

    private fun dimBrightness() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.System.canWrite(this)) return
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        prefs.edit().putInt(KEY_BRIGHTNESS_PREV,
            Settings.System.getInt(contentResolver, Settings.System.SCREEN_BRIGHTNESS, 128))
            .putBoolean(KEY_BEDTIME_ACTIVE, true).apply()
        Settings.System.putInt(contentResolver, Settings.System.SCREEN_BRIGHTNESS, 13)
    }

    private fun setMorningAlarm(hour: Int, minute: Int) {
        val am  = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val cal = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, hour); set(Calendar.MINUTE, minute)
            set(Calendar.SECOND, 0); set(Calendar.MILLISECOND, 0)
            if (timeInMillis < System.currentTimeMillis()) add(Calendar.DAY_OF_MONTH, 1)
        }
        val pi = PendingIntent.getService(this, 999,
            Intent(this, PhaseOutService::class.java).apply { action = ACTION_MORNING_RESTORE },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        am.setAlarmClock(AlarmManager.AlarmClockInfo(cal.timeInMillis, pi), pi)
    }

    private fun performMorningRestore() {
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        if (!prefs.getBoolean(KEY_BEDTIME_ACTIVE, false)) return
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.setInterruptionFilter(prefs.getInt(KEY_DND_PREV_FILTER, NotificationManager.INTERRUPTION_FILTER_ALL))
        Settings.System.putInt(contentResolver, Settings.System.SCREEN_BRIGHTNESS, prefs.getInt(KEY_BRIGHTNESS_PREV, 128))
        prefs.edit().putBoolean(KEY_BEDTIME_ACTIVE, false).apply()
        sendAlert("Good morning! ☀️", "Brightness and sound restored.")
    }

    private fun getForegroundApp(): String? {
        if (!hasUsagePermission()) return null
        return try {
            val usm = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
            val now = System.currentTimeMillis()
            usm.queryUsageStats(UsageStatsManager.INTERVAL_BEST, now - 10_000L, now)
                ?.maxByOrNull { it.lastTimeUsed }?.packageName
        } catch (e: Exception) { null }
    }

    private fun sendAlert(title: String, body: String) {
        try {
            val nm  = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val pi  = PendingIntent.getActivity(this, 0,
                packageManager.getLaunchIntentForPackage(packageName),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
            nm.notify(System.currentTimeMillis().toInt(),
                NotificationCompat.Builder(this, ALERT_CHANNEL_ID)
                    .setSmallIcon(android.R.drawable.ic_dialog_info)
                    .setContentTitle(title).setContentText(body)
                    .setAutoCancel(true).setContentIntent(pi)
                    .setPriority(NotificationCompat.PRIORITY_HIGH)
                    .setDefaults(NotificationCompat.DEFAULT_ALL)
                    .setSound(uri).setVibrate(longArrayOf(0, 250, 250, 250))
                    .build())
        } catch (e: Exception) { Log.e(TAG, "sendAlert: ${e.message}") }
    }

    private fun isNotificationListenerEnabled(): Boolean {
        val s = Settings.Secure.getString(contentResolver, "enabled_notification_listeners") ?: return false
        return s.contains(ComponentName(this, PhaseOutNotificationListener::class.java).flattenToString()) || s.contains(packageName)
    }

    private fun hasUsagePermission(): Boolean {
        return try {
            val appOps = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
            val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q)
                appOps.unsafeCheckOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), packageName)
            else @Suppress("DEPRECATION") appOps.checkOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), packageName)
            mode == AppOpsManager.MODE_ALLOWED
        } catch (e: Exception) { false }
    }

    private fun saveFocusState(active: Boolean, allowlist: List<String>) {
        getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).edit()
            .putBoolean(KEY_FOCUS_ACTIVE, active)
            .putString(KEY_FOCUS_ALLOWLIST, org.json.JSONArray(allowlist).toString()).apply()
    }

    private fun saveTimerState(active: Boolean, expiryMs: Long) {
        getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).edit()
            .putBoolean(KEY_TIMER_ACTIVE, active).putLong(KEY_TIMER_EXPIRY, expiryMs).apply()
    }

    private fun startForegroundCompat() {
        val notif = NotificationCompat.Builder(this, NOTIF_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle("PhaseOut is active").setContentText("Monitoring your schedules")
            .setOngoing(true).build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q)
            startForeground(NOTIF_ID, notif, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        else startForeground(NOTIF_ID, notif)
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm  = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
        val aa  = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_NOTIFICATION)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build()

        nm.createNotificationChannel(NotificationChannel(
            NOTIF_CHANNEL_ID, "PhaseOut Service", NotificationManager.IMPORTANCE_LOW)
            .apply { setSound(null, null); enableVibration(false) })

        nm.createNotificationChannel(NotificationChannel(
            ALERT_CHANNEL_ID, "PhaseOut Alerts", NotificationManager.IMPORTANCE_HIGH)
            .apply { enableVibration(true); vibrationPattern = longArrayOf(0,250,250,250); setSound(uri, aa) })

        nm.createNotificationChannel(NotificationChannel(
            PREACTION_CHANNEL, "Schedule Reminders", NotificationManager.IMPORTANCE_HIGH)
            .apply { description = "30-second warning before a schedule fires"; enableVibration(true); setSound(uri, aa) })

        Log.i(TAG, "Notification channels created (IMPORTANCE_HIGH + sound)")
    }
}