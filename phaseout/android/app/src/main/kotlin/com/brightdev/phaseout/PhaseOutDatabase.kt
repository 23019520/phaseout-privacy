// ─────────────────────────────────────────────────────────────
//  PhaseOutDatabase.kt  — v2
//  Adds wake_hour / wake_minute for morning alarm support.
// ─────────────────────────────────────────────────────────────

package com.brightdev.phaseout

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.util.Log
import org.json.JSONArray
import java.io.File

data class ScheduleRow(
    val id:          Int,
    val name:        String,
    val triggerHour: Int,
    val triggerMin:  Int,
    val daysOfWeek:  List<Int>,
    val actions:     List<String>,
    val enabled:     Boolean,
    val wakeHour:    Int? = null,
    val wakeMinute:  Int? = null,
)

data class FocusSessionRow(
    val id:        Int,
    val allowlist: List<String>,
    val active:    Boolean,
)

object PhaseOutDatabase {

    private const val TAG     = "PhaseOut.DB"
    private const val DB_NAME = "phaseout.db"

    private fun resolvePath(context: Context): String? {
        val candidates = listOf(
            File(context.getDatabasePath(DB_NAME).absolutePath),
            File(context.applicationInfo.dataDir + "/databases/" + DB_NAME),
            File(context.filesDir.parent + "/databases/" + DB_NAME),
        )

        for (f in candidates) {
            Log.d(TAG, "Checking: ${f.absolutePath} exists=${f.exists()} size=${if (f.exists()) f.length() else 0}")
            if (f.exists() && f.length() > 0) {
                Log.i(TAG, "Using DB: ${f.absolutePath}")
                return f.absolutePath
            }
        }
        Log.w(TAG, "DB not found in any candidate path")
        return null
    }

    private fun open(context: Context): SQLiteDatabase? {
        val path = resolvePath(context) ?: return null
        return try {
            SQLiteDatabase.openDatabase(path, null, SQLiteDatabase.OPEN_READONLY)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to open DB: ${e.message}")
            null
        }
    }

    fun getEnabledSchedules(context: Context): List<ScheduleRow> {
        val db = open(context) ?: return emptyList()
        val result = mutableListOf<ScheduleRow>()
        try {
            val tableCheck = db.rawQuery(
                "SELECT name FROM sqlite_master WHERE type='table' AND name='schedules'", null)
            val exists = tableCheck.use { it.moveToFirst() }
            if (!exists) { Log.w(TAG, "schedules table missing"); return emptyList() }

            val count = db.rawQuery("SELECT COUNT(*) FROM schedules", null)
                .use { if (it.moveToFirst()) it.getInt(0) else 0 }
            Log.d(TAG, "Total schedules in DB: $count")

            // Check if wake columns exist
            val hasWakeColumns = try {
                db.rawQuery("SELECT wake_hour FROM schedules LIMIT 1", null).close()
                true
            } catch (e: Exception) { false }

            val query = if (hasWakeColumns)
                "SELECT id, name, trigger_time, days_of_week, actions_json, enabled, wake_hour, wake_minute FROM schedules WHERE enabled = 1"
            else
                "SELECT id, name, trigger_time, days_of_week, actions_json, enabled FROM schedules WHERE enabled = 1"

            val cursor = db.rawQuery(query, null)
            cursor.use { c ->
                while (c.moveToNext()) {
                    try {
                        val timeParts = c.getString(2).split(":")
                        val hour = timeParts[0].toInt()
                        val min  = timeParts[1].toInt()

                        val daysJson = JSONArray(c.getString(3))
                        val days = (0 until daysJson.length()).map { daysJson.getInt(it) }

                        val actionsJson = JSONArray(c.getString(4))
                        val actions = (0 until actionsJson.length()).map { actionsJson.getString(it) }

                        val wakeH = if (hasWakeColumns && !c.isNull(6)) c.getInt(6) else null
                        val wakeM = if (hasWakeColumns && !c.isNull(7)) c.getInt(7) else null

                        val row = ScheduleRow(
                            id          = c.getInt(0),
                            name        = c.getString(1),
                            triggerHour = hour,
                            triggerMin  = min,
                            daysOfWeek  = days,
                            actions     = actions,
                            enabled     = c.getInt(5) == 1,
                            wakeHour    = wakeH,
                            wakeMinute  = wakeM,
                        )
                        Log.d(TAG, "Loaded: '${row.name}' ${row.triggerHour}:${row.triggerMin.toString().padStart(2,'0')} days=${row.daysOfWeek} actions=${row.actions}")
                        result.add(row)
                    } catch (e: Exception) {
                        Log.w(TAG, "Parse error: ${e.message}")
                    }
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "getEnabledSchedules: ${e.message}")
        } finally {
            db.close()
        }
        Log.d(TAG, "Loaded ${result.size} enabled schedule(s)")
        return result
    }

    fun getActiveFocusSession(context: Context): FocusSessionRow? {
        val db = open(context) ?: return null
        try {
            val cursor = db.rawQuery(
                "SELECT id, allowlist FROM focus_sessions WHERE end_time IS NULL ORDER BY start_time DESC LIMIT 1", null)
            cursor.use { c ->
                if (c.moveToFirst()) {
                    val arr = JSONArray(c.getString(1))
                    return FocusSessionRow(
                        id        = c.getInt(0),
                        allowlist = (0 until arr.length()).map { arr.getString(it) },
                        active    = true,
                    )
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "getActiveFocusSession: ${e.message}")
        } finally {
            db.close()
        }
        return null
    }
}