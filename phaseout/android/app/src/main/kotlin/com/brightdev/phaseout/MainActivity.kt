// ─────────────────────────────────────────────────────────────
//  android/app/src/main/kotlin/com/brightdev/phaseout/MainActivity.kt
//  PhaseOut — Native Android MethodChannel handler
//
//  Channels handled:
//    com.brightdev.phaseout/media  — stop media, audio focus, launch app
//    com.brightdev.phaseout/usage  — app usage stats, permission check
// ─────────────────────────────────────────────────────────────

package com.brightdev.phaseout

import android.app.AppOpsManager
import android.app.usage.UsageStatsManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.media.AudioManager
import android.media.session.MediaSessionManager
import android.os.Build
import android.os.Process
import android.provider.Settings
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.service.notification.NotificationListenerService

class MainActivity : FlutterActivity() {

    private val tag              = "PhaseOut.MainActivity"
    private val mediaChannelName = "com.brightdev.phaseout/media"
    private val usageChannelName = "com.brightdev.phaseout/usage"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        setupMediaChannel(flutterEngine)
        setupUsageChannel(flutterEngine)
    }

    // ── Media channel ─────────────────────────────────────────
    private fun setupMediaChannel(flutterEngine: FlutterEngine) {
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            mediaChannelName
        ).setMethodCallHandler { call, result ->
            Log.d(tag, "Media channel received: ${call.method}")
            when (call.method) {
                "stopAllMedia" -> {
                    val success = handleStopAllMedia()
                    Log.d(tag, "stopAllMedia result: $success")
                    result.success(success)
                }
                "releaseAudioFocus" -> {
                    val success = handleReleaseAudioFocus()
                    Log.d(tag, "releaseAudioFocus result: $success")
                    result.success(success)
                }
                "launchApp" -> {
                    val packageName = call.argument<String>("package")
                    if (packageName == null) {
                        result.error("INVALID_ARGUMENT", "package name required", null)
                        return@setMethodCallHandler
                    }
                    result.success(handleLaunchApp(packageName))
                }
                else -> result.notImplemented()
            }
        }
    }

    // ── Usage channel ─────────────────────────────────────────
    private fun setupUsageChannel(flutterEngine: FlutterEngine) {
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            usageChannelName
        ).setMethodCallHandler { call, result ->
            Log.d(tag, "Usage channel received: ${call.method}")
            when (call.method) {
                "getUsageStats" -> {
                    val startMs = call.argument<Long>("startMs")
                    val endMs   = call.argument<Long>("endMs")
                    if (startMs == null || endMs == null) {
                        result.error("INVALID_ARGUMENT", "startMs and endMs required", null)
                        return@setMethodCallHandler
                    }
                    result.success(handleGetUsageStats(startMs, endMs))
                }
                "hasUsagePermission" -> {
                    result.success(hasUsagePermission())
                }
                "openUsageSettings" -> {
                    handleOpenUsageSettings()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    // ─────────────────────────────────────────────────────────
    //  MEDIA HANDLERS
    // ─────────────────────────────────────────────────────────

    private fun handleStopAllMedia(): Boolean {
        return try {
            val mediaSessionManager = getSystemService(
                Context.MEDIA_SESSION_SERVICE
            ) as MediaSessionManager

            val componentName = ComponentName(
                this,
                PhaseOutNotificationListener::class.java
            )

            val activeSessions = mediaSessionManager.getActiveSessions(componentName)

            if (activeSessions.isEmpty()) {
                Log.d(tag, "No active media sessions found")
                return handleReleaseAudioFocus()
            }

            var stopped = 0
            for (session in activeSessions) {
                try {
                    session.transportControls.stop()
                    stopped++
                    Log.d(tag, "Stopped session: ${session.packageName}")
                } catch (e: Exception) {
                    Log.w(tag, "Could not stop ${session.packageName}: ${e.message}")
                }
            }
            Log.d(tag, "Stopped $stopped/${activeSessions.size} sessions")
            true

        } catch (e: SecurityException) {
            Log.w(tag, "SecurityException — falling back to audio focus: ${e.message}")
            handleReleaseAudioFocus()
        } catch (e: Exception) {
            Log.e(tag, "handleStopAllMedia failed: ${e.message}")
            false
        }
    }

    private fun handleReleaseAudioFocus(): Boolean {
        return try {
            val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val request = android.media.AudioFocusRequest.Builder(
                    AudioManager.AUDIOFOCUS_GAIN
                ).build()
                audioManager.abandonAudioFocusRequest(request)
            } else {
                @Suppress("DEPRECATION")
                audioManager.abandonAudioFocus(null)
            }
            Log.d(tag, "Audio focus released")
            true
        } catch (e: Exception) {
            Log.e(tag, "handleReleaseAudioFocus failed: ${e.message}")
            false
        }
    }

    private fun handleLaunchApp(packageName: String): Boolean {
        return try {
            val intent = packageManager.getLaunchIntentForPackage(packageName)
            if (intent == null) {
                Log.w(tag, "No launch intent for: $packageName")
                return false
            }
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
            Log.d(tag, "Launched: $packageName")
            true
        } catch (e: Exception) {
            Log.e(tag, "handleLaunchApp($packageName) failed: ${e.message}")
            false
        }
    }

    // ─────────────────────────────────────────────────────────
    //  USAGE HANDLERS
    // ─────────────────────────────────────────────────────────

    private fun handleGetUsageStats(startMs: Long, endMs: Long): Map<String, Long> {
        return try {
            if (!hasUsagePermission()) {
                Log.w(tag, "PACKAGE_USAGE_STATS not granted")
                return emptyMap()
            }

            val usageManager = getSystemService(
                Context.USAGE_STATS_SERVICE
            ) as UsageStatsManager

            val stats = usageManager.queryUsageStats(
                UsageStatsManager.INTERVAL_DAILY,
                startMs,
                endMs
            )

            if (stats.isNullOrEmpty()) {
                Log.d(tag, "No usage stats returned")
                return emptyMap()
            }

            // Aggregate by package name (queryUsageStats can return duplicates)
            val result = mutableMapOf<String, Long>()
            for (stat in stats) {
                val minutes = stat.totalTimeInForeground / 60000L
                if (minutes > 0) {
                    result[stat.packageName] = (result[stat.packageName] ?: 0L) + minutes
                }
            }

            Log.d(tag, "Usage stats: ${result.size} apps with foreground time")
            result

        } catch (e: Exception) {
            Log.e(tag, "handleGetUsageStats failed: ${e.message}")
            emptyMap()
        }
    }

    private fun hasUsagePermission(): Boolean {
        return try {
            val appOps = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
            val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                appOps.unsafeCheckOpNoThrow(
                    AppOpsManager.OPSTR_GET_USAGE_STATS,
                    Process.myUid(),
                    packageName
                )
            } else {
                @Suppress("DEPRECATION")
                appOps.checkOpNoThrow(
                    AppOpsManager.OPSTR_GET_USAGE_STATS,
                    Process.myUid(),
                    packageName
                )
            }
            mode == AppOpsManager.MODE_ALLOWED
        } catch (e: Exception) {
            Log.e(tag, "hasUsagePermission check failed: ${e.message}")
            false
        }
    }

    private fun handleOpenUsageSettings() {
        try {
            val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
        } catch (e: Exception) {
            Log.e(tag, "handleOpenUsageSettings failed: ${e.message}")
        }
    }
}

// ─────────────────────────────────────────────────────────────
//  Notification Listener Service
//  Required for MediaSessionManager.getActiveSessions()
//  Declare this in AndroidManifest.xml inside <application>
// ─────────────────────────────────────────────────────────────
class PhaseOutNotificationListener : NotificationListenerService()