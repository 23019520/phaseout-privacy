// ─────────────────────────────────────────────────────────────
//  lib/db/migrations.dart
//  PhaseOut — sqflite schema migrations
//
//  v1 — schedules, usage_events          (Sprint 1)
//  v2 — app_usage_daily                  (Sprint 2)
//  v3 — scenarios, battery_snapshots     (Sprint 3+)
// ─────────────────────────────────────────────────────────────

import 'package:sqflite/sqflite.dart';
import '../utils/constants.dart';

class DatabaseMigrations {

  DatabaseMigrations._();

  // ── v1 — Initial schema ────────────────────────────────────
  static Future<void> createV1(Database db) async {
    await _createSchedules(db);
    await _createUsageEvents(db);
  }

  // ── v2 — App usage tracking ────────────────────────────────
  static Future<void> migrateV1ToV2(Database db) async {
    await _createAppUsageDaily(db);
  }

  // ── v3 — (future) Scenarios + battery snapshots ────────────
  // static Future<void> migrateV2ToV3(Database db) async {
  //   await _createScenarios(db);
  //   await _createBatterySnapshots(db);
  // }

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
        created_at    TEXT    NOT NULL
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

  // ── Future tables ──────────────────────────────────────────

  // static Future<void> _createScenarios(Database db) async {
  //   await db.execute('''
  //     CREATE TABLE ${AppConstants.tableScenarios} (
  //       id            INTEGER PRIMARY KEY AUTOINCREMENT,
  //       name          TEXT    NOT NULL,
  //       trigger_json  TEXT    NOT NULL,
  //       action_json   TEXT    NOT NULL,
  //       enabled       INTEGER NOT NULL DEFAULT 1,
  //       created_at    TEXT    NOT NULL,
  //       last_fired_at TEXT
  //     )
  //   ''');
  // }

  // static Future<void> _createBatterySnapshots(Database db) async {
  //   await db.execute('''
  //     CREATE TABLE ${AppConstants.tableBattery} (
  //       id           INTEGER PRIMARY KEY AUTOINCREMENT,
  //       recorded_at  TEXT    NOT NULL,
  //       level        INTEGER NOT NULL,
  //       charging     INTEGER NOT NULL,
  //       day_of_week  INTEGER NOT NULL
  //     )
  //   ''');
  // }
}