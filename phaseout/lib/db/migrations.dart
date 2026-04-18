// ─────────────────────────────────────────────────────────────
//  lib/db/migrations.dart
//  PhaseOut — sqflite schema migrations
//
//  v1 — schedules, usage_events
//  v2 — app_usage_daily
//  v3 — focus_sessions, battery_snapshots
//  v4 — wake_hour, wake_minute on schedules (morning alarm)
// ─────────────────────────────────────────────────────────────

import 'package:sqflite/sqflite.dart';
import '../utils/constants.dart';

class DatabaseMigrations {

  DatabaseMigrations._();

  // ── v1 ─────────────────────────────────────────────────────
  static Future<void> createV1(Database db) async {
    await _createSchedules(db);
    await _createUsageEvents(db);
  }

  // ── v2 ─────────────────────────────────────────────────────
  static Future<void> migrateV1ToV2(Database db) async {
    await _createAppUsageDaily(db);
  }

  // ── v3 ─────────────────────────────────────────────────────
  static Future<void> migrateV2ToV3(Database db) async {
    await _createFocusSessions(db);
    await _createBatterySnapshots(db);
  }

  // ── v4 — morning alarm columns on schedules ────────────────
  // Uses try/catch on each ALTER TABLE so it is safe to run
  // even if the columns already exist (e.g. after a reinstall
  // where the DB was not wiped).
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

  // ─────────────────────────────────────────────────────────
  //  TABLE DEFINITIONS
  // ─────────────────────────────────────────────────────────

  // Schedules now includes wake columns from the start
  // so fresh installs at v4 don't need the migration.
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

  static Future<void> _createFocusSessions(Database db) async {
    await db.execute('''
      CREATE TABLE ${AppConstants.tableFocusSessions} (
        id                INTEGER PRIMARY KEY AUTOINCREMENT,
        start_time        TEXT    NOT NULL,
        end_time          TEXT,
        allowlist         TEXT    NOT NULL,
        blocked_attempts  INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  static Future<void> _createBatterySnapshots(Database db) async {
    await db.execute('''
      CREATE TABLE ${AppConstants.tableBattery} (
        id           INTEGER PRIMARY KEY AUTOINCREMENT,
        recorded_at  TEXT    NOT NULL,
        level        INTEGER NOT NULL,
        charging     INTEGER NOT NULL,
        day_of_week  INTEGER NOT NULL
      )
    ''');
  }
}