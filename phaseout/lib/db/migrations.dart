// ─────────────────────────────────────────────────────────────
//  lib/db/migrations.dart  (UPGRADED — v6)
//  PhaseOut — sqflite schema migrations
//
//  v1 — schedules, usage_events
//  v2 — app_usage_daily
//  v3 — focus_sessions, battery_snapshots
//  v4 — wake_hour, wake_minute on schedules (morning alarm)
//  v5 — battery_snapshots.screen_on_seconds (ML signal)
//       day_profiles (per-weekday ML model storage)
//  v6 — focus_sessions.allowlist → blockedApps (blacklist refactor)
// ─────────────────────────────────────────────────────────────

import 'package:sqflite/sqflite.dart';
import '../utils/constants.dart';

class DatabaseMigrations {

  DatabaseMigrations._();

  // ── v1 ──────────────────────────────────────────────────────
  static Future<void> createV1(Database db) async {
    await _createSchedules(db);
    await _createUsageEvents(db);
  }

  // ── v2 ──────────────────────────────────────────────────────
  static Future<void> migrateV1ToV2(Database db) async {
    await _createAppUsageDaily(db);
  }

  // ── v3 ──────────────────────────────────────────────────────
  static Future<void> migrateV2ToV3(Database db) async {
    await _createFocusSessions(db);
    await _createBatterySnapshots(db);
  }

  // ── v4 — morning alarm columns on schedules ─────────────────
  static Future<void> migrateV3ToV4(Database db) async {
    try {
      await db.execute(
        'ALTER TABLE ${AppConstants.tableSchedules} '
        'ADD COLUMN wake_hour INTEGER',
      );
    } catch (_) {}
    try {
      await db.execute(
        'ALTER TABLE ${AppConstants.tableSchedules} '
        'ADD COLUMN wake_minute INTEGER',
      );
    } catch (_) {}
  }

  // ── v5 — ML signal + day profiles ───────────────────────────
  static Future<void> migrateV4ToV5(Database db) async {
    try {
      await db.execute(
        'ALTER TABLE ${AppConstants.tableBattery} '
        'ADD COLUMN screen_on_seconds INTEGER',
      );
    } catch (_) {}
    await _createDayProfiles(db);
  }

  // ── v6 — rename focus_sessions.allowlist → blockedApps ──────
  //
  // Uses table-swap instead of ALTER TABLE RENAME COLUMN because
  // Android devices below API 29 ship with SQLite < 3.25.0 which
  // does not support RENAME COLUMN.
  static Future<void> migrateV5ToV6(Database db) async {
    // 1. New table with correct column name.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS focus_sessions_new (
        id               INTEGER PRIMARY KEY AUTOINCREMENT,
        start_time       TEXT    NOT NULL,
        end_time         TEXT,
        blockedApps      TEXT    NOT NULL DEFAULT '[]',
        blocked_attempts INTEGER NOT NULL DEFAULT 0
      )
    ''');

    // 2. Copy existing rows, mapping allowlist → blockedApps.
    try {
      await db.execute('''
        INSERT INTO focus_sessions_new
          (id, start_time, end_time, blockedApps, blocked_attempts)
        SELECT
          id, start_time, end_time, allowlist, blocked_attempts
        FROM focus_sessions
      ''');
    } catch (_) {
      // focus_sessions didn't exist yet on this install — nothing to copy.
    }

    // 3. Swap tables.
    await db.execute('DROP TABLE IF EXISTS focus_sessions');
    await db.execute(
        'ALTER TABLE focus_sessions_new RENAME TO focus_sessions');
  }

  // ─────────────────────────────────────────────────────────
  //  TABLE DEFINITIONS
  // ─────────────────────────────────────────────────────────

  static Future<void> _createSchedules(Database db) async {
    await db.execute('''
      CREATE TABLE ${AppConstants.tableSchedules} (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        name          TEXT    NOT NULL,
        trigger_time  TEXT    NOT NULL,
        days_of_week  TEXT    NOT NULL,
        actions_json  TEXT    NOT NULL,
        enabled       INTEGER NOT NULL DEFAULT 1,
        created_at    TEXT    NOT NULL,
        wake_hour     INTEGER,
        wake_minute   INTEGER
      )
    ''');
  }

  static Future<void> _createUsageEvents(Database db) async {
    await db.execute('''
      CREATE TABLE ${AppConstants.tableUsageEvents} (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        event_time    TEXT    NOT NULL,
        event_type    TEXT    NOT NULL,
        reference_id  INTEGER,
        outcome       TEXT,
        detail        TEXT
      )
    ''');
  }

  static Future<void> _createAppUsageDaily(Database db) async {
    await db.execute('''
      CREATE TABLE ${AppConstants.tableAppUsage} (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        package_name  TEXT    NOT NULL,
        app_label     TEXT    NOT NULL DEFAULT '',
        date          TEXT    NOT NULL,
        usage_minutes INTEGER NOT NULL DEFAULT 0,
        limit_minutes INTEGER,
        UNIQUE(package_name, date)
      )
    ''');
  }

  // Fresh installs at v6+ get blockedApps from the start.
  static Future<void> _createFocusSessions(Database db) async {
    await db.execute('''
      CREATE TABLE ${AppConstants.tableFocusSessions} (
        id               INTEGER PRIMARY KEY AUTOINCREMENT,
        start_time       TEXT    NOT NULL,
        end_time         TEXT,
        blockedApps      TEXT    NOT NULL DEFAULT '[]',
        blocked_attempts INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  static Future<void> _createBatterySnapshots(Database db) async {
    await db.execute('''
      CREATE TABLE ${AppConstants.tableBattery} (
        id                INTEGER PRIMARY KEY AUTOINCREMENT,
        recorded_at       TEXT    NOT NULL,
        level             INTEGER NOT NULL,
        charging          INTEGER NOT NULL,
        day_of_week       INTEGER NOT NULL,
        screen_on_seconds INTEGER
      )
    ''');
  }

  static Future<void> _createDayProfiles(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ${AppConstants.tableDayProfiles} (
        id                  INTEGER PRIMARY KEY AUTOINCREMENT,
        day_of_week         INTEGER NOT NULL UNIQUE,
        avg_drain_per_hour  REAL    NOT NULL DEFAULT 0,
        avg_daily_drain     REAL    NOT NULL DEFAULT 0,
        avg_screen_minutes  REAL    NOT NULL DEFAULT 0,
        busy_score          REAL    NOT NULL DEFAULT 0,
        sample_weeks        INTEGER NOT NULL DEFAULT 0,
        updated_at          TEXT    NOT NULL
      )
    ''');
  }
}