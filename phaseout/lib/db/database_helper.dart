// ─────────────────────────────────────────────────────────────
//  lib/db/database_helper.dart
//  PhaseOut — sqflite database access layer
// ─────────────────────────────────────────────────────────────

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/schedule_model.dart';
import '../models/usage_event_model.dart';
import '../utils/constants.dart';
import '../utils/logger.dart';
import 'migrations.dart';
import '../models/app_usage_model.dart';
import '../models/focus_session_model.dart';
import '../models/battery_snapshot_model.dart';

class DatabaseHelper {

  static const String _tag = 'DatabaseHelper';

  // ── Singleton ──────────────────────────────────────────────
  static final DatabaseHelper instance = DatabaseHelper._internal();
  factory DatabaseHelper() => instance;
  DatabaseHelper._internal();

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
      version:   AppConstants.dbVersion, // now 4
      onCreate:  _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  // Called on fresh install — build all tables at current version
  Future<void> _onCreate(Database db, int version) async {
    AppLogger.i(_tag, 'Creating database schema v$version');
    await DatabaseMigrations.createV1(db);
    if (version >= 2) await DatabaseMigrations.migrateV1ToV2(db);
    if (version >= 3) await DatabaseMigrations.migrateV2ToV3(db);
    // v4 columns (wake_hour, wake_minute) are baked into _createSchedules
    // in migrations.dart so no extra call needed for fresh installs.
  }

