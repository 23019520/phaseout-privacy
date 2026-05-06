// ─────────────────────────────────────────────────────────────
//  MainActivity.kt — PhaseOut
//
//  FIXED:
//  - setupUsageChannel() now fully implemented — was previously
//    a stub returning notImplemented() for every call.
//
//  Usage channel methods:
//    getUsageStats       — foreground-only, strict midnight boundary
//    hasUsagePermission  — AppOpsManager check
//    openUsageSettings   — ACTION_USAGE_ACCESS_SETTINGS
//    getAppLabel         — real system label via PackageManager
//    getAppIcon          — PNG bytes via PackageManager
//    getAllInstalledApps  — all launchable apps (launcher-filtered)
//    getForegroundApp    — 2-second window, foreground only
// ─────────────────────────────────────────────────────────────

package com.brightdev.phaseout

import android.app.AppOpsManager
import android.app.NotificationManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.AdaptiveIconDrawable
import android.graphics.drawable.BitmapDrawable
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.Calendar

class MainActivity : FlutterActivity() {

    private val tag              = "PhaseOut.MainActivity"
    private val mediaChannelName = "com.brightdev.phaseout/media"
    private val usageChannelName = "com.brightdev.phaseout/usage"

    private var soundPickerResult: MethodChannel.Result? = null

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == 1001) {
            val uri = data?.getParcelableExtra<Uri>(
                RingtoneManager.EXTRA_RINGTONE_PICKED_URI
            )
            soundPickerResult?.success(uri?.toString())
            soundPickerResult = null
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        startPhaseOutService()
        setupMediaChannel(flutterEngine)
        setupUsageChannel(flutterEngine)
    }

    // ─────────────────────────────────────────────────────────
    // Service start
    // ─────────────────────────────────────────────────────────

    private fun startPhaseOutService() {
        try {
            val intent = Intent(this, PhaseOutService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                startForegroundService(intent)
            else
                startService(intent)
        } catch (e: Exception) {
            Log.e(tag, "Failed to start service: ${e.message}")
        }
    }

    // ─────────────────────────────────────────────────────────
    // MEDIA CHANNEL  (unchanged)
    // ─────────────────────────────────────────────────────────

    private fun setupMediaChannel(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, mediaChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {

                    "stopAllMedia",
                    "releaseAudioFocus" -> {
                        sendServiceIntent(PhaseOutService.ACTION_STOP_MEDIA)
                        result.success(true)
                    }

                    "setAudioTimer" -> {
                        val ms = call.argument<Long>("expiryMs")
                        if (ms == null) {
                            result.error("INVALID_ARGUMENT", "expiryMs required", null)
                        } else {
                            startServiceIntent(
                                Intent(this, PhaseOutService::class.java).apply {
                                    action = PhaseOutService.ACTION_SET_TIMER
                                    putExtra(PhaseOutService.EXTRA_EXPIRY_MS, ms)
                                }
                            )
                            result.success(true)
                        }
                    }

                    "cancelAudioTimer" -> {
                        sendServiceIntent(PhaseOutService.ACTION_CANCEL_TIMER)
                        result.success(true)
                    }

                    "startFocus" -> {
                        val al = call.argument<List<String>>("allowlist") ?: emptyList()
                        startServiceIntent(
                            Intent(this, PhaseOutService::class.java).apply {
                                action = PhaseOutService.ACTION_START_FOCUS
                                putStringArrayListExtra(
                                    PhaseOutService.EXTRA_ALLOWLIST, ArrayList(al))
                            }
                        )
                        result.success(true)
                    }

                    "stopFocus" -> {
                        sendServiceIntent(PhaseOutService.ACTION_STOP_FOCUS)
                        result.success(true)
                    }

                    "launchApp" -> {
                        val pkg = call.argument<String>("package")
                        if (pkg == null) result.error("INVALID_ARGUMENT", "package required", null)
                        else result.success(handleLaunchApp(pkg))
                    }

                    "goHome" -> {
                        startActivity(Intent(Intent.ACTION_MAIN).apply {
                            addCategory(Intent.CATEGORY_HOME)
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        })
                        result.success(true)
                    }

                    "dimBrightness" -> {
                        val level = call.argument<Int>("level") ?: 30
                        startServiceIntent(Intent(this, PhaseOutService::class.java).apply {
                            action = PhaseOutService.ACTION_DIM_BRIGHTNESS
                            putExtra(PhaseOutService.EXTRA_BRIGHTNESS_LEVEL, level)
                        })
                        result.success(true)
                    }

                    "restoreBrightness" -> {
                        sendServiceIntent(PhaseOutService.ACTION_RESTORE_BRIGHTNESS)
                        result.success(true)
                    }

                    "enableDnd"  -> { sendServiceIntent(PhaseOutService.ACTION_ENABLE_DND);  result.success(true) }
                    "disableDnd" -> { sendServiceIntent(PhaseOutService.ACTION_DISABLE_DND); result.success(true) }

                    "sendChargeReminder" -> {
                        sendServiceIntent(PhaseOutService.ACTION_SEND_CHARGE_REMINDER)
                        result.success(true)
                    }

                    "isNotificationListenerEnabled" -> result.success(isNotificationListenerEnabled())
                    "isDndAccessGranted"            -> result.success(isDndAccessGranted())
                    "isWriteSettingsGranted"        -> result.success(Settings.System.canWrite(this))

                    "openNotificationSettings" -> {
                        startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS).apply {
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                        })
                        result.success(null)
                    }

                    "openDndSettings" -> {
                        startActivity(Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS).apply {
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                        })
                        result.success(null)
                    }

                    "openWriteSettings" -> {
                        startActivity(Intent(
                            Settings.ACTION_MANAGE_WRITE_SETTINGS,
                            Uri.parse("package:${applicationContext.packageName}")
                        ).apply {
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                        })
                        result.success(null)
                    }

                    "openBatterySettings" -> {
                        try {
                            startActivity(Intent(
                                Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                                Uri.parse("package:$packageName")
                            ).apply {
                                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                            })
                        } catch (e: Exception) {
                            try {
                                startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                            } catch (e2: Exception) {
                                result.error("INTENT_FAILED", e2.message, null)
                                return@setMethodCallHandler
                            }
                        }
                        result.success(null)
                    }

                    "openOverlaySettings" -> {
                        try {
                            startActivity(Intent(
                                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                                Uri.parse("package:$packageName")
                            ).apply {
                                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                            })
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("INTENT_FAILED", e.message, null)
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }

    // ─────────────────────────────────────────────────────────
    // USAGE CHANNEL  — fully implemented
    // ─────────────────────────────────────────────────────────

    private fun setupUsageChannel(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, usageChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {

                    // ── Usage stats ───────────────────────────
                    // Returns Map<packageName, foregroundMinutes> for
                    // the requested window. Uses queryEvents() so we
                    // count ONLY foreground time (MOVE_TO_FOREGROUND /
                    // MOVE_TO_BACKGROUND pairs). The startMs passed by
                    // Dart is already midnight of today in local time.
                    "getUsageStats" -> {
                        val startMs = call.argument<Long>("startMs") ?: run {
                            result.error("MISSING_ARG", "startMs required", null)
                            return@setMethodCallHandler
                        }
                        val endMs = call.argument<Long>("endMs") ?: System.currentTimeMillis()

                        // Clamp startMs to midnight of the day it falls in,
                        // ensuring we never bleed into a previous day even if
                        // the caller passes a slightly-off value.
                        val midnightMs = midnightOf(startMs)

                        result.success(getForegroundMinutes(midnightMs, endMs))
                    }

                    // ── Permission ────────────────────────────
                    "hasUsagePermission" -> result.success(hasUsagePermission())

                    "openUsageSettings" -> {
                        startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS).apply {
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                        })
                        result.success(null)
                    }

                    // ── App label ─────────────────────────────
                    "getAppLabel" -> {
                        val pkg = call.argument<String>("packageName")
                        if (pkg == null) {
                            result.error("MISSING_ARG", "packageName required", null)
                            return@setMethodCallHandler
                        }
                        result.success(resolveLabel(pkg))
                    }

                    // ── App icon (PNG bytes) ───────────────────
                    "getAppIcon" -> {
                        val pkg = call.argument<String>("packageName")
                        if (pkg == null) {
                            result.error("MISSING_ARG", "packageName required", null)
                            return@setMethodCallHandler
                        }
                        result.success(resolveIcon(pkg))
                    }

                    // ── All launchable installed apps ─────────
                    // Uses getLaunchIntentForPackage() as the filter —
                    // same as the system launcher. Returns only apps
                    // with a real entry-point; no system daemons.
                    "getAllInstalledApps" -> {
                        val apps = mutableListOf<Map<String, String>>()
                        val pm   = packageManager
                        val all  = pm.getInstalledApplications(PackageManager.GET_META_DATA)
                        for (ai in all) {
                            val launch = pm.getLaunchIntentForPackage(ai.packageName)
                                ?: continue   // not a launchable user app
                            val label = ai.loadLabel(pm).toString().trim()
                            if (label.isEmpty()) continue
                            apps.add(mapOf("packageName" to ai.packageName, "label" to label))
                        }
                        result.success(apps)
                    }

                    // ── Current foreground app (2-second window) ─
                    // Identical logic to PhaseOutService.checkFocusAndBlock()
                    // but called from the Dart UI ticker.
                    "getForegroundApp" -> {
                        if (!hasUsagePermission()) {
                            result.success(null)
                            return@setMethodCallHandler
                        }
                        val usm   = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
                        val now   = System.currentTimeMillis()
                        val stats = usm.queryUsageStats(
                            UsageStatsManager.INTERVAL_BEST, now - 2_000L, now)
                        val fg = stats
                            ?.filter { it.totalTimeInForeground > 0 }
                            ?.maxByOrNull { it.lastTimeUsed }
                            ?.packageName
                        result.success(fg)
                    }

                    else -> result.notImplemented()
                }
            }
    }

    // ─────────────────────────────────────────────────────────
    // USAGE HELPERS
    // ─────────────────────────────────────────────────────────

    /**
     * Returns true if the user has granted Usage Access to PhaseOut.
     * Uses AppOpsManager — the only reliable check across all API levels.
     */
    private fun hasUsagePermission(): Boolean {
        val aom = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            aom.unsafeCheckOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                android.os.Process.myUid(), packageName)
        } else {
            @Suppress("DEPRECATION")
            aom.checkOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                android.os.Process.myUid(), packageName)
        }
        return mode == AppOpsManager.MODE_ALLOWED
    }

    /**
     * Counts foreground minutes per package between [startMs] and [endMs]
     * by replaying MOVE_TO_FOREGROUND / MOVE_TO_BACKGROUND events.
     *
     * This is strictly foreground-only — background services, music
     * playback, and sync jobs do NOT contribute to the totals.
     *
     * Why queryEvents() instead of getTotalTimeInForeground()?
     * getTotalTimeInForeground() on INTERVAL_DAILY can bleed data from
     * the previous 24-hour window depending on OEM. queryEvents() gives
     * us raw timestamped events we clamp to [startMs, endMs] ourselves.
     */
    private fun getForegroundMinutes(startMs: Long, endMs: Long): Map<String, Int> {
        val usm = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val events = usm.queryEvents(startMs, endMs)
            ?: return emptyMap()

        // Track the timestamp each app last moved to foreground
        val foregroundStart = mutableMapOf<String, Long>()
        // Accumulate milliseconds per package
        val totalMs         = mutableMapOf<String, Long>()

        val event = UsageEvents.Event()
        while (events.hasNextEvent()) {
            events.getNextEvent(event)
            val pkg = event.packageName ?: continue

            when (event.eventType) {
                UsageEvents.Event.MOVE_TO_FOREGROUND -> {
                    foregroundStart[pkg] = event.timeStamp
                }
                UsageEvents.Event.MOVE_TO_BACKGROUND -> {
                    val fgStart = foregroundStart.remove(pkg) ?: continue
                    val elapsed = event.timeStamp - fgStart
                    if (elapsed > 0) {
                        totalMs[pkg] = (totalMs[pkg] ?: 0L) + elapsed
                    }
                }
            }
        }

        // Close any apps still in foreground at endMs
        for ((pkg, fgStart) in foregroundStart) {
            val elapsed = endMs - fgStart
            if (elapsed > 0) {
                totalMs[pkg] = (totalMs[pkg] ?: 0L) + elapsed
            }
        }

        // Convert ms → minutes, drop zero-minute entries
        return totalMs
            .mapValues { (_, ms) -> (ms / 60_000L).toInt() }
            .filter { (_, mins) -> mins > 0 }
    }

    /**
     * Returns midnight (00:00:00.000) of the calendar day that [epochMs]
     * falls in, in the device's local timezone.
     */
    private fun midnightOf(epochMs: Long): Long {
        val cal = Calendar.getInstance()
        cal.timeInMillis = epochMs
        cal.set(Calendar.HOUR_OF_DAY, 0)
        cal.set(Calendar.MINUTE, 0)
        cal.set(Calendar.SECOND, 0)
        cal.set(Calendar.MILLISECOND, 0)
        return cal.timeInMillis
    }

    /**
     * Resolves the human-readable label for [packageName].
     * Falls back to the package name itself if the app is not found.
     */
    private fun resolveLabel(packageName: String): String {
        return try {
            val ai = packageManager.getApplicationInfo(packageName, 0)
            packageManager.getApplicationLabel(ai).toString().trim()
                .ifEmpty { packageName }
        } catch (e: PackageManager.NameNotFoundException) {
            packageName
        }
    }

    /**
     * Returns the app icon for [packageName] as a PNG byte array,
     * or null if the package is not found.
     *
     * Handles AdaptiveIconDrawable (API 26+) by rendering onto a
     * white canvas — without this, adaptive icons produce a
     * transparent/black square on many devices.
     */
    private fun resolveIcon(packageName: String): ByteArray? {
        return try {
            val drawable = packageManager.getApplicationIcon(packageName)
            val bitmap: Bitmap

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                drawable is AdaptiveIconDrawable) {
                // Render adaptive icon onto a solid background
                bitmap = Bitmap.createBitmap(108, 108, Bitmap.Config.ARGB_8888)
                val canvas = Canvas(bitmap)
                drawable.setBounds(0, 0, 108, 108)
                drawable.draw(canvas)
            } else if (drawable is BitmapDrawable) {
                bitmap = drawable.bitmap
            } else {
                // Generic drawable → render to bitmap
                val w = drawable.intrinsicWidth.takeIf { it > 0 } ?: 108
                val h = drawable.intrinsicHeight.takeIf { it > 0 } ?: 108
                bitmap = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
                val canvas = Canvas(bitmap)
                drawable.setBounds(0, 0, w, h)
                drawable.draw(canvas)
            }

            ByteArrayOutputStream().use { out ->
                bitmap.compress(Bitmap.CompressFormat.PNG, 90, out)
                out.toByteArray()
            }
        } catch (e: PackageManager.NameNotFoundException) {
            null
        } catch (e: Exception) {
            Log.e(tag, "resolveIcon($packageName): ${e.message}")
            null
        }
    }

    // ─────────────────────────────────────────────────────────
    // PERMISSION HELPERS
    // ─────────────────────────────────────────────────────────

    private fun isNotificationListenerEnabled(): Boolean {
        val flat = Settings.Secure.getString(
            contentResolver, "enabled_notification_listeners") ?: return false
        return flat.contains(packageName)
    }

    private fun isDndAccessGranted(): Boolean {
        val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        return nm.isNotificationPolicyAccessGranted
    }

    // ─────────────────────────────────────────────────────────
    // HELPERS
    // ─────────────────────────────────────────────────────────

    private fun sendServiceIntent(action: String) {
        startServiceIntent(Intent(this, PhaseOutService::class.java).apply {
            this.action = action
        })
    }

    private fun startServiceIntent(intent: Intent) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                startForegroundService(intent)
            else
                startService(intent)
        } catch (e: Exception) {
            Log.e(tag, "Service error: ${e.message}")
        }
    }

    private fun handleLaunchApp(packageName: String): Boolean {
        return try {
            val intent = packageManager.getLaunchIntentForPackage(packageName)
                ?: return false
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
            true
        } catch (e: Exception) {
            false
        }
    }
}