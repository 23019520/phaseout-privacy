// ─────────────────────────────────────────────────────────────
//  MainActivity.kt — PhaseOut
// ─────────────────────────────────────────────────────────────

package com.brightdev.phaseout

import android.app.AppOpsManager
import android.app.usage.UsageStatsManager
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.drawable.BitmapDrawable
import android.os.Build
import android.os.Process
import android.provider.Settings
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

class MainActivity : FlutterActivity() {

    private val tag              = "PhaseOut.MainActivity"
    private val mediaChannelName = "com.brightdev.phaseout/media"
    private val usageChannelName = "com.brightdev.phaseout/usage"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        startPhaseOutService()
        setupMediaChannel(flutterEngine)
        setupUsageChannel(flutterEngine)
    }

    private fun startPhaseOutService() {
        try {
            val intent = Intent(this, PhaseOutService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                startForegroundService(intent)
            else startService(intent)
        } catch (e: Exception) {
            Log.e(tag, "Failed to start PhaseOutService: ${e.message}")
        }
    }

    private fun setupMediaChannel(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, mediaChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "stopAllMedia" -> { sendServiceIntent(PhaseOutService.ACTION_STOP_MEDIA); result.success(true) }
                    "releaseAudioFocus" -> { sendServiceIntent(PhaseOutService.ACTION_STOP_MEDIA); result.success(true) }
                    "setAudioTimer" -> {
                        val ms = call.argument<Long>("expiryMs")
                        if (ms == null) result.error("INVALID_ARGUMENT","expiryMs required",null)
                        else {
                            startServiceIntent(Intent(this, PhaseOutService::class.java).apply {
                                action = PhaseOutService.ACTION_SET_TIMER
                                putExtra(PhaseOutService.EXTRA_EXPIRY_MS, ms)
                            }); result.success(true)
                        }
                    }
                    "cancelAudioTimer" -> { sendServiceIntent(PhaseOutService.ACTION_CANCEL_TIMER); result.success(true) }
                    "startFocus" -> {
                        val al = call.argument<List<String>>("allowlist") ?: emptyList()
                        startServiceIntent(Intent(this, PhaseOutService::class.java).apply {
                            action = PhaseOutService.ACTION_START_FOCUS
                            putStringArrayListExtra(PhaseOutService.EXTRA_ALLOWLIST, ArrayList(al))
                        }); result.success(true)
                    }
                    "stopFocus" -> { sendServiceIntent(PhaseOutService.ACTION_STOP_FOCUS); result.success(true) }
                    "launchApp" -> {
                        val pkg = call.argument<String>("package")
                        if (pkg == null) result.error("INVALID_ARGUMENT","package required",null)
                        else result.success(handleLaunchApp(pkg))
                    }
                    "openNotificationSettings" -> {
                        startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
                            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun setupUsageChannel(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, usageChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getUsageStats" -> {
                        val startMs = call.argument<Long>("startMs")
                        val endMs   = call.argument<Long>("endMs")
                        if (startMs == null || endMs == null)
                            result.error("INVALID_ARGUMENT","startMs and endMs required",null)
                        else result.success(handleGetUsageStats(startMs, endMs))
                    }
                    "hasUsagePermission" -> result.success(hasUsagePermission())
                    "openUsageSettings" -> {
                        startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
                            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                        result.success(null)
                    }
                    "getAppLabel" -> {
                        val pkg = call.argument<String>("packageName")
                        if (pkg == null) result.error("INVALID_ARGUMENT","packageName required",null)
                        else result.success(getAppLabel(pkg))
                    }
                    "getAppIcon" -> {
                        val pkg = call.argument<String>("packageName")
                        if (pkg == null) result.error("INVALID_ARGUMENT","packageName required",null)
                        else result.success(getAppIconBytes(pkg))
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun handleGetUsageStats(startMs: Long, endMs: Long): Map<String, Long> {
        return try {
            if (!hasUsagePermission()) return emptyMap()
            val usm = getSystemService(USAGE_STATS_SERVICE) as UsageStatsManager
            val windowSec = (endMs - startMs) / 1000
            val interval  = if (windowSec < 3600) UsageStatsManager.INTERVAL_BEST
                            else UsageStatsManager.INTERVAL_DAILY
            val stats = usm.queryUsageStats(interval, startMs, endMs) ?: return emptyMap()
            val result = mutableMapOf<String, Long>()
            for (stat in stats) {
                val mins = stat.totalTimeInForeground / 60000L
                if (mins > 0) result[stat.packageName] = (result[stat.packageName] ?: 0L) + mins
            }
            result
        } catch (e: Exception) { emptyMap() }
    }

    private fun hasUsagePermission(): Boolean {
        return try {
            val appOps = getSystemService(APP_OPS_SERVICE) as AppOpsManager
            val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q)
                appOps.unsafeCheckOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), packageName)
            else @Suppress("DEPRECATION")
                appOps.checkOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), packageName)
            mode == AppOpsManager.MODE_ALLOWED
        } catch (e: Exception) { false }
    }

    private fun getAppLabel(packageName: String): String {
        return try {
            val info = packageManager.getApplicationInfo(packageName, PackageManager.GET_META_DATA)
            packageManager.getApplicationLabel(info).toString()
        } catch (e: Exception) { packageName }
    }

    private fun getAppIconBytes(packageName: String): ByteArray? {
        return try {
            val drawable = packageManager.getApplicationIcon(packageName)
            val bitmap = when (drawable) {
                is BitmapDrawable -> drawable.bitmap
                else -> {
                    val bmp = Bitmap.createBitmap(
                        drawable.intrinsicWidth.coerceAtLeast(48),
                        drawable.intrinsicHeight.coerceAtLeast(48),
                        Bitmap.Config.ARGB_8888)
                    val canvas = Canvas(bmp)
                    drawable.setBounds(0, 0, canvas.width, canvas.height)
                    drawable.draw(canvas)
                    bmp
                }
            }
            val stream  = ByteArrayOutputStream()
            val scaled  = Bitmap.createScaledBitmap(bitmap, 48, 48, true)
            scaled.compress(Bitmap.CompressFormat.PNG, 90, stream)
            stream.toByteArray()
        } catch (e: Exception) { null }
    }

    private fun handleLaunchApp(packageName: String): Boolean {
        return try {
            val intent = packageManager.getLaunchIntentForPackage(packageName) ?: return false
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent); true
        } catch (e: Exception) { false }
    }

    private fun sendServiceIntent(action: String) {
        startServiceIntent(Intent(this, PhaseOutService::class.java).apply { this.action = action })
    }

    private fun startServiceIntent(intent: Intent) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(intent)
            else startService(intent)
        } catch (e: Exception) { Log.e(tag, "startServiceIntent: ${e.message}") }
    }
}