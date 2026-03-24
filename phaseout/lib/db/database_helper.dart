// ─────────────────────────────────────────────────────────────
//  lib/db/database_helper.dart
//  PhaseOut — sqflite database access layer
//
//  Singleton pattern: call DatabaseHelper.instance to get the
//  shared instance. The database is opened once and reused.
//
//  All database calls are async and return Futures.
// ─────────────────────────────────────────────────────────────

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/schedule_model.dart';
import '../models/usage_event_model.dart';
import '../utils/constants.dart';
import '../utils/logger.dart';
import 'migrations.dart';
import '../models/app_usage_model.dart';

class DatabaseHelper {

  static const String _tag = 'DatabaseHelper';

  // ── Singleton ──────────────────────────────────────────────
  static final DatabaseHelper instance = DatabaseHelper._internal();
  factory DatabaseHelper() => instance;
  DatabaseHelper._internal();

  // The actual sqflite Database object. Lazily opened on first access.
  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  // ── Init ───────────────────────────────────────────────────
  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path   = join(dbPath, AppConstants.dbName);

    AppLogger.i(_tag, 'Opening database at $path');

    return await openDatabase(
      path,
      version:  AppConstants.dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  // Called once on first install
  Future<void> _onCreate(Database db, int version) async {
  AppLogger.i(_tag, 'Creating database schema v$version');
  await DatabaseMigrations.createV1(db);
  if (version >= 2) await DatabaseMigrations.migrateV1ToV2(db);
}

  // Called when dbVersion is bumped in a future release
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
  AppLogger.i(_tag, 'Upgrading database from v$oldVersion to v$newVersion');
  if (oldVersion < 2) await DatabaseMigrations.migrateV1ToV2(db);
}

  // ── Close (call during testing only) ──────────────────────
  Future<void> close() async {
    final db = await database;
    await db.close();
    _database = null;
    AppLogger.i(_tag, 'Database closed');
  }

  // ─────────────────────────────────────────────────────────
  //  SCHEDULES
  // ─────────────────────────────────────────────────────────