  // Called when existing install upgrades from an older version
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    AppLogger.i(_tag, 'Upgrading database v$oldVersion → v$newVersion');
    if (oldVersion < 2) await DatabaseMigrations.migrateV1ToV2(db);
    if (oldVersion < 3) await DatabaseMigrations.migrateV2ToV3(db);
    if (oldVersion < 4) await DatabaseMigrations.migrateV3ToV4(db);
  }

  // ── Close (testing only) ───────────────────────────────────
  Future<void> close() async {
    final db = await database;
    await db.close();
    _database = null;
    AppLogger.i(_tag, 'Database closed');
  }

  // ─────────────────────────────────────────────────────────
  //  SCHEDULES
  // ─────────────────────────────────────────────────────────

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

  Future<int> updateSchedule(ScheduleModel schedule) async {
    try {
      final db    = await database;
      final count = await db.update(
        AppConstants.tableSchedules,
        schedule.toMap(),
        where:     'id = ?',
        whereArgs: [schedule.id],
      );
      AppLogger.d(_tag, 'Updated schedule id=${schedule.id}');
      return count;
    } catch (e, st) {
      AppLogger.e(_tag, 'Failed to update schedule', e, st);
      rethrow;
    }
  }

  Future<int> deleteSchedule(int id) async {
    try {
      final db    = await database;
      final count = await db.delete(
        AppConstants.tableSchedules,
        where:     'id = ?',
        whereArgs: [id],
      );
      AppLogger.d(_tag, 'Deleted schedule id=$id');
      return count;
    } catch (e, st) {
      AppLogger.e(_tag, 'Failed to delete schedule', e, st);
      rethrow;
    }
  }

  Future<List<ScheduleModel>> getEnabledSchedules() async {
    try {
      final db   = await database;
      final maps = await db.query(
        AppConstants.tableSchedules,
        where:     'enabled = ?',
        whereArgs: [1],
      );
      return maps.map(ScheduleModel.fromMap).toList();
    } catch (e, st) {
      AppLogger.e(_tag, 'Failed to get enabled schedules', e, st);
      return [];
    }
  }

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

  Future<ScheduleModel?> getScheduleById(int id) async {
    try {
      final db   = await database;
      final maps = await db.query(
        AppConstants.tableSchedules,
        where:     'id = ?',
        whereArgs: [id],
        limit:     1,
      );
      if (maps.isEmpty) return null;
      return ScheduleModel.fromMap(maps.first);
    } catch (e, st) {
      AppLogger.e(_tag, 'Failed to get schedule id=$id', e, st);
      return null;
    }
  }

  // ─────────────────────────────────────────────────────────
  //  APP USAGE
  // ─────────────────────────────────────────────────────────

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

  Future<List<AppUsageModel>> getUsageForDate(String date) async {
    try {
      final db   = await database;
      final maps = await db.query(
        AppConstants.tableAppUsage,
        where:     'date = ?',
        whereArgs: [date],
        orderBy:   'usage_minutes DESC',
      );
      return maps.map(AppUsageModel.fromMap).toList();
    } catch (e, st) {
      AppLogger.e(_tag, 'Failed to get usage for $date', e, st);
      return [];
    }
  }

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

  Future<void> setAppLimit(String packageName, int limitMinutes) async {
    try {
      final db    = await database;
      final today = AppUsageModel.todayString();

      final count = await db.update(
        AppConstants.tableAppUsage,
        {'limit_minutes': limitMinutes},
        where:     'package_name = ? AND date = ?',
        whereArgs: [packageName, today],
      );

      if (count == 0) {
        await db.insert(
          AppConstants.tableAppUsage,
          AppUsageModel(
            packageName:  packageName,
            appLabel:     packageName,
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

  Future<List<AppUsageModel>> getAppsOverLimit() async {
    try {
      final db    = await database;
      final today = AppUsageModel.todayString();

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
  //  FOCUS SESSIONS
  // ─────────────────────────────────────────────────────────

  Future<int> insertFocusSession(FocusSessionModel session) async {
    try {
      final db = await database;
      final id = await db.insert(
        AppConstants.tableFocusSessions,
        session.toMap(),
      );
      AppLogger.d(_tag, 'Focus session inserted id=$id');
      return id;
    } catch (e, st) {
      AppLogger.e(_tag, 'Failed to insert focus session', e, st);
      rethrow;
    }
  }

  Future<void> endFocusSession(int id) async {
    try {
      final db = await database;
      await db.update(
        AppConstants.tableFocusSessions,
        {'end_time': DateTime.now().toIso8601String()},
        where:     'id = ?',
        whereArgs: [id],
      );
      AppLogger.d(_tag, 'Focus session ended id=$id');
    } catch (e, st) {
      AppLogger.e(_tag, 'Failed to end focus session', e, st);
      rethrow;
    }
  }

  Future<void> incrementBlockedAttempts(int sessionId) async {
    try {
      final db = await database;
      await db.rawUpdate('''
        UPDATE ${AppConstants.tableFocusSessions}
        SET blocked_attempts = blocked_attempts + 1
        WHERE id = ?
      ''', [sessionId]);
    } catch (e, st) {
      AppLogger.e(_tag, 'Failed to increment blocked attempts', e, st);
    }
  }

  // ─────────────────────────────────────────────────────────
  //  BATTERY SNAPSHOTS
  // ─────────────────────────────────────────────────────────

  Future<void> insertBatterySnapshot(BatterySnapshotModel snapshot) async {
    try {
      final db = await database;
      await db.insert(AppConstants.tableBattery, snapshot.toMap());
      AppLogger.d(_tag, 'Battery snapshot: ${snapshot.level}%');
    } catch (e, st) {
      AppLogger.e(_tag, 'Failed to insert battery snapshot', e, st);
      rethrow;
    }
  }

  Future<List<BatterySnapshotModel>> getBatterySnapshots({
    int days = 28,
  }) async {
    try {
      final db    = await database;
      final since = DateTime.now()
          .subtract(Duration(days: days))
          .toIso8601String();
      final maps  = await db.query(
        AppConstants.tableBattery,
        where:     'recorded_at > ?',
        whereArgs: [since],
        orderBy:   'recorded_at DESC',
      );
      return maps.map(BatterySnapshotModel.fromMap).toList();
    } catch (e, st) {
      AppLogger.e(_tag, 'Failed to get battery snapshots', e, st);
      return [];
    }
  }

  // ─────────────────────────────────────────────────────────
  //  USAGE EVENTS
  // ─────────────────────────────────────────────────────────

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