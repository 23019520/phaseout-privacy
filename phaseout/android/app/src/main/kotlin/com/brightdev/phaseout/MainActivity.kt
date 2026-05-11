// ─────────────────────────────────────────────────────────────
//  MainActivity.kt — PhaseOut
//
//  KEY FIX — getAllInstalledApps:
//    Old: pm.getLaunchIntentForPackage(pkg) — unreliable on OEMs,
//         returns null for apps the user hasn't recently opened,
//         causing apps to appear/disappear between calls.
//
//    New: pm.queryIntentActivities(MAIN + CATEGORY_LAUNCHER) —
//         the canonical way Android builds the app drawer. Returns
//         every app with a launcher icon, regardless of whether it
//         has been opened. Consistent across all OEMs and API levels.
//
//  All other methods unchanged.
// ─────────────────────────────────────────────────────────────

package com.brightdev.phaseout

import android.app.AppOpsManager
import android.app.NotificationManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ResolveInfo
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
    //  Service start
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
    //  MEDIA CHANNEL
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
                        val al = call.argument<List<String>>("blockedApps") ?: emptyList()  // ← fixed
                        startServiceIntent(
                            Intent(this, PhaseOutService::class.java).apply {
                                action = PhaseOutService.ACTION_START_FOCUS
                                putStringArrayListExtra(
                                    PhaseOutService.EXTRA_BLOCKED_APPS, ArrayList(al))
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

                    "pickNotificationSound" -> {
                        val intent = Intent(RingtoneManager.ACTION_RINGTONE_PICKER).apply {
                            putExtra(RingtoneManager.EXTRA_RINGTONE_TYPE,
                                RingtoneManager.TYPE_NOTIFICATION)
                            putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_SILENT, false)
                        }
                        soundPickerResult = result
                        startActivityForResult(intent, 1001)
                    }

                    else -> result.notImplemented()
                }
            }
    }

    // ─────────────────────────────────────────────────────────
    //  USAGE CHANNEL
    // ─────────────────────────────────────────────────────────

    private fun setupUsageChannel(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, usageChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {

                    "getUsageStats" -> {
                        val startMs = call.argument<Long>("startMs") ?: run {
                            result.error("MISSING_ARG", "startMs required", null)
                            return@setMethodCallHandler
                        }
                        val endMs = call.argument<Long>("endMs") ?: System.currentTimeMillis()
                        result.success(getForegroundMinutes(midnightOf(startMs), endMs))
                    }

                    "hasUsagePermission" -> result.success(hasUsagePermission())

                    "openUsageSettings" -> {
                        startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS).apply {
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                        })
                        result.success(null)
                    }

                    "getAppLabel" -> {
                        val pkg = call.argument<String>("packageName") ?: run {
                            result.error("MISSING_ARG", "packageName required", null)
                            return@setMethodCallHandler
                        }
                        result.success(resolveLabel(pkg))
                    }

                    "getAppIcon" -> {
                        val pkg = call.argument<String>("packageName") ?: run {
                            result.error("MISSING_ARG", "packageName required", null)
                            return@setMethodCallHandler
                        }
                        result.success(resolveIcon(pkg))
                    }

                    // ── KEY FIX ───────────────────────────────
                    // Old approach: pm.getLaunchIntentForPackage(pkg)
                    //   Problem: on many OEMs this returns null for apps
                    //   that haven't been launched recently, or for apps
                    //   whose launcher activity is declared in a way that
                    //   doesn't match the simple package-name lookup.
                    //   Result: the app list is incomplete and changes
                    //   between calls depending on usage history.
                    //
                    // New approach: queryIntentActivities with ACTION_MAIN
                    //   + CATEGORY_LAUNCHER — exactly how the Android
                    //   system builds the app drawer. Every app with a
                    //   visible launcher icon appears here, unconditionally,
                    //   regardless of whether it has ever been opened.
                    //   Result: a complete, stable, deterministic list.
                    "getAllInstalledApps" -> {
                        result.success(getLauncherApps())
                    }

                    "getForegroundApp" -> {
                        if (!hasUsagePermission()) {
                            result.success(null)
                            return@setMethodCallHandler
                        }
                        val usm   = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
                        val now   = System.currentTimeMillis()
                        val stats = usm.queryUsageStats(
                            UsageStatsManager.INTERVAL_BEST, now - 2_000L, now)
                        val fg    = stats
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
    //  getLauncherApps  — the correct implementation
    // ─────────────────────────────────────────────────────────

    /**
     * Returns all apps that have a launcher entry — i.e. every app
     * that appears in the device's app drawer.
     *
     * Uses queryIntentActivities(ACTION_MAIN + CATEGORY_LAUNCHER)
     * which is the canonical Android approach. Unlike
     * getLaunchIntentForPackage(), this:
     *   • Does not depend on whether the app has been opened before
     *   • Works identically across Samsung, Xiaomi, Huawei, Pixel, etc.
     *   • Returns a stable, deterministic list on every call
     *   • Correctly handles apps with multiple launcher activities
     *     (deduped by package name below)
     *
     * PhaseOut itself is excluded so it never appears in either
     * the usage app-picker or the focus allowlist picker.
     */
    private fun getLauncherApps(): List<Map<String, String>> {
        val pm      = packageManager
        val intent  = Intent(Intent.ACTION_MAIN).apply {
            addCategory(Intent.CATEGORY_LAUNCHER)
        }

        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
            PackageManager.MATCH_ALL
        else
            0

        val resolved: List<ResolveInfo> = pm.queryIntentActivities(intent, flags)

        // Deduplicate by package name — some apps register multiple
        // launcher activities (e.g. tablets with split-screen shortcuts).
        val seen  = mutableSetOf<String>()
        val apps  = mutableListOf<Map<String, String>>()

        for (ri in resolved) {
            val pkg   = ri.activityInfo.packageName ?: continue
            if (pkg == packageName)  continue   // exclude PhaseOut itself
            if (!seen.add(pkg))      continue   // deduplicate

            val label = ri.loadLabel(pm).toString().trim()
            if (label.isEmpty())     continue

            apps.add(mapOf("packageName" to pkg, "label" to label))
        }

        // Sort alphabetically so the Dart side receives a stable order
        // and doesn't need to sort (though it may re-sort for display).
        apps.sortBy { it["label"]!!.lowercase() }
        return apps
    }

    // ─────────────────────────────────────────────────────────
    //  Usage helpers
    // ─────────────────────────────────────────────────────────

    private fun hasUsagePermission(): Boolean {
        val aom  = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
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

    private fun getForegroundMinutes(startMs: Long, endMs: Long): Map<String, Int> {
        val usm    = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val events = usm.queryEvents(startMs, endMs) ?: return emptyMap()

        val foregroundStart = mutableMapOf<String, Long>()
        val totalMs         = mutableMapOf<String, Long>()
        val event           = UsageEvents.Event()

        while (events.hasNextEvent()) {
            events.getNextEvent(event)
            val pkg = event.packageName ?: continue
            when (event.eventType) {
                UsageEvents.Event.MOVE_TO_FOREGROUND ->
                    foregroundStart[pkg] = event.timeStamp
                UsageEvents.Event.MOVE_TO_BACKGROUND -> {
                    val fgStart = foregroundStart.remove(pkg) ?: continue
                    val elapsed = event.timeStamp - fgStart
                    if (elapsed > 0) totalMs[pkg] = (totalMs[pkg] ?: 0L) + elapsed
                }
            }
        }

        // Close apps still in foreground at endMs
        for ((pkg, fgStart) in foregroundStart) {
            val elapsed = endMs - fgStart
            if (elapsed > 0) totalMs[pkg] = (totalMs[pkg] ?: 0L) + elapsed
        }

        return totalMs
            .mapValues { (_, ms) -> (ms / 60_000L).toInt() }
            .filter    { (_, mins) -> mins > 0 }
    }

    private fun midnightOf(epochMs: Long): Long {
        val cal = Calendar.getInstance()
        cal.timeInMillis = epochMs
        cal.set(Calendar.HOUR_OF_DAY, 0)
        cal.set(Calendar.MINUTE,      0)
        cal.set(Calendar.SECOND,      0)
        cal.set(Calendar.MILLISECOND, 0)
        return cal.timeInMillis
    }

    private fun resolveLabel(packageName: String): String = try {
        val ai = packageManager.getApplicationInfo(packageName, 0)
        packageManager.getApplicationLabel(ai).toString().trim().ifEmpty { packageName }
    } catch (e: PackageManager.NameNotFoundException) { packageName }

    private fun resolveIcon(packageName: String): ByteArray? = try {
        val drawable = packageManager.getApplicationIcon(packageName)
        val bitmap: Bitmap = when {
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            drawable is AdaptiveIconDrawable -> {
                Bitmap.createBitmap(108, 108, Bitmap.Config.ARGB_8888).also {
                    val canvas = Canvas(it)
                    drawable.setBounds(0, 0, 108, 108)
                    drawable.draw(canvas)
                }
            }
            drawable is BitmapDrawable -> drawable.bitmap
            else -> {
                val w = drawable.intrinsicWidth.takeIf  { it > 0 } ?: 108
                val h = drawable.intrinsicHeight.takeIf { it > 0 } ?: 108
                Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888).also {
                    val canvas = Canvas(it)
                    drawable.setBounds(0, 0, w, h)
                    drawable.draw(canvas)
                }
            }
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

    // ─────────────────────────────────────────────────────────
    //  Permission helpers
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
    //  Intent helpers
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

    private fun handleLaunchApp(packageName: String): Boolean = try {
        val intent = packageManager.getLaunchIntentForPackage(packageName) ?: return false
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        startActivity(intent)
        true
    } catch (e: Exception) { false }
}