  // Insert a new schedule. Returns the new row ID.
  Future<int> insertSchedule(ScheduleModel schedule) async {
    try {
      final db = await database;
      final id = await db.insert(
        AppConstants.tableSchedules,
        schedule.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      AppLogger.d(_tag, 'Inserted schedule id=$id name=${schedule.name}');
      return id;
    } catch (e, st) {
      AppLogger.e(_tag, 'Failed to insert schedule', e, st);
      rethrow;
    }
  }

  // Update an existing schedule by its ID.
  Future<int> updateSchedule(ScheduleModel schedule) async {
    try {
      final db = await database;
      final count = await db.update(
        AppConstants.tableSchedules,
        schedule.toMap(),
        where: 'id = ?',
        whereArgs: [schedule.id],
      );
      AppLogger.d(_tag, 'Updated schedule id=${schedule.id}');
      return count;
    } catch (e, st) {
      AppLogger.e(_tag, 'Failed to update schedule', e, st);
      rethrow;
    }
  }

  // Delete a schedule by its ID.
  Future<int> deleteSchedule(int id) async {
    try {
      final db = await database;
      final count = await db.delete(
        AppConstants.tableSchedules,
        where: 'id = ?',
        whereArgs: [id],
      );
      AppLogger.d(_tag, 'Deleted schedule id=$id');
      return count;
    } catch (e, st) {
      AppLogger.e(_tag, 'Failed to delete schedule', e, st);
      rethrow;
    }
  }

  // Returns all enabled schedules.
  // Called by SchedulerService on every BGS tick.
  Future<List<ScheduleModel>> getEnabledSchedules() async {
    try {
      final db   = await database;
      final maps = await db.query(
        AppConstants.tableSchedules,
        where: 'enabled = ?',
        whereArgs: [1],
      );
      return maps.map(ScheduleModel.fromMap).toList();
    } catch (e, st) {
      AppLogger.e(_tag, 'Failed to get enabled schedules', e, st);
      return [];
    }
  }

  // Returns all schedules (enabled and disabled).
  // Used by the Schedules list screen.
  Future<List<ScheduleModel>> getAllSchedules() async {
    try {
      final db   = await database;
      final maps = await db.query(
        AppConstants.tableSchedules,
        orderBy: 'created_at DESC',
      );
      return maps.map(ScheduleModel.fromMap).toList();
    } catch (e, st) {
      AppLogger.e(_tag, 'Failed to get all schedules', e, st);
      return [];
    }
  }

  // Returns a single schedule by ID. Returns null if not found.
  Future<ScheduleModel?> getScheduleById(int id) async {
    try {
      final db   = await database;
      final maps = await db.query(
        AppConstants.tableSchedules,
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (maps.isEmpty) return null;
      return ScheduleModel.fromMap(maps.first);
    } catch (e, st) {
      AppLogger.e(_tag, 'Failed to get schedule by id=$id', e, st);
      return null;
    }
  }

  // ─────────────────────────────────────────────────────────
  //  APP USAGE
  // ─────────────────────────────────────────────────────────
 
  // Insert a new usage row or update minutes if row already exists.
  // Uses the UNIQUE(package_name, date) constraint.
  Future<void> insertOrUpdateUsage(AppUsageModel usage) async {
    try {
      final db = await database;
      await db.insert(
        AppConstants.tableAppUsage,
        usage.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      AppLogger.d(_tag, 'Usage saved: ${usage.packageName} = ${usage.usageMinutes}m');
    } catch (e, st) {
      AppLogger.e(_tag, 'Failed to insert/update usage', e, st);
      rethrow;
    }
  }
 
  // Returns all app usage rows for a given date (YYYY-MM-DD).
  // Ordered by usage_minutes descending — most used first.
  Future<List<AppUsageModel>> getUsageForDate(String date) async {
    try {
      final db   = await database;
      final maps = await db.query(
        AppConstants.tableAppUsage,
        where:   'date = ?',
        whereArgs: [date],
        orderBy: 'usage_minutes DESC',
      );
      return maps.map(AppUsageModel.fromMap).toList();
    } catch (e, st) {
      AppLogger.e(_tag, 'Failed to get usage for date $date', e, st);
      return [];
    }
  }
 
  // Returns a single usage row for a specific app on a specific date.
  // Returns null if no row exists yet for that app/date combination.
  Future<AppUsageModel?> getUsageForPackage(
    String packageName,
    String date,
  ) async {
    try {
      final db   = await database;
      final maps = await db.query(
        AppConstants.tableAppUsage,
        where:     'package_name = ? AND date = ?',
        whereArgs: [packageName, date],
        limit:     1,
      );
      if (maps.isEmpty) return null;
      return AppUsageModel.fromMap(maps.first);
    } catch (e, st) {
      AppLogger.e(_tag, 'Failed to get usage for $packageName on $date', e, st);
      return null;
    }
  }
 
  // Sets or updates the daily usage limit for an app.
  // Creates a stub row for today if one doesn't exist yet.
  Future<void> setAppLimit(String packageName, int limitMinutes) async {
    try {
      final db    = await database;
      final today = AppUsageModel.todayString();
 
      // Try to update existing row first
      final count = await db.update(
        AppConstants.tableAppUsage,
        {'limit_minutes': limitMinutes},
        where:     'package_name = ? AND date = ?',
        whereArgs: [packageName, today],
      );
 
      // If no row existed yet, insert a stub with 0 minutes used
      if (count == 0) {
        await db.insert(
          AppConstants.tableAppUsage,
          AppUsageModel(
            packageName:  packageName,
            appLabel:     packageName, // real label filled in by monitor
            date:         today,
            usageMinutes: 0,
            limitMinutes: limitMinutes,
          ).toMap(),
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
 
      AppLogger.i(_tag, 'Limit set: $packageName = ${limitMinutes}m/day');
    } catch (e, st) {
      AppLogger.e(_tag, 'Failed to set limit for $packageName', e, st);
      rethrow;
    }
  }
 
  // Returns all apps where usage has reached or exceeded the limit today.
  // Called by UsageMonitorService on every BGS tick.
  Future<List<AppUsageModel>> getAppsOverLimit() async {
    try {
      final db    = await database;
      final today = AppUsageModel.todayString();
 
      // Raw query because sqflite WHERE doesn't support column comparisons
      final maps = await db.rawQuery('''
        SELECT * FROM ${AppConstants.tableAppUsage}
        WHERE date = ?
          AND limit_minutes IS NOT NULL
          AND usage_minutes >= limit_minutes
        ORDER BY usage_minutes DESC
      ''', [today]);
 
      return maps.map(AppUsageModel.fromMap).toList();
    } catch (e, st) {
      AppLogger.e(_tag, 'Failed to get apps over limit', e, st);
      return [];
    }
  }
 

  // ─────────────────────────────────────────────────────────
  //  USAGE EVENTS
  // ─────────────────────────────────────────────────────────

  // Write a BGS action log entry.
  Future<int> insertUsageEvent(UsageEventModel event) async {
    try {
      final db = await database;
      final id = await db.insert(
        AppConstants.tableUsageEvents,
        event.toMap(),
      );
      AppLogger.d(_tag, 'Logged event type=${event.eventType} id=$id');
      return id;
    } catch (e, st) {
      AppLogger.e(_tag, 'Failed to insert usage event', e, st);
      rethrow;
    }
  }

  // Returns all usage events ordered by most recent first.
  Future<List<UsageEventModel>> getUsageEvents({int limit = 100}) async {
    try {
      final db   = await database;
      final maps = await db.query(
        AppConstants.tableUsageEvents,
        orderBy: 'event_time DESC',
        limit:   limit,
      );
      return maps.map(UsageEventModel.fromMap).toList();
    } catch (e, st) {
      AppLogger.e(_tag, 'Failed to get usage events', e, st);
      return [];
    }
  }
}
