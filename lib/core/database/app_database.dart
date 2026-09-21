import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

import '../utils/data_version.dart';
import '../utils/uuid.dart';

/// Central database singleton for the pet diary app.
///
/// Schema migrations are versioned — bump [VERSION] and add a new entry to
/// [_migrations] when the schema changes.  Never modify existing migration
/// functions after they have shipped.
class AppDatabase {
  /// Current database schema version.  Bump this when you add a migration.
  // ignore: constant_identifier_names // 版本常量遵循 SCREAMING_CASE 惯例
  static const VERSION = 18;

  static Database? _db;

  /// Ordered list of migration functions.  Index 0 is the initial creation
  /// (version 1), index 1 upgrades from v1 → v2, etc.
  static final List<Future<void> Function(Database, int old, int newV)>
  _migrations = [
    _onCreate,
    _migrateV1ToV2,
    _migrateV2ToV3,
    _migrateV3ToV4,
    _migrateV4ToV5,
    _migrateV5ToV6,
    _migrateV6ToV7,
    _migrateV7ToV8,
    _migrateV8ToV9,
    _migrateV9ToV10,
    _migrateV10ToV11,
    _migrateV11ToV12,
    _migrateV12ToV13,
    _migrateV13ToV14,
    _migrateV14ToV15,
    _migrateV15ToV16,
    _migrateV16ToV17,
    _migrateV17ToV18,
  ];

  /// V3 (2026-07-15): Ensure notification columns exist (safe re-run).
  static Future<void> _migrateV2ToV3(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    final columns = (await db.rawQuery(
      'PRAGMA table_info(reminders)',
    )).map((r) => r['name'] as String).toSet();
    const newCols = {
      'notification_time': 'TEXT',
      'sound_enabled': 'INTEGER NOT NULL DEFAULT 1',
      'vibrate_enabled': 'INTEGER NOT NULL DEFAULT 1',
      'repeat_end_date': 'INTEGER',
    };
    for (final entry in newCols.entries) {
      if (!columns.contains(entry.key)) {
        await db.execute(
          'ALTER TABLE reminders ADD COLUMN ${entry.key} ${entry.value}',
        );
      }
    }
  }

  /// V2 (2026-07-15): Add notification time, sound/vibration toggles,
  /// and repeat_end_date to reminders.
  static Future<void> _migrateV1ToV2(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    final columns = (await db.rawQuery(
      'PRAGMA table_info(reminders)',
    )).map((r) => r['name'] as String).toSet();
    const newCols = {
      'notification_time': 'TEXT',
      'sound_enabled': 'INTEGER NOT NULL DEFAULT 1',
      'vibrate_enabled': 'INTEGER NOT NULL DEFAULT 1',
      'repeat_end_date': 'INTEGER',
    };
    for (final entry in newCols.entries) {
      if (!columns.contains(entry.key)) {
        await db.execute(
          'ALTER TABLE reminders ADD COLUMN ${entry.key} ${entry.value}',
        );
      }
    }
  }

  /// V5 (2026-07-18): Add 爪游 Pokémon-style tables (caught_pets, pokedex, gym_badges, poke_balls, pet_moves).
  static Future<void> _migrateV4ToV5(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    // ── caught_pets ──────────────────────────────────────────────
    final cpCols = (await db.rawQuery(
      'PRAGMA table_info(caught_pets)',
    )).map((r) => r['name'] as String).toSet();
    if (cpCols.isEmpty) {
      await db.execute('''
        CREATE TABLE caught_pets (
          id TEXT PRIMARY KEY,
          owner_virtual_pet_id TEXT NOT NULL REFERENCES virtual_pets(id) ON DELETE CASCADE,
          species_id TEXT NOT NULL,
          species_name TEXT NOT NULL,
          nickname TEXT,
          level INTEGER NOT NULL DEFAULT 1,
          experience INTEGER NOT NULL DEFAULT 0,
          current_hp INTEGER NOT NULL DEFAULT 100,
          max_hp INTEGER NOT NULL DEFAULT 100,
          atk INTEGER NOT NULL DEFAULT 10,
          def INTEGER NOT NULL DEFAULT 10,
          spd INTEGER NOT NULL DEFAULT 10,
          moves_json TEXT NOT NULL DEFAULT '[]',
          status_effect TEXT,
          is_in_team INTEGER NOT NULL DEFAULT 0,
          team_slot INTEGER,
          is_fainted INTEGER NOT NULL DEFAULT 0,
          times_caught INTEGER NOT NULL DEFAULT 1,
          caught_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        )
      ''');
    }

    // ── pokedex_entries ───────────────────────────────────────────
    final pdCols = (await db.rawQuery(
      'PRAGMA table_info(pokedex_entries)',
    )).map((r) => r['name'] as String).toSet();
    if (pdCols.isEmpty) {
      await db.execute('''
        CREATE TABLE pokedex_entries (
          id TEXT PRIMARY KEY,
          species_id TEXT NOT NULL,
          species_name TEXT NOT NULL,
          seen INTEGER NOT NULL DEFAULT 0,
          caught INTEGER NOT NULL DEFAULT 0,
          times_seen INTEGER NOT NULL DEFAULT 0,
          times_caught INTEGER NOT NULL DEFAULT 0,
          first_caught_level INTEGER,
          first_caught_at INTEGER,
          updated_at INTEGER NOT NULL
        )
      ''');
    }

    // ── gym_badges ────────────────────────────────────────────────
    final gbCols = (await db.rawQuery(
      'PRAGMA table_info(gym_badges)',
    )).map((r) => r['name'] as String).toSet();
    if (gbCols.isEmpty) {
      await db.execute('''
        CREATE TABLE gym_badges (
          id TEXT PRIMARY KEY,
          gym_id TEXT NOT NULL,
          gym_name TEXT NOT NULL,
          badge_level INTEGER NOT NULL,
          earned_at INTEGER NOT NULL
        )
      ''');
    }

    // ── poke_balls ────────────────────────────────────────────────
    final pbCols = (await db.rawQuery(
      'PRAGMA table_info(poke_balls)',
    )).map((r) => r['name'] as String).toSet();
    if (pbCols.isEmpty) {
      await db.execute('''
        CREATE TABLE poke_balls (
          id TEXT PRIMARY KEY,
          ball_type TEXT NOT NULL,
          quantity INTEGER NOT NULL DEFAULT 0
        )
      ''');
      // Insert defaults
      await db.execute('''
        INSERT INTO poke_balls (id, ball_type, quantity) VALUES
          ('pb_normal', 'normal', 10),
          ('pb_great', 'great', 5),
          ('pb_ultra', 'ultra', 0),
          ('pb_master', 'master', 0)
      ''');
    }
  }

  /// V6 (2026-07-19): Add completed_quest_ids column to game_currencies.
  static Future<void> _migrateV5ToV6(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    final gcCols = (await db.rawQuery(
      'PRAGMA table_info(game_currencies)',
    )).map((r) => r['name'] as String).toSet();
    if (!gcCols.contains('completed_quest_ids')) {
      await db.execute(
        'ALTER TABLE game_currencies ADD COLUMN completed_quest_ids TEXT NOT NULL DEFAULT \'[]\'',
      );
    }
  }

  /// V7 (2026-07-31): Add game_saves table for the CatPlanet idle-game
  /// engine (single-row 'main' save, JSON blob + version).
  static Future<void> _migrateV6ToV7(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    final cols = (await db.rawQuery(
      'PRAGMA table_info(game_saves)',
    )).map((r) => r['name'] as String).toSet();
    if (cols.isEmpty) {
      await db.execute('''
        CREATE TABLE game_saves (
          id TEXT PRIMARY KEY,
          save_version INTEGER NOT NULL,
          state_json TEXT NOT NULL,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        )
      ''');
    }
  }

  /// V8 (2026-07-31): Add last_done_date to reminders so the editor can
  /// compute the next due date from the last actual completion instead of
  /// back-deriving from first_due_date (which goes stale after completing
  /// instances).
  static Future<void> _migrateV7ToV8(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    final cols = (await db.rawQuery(
      'PRAGMA table_info(reminders)',
    )).map((r) => r['name'] as String).toSet();
    if (!cols.contains('last_done_date')) {
      await db.execute(
        'ALTER TABLE reminders ADD COLUMN last_done_date INTEGER',
      );
    }
  }

  /// V9 (2026-07-31): Add indexes for FK hot paths (diaries/reminders/
  /// game tables). Idempotent — safe on both fresh installs and upgrades.
  static Future<void> _migrateV8ToV9(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    const statements = [
      'CREATE INDEX IF NOT EXISTS idx_diaries_pet_id ON diaries(pet_id)',
      'CREATE INDEX IF NOT EXISTS idx_diary_images_diary_id ON diary_images(diary_id)',
      'CREATE INDEX IF NOT EXISTS idx_diary_tags_diary_id ON diary_tags(diary_id)',
      'CREATE INDEX IF NOT EXISTS idx_diary_tags_tag_id ON diary_tags(tag_id)',
      'CREATE INDEX IF NOT EXISTS idx_reminders_pet_id ON reminders(pet_id)',
      'CREATE INDEX IF NOT EXISTS idx_ri_reminder_id ON reminder_instances(reminder_id)',
      'CREATE INDEX IF NOT EXISTS idx_vp_real_pet_id ON virtual_pets(real_pet_id)',
      'CREATE INDEX IF NOT EXISTS idx_caught_owner ON caught_pets(owner_virtual_pet_id)',
      'CREATE INDEX IF NOT EXISTS idx_reward_vpet ON reward_log(virtual_pet_id)',
      'CREATE INDEX IF NOT EXISTS idx_adventure_vpet ON adventure_log(virtual_pet_id)',
      'CREATE INDEX IF NOT EXISTS idx_checkin_vpet ON checkin_history(virtual_pet_id)',
    ];
    for (final sql in statements) {
      await db.execute(sql);
    }
  }

  /// V10 (2026-08-01): 区分级联删除与个体删除。
  /// 新增 deleted_with_pet 标记：宠物级联删除置 1，个体删除置 0，
  /// restorePet 只恢复被级联删除的记录（修复「恢复宠物复活已删日记/提醒」）。
  /// 老数据回填为级联标记：旧版无法区分个体/级联删除，全部视为级联，
  /// 保证升级后恢复宠物仍能找回旧数据（保留老版本数据为最高优先）。
  static Future<void> _migrateV9ToV10(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    for (final table in ['diaries', 'reminders']) {
      final columns = (await db.rawQuery(
        'PRAGMA table_info($table)',
      )).map((r) => r['name'] as String).toSet();
      if (!columns.contains('deleted_with_pet')) {
        await db.execute(
          'ALTER TABLE $table ADD COLUMN deleted_with_pet INTEGER NOT NULL DEFAULT 0',
        );
        // 仅首次加列时回填（幂等：重复迁移不会覆盖新数据）
        await db.execute(
          'UPDATE $table SET deleted_with_pet = 1 WHERE is_deleted = 1',
        );
      }
    }
  }

  /// V11 (2026-08-09): 可选模块注册表（插口）。
  /// 供未来的可选模块登记启用状态，避免把模块开关硬编码进业务代码。
  static Future<void> _migrateV10ToV11(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    final cols = (await db.rawQuery(
      'PRAGMA table_info(module_registry)',
    )).map((r) => r['name'] as String).toSet();
    if (cols.isEmpty) {
      await db.execute('''
        CREATE TABLE module_registry (
          module_id TEXT PRIMARY KEY,
          enabled INTEGER NOT NULL DEFAULT 1,
          installed_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        )
      ''');
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.execute('''
      INSERT OR IGNORE INTO module_registry (module_id, enabled, installed_at, updated_at)
      VALUES
        ('fortune', 0, $now, $now),
        ('miaoxing_rise', 0, $now, $now)
    ''');
  }

  /// V12 (2026-08-24): 宠物档案增加当前体重，供提醒/健康管理联动。
  /// 只加列、可空，不破坏旧数据；可从最近爪札体重回填。
  static Future<void> _migrateV11ToV12(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    final cols = (await db.rawQuery(
      'PRAGMA table_info(pets)',
    )).map((r) => r['name'] as String).toSet();
    if (!cols.contains('current_weight_kg')) {
      await db.execute('ALTER TABLE pets ADD COLUMN current_weight_kg REAL');
    }
    if (!cols.contains('weight_updated_at')) {
      await db.execute('ALTER TABLE pets ADD COLUMN weight_updated_at INTEGER');
    }
    // 回填：用该宠物最新一篇有体重的爪札作为初始当前体重。
    await db.execute('''
      UPDATE pets
      SET current_weight_kg = (
        SELECT d.weight FROM diaries d
        WHERE d.pet_id = pets.id AND d.is_deleted = 0 AND d.weight IS NOT NULL
        ORDER BY d.diary_date DESC, d.created_at DESC LIMIT 1
      ),
      weight_updated_at = (
        SELECT d.diary_date FROM diaries d
        WHERE d.pet_id = pets.id AND d.is_deleted = 0 AND d.weight IS NOT NULL
        ORDER BY d.diary_date DESC, d.created_at DESC LIMIT 1
      )
      WHERE current_weight_kg IS NULL
    ''');
  }

  /// V13 (2026-08-25): 提醒增加“是否重复”显式标记。
  /// 旧版本提醒默认视为单次（is_repeating=0），避免历史自定义提醒被误判为重复项。
  static Future<void> _migrateV12ToV13(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    final cols = (await db.rawQuery(
      'PRAGMA table_info(reminders)',
    )).map((r) => r['name'] as String).toSet();
    if (!cols.contains('is_repeating')) {
      await db.execute(
        'ALTER TABLE reminders ADD COLUMN is_repeating INTEGER NOT NULL DEFAULT 0',
      );
    }
  }

  /// V14 (2026-08-28): 提醒实例增加“第 N 次”序号，用于待办/已完成列表。
  static Future<void> _migrateV13ToV14(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    final cols = (await db.rawQuery(
      'PRAGMA table_info(reminder_instances)',
    )).map((r) => r['name'] as String).toSet();
    if (!cols.contains('occurrence_no')) {
      await db.execute(
        'ALTER TABLE reminder_instances ADD COLUMN occurrence_no INTEGER NOT NULL DEFAULT 1',
      );
    }
    // 旧数据回填：按 reminder 内完成顺序编号一次。
    await db.execute('''
      UPDATE reminder_instances
      SET occurrence_no = (
        SELECT COUNT(*) FROM reminder_instances AS ri2
        WHERE ri2.reminder_id = reminder_instances.reminder_id
          AND ri2.completed = 1
          AND ri2.completed_at IS NOT NULL
          AND ri2.completed_at <= reminder_instances.completed_at
      ) + 1
      WHERE reminder_instances.completed = 1
    ''');
  }

  /// V15 (2026-08-29): 提醒实例支持软删除（“已完成记录删除进最近删除”）。
  /// 旧数据回填：全部视为未删除（默认 0），无需额外 UPDATE。
  static Future<void> _migrateV14ToV15(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    final cols = (await db.rawQuery(
      'PRAGMA table_info(reminder_instances)',
    )).map((r) => r['name'] as String).toSet();
    if (!cols.contains('is_deleted')) {
      await db.execute(
        'ALTER TABLE reminder_instances ADD COLUMN is_deleted INTEGER NOT NULL DEFAULT 0',
      );
    }
    if (!cols.contains('deleted_at')) {
      await db.execute(
        'ALTER TABLE reminder_instances ADD COLUMN deleted_at INTEGER',
      );
    }
  }

  /// V16 (2026-09-20): 提醒实例增加“随宠物级联删除”标记。
  ///
  /// 背景：restorePet 原先只判断"提醒实体是否级联删除"，会把用户**个体删除**
  /// 的完成记录一起复活（docs/代码审计待办.md P1-2）。
  /// 只增列 + 旧数据回填：把当前仍属于"级联删除提醒"的软删实例标记为级联删除，
  /// 保证升级前后行为一致；此后个体删除的实例标记为 0，不会再被恢复宠物复活。
  static Future<void> _migrateV15ToV16(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    final cols = (await db.rawQuery(
      'PRAGMA table_info(reminder_instances)',
    )).map((r) => r['name'] as String).toSet();
    if (!cols.contains('deleted_with_pet')) {
      await db.execute(
        'ALTER TABLE reminder_instances ADD COLUMN deleted_with_pet INTEGER NOT NULL DEFAULT 0',
      );
    }
    await db.execute('''
      UPDATE reminder_instances
      SET deleted_with_pet = 1
      WHERE is_deleted = 1
        AND reminder_id IN (
          SELECT id FROM reminders WHERE is_deleted = 1 AND deleted_with_pet = 1
        )
    ''');

    // 顺带修正 V14 回填的序号 off-by-one（docs/代码审计待办.md P2-1）：
    // 当时用 COUNT(... <= completed_at) + 1，COUNT 含自身 → 最早一条得 2，
    // 历史记录被编成 2..n+1；这里就地重算为 1..n（不新增迁移版本，
    // 因为 V16 尚未随任何安装包发布，尚未回填过的库不受影响）。
    await db.execute('''
      UPDATE reminder_instances
      SET occurrence_no = (
        SELECT COUNT(*) FROM reminder_instances AS ri2
        WHERE ri2.reminder_id = reminder_instances.reminder_id
          AND ri2.completed = 1
          AND ri2.completed_at IS NOT NULL
          AND (
            ri2.completed_at < reminder_instances.completed_at
            OR (ri2.completed_at = reminder_instances.completed_at
                AND ri2.id <= reminder_instances.id)
          )
      )
      WHERE completed = 1 AND completed_at IS NOT NULL
    ''');
    // 待办实例的序号应为"已完成条数 + 1"（V14 时它们被留在默认值 1）。
    await db.execute('''
      UPDATE reminder_instances
      SET occurrence_no = (
        SELECT COUNT(*) + 1 FROM reminder_instances AS ri2
        WHERE ri2.reminder_id = reminder_instances.reminder_id
          AND ri2.completed = 1
      )
      WHERE completed = 0
    ''');
  }

  /// V18 (2026-09-21): 用药疗程。
  ///
  /// `course_days` 非空 = 这是一条用药提醒；`dose_times` = 每天服药时刻，
  /// 逗号分隔的「当日分钟数」（如 540,1260 = 09:00、21:00）。
  /// 只增列、可空：老库升级后两列都是 NULL，全部历史提醒保持「非用药」行为，
  /// 升级前后行为完全一致（见 docs/superpowers/specs/2026-09-21-用药疗程-design.md）。
  static Future<void> _migrateV17ToV18(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    final cols = (await db.rawQuery(
      'PRAGMA table_info(reminders)',
    )).map((r) => r['name'] as String).toSet();
    if (!cols.contains('course_days')) {
      await db.execute('ALTER TABLE reminders ADD COLUMN course_days INTEGER');
    }
    if (!cols.contains('dose_times')) {
      await db.execute('ALTER TABLE reminders ADD COLUMN dose_times TEXT');
    }
  }

  /// V17 (2026-09-20): 提醒实例增加“随提醒删除”标记。
  ///
  /// 背景：restoreReminder 原先无条件恢复该提醒下**所有**软删实例，会把用户
  /// 在“最近删除”里**单独删掉的完成记录**一起复活（docs/代码审计待办.md P2-2，
  /// 与 P1-2 的“恢复宠物复活个体删除记录”同源）。
  /// 只增列 + 旧数据回填：把看起来"与提醒同一次删除"的实例标记为随提醒删除
  /// （待办：删除时刻不晚于实体删除时刻；完成记录：必须与实体同一时刻删除——
  /// 完成记录只能在实体删除**之后**被单独删掉，因此这条能区分开），
  /// 保证升级前后恢复行为一致；此后两个删除入口各自打各自的标记。
  static Future<void> _migrateV16ToV17(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    final cols = (await db.rawQuery(
      'PRAGMA table_info(reminder_instances)',
    )).map((r) => r['name'] as String).toSet();
    if (!cols.contains('deleted_with_reminder')) {
      await db.execute(
        'ALTER TABLE reminder_instances ADD COLUMN deleted_with_reminder INTEGER NOT NULL DEFAULT 0',
      );
    }
    // 旧数据回填（幂等：重复迁移不会覆盖新数据）。
    // "实体删除时刻"用 reminders.updated_at 表达：softDeleteReminder 与
    // deleteCompletedInstance 都用同一个 nowMs() 同时写 updated_at 和实例
    // deleted_at，且删除之后没有任何路径再改写实体的 updated_at。
    await db.execute('''
      UPDATE reminder_instances
      SET deleted_with_reminder = 1
      WHERE is_deleted = 1
        AND deleted_with_pet = 0
        AND reminder_id IN (
          SELECT id FROM reminders WHERE is_deleted = 1 AND deleted_with_pet = 0
        )
        AND (
          (completed = 0 AND deleted_at <= (
            SELECT updated_at FROM reminders WHERE reminders.id = reminder_instances.reminder_id
          ))
          OR (completed = 1 AND deleted_at = (
            SELECT updated_at FROM reminders WHERE reminders.id = reminder_instances.reminder_id
          ))
        )
    ''');
  }

  /// V4 (2026-07-18): Add 7 game tables for the 爪游 Pokémon-style module.
  static Future<void> _migrateV3ToV4(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    // ── virtual_pets ────────────────────────────────────────────────
    final vpCols = (await db.rawQuery(
      'PRAGMA table_info(virtual_pets)',
    )).map((r) => r['name'] as String).toSet();
    if (vpCols.isEmpty) {
      await db.execute('''
        CREATE TABLE virtual_pets (
          id TEXT PRIMARY KEY,
          real_pet_id TEXT NOT NULL REFERENCES pets(id) ON DELETE CASCADE,
          name TEXT NOT NULL,
          level INTEGER NOT NULL DEFAULT 1,
          experience INTEGER NOT NULL DEFAULT 0,
          evolution_stage TEXT NOT NULL DEFAULT 'baby',
          stat_str INTEGER NOT NULL DEFAULT 5,
          stat_int INTEGER NOT NULL DEFAULT 5,
          stat_dex INTEGER NOT NULL DEFAULT 5,
          stat_sta_max INTEGER NOT NULL DEFAULT 100,
          stat_hp_max INTEGER NOT NULL DEFAULT 100,
          stamina_current INTEGER NOT NULL DEFAULT 100,
          hp_current INTEGER NOT NULL DEFAULT 100,
          weapon_id TEXT,
          armor_id TEXT,
          accessory_id TEXT,
          skill_levels TEXT NOT NULL DEFAULT '{}',
          mood INTEGER NOT NULL DEFAULT 50,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        )
      ''');
    }

    // ── game_currencies ─────────────────────────────────────────────
    final gcCols = (await db.rawQuery(
      'PRAGMA table_info(game_currencies)',
    )).map((r) => r['name'] as String).toSet();
    if (gcCols.isEmpty) {
      await db.execute('''
        CREATE TABLE game_currencies (
          id TEXT PRIMARY KEY,
          paw_coins INTEGER NOT NULL DEFAULT 0,
          memory_fragments INTEGER NOT NULL DEFAULT 0,
          last_daily_refresh_date INTEGER,
          consecutive_checkin_days INTEGER NOT NULL DEFAULT 0,
          last_checkin_date INTEGER,
          total_diaries_written INTEGER NOT NULL DEFAULT 0,
          total_reminders_completed INTEGER NOT NULL DEFAULT 0,
          total_adventures_completed INTEGER NOT NULL DEFAULT 0,
          updated_at INTEGER NOT NULL
        )
      ''');
    }

    // ── equipment ───────────────────────────────────────────────────
    final eqCols = (await db.rawQuery(
      'PRAGMA table_info(equipment)',
    )).map((r) => r['name'] as String).toSet();
    if (eqCols.isEmpty) {
      await db.execute('''
        CREATE TABLE equipment (
          id TEXT PRIMARY KEY,
          template_id TEXT NOT NULL,
          equipped INTEGER NOT NULL DEFAULT 0,
          slot_type TEXT NOT NULL,
          rarity TEXT NOT NULL DEFAULT 'common',
          level INTEGER NOT NULL DEFAULT 1,
          bonus_atk INTEGER NOT NULL DEFAULT 0,
          bonus_def INTEGER NOT NULL DEFAULT 0,
          bonus_luk INTEGER NOT NULL DEFAULT 0,
          bonus_str INTEGER NOT NULL DEFAULT 0,
          bonus_int INTEGER NOT NULL DEFAULT 0,
          bonus_dex INTEGER NOT NULL DEFAULT 0,
          acquired_at INTEGER NOT NULL,
          acquired_source TEXT NOT NULL
        )
      ''');
    }

    // ── adventure_log ───────────────────────────────────────────────
    final alCols = (await db.rawQuery(
      'PRAGMA table_info(adventure_log)',
    )).map((r) => r['name'] as String).toSet();
    if (alCols.isEmpty) {
      await db.execute('''
        CREATE TABLE adventure_log (
          id TEXT PRIMARY KEY,
          virtual_pet_id TEXT NOT NULL REFERENCES virtual_pets(id) ON DELETE CASCADE,
          map_id TEXT NOT NULL,
          started_at INTEGER NOT NULL,
          completed_at INTEGER NOT NULL,
          duration_seconds INTEGER NOT NULL,
          stamina_cost INTEGER NOT NULL DEFAULT 0,
          result TEXT NOT NULL DEFAULT 'pending',
          monster_id TEXT,
          monster_name TEXT,
          monster_level INTEGER,
          player_effective_atk INTEGER NOT NULL DEFAULT 0,
          player_effective_def INTEGER NOT NULL DEFAULT 0,
          loot_json TEXT NOT NULL DEFAULT '[]',
          coins_earned INTEGER NOT NULL DEFAULT 0,
          xp_earned INTEGER NOT NULL DEFAULT 0,
          detailed_report TEXT
        )
      ''');
    }

    // ── achievement_progress ────────────────────────────────────────
    final apCols = (await db.rawQuery(
      'PRAGMA table_info(achievement_progress)',
    )).map((r) => r['name'] as String).toSet();
    if (apCols.isEmpty) {
      await db.execute('''
        CREATE TABLE achievement_progress (
          id TEXT PRIMARY KEY,
          achievement_id TEXT NOT NULL,
          unlocked INTEGER NOT NULL DEFAULT 0,
          unlocked_at INTEGER,
          progress INTEGER NOT NULL DEFAULT 0,
          target INTEGER NOT NULL DEFAULT 1,
          created_at INTEGER NOT NULL
        )
      ''');
    }

    // ── reward_log ──────────────────────────────────────────────────
    final rlCols = (await db.rawQuery(
      'PRAGMA table_info(reward_log)',
    )).map((r) => r['name'] as String).toSet();
    if (rlCols.isEmpty) {
      await db.execute('''
        CREATE TABLE reward_log (
          id TEXT PRIMARY KEY,
          virtual_pet_id TEXT NOT NULL,
          source TEXT NOT NULL,
          source_id TEXT,
          xp_earned INTEGER NOT NULL DEFAULT 0,
          coins_earned INTEGER NOT NULL DEFAULT 0,
          fragments_earned INTEGER NOT NULL DEFAULT 0,
          stat_str_gained INTEGER NOT NULL DEFAULT 0,
          stat_int_gained INTEGER NOT NULL DEFAULT 0,
          stat_dex_gained INTEGER NOT NULL DEFAULT 0,
          created_at INTEGER NOT NULL
        )
      ''');
    }

    // ── checkin_history ─────────────────────────────────────────────
    final chCols = (await db.rawQuery(
      'PRAGMA table_info(checkin_history)',
    )).map((r) => r['name'] as String).toSet();
    if (chCols.isEmpty) {
      await db.execute('''
        CREATE TABLE checkin_history (
          id TEXT PRIMARY KEY,
          virtual_pet_id TEXT NOT NULL,
          checkin_date INTEGER NOT NULL,
          diary_count INTEGER NOT NULL DEFAULT 0,
          reminder_count INTEGER NOT NULL DEFAULT 0,
          created_at INTEGER NOT NULL
        )
      ''');
    }
  }

  static Future<Database> get instance async {
    if (_db != null) return _db!;
    _db = await _init();
    return _db!;
  }

  /// 测试专用：覆盖数据库路径（例如 `inMemoryDatabasePath`）。
  /// 生产代码不得设置；测试结束应置回 null。
  static String? debugDatabasePathOverride;

  /// 测试专用：关闭并清空单例，便于用例之间相互隔离。
  static Future<void> debugResetForTest() async {
    await _db?.close();
    _db = null;
  }

  static Future<Database> _init() async {
    // 有测试覆盖时不要调用 getDatabasesPath()（它会去创建真实目录）。
    final overridePath = debugDatabasePathOverride;
    final path = overridePath ?? p.join(await getDatabasesPath(), 'clawtag.db');
    return openDatabase(
      path,
      version: VERSION,
      onCreate: (db, version) async {
        debugPrint('AppDatabase: onCreate v$version @ $path');
        for (var i = 0; i < version; i++) {
          await _migrations[i](db, i + 1, version);
        }
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        debugPrint('AppDatabase: onUpgrade $oldVersion → $newVersion @ $path');
        for (var v = oldVersion + 1; v <= newVersion; v++) {
          await _migrations[v - 1](db, oldVersion, v);
        }
      },
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
    );
  }

  // ========================================
  // Schema creation (version 1)
  // ========================================
  static Future<void> _onCreate(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    await db.execute('''
      CREATE TABLE pets (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        species TEXT NOT NULL,
        breed TEXT,
        gender TEXT NOT NULL DEFAULT 'unknown',
        birth_date INTEGER,
        meet_date INTEGER NOT NULL,
        meet_type TEXT NOT NULL DEFAULT 'adopt',
        avatar_path TEXT,
        notes TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        row_version INTEGER NOT NULL DEFAULT 1,
        is_deleted INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE diaries (
        id TEXT PRIMARY KEY,
        pet_id TEXT NOT NULL REFERENCES pets(id) ON DELETE CASCADE,
        title TEXT NOT NULL,
        content TEXT NOT NULL,
        mood TEXT,
        weather TEXT,
        weight REAL,
        diary_date INTEGER NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        row_version INTEGER NOT NULL DEFAULT 1,
        is_deleted INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE diary_images (
        id TEXT PRIMARY KEY,
        diary_id TEXT NOT NULL REFERENCES diaries(id) ON DELETE CASCADE,
        local_path TEXT NOT NULL,
        remote_url TEXT,
        sort_order INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE tags (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL UNIQUE,
        color INTEGER,
        created_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE diary_tags (
        diary_id TEXT NOT NULL REFERENCES diaries(id) ON DELETE CASCADE,
        tag_id TEXT NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
        PRIMARY KEY (diary_id, tag_id)
      )
    ''');

    await db.execute('''
      CREATE TABLE reminders (
        id TEXT PRIMARY KEY,
        pet_id TEXT NOT NULL REFERENCES pets(id) ON DELETE CASCADE,
        title TEXT NOT NULL,
        type TEXT NOT NULL,
        description TEXT,
        first_due_date INTEGER NOT NULL,
        repeat_unit TEXT NOT NULL DEFAULT 'once',
        repeat_interval INTEGER NOT NULL DEFAULT 1,
        notification_time TEXT,
        sound_enabled INTEGER NOT NULL DEFAULT 1,
        vibrate_enabled INTEGER NOT NULL DEFAULT 1,
        repeat_end_date INTEGER,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        row_version INTEGER NOT NULL DEFAULT 1,
        is_deleted INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE reminder_instances (
        id TEXT PRIMARY KEY,
        reminder_id TEXT NOT NULL REFERENCES reminders(id) ON DELETE CASCADE,
        due_date INTEGER NOT NULL,
        completed INTEGER NOT NULL DEFAULT 0,
        completed_at INTEGER,
        created_at INTEGER NOT NULL
      )
    ''');
  }

  // ========================================
  // Helpers
  // ========================================

  /// Generates a time-sortable UUID v7.
  ///
  /// Layout (RFC 9562):
  ///   bytes 0-5  — Unix-millisecond timestamp (48 bits, big-endian)
  ///   bytes 6-15 — cryptographically-random data
  ///   byte 6     — version nibble set to 7 (0x70)
  ///   byte 8     — variant nibble set to 10xx (0x80)
  static String uuid() => generateUuidV7();

  /// Current timestamp in milliseconds since epoch (UTC).
  static int nowMs() => DateTime.now().millisecondsSinceEpoch;

  // ========================================
  // Serialization helpers
  // ========================================
  static DateTime? _toDateTime(dynamic v) {
    if (v == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(v as int);
  }

  /// 空串路径归一为 null，避免空路径触发原生图片/视频解码错误。
  static String? _nonEmptyOrNull(String? v) =>
      (v == null || v.trim().isEmpty) ? null : v;

  // ========================================
  // Pets
  // ========================================
  static Future<List<Pet>> getAllPets() async {
    final db = await instance;
    final rows = await db.query(
      'pets',
      where: 'is_deleted = 0',
      orderBy: 'created_at DESC',
    );
    return rows.map(_petFromMap).toList();
  }

  /// 软删除的宠物，用于“最近删除”列表。
  static Future<List<Pet>> getDeletedPets() async {
    final db = await instance;
    final rows = await db.query(
      'pets',
      where: 'is_deleted = 1',
      orderBy: 'updated_at DESC',
    );
    return rows.map(_petFromMap).toList();
  }

  static Future<Pet?> getPet(String id) async {
    final db = await instance;
    final rows = await db.query('pets', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : _petFromMap(rows.first);
  }

  static Future<void> insertPet(Pet pet) async {
    final db = await instance;
    await db.insert('pets', _petToMap(pet));
    DataVersion.bump();
  }

  static Future<void> updatePet(Pet pet) async {
    final db = await instance;
    await db.update(
      'pets',
      _petToMap(pet),
      where: 'id = ?',
      whereArgs: [pet.id],
    );
    DataVersion.bump();
  }

  /// Soft-deletes a pet AND all associated records.
  ///
  /// This cascades the soft-delete to all diaries, diary images,
  /// reminders, and reminder instances belonging to this pet.
  static Future<void> softDeletePet(String id) async {
    final db = await instance;
    final ts = nowMs();
    await db.transaction((txn) async {
      // 级联软删日记/提醒：只标记尚未被个体删除的记录（个体删除过的保留其状态）
      await txn.update(
        'diaries',
        {
          'is_deleted': 1,
          'deleted_with_pet': 1,
          'updated_at': ts,
          'row_version': -1,
        },
        where: 'pet_id = ? AND is_deleted = 0',
        whereArgs: [id],
      );
      await txn.update(
        'reminders',
        {
          'is_deleted': 1,
          'deleted_with_pet': 1,
          'updated_at': ts,
          'row_version': -1,
        },
        where: 'pet_id = ? AND is_deleted = 0',
        whereArgs: [id],
      );
      // 级联软删提醒实例（与实体状态一致；restorePet 会一并恢复）
      await txn.update(
        'reminder_instances',
        {'is_deleted': 1, 'deleted_at': ts, 'deleted_with_pet': 1},
        where:
            'reminder_id IN (SELECT id FROM reminders WHERE pet_id = ?) AND is_deleted = 0',
        whereArgs: [id],
      );
      // Soft-delete the pet itself
      await txn.update(
        'pets',
        {'is_deleted': 1, 'updated_at': ts, 'row_version': -1},
        where: 'id = ?',
        whereArgs: [id],
      );
    });
    DataVersion.bump();
  }

  static Future<void> restorePet(String id) async {
    final db = await instance;
    final ts = nowMs();
    await db.transaction((txn) async {
      await txn.update(
        'pets',
        {'is_deleted': 0, 'updated_at': ts, 'row_version': 1},
        where: 'id = ?',
        whereArgs: [id],
      );
      // 先恢复实例：此时 reminders 仍保留 deleted_with_pet=1，
      // 才能准确定位“被级联删除的提醒”的软删实例。
      // 注意顺序：如果把 reminders 先改为 deleted_with_pet=0，
      // 后面的实例子查询会查不到任何提醒，导致待办/完成记录全部漏恢复。
      // 只恢复被级联删除的实例；两个删除标记一起清零，避免陈旧标记
      // 影响后续的恢复语义（P2-2 起实例有两个"随谁删除"的标记）。
      await txn.update(
        'reminder_instances',
        {
          'is_deleted': 0,
          'deleted_at': null,
          'deleted_with_pet': 0,
          'deleted_with_reminder': 0,
        },
        where: '''
          reminder_id IN (
            SELECT id FROM reminders
            WHERE pet_id = ? AND deleted_with_pet = 1
          ) AND is_deleted = 1 AND deleted_with_pet = 1
        ''',
        whereArgs: [id],
      );
      // 只恢复被级联删除的记录（个体已删的不复活），并清除级联标记
      await txn.update(
        'diaries',
        {
          'is_deleted': 0,
          'deleted_with_pet': 0,
          'updated_at': ts,
          'row_version': 1,
        },
        where: 'pet_id = ? AND deleted_with_pet = 1',
        whereArgs: [id],
      );
      await txn.update(
        'reminders',
        {
          'is_deleted': 0,
          'deleted_with_pet': 0,
          'updated_at': ts,
          'row_version': 1,
        },
        where: 'pet_id = ? AND deleted_with_pet = 1',
        whereArgs: [id],
      );
    });
    DataVersion.bump();
  }

  /// 彻底删除宠物及其关联爪札/提醒（用于“最近删除”的彻底删除）。
  static Future<void> permanentlyDeletePet(String id) async {
    final db = await instance;
    // 先记录该宠物下所有爪札媒体文件，事务成功后再清理物理文件，
    // 避免彻底删除后数据库已清空但磁盘文件成为孤儿。
    final mediaRows = await db.query(
      'diary_images',
      columns: ['local_path'],
      where: 'diary_id IN (SELECT id FROM diaries WHERE pet_id = ?)',
      whereArgs: [id],
    );
    final mediaPaths = mediaRows
        .map((r) => r['local_path'] as String?)
        .whereType<String>()
        .toList();

    await db.transaction((txn) async {
      await txn.delete(
        'reminder_instances',
        where: 'reminder_id IN (SELECT id FROM reminders WHERE pet_id = ?)',
        whereArgs: [id],
      );
      await txn.delete('reminders', where: 'pet_id = ?', whereArgs: [id]);
      await txn.delete(
        'diary_tags',
        where: 'diary_id IN (SELECT id FROM diaries WHERE pet_id = ?)',
        whereArgs: [id],
      );
      await txn.delete(
        'diary_images',
        where: 'diary_id IN (SELECT id FROM diaries WHERE pet_id = ?)',
        whereArgs: [id],
      );
      await txn.delete('diaries', where: 'pet_id = ?', whereArgs: [id]);
      await txn.delete('pets', where: 'id = ?', whereArgs: [id]);
    });
    DataVersion.bump();
    for (final path in mediaPaths) {
      _deleteFileSafe(path);
    }
  }

  static Map<String, dynamic> _petToMap(Pet pet) => {
    'id': pet.id,
    'name': pet.name,
    'species': pet.species,
    'breed': pet.breed,
    'gender': pet.gender,
    'birth_date': pet.birthDate?.millisecondsSinceEpoch,
    'meet_date': pet.meetDate.millisecondsSinceEpoch,
    'meet_type': pet.meetType,
    'avatar_path': pet.avatarPath,
    'notes': pet.notes,
    'current_weight_kg': pet.currentWeightKg,
    'weight_updated_at': pet.weightUpdatedAt?.millisecondsSinceEpoch,
    'created_at': pet.createdAt.millisecondsSinceEpoch,
    'updated_at': pet.updatedAt.millisecondsSinceEpoch,
    'row_version': pet.rowVersion,
    'is_deleted': pet.isDeleted ? 1 : 0,
  };

  static Pet _petFromMap(Map<String, dynamic> m) => Pet(
    id: m['id'] as String,
    name: m['name'] as String,
    species: m['species'] as String,
    breed: m['breed'] as String?,
    gender: m['gender'] as String,
    birthDate: _toDateTime(m['birth_date']),
    meetDate: DateTime.fromMillisecondsSinceEpoch(m['meet_date'] as int),
    meetType: m['meet_type'] as String,
    avatarPath: _nonEmptyOrNull(m['avatar_path'] as String?),
    notes: m['notes'] as String?,
    currentWeightKg: (m['current_weight_kg'] as num?)?.toDouble(),
    weightUpdatedAt: _toDateTime(m['weight_updated_at']),
    createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(m['updated_at'] as int),
    rowVersion: m['row_version'] as int,
    isDeleted: (m['is_deleted'] as int) == 1,
  );

  // ========================================
  // Diaries
  // ========================================

  /// Returns all non-deleted diaries whose pet is also non-deleted.
  static Future<List<Diary>> getAllDiaries() async {
    final db = await instance;
    final rows = await db.rawQuery('''
      SELECT d.* FROM diaries d
      INNER JOIN pets p ON d.pet_id = p.id
      WHERE d.is_deleted = 0 AND p.is_deleted = 0
      ORDER BY d.diary_date DESC
    ''');
    return rows.map(_diaryFromMap).toList();
  }

  /// 软删除的爪札，用于“最近删除”列表。
  static Future<List<Diary>> getDeletedDiaries() async {
    final db = await instance;
    final rows = await db.query(
      'diaries',
      where: 'is_deleted = 1',
      orderBy: 'updated_at DESC',
    );
    return rows.map(_diaryFromMap).toList();
  }

  /// Returns non-deleted diaries for a specific pet (always includes
  /// results even if the pet is deleted, so the detail screen works).
  static Future<List<Diary>> getPetDiaries(String petId) async {
    final db = await instance;
    final rows = await db.query(
      'diaries',
      where: 'pet_id = ? AND is_deleted = 0',
      whereArgs: [petId],
      orderBy: 'diary_date DESC',
    );
    return rows.map(_diaryFromMap).toList();
  }

  static Future<Diary?> getDiary(String id) async {
    final db = await instance;
    final rows = await db.query('diaries', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : _diaryFromMap(rows.first);
  }

  static Future<void> insertDiary(Diary diary) async {
    final db = await instance;
    await db.insert('diaries', _diaryToMap(diary));
    DataVersion.bump();
  }

  /// Inserts a diary together with its images and tags in a single
  /// transaction — all or nothing.
  static Future<void> insertDiaryWithRelations({
    required Diary diary,
    required List<String> imagePaths,
    required List<String> tagIds,
  }) async {
    final db = await instance;
    final now = DateTime.now();
    await db.transaction((txn) async {
      await txn.insert('diaries', _diaryToMap(diary));
      for (var i = 0; i < imagePaths.length; i++) {
        await txn.insert('diary_images', {
          'id': uuid(),
          'diary_id': diary.id,
          'local_path': imagePaths[i],
          'sort_order': i,
          'created_at': now.millisecondsSinceEpoch,
        });
      }
      await txn.delete(
        'diary_tags',
        where: 'diary_id = ?',
        whereArgs: [diary.id],
      );
      for (final tid in tagIds) {
        await txn.insert('diary_tags', {
          'diary_id': diary.id,
          'tag_id': tid,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    });
    DataVersion.bump();
  }

  static Future<void> updateDiary(Diary diary) async {
    final db = await instance;
    await db.update(
      'diaries',
      _diaryToMap(diary),
      where: 'id = ?',
      whereArgs: [diary.id],
    );
    DataVersion.bump();
  }

  /// Updates a diary and replaces its images and tags atomically.
  static Future<void> updateDiaryWithRelations({
    required Diary diary,
    required List<String> imagePaths,
    required List<String> tagIds,
  }) async {
    final db = await instance;
    final now = DateTime.now();
    await db.transaction((txn) async {
      await txn.update(
        'diaries',
        _diaryToMap(diary),
        where: 'id = ?',
        whereArgs: [diary.id],
      );
      await txn.delete(
        'diary_images',
        where: 'diary_id = ?',
        whereArgs: [diary.id],
      );
      for (var i = 0; i < imagePaths.length; i++) {
        await txn.insert('diary_images', {
          'id': uuid(),
          'diary_id': diary.id,
          'local_path': imagePaths[i],
          'sort_order': i,
          'created_at': now.millisecondsSinceEpoch,
        });
      }
      await txn.delete(
        'diary_tags',
        where: 'diary_id = ?',
        whereArgs: [diary.id],
      );
      for (final tid in tagIds) {
        await txn.insert('diary_tags', {
          'diary_id': diary.id,
          'tag_id': tid,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    });
    DataVersion.bump();
  }

  /// Soft-deletes a diary.  Does NOT delete physical image files —
  /// call [deleteDiaryImageFiles] first if you want to reclaim disk space.
  static Future<void> softDeleteDiary(String id) async {
    final db = await instance;
    // 个体删除：明确非级联删除（restorePet 不会复活它）
    await db.update(
      'diaries',
      {
        'is_deleted': 1,
        'deleted_with_pet': 0,
        'updated_at': nowMs(),
        'row_version': -1,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    DataVersion.bump();
  }

  /// 恢复一条软删爪札。
  ///
  /// 若它的宠物仍处于软删状态（即这条爪札是"随宠物删除"的），只把爪札
  /// 置为未删会让它**哪个列表都查不到**（getAllDiaries 要求宠物未删），
  /// 因此改为联动恢复整只宠物（与「提醒」分组的级联恢复语义一致）；
  /// 若该爪札此前是个体删除（不在级联范围内），用户点了它的"恢复"就一并恢复它。
  static Future<void> restoreDiary(String id) async {
    final db = await instance;
    final ts = nowMs();
    final rows = await db.query(
      'diaries',
      columns: ['pet_id'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final petId = rows.first['pet_id'] as String;
    final petRows = await db.query(
      'pets',
      columns: ['is_deleted'],
      where: 'id = ?',
      whereArgs: [petId],
      limit: 1,
    );
    final petDeleted =
        petRows.isNotEmpty && ((petRows.first['is_deleted'] as int?) ?? 0) == 1;

    if (petDeleted) {
      await restorePet(petId);
    }
    await db.update(
      'diaries',
      {
        'is_deleted': 0,
        'deleted_with_pet': 0,
        'updated_at': ts,
        'row_version': 1,
      },
      where: 'id = ? AND is_deleted = 1',
      whereArgs: [id],
    );
    DataVersion.bump();
  }

  /// 彻底删除爪札：只删除数据库记录（爪札/标签关联/媒体关联），
  /// 不删除媒体物理文件。是否彻底清理媒体由用户自行决定，避免误删。
  static Future<void> permanentlyDeleteDiary(String diaryId) async {
    final db = await instance;
    await db.transaction((txn) async {
      await txn.delete(
        'diary_tags',
        where: 'diary_id = ?',
        whereArgs: [diaryId],
      );
      await txn.delete(
        'diary_images',
        where: 'diary_id = ?',
        whereArgs: [diaryId],
      );
      await txn.delete('diaries', where: 'id = ?', whereArgs: [diaryId]);
    });
    DataVersion.bump();
  }

  /// Deletes all physical image files associated with a diary.
  /// Call this before [softDeleteDiary] if you want to free disk space.
  static Future<void> deleteDiaryImageFiles(String diaryId) async {
    final images = await getDiaryImages(diaryId);
    for (final img in images) {
      _deleteFileSafe(img.localPath);
    }
  }

  static Future<int> getDiaryCountForPet(String petId) async {
    final db = await instance;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as cnt FROM diaries WHERE pet_id = ? AND is_deleted = 0',
      [petId],
    );
    return (result.first['cnt'] as int?) ?? 0;
  }

  /// Returns a map of pet-id → diary-count in a single query.
  /// Avoids the N+1 pattern in [PetListScreen].
  static Future<Map<String, int>> getDiaryCountsForAllPets() async {
    final db = await instance;
    final rows = await db.rawQuery(
      'SELECT pet_id, COUNT(*) as cnt FROM diaries '
      'WHERE is_deleted = 0 GROUP BY pet_id',
    );
    final map = <String, int>{};
    for (final row in rows) {
      map[row['pet_id'] as String] = (row['cnt'] as int?) ?? 0;
    }
    return map;
  }

  /// SQLite 绑定变量有数量上限（老设备 999，Android 12+ 放宽到 32766）。
  /// 一次把上千个 id 塞进 `IN (...)` 会抛 "too many SQL variables"，
  /// 导致整页列表加载失败；统一按该粒度分片查询后合并（见 docs/代码审计待办.md P2-6）。
  static const int _sqlParamChunkSize = 500;

  /// 把 id 列表切成不超过 [_sqlParamChunkSize] 的分片。
  static Iterable<List<String>> _idChunks(List<String> ids) sync* {
    for (var i = 0; i < ids.length; i += _sqlParamChunkSize) {
      final end = i + _sqlParamChunkSize;
      yield ids.sublist(i, end > ids.length ? ids.length : end);
    }
  }

  /// Batch-loads the first image (sort_order = 0) for each diary id.
  static Future<Map<String, String?>> getDiaryFirstImages(
    List<String> diaryIds,
  ) async {
    if (diaryIds.isEmpty) return {};
    final db = await instance;
    final map = <String, String?>{};
    for (final chunk in _idChunks(diaryIds)) {
      final placeholders = chunk.map((_) => '?').join(',');
      final rows = await db.rawQuery(
        'SELECT diary_id, local_path FROM diary_images '
        'WHERE diary_id IN ($placeholders) AND sort_order = 0',
        chunk,
      );
      for (final row in rows) {
        map[row['diary_id'] as String] = row['local_path'] as String?;
      }
    }
    return map;
  }

  /// Batch-loads all media paths for multiple diary ids, keeping sort order.
  /// 朋友圈式列表需要展示全部照片/视频，而不再只取第一张。
  static Future<Map<String, List<String>>> getDiaryMediaBatch(
    List<String> diaryIds,
  ) async {
    if (diaryIds.isEmpty) return {};
    final db = await instance;
    final map = <String, List<String>>{};
    for (final chunk in _idChunks(diaryIds)) {
      final placeholders = chunk.map((_) => '?').join(',');
      final rows = await db.rawQuery(
        'SELECT diary_id, local_path FROM diary_images '
        'WHERE diary_id IN ($placeholders) ORDER BY diary_id, sort_order',
        chunk,
      );
      for (final row in rows) {
        final diaryId = row['diary_id'] as String;
        map.putIfAbsent(diaryId, () => []).add(row['local_path'] as String);
      }
    }
    return map;
  }

  /// Batch-loads tags for multiple diary ids (returns diary-id → tags).
  static Future<Map<String, List<Tag>>> getDiaryTagsBatch(
    List<String> diaryIds,
  ) async {
    if (diaryIds.isEmpty) return {};
    final db = await instance;
    final map = <String, List<Tag>>{};
    for (final chunk in _idChunks(diaryIds)) {
      final placeholders = chunk.map((_) => '?').join(',');
      final rows = await db.rawQuery(
        'SELECT dt.diary_id, t.* FROM diary_tags dt '
        'INNER JOIN tags t ON t.id = dt.tag_id '
        'WHERE dt.diary_id IN ($placeholders)',
        chunk,
      );
      for (final row in rows) {
        final diaryId = row['diary_id'] as String;
        map.putIfAbsent(diaryId, () => []).add(_tagFromMap(row));
      }
    }
    return map;
  }

  static Map<String, dynamic> _diaryToMap(Diary d) => {
    'id': d.id,
    'pet_id': d.petId,
    'title': d.title,
    'content': d.content,
    'mood': d.mood,
    'weather': d.weather,
    'weight': d.weight,
    'diary_date': d.diaryDate.millisecondsSinceEpoch,
    'created_at': d.createdAt.millisecondsSinceEpoch,
    'updated_at': d.updatedAt.millisecondsSinceEpoch,
    'row_version': d.rowVersion,
    'is_deleted': d.isDeleted ? 1 : 0,
  };

  static Diary _diaryFromMap(Map<String, dynamic> m) => Diary(
    id: m['id'] as String,
    petId: m['pet_id'] as String,
    title: m['title'] as String,
    content: m['content'] as String,
    mood: m['mood'] as String?,
    weather: m['weather'] as String?,
    weight: (m['weight'] as num?)?.toDouble(),
    diaryDate: DateTime.fromMillisecondsSinceEpoch(m['diary_date'] as int),
    createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(m['updated_at'] as int),
    rowVersion: m['row_version'] as int,
    isDeleted: (m['is_deleted'] as int) == 1,
  );

  // ========================================
  // DiaryImages
  // ========================================
  static Future<List<DiaryImage>> getDiaryImages(String diaryId) async {
    final db = await instance;
    final rows = await db.query(
      'diary_images',
      where: 'diary_id = ?',
      whereArgs: [diaryId],
      orderBy: 'sort_order',
    );
    return rows.map(_diaryImageFromMap).toList();
  }

  static Future<void> insertDiaryImage(DiaryImage img) async {
    final db = await instance;
    await db.insert('diary_images', _diaryImageToMap(img));
  }

  /// Deletes a diary image record and removes the physical file.
  static Future<void> deleteDiaryImage(String id) async {
    final db = await instance;
    final rows = await db.query(
      'diary_images',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (rows.isNotEmpty) {
      _deleteFileSafe(rows.first['local_path'] as String);
    }
    await db.delete('diary_images', where: 'id = ?', whereArgs: [id]);
  }

  static Future<void> deleteDiaryImagesForDiary(String diaryId) async {
    final images = await getDiaryImages(diaryId);
    final db = await instance;
    await db.delete(
      'diary_images',
      where: 'diary_id = ?',
      whereArgs: [diaryId],
    );
    for (final img in images) {
      _deleteFileSafe(img.localPath);
    }
  }

  static Map<String, dynamic> _diaryImageToMap(DiaryImage d) => {
    'id': d.id,
    'diary_id': d.diaryId,
    'local_path': d.localPath,
    'remote_url': d.remoteUrl,
    'sort_order': d.sortOrder,
    'created_at': d.createdAt.millisecondsSinceEpoch,
  };

  static DiaryImage _diaryImageFromMap(Map<String, dynamic> m) => DiaryImage(
    id: m['id'] as String,
    diaryId: m['diary_id'] as String,
    localPath: (m['local_path'] as String? ?? '').trim(),
    remoteUrl: m['remote_url'] as String?,
    sortOrder: m['sort_order'] as int,
    createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
  );

  // ========================================
  // Tags
  // ========================================
  static Future<List<Tag>> getAllTags() async {
    final db = await instance;
    final rows = await db.query('tags', orderBy: 'created_at DESC');
    return rows.map(_tagFromMap).toList();
  }

  static Future<Tag?> getTagByName(String name) async {
    final db = await instance;
    final rows = await db.query('tags', where: 'name = ?', whereArgs: [name]);
    return rows.isEmpty ? null : _tagFromMap(rows.first);
  }

  static Future<String> insertTag(Tag tag) async {
    final db = await instance;
    await db.insert('tags', _tagToMap(tag));
    DataVersion.bump();
    return tag.id;
  }

  static Future<void> updateTag(Tag tag) async {
    final db = await instance;
    await db.update(
      'tags',
      _tagToMap(tag),
      where: 'id = ?',
      whereArgs: [tag.id],
    );
    DataVersion.bump();
  }

  static Future<void> deleteTag(String id) async {
    final db = await instance;
    await db.delete('tags', where: 'id = ?', whereArgs: [id]);
    // Also clean up diary-tag relationships
    await db.delete('diary_tags', where: 'tag_id = ?', whereArgs: [id]);
    DataVersion.bump();
  }

  static Map<String, dynamic> _tagToMap(Tag t) => {
    'id': t.id,
    'name': t.name,
    'color': t.color,
    'created_at': t.createdAt.millisecondsSinceEpoch,
  };

  static Tag _tagFromMap(Map<String, dynamic> m) => Tag(
    id: m['id'] as String,
    name: m['name'] as String,
    color: m['color'] as int?,
    createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
  );

  // ========================================
  // DiaryTags
  // ========================================
  static Future<List<Tag>> getDiaryTags(String diaryId) async {
    final db = await instance;
    final rows = await db.rawQuery(
      'SELECT t.* FROM tags t '
      'INNER JOIN diary_tags dt ON t.id = dt.tag_id '
      'WHERE dt.diary_id = ?',
      [diaryId],
    );
    return rows.map(_tagFromMap).toList();
  }

  /// Atomically replaces all tags for a diary inside a transaction.
  static Future<void> setDiaryTags(String diaryId, List<String> tagIds) async {
    final db = await instance;
    await db.transaction((txn) async {
      await txn.delete(
        'diary_tags',
        where: 'diary_id = ?',
        whereArgs: [diaryId],
      );
      for (final tid in tagIds) {
        await txn.insert('diary_tags', {
          'diary_id': diaryId,
          'tag_id': tid,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    });
    DataVersion.bump();
  }

  // ========================================
  // Reminders
  // ========================================
  static Future<List<Reminder>> getAllReminders() async {
    final db = await instance;
    final rows = await db.rawQuery('''
      SELECT r.* FROM reminders r
      INNER JOIN pets p ON r.pet_id = p.id
      WHERE r.is_deleted = 0 AND p.is_deleted = 0
      ORDER BY r.first_due_date ASC
    ''');
    return rows.map(_reminderFromMap).toList();
  }

  /// 软删除的提醒，用于“最近删除”列表。
  static Future<List<Reminder>> getDeletedReminders() async {
    final db = await instance;
    final rows = await db.query(
      'reminders',
      where: 'is_deleted = 1',
      orderBy: 'updated_at DESC',
    );
    return rows.map(_reminderFromMap).toList();
  }

  static Future<List<Reminder>> getPetReminders(String petId) async {
    final db = await instance;
    final rows = await db.query(
      'reminders',
      where: 'pet_id = ? AND is_deleted = 0',
      whereArgs: [petId],
      orderBy: 'first_due_date ASC',
    );
    return rows.map(_reminderFromMap).toList();
  }

  static Future<void> insertReminder(Reminder r) async {
    final db = await instance;
    await db.insert('reminders', _reminderToMap(r));
    DataVersion.bump();
  }

  /// 更新提醒实体。
  ///
  /// **不写回删除状态（is_deleted）**：软删/恢复只能走 [softDeleteReminder] /
  /// [restoreReminder]。否则上层拿着"保存前的旧对象"保存时，会把实体重新
  /// 标记成已删除，产生"待办与最近删除都看不到、通知却照弹"的幽灵提醒
  /// （见 docs/代码审计待办.md P0-1，回归用例 audit_regression_test.dart）。
  static Future<void> updateReminder(Reminder r) async {
    final db = await instance;
    final values = _reminderToMap(r)..remove('is_deleted');
    await db.update('reminders', values, where: 'id = ?', whereArgs: [r.id]);
    DataVersion.bump();
  }

  /// 事务化保存「提醒实体 + 待办实例」（新建 / 编辑二合一）。
  ///
  /// 编辑器原先分 3 次独立写库（更新实体 → 硬删旧待办 → 插入新待办），中途失败会留下
  /// "待办已被物理删除、且最近删除里也找不回"的中间态（见 docs/代码审计待办.md P1-8）。
  /// 序号在事务内按"删除旧待办之后的 MAX + 1"计算，与旧行为一致。
  ///
  /// - [isNew] 为 true 时插入实体；否则更新实体（不写回 is_deleted）并硬删其未完成实例；
  /// - [completedAt] 非空时把新实例直接标记为已完成（保存"已过期"时间的情形）；
  /// - [nextDueDate] / [nextInstanceId] 非空时再补一条待办实例（过期重复提醒需要）。
  ///
  /// 返回实际分配的序号，供调用方拼通知标题（标题要显示"第X次"）。
  static Future<({int occurrenceNo, int? nextOccurrenceNo})>
  saveReminderWithInstance({
    required Reminder reminder,
    required bool isNew,
    required String instanceId,
    required DateTime instanceDueDate,
    DateTime? completedAt,
    DateTime? nextDueDate,
    String? nextInstanceId,

    /// 显式指定这条实例的「第几次」（用户在编辑器里选的值）。
    /// 为空时按 MAX + 1 自动编号（默认行为）。
    int? occurrenceNo,
  }) async {
    final db = await instance;
    final ts = nowMs();
    final requestedNo = occurrenceNo;
    late int resolvedNo;
    int? nextNo;
    await db.transaction((txn) async {
      if (isNew) {
        await txn.insert('reminders', _reminderToMap(reminder));
      } else {
        final values = _reminderToMap(reminder)..remove('is_deleted');
        await txn.update(
          'reminders',
          values,
          where: 'id = ?',
          whereArgs: [reminder.id],
        );
        await txn.delete(
          'reminder_instances',
          where: 'reminder_id = ? AND completed = 0',
          whereArgs: [reminder.id],
        );
      }

      resolvedNo = requestedNo ?? await _nextOccurrenceNo(txn, reminder.id);
      await txn.insert('reminder_instances', {
        'id': instanceId,
        'reminder_id': reminder.id,
        'due_date': instanceDueDate.millisecondsSinceEpoch,
        'completed': completedAt != null ? 1 : 0,
        'completed_at': completedAt?.millisecondsSinceEpoch,
        'occurrence_no': resolvedNo,
        'created_at': ts,
        'is_deleted': 0,
        'deleted_at': null,
        'deleted_with_pet': 0,
      });

      if (completedAt != null) {
        // 与 completeInstance 一致：直接进已完成并记录上次完成时间
        await txn.update(
          'reminders',
          {'last_done_date': ts, 'updated_at': ts},
          where: 'id = ?',
          whereArgs: [reminder.id],
        );
      }

      if (nextDueDate != null && nextInstanceId != null) {
        nextNo = resolvedNo + 1;
        await txn.insert('reminder_instances', {
          'id': nextInstanceId,
          'reminder_id': reminder.id,
          'due_date': nextDueDate.millisecondsSinceEpoch,
          'completed': 0,
          'completed_at': null,
          'occurrence_no': nextNo,
          'created_at': ts,
          'is_deleted': 0,
          'deleted_at': null,
          'deleted_with_pet': 0,
        });
      }
    });
    DataVersion.bump();
    return (occurrenceNo: resolvedNo, nextOccurrenceNo: nextNo);
  }

  /// 事务化保存「用药疗程实体 + 全部服药实例」。
  ///
  /// - [doses] 由调用方用 expandDoseTimes 算好（纯函数，便于单测）；
  /// - 已完成 / 软删的实例**一律保留**（历史事实不可改写）；
  /// - 未完成（completed = 0）的旧实例**硬删后按 [doses] 重建**，因此
  ///   [reuseInstanceIds] 用于复用「计划时刻未变」的实例 ID —— 用药通知按实例 ID 排，
  ///   换 ID 会导致旧通知取消不掉、新通知也覆盖不上（静默漏提醒）。键为计划时刻。
  ///
  /// 已知取舍：编辑时**已完成的实例不会被删**，所以给某天新增一个更早的服药时刻时，
  /// 那天可能出现「已完成 09:00 + 未完成 09:00」两条（新计划新加的这一次确实还没喂过）。
  /// 这是有意保留的行为：宁可多出一次待喂，也不能改写用户已经记录过的完成历史。
  static Future<void> saveMedicationCourse({
    required Reminder reminder,
    required bool isNew,
    required List<({String id, DateTime dueDate, int occurrenceNo})> doses,
    Map<DateTime, String> reuseInstanceIds = const {},
  }) async {
    final db = await instance;
    final ts = nowMs();
    await db.transaction((txn) async {
      if (isNew) {
        await txn.insert('reminders', _reminderToMap(reminder));
      } else {
        final values = _reminderToMap(reminder)..remove('is_deleted');
        await txn.update(
          'reminders',
          values,
          where: 'id = ?',
          whereArgs: [reminder.id],
        );
      }
      // 无论新建还是编辑：先把这条提醒的**未完成**实例清干净（同一事务内）。
      // 新建时天然为空；编辑时这一步保证「改短疗程 / 改时间点」不会留下旧计划的行。
      await txn.delete(
        'reminder_instances',
        where: 'reminder_id = ? AND completed = 0',
        whereArgs: [reminder.id],
      );
      // 防御：复用 ID 必须真的可以复用。已完成 / 软删实例在编辑时**不会被删除**，
      // 若把它们的 ID 复用到新实例上会撞 UNIQUE（或更糟：张冠李戴地改掉历史记录）。
      // 这里查出该提醒当前仍存在的实例 ID，把这些复用项直接丢掉（改用新生成的 ID）。
      var reusable = reuseInstanceIds;
      if (reusable.isNotEmpty) {
        final existing = await txn.query(
          'reminder_instances',
          columns: ['id'],
          where: 'reminder_id = ?',
          whereArgs: [reminder.id],
        );
        final taken = existing.map((r) => r['id'] as String).toSet();
        reusable = {
          for (final e in reusable.entries)
            if (!taken.contains(e.value)) e.key: e.value,
        };
      }
      // 已经**有记录**的计划时刻不再补待办：编辑疗程时，当天可能已经喂过 09:00，
      // 若再插一条 09:00 的待办，卡片就会从「今日 2/2」变成「2/4」（真机上被指出过）。
      final keptRows = await txn.query(
        'reminder_instances',
        columns: ['due_date'],
        where: 'reminder_id = ?',
        whereArgs: [reminder.id],
      );
      final keptMoments = keptRows.map((r) => r['due_date'] as int).toSet();
      for (final dose in doses) {
        if (keptMoments.contains(dose.dueDate.millisecondsSinceEpoch)) continue;
        await txn.insert('reminder_instances', {
          'id': reusable[dose.dueDate] ?? dose.id,
          'reminder_id': reminder.id,
          'due_date': dose.dueDate.millisecondsSinceEpoch,
          'completed': 0,
          'completed_at': null,
          'occurrence_no': dose.occurrenceNo,
          'created_at': ts,
          'is_deleted': 0,
          'deleted_at': null,
          'deleted_with_pet': 0,
          'deleted_with_reminder': 0,
        });
      }
    });
    DataVersion.bump();
  }

  /// 提醒的下一个实例序号（MAX + 1）；事务内调用时传 txn。
  static Future<int> _nextOccurrenceNo(
    DatabaseExecutor ex,
    String reminderId,
  ) async {
    final rows = await ex.rawQuery(
      'SELECT MAX(occurrence_no) AS max_no FROM reminder_instances WHERE reminder_id = ?',
      [reminderId],
    );
    return ((rows.first['max_no'] as int?) ?? 0) + 1;
  }

  static Future<void> softDeleteReminder(String id) async {
    final db = await instance;
    final ts = nowMs();
    // 个体删除：软删实体 + 当前待办实例（completed=0，打上 deleted_with_reminder
    // 标记）；已完成历史保留，继续显示在“已完成”分区（getCompletedInstances
    // 允许个体软删实体的记录）。恢复提醒时只找回**随本次删除一起删掉**的实例，
    // 用户在最近删除里单独删掉的那条完成记录不复活（docs/代码审计待办.md P2-2）。
    await db.transaction((txn) async {
      await txn.update(
        'reminders',
        {
          'is_deleted': 1,
          'deleted_with_pet': 0,
          'updated_at': ts,
          'row_version': -1,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      await txn.update(
        'reminder_instances',
        {
          'is_deleted': 1,
          'deleted_at': ts,
          'deleted_with_pet': 0,
          'deleted_with_reminder': 1,
        },
        where: 'reminder_id = ? AND completed = 0 AND is_deleted = 0',
        whereArgs: [id],
      );
    });
    DataVersion.bump();
  }

  /// 恢复提醒实体 + **随该提醒一起被删除**的实例。
  ///
  /// 还原两类实例（用户的显式"恢复"应让整条提醒回到可用状态）：
  /// - 随提醒删除的实例（softDeleteReminder 打的 `deleted_with_reminder` 标记）；
  /// - 随宠物级联删除的实例（`deleted_with_pet` 标记，见 P2-4 与既有用例）。
  ///
  /// 但**不**还原用户在最近删除里单独删除的完成记录：它会被静默复活并从
  /// 最近删除里消失（docs/代码审计待办.md P2-2）。两个删除入口都会把这些标记
  /// 显式写 0，所以上面两类条件正好等于"不是用户个体删除"。
  /// 恢复时两个标记都清零，避免陈旧标记影响后续语义。
  static Future<void> restoreReminder(String id) async {
    final db = await instance;
    await db.transaction((txn) async {
      await txn.update(
        'reminders',
        // 同时清掉级联标记，避免留下父级仍删、子级已活的分裂态（P2-4）
        {
          'is_deleted': 0,
          'deleted_with_pet': 0,
          'updated_at': nowMs(),
          'row_version': 1,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      await txn.update(
        'reminder_instances',
        {
          'is_deleted': 0,
          'deleted_at': null,
          'deleted_with_pet': 0,
          'deleted_with_reminder': 0,
        },
        where:
            'reminder_id = ? AND is_deleted = 1 AND (deleted_with_reminder = 1 OR deleted_with_pet = 1)',
        whereArgs: [id],
      );
    });
    DataVersion.bump();
  }

  /// 彻底删除提醒及其实例。
  static Future<void> permanentlyDeleteReminder(String id) async {
    final db = await instance;
    await db.transaction((txn) async {
      await txn.delete(
        'reminder_instances',
        where: 'reminder_id = ?',
        whereArgs: [id],
      );
      await txn.delete('reminders', where: 'id = ?', whereArgs: [id]);
    });
    DataVersion.bump();
  }

  /// 服药时刻编码：逗号分隔的当日分钟数（升序），空列表写 null。
  static String? encodeDoseTimes(List<int> times) {
    if (times.isEmpty) return null;
    final sorted = [...times]..sort();
    return sorted.join(',');
  }

  /// 服药时刻解码：容错（丢弃非法值、去重、升序），解析失败返回空列表，绝不抛异常。
  static List<int> decodeDoseTimes(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const [];
    final out = <int>{};
    for (final part in raw.split(',')) {
      final v = int.tryParse(part.trim());
      if (v != null && v >= 0 && v < 24 * 60) out.add(v);
    }
    final list = out.toList()..sort();
    return list;
  }

  static Map<String, dynamic> _reminderToMap(Reminder r) => {
    'id': r.id,
    'pet_id': r.petId,
    'title': r.title,
    'type': r.type,
    'description': r.description,
    'first_due_date': r.firstDueDate.millisecondsSinceEpoch,
    'repeat_unit': r.repeatUnit,
    'repeat_interval': r.repeatInterval,
    'is_repeating': r.isRepeating ? 1 : 0,
    'notification_time': r.notificationTime,
    'sound_enabled': r.soundEnabled ? 1 : 0,
    'vibrate_enabled': r.vibrateEnabled ? 1 : 0,
    'repeat_end_date': r.repeatEndDate?.millisecondsSinceEpoch,
    'last_done_date': r.lastDoneDate?.millisecondsSinceEpoch,
    'course_days': r.courseDays,
    'dose_times': encodeDoseTimes(r.doseTimes),
    'created_at': r.createdAt.millisecondsSinceEpoch,
    'updated_at': r.updatedAt.millisecondsSinceEpoch,
    'row_version': r.rowVersion,
    'is_deleted': r.isDeleted ? 1 : 0,
  };

  static Reminder _reminderFromMap(Map<String, dynamic> m) => Reminder(
    id: m['id'] as String,
    petId: m['pet_id'] as String,
    title: m['title'] as String,
    type: m['type'] as String,
    description: m['description'] as String?,
    firstDueDate: DateTime.fromMillisecondsSinceEpoch(
      m['first_due_date'] as int,
    ),
    repeatUnit: m['repeat_unit'] as String,
    repeatInterval: m['repeat_interval'] as int,
    isRepeating: ((m['is_repeating'] as int?) ?? 0) == 1,
    notificationTime: m['notification_time'] as String?,
    soundEnabled: ((m['sound_enabled'] as int?) ?? 1) == 1,
    vibrateEnabled: ((m['vibrate_enabled'] as int?) ?? 1) == 1,
    repeatEndDate: m['repeat_end_date'] != null
        ? DateTime.fromMillisecondsSinceEpoch(m['repeat_end_date'] as int)
        : null,
    lastDoneDate: _toDateTime(m['last_done_date']),
    courseDays: m['course_days'] as int?,
    doseTimes: decodeDoseTimes(m['dose_times'] as String?),
    createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(m['updated_at'] as int),
    rowVersion: m['row_version'] as int,
    isDeleted: (m['is_deleted'] as int) == 1,
  );

  // ========================================
  // ReminderInstances
  // ========================================

  /// Returns non-completed instances for non-deleted reminders only.
  static Future<List<ReminderInstance>> getPendingInstances() async {
    final db = await instance;
    final rows = await db.rawQuery('''
      SELECT ri.* FROM reminder_instances ri
      INNER JOIN reminders r ON ri.reminder_id = r.id
      INNER JOIN pets p ON r.pet_id = p.id
      WHERE ri.completed = 0
        AND ri.is_deleted = 0
        AND r.is_deleted = 0
        AND p.is_deleted = 0
      ORDER BY ri.due_date ASC
    ''');
    return rows.map(_instanceFromMap).toList();
  }

  /// 已完成实例，用于“已完成”列表（按完成时间倒序）。
  /// 允许个体软删提醒（deleted_with_pet=0）的未删历史继续显示；
  /// 宠物级联删除（deleted_with_pet=1）仍整体隐藏。
  /// 某只宠物**所有提醒的全部实例**（待办 + 已完成），按到期时间倒序。
  ///
  /// 用于宠物护理记录页：一次取回后在内存里按项目名合并分组
  /// （命中 idx_reminders_pet_id / idx_ri_reminder_id）。已软删的提醒与实例都不返回。
  static Future<List<ReminderInstance>> getInstancesForPet(String petId) async {
    final db = await instance;
    final rows = await db.rawQuery(
      '''
      SELECT ri.* FROM reminder_instances ri
      INNER JOIN reminders r ON ri.reminder_id = r.id
      WHERE r.pet_id = ?
        AND r.is_deleted = 0
        AND ri.is_deleted = 0
      ORDER BY ri.due_date DESC
    ''',
      [petId],
    );
    return rows.map(_instanceFromMap).toList();
  }

  /// 单条提醒的**全部实例**（待办 + 已完成），按「第几次」倒序。
  ///
  /// 用于「提醒历史」与宠物护理记录的时间线；已软删的实例不返回
  /// （恢复仍走『最近删除』）。命中 idx_ri_reminder_id。
  static Future<List<ReminderInstance>> getInstancesForReminder(
    String reminderId,
  ) async {
    final db = await instance;
    final rows = await db.query(
      'reminder_instances',
      where: 'reminder_id = ? AND is_deleted = 0',
      whereArgs: [reminderId],
      orderBy: 'occurrence_no DESC, due_date DESC',
    );
    return rows.map(_instanceFromMap).toList();
  }

  static Future<List<ReminderInstance>> getCompletedInstances() async {
    final db = await instance;
    final rows = await db.rawQuery('''
      SELECT ri.* FROM reminder_instances ri
      INNER JOIN reminders r ON ri.reminder_id = r.id
      INNER JOIN pets p ON r.pet_id = p.id
      WHERE ri.completed = 1
        AND ri.is_deleted = 0
        AND (r.is_deleted = 0 OR r.deleted_with_pet = 0)
        AND p.is_deleted = 0
      ORDER BY ri.completed_at DESC
    ''');
    return rows.map(_instanceFromMap).toList();
  }

  /// 下一个提醒实例序号：当前最大 occurrence_no + 1。
  static Future<int> getNextOccurrenceNo(String reminderId) async {
    final db = await instance;
    return _nextOccurrenceNo(db, reminderId);
  }

  /// 软删除一条已完成记录（进“最近删除”），并在提醒已无任何未删实例时
  /// 联动软删除提醒实体，避免出现“幽灵提醒”（两个分区都看不到但占着数据库）。
  static Future<void> deleteCompletedInstance(String id) async {
    final db = await instance;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'reminder_instances',
        where: 'id = ? AND completed = 1',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty) return;
      final reminderId = rows.first['reminder_id'] as String;
      // deleted_with_reminder 必须为 0：这条是**用户个体删除**的完成记录，
      // 恢复提醒实体时不得把它一起复活（docs/代码审计待办.md P2-2）。
      await txn.update(
        'reminder_instances',
        {
          'is_deleted': 1,
          'deleted_at': nowMs(),
          'deleted_with_pet': 0,
          'deleted_with_reminder': 0,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      if (!await _hasActiveInstances(txn, reminderId)) {
        await txn.update(
          'reminders',
          {
            'is_deleted': 1,
            'deleted_with_pet': 0,
            'updated_at': nowMs(),
            'row_version': -1,
          },
          where: 'id = ?',
          whereArgs: [reminderId],
        );
      }
    });
    DataVersion.bump();
  }

  /// 提醒是否仍存在未删实例（待办或完成记录）。
  static Future<bool> _hasActiveInstances(
    DatabaseExecutor txn,
    String reminderId,
  ) async {
    final rows = await txn.rawQuery(
      'SELECT COUNT(*) AS cnt FROM reminder_instances WHERE reminder_id = ? AND is_deleted = 0',
      [reminderId],
    );
    return ((rows.first['cnt'] as int?) ?? 0) > 0;
  }

  /// 软删除的待办实例（用于“最近删除”提醒实体条目显示“当前次数”，
  /// 即删除时那条待办的 occurrence_no）。含个体删除与宠物级联删除。
  static Future<List<ReminderInstance>> getDeletedPendingInstances() async {
    final db = await instance;
    final rows = await db.rawQuery('''
      SELECT ri.* FROM reminder_instances ri
      INNER JOIN reminders r ON ri.reminder_id = r.id
      WHERE ri.is_deleted = 1
        AND ri.completed = 0
      ORDER BY ri.deleted_at DESC
    ''');
    return rows.map(_instanceFromMap).toList();
  }

  /// 软删除的已完成记录（用于“最近删除-提醒”分组，与软删提醒实体混排）。
  /// 含个体删除与宠物级联删除（级联条目恢复时联动恢复宠物，见最近删除页）。
  static Future<List<ReminderInstance>> getDeletedCompletedInstances() async {
    final db = await instance;
    final rows = await db.rawQuery('''
      SELECT ri.* FROM reminder_instances ri
      INNER JOIN reminders r ON ri.reminder_id = r.id
      WHERE ri.is_deleted = 1
        AND ri.completed = 1
      ORDER BY ri.deleted_at DESC
    ''');
    return rows.map(_instanceFromMap).toList();
  }

  /// 恢复一条软删除的已完成记录（保留原 occurrence_no；MAX 计数含软删
  /// 记录，序号不会重复）。若对应提醒实体已（因个体删除）软删，则一并
  /// 恢复实体，保证恢复后列表可见、状态一致。
  static Future<void> restoreCompletedInstance(String id) async {
    final db = await instance;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'reminder_instances',
        where: 'id = ? AND is_deleted = 1',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty) return;
      final reminderId = rows.first['reminder_id'] as String;
      await txn.update(
        'reminder_instances',
        {
          'is_deleted': 0,
          'deleted_at': null,
          'deleted_with_pet': 0,
          'deleted_with_reminder': 0,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      // 若实体已软删则一并恢复（个体删除的实体其 deleted_with_pet=0）。
      await txn.update(
        'reminders',
        {'is_deleted': 0, 'updated_at': nowMs(), 'row_version': 1},
        where: 'id = ? AND is_deleted = 1 AND deleted_with_pet = 0',
        whereArgs: [reminderId],
      );
    });
    DataVersion.bump();
  }

  /// 彻底删除一条已完成记录：只物理删除该条实例，不连带同提醒下其他
  /// 最近删除记录。
  ///
  /// 但若删完后该提醒（个体删除、非级联）已经**一条实例都不剩**，它会退化成
  /// "最近删除里看不到（列表只展示有软删待办实例的实体）、也恢复不了"的幽灵实体，
  /// 因此同事务把这种实体一并清掉（见 docs/代码审计待办.md P2-3）。
  /// 级联删除（deleted_with_pet=1）的实体不动：它归"恢复宠物"管。
  static Future<void> permanentlyDeleteCompletedInstance(String id) async {
    final db = await instance;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'reminder_instances',
        columns: ['reminder_id'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty) return;
      final reminderId = rows.first['reminder_id'] as String;
      await txn.delete('reminder_instances', where: 'id = ?', whereArgs: [id]);

      final left = await txn.rawQuery(
        'SELECT COUNT(*) AS cnt FROM reminder_instances WHERE reminder_id = ?',
        [reminderId],
      );
      final remaining = (left.first['cnt'] as int?) ?? 0;
      if (remaining == 0) {
        await txn.delete(
          'reminders',
          where: 'id = ? AND is_deleted = 1 AND deleted_with_pet = 0',
          whereArgs: [reminderId],
        );
      }
    });
    DataVersion.bump();
  }

  /// 待办区提醒卡片数（= 提醒 Tab 待办分区可见的提醒数）。
  static Future<int> countPendingReminderCards() async {
    final db = await instance;
    final rows = await db.rawQuery('''
      SELECT COUNT(DISTINCT ri.reminder_id) AS cnt FROM reminder_instances ri
      INNER JOIN reminders r ON ri.reminder_id = r.id
      INNER JOIN pets p ON r.pet_id = p.id
      WHERE ri.completed = 0
        AND ri.is_deleted = 0
        AND r.is_deleted = 0
        AND p.is_deleted = 0
    ''');
    return (rows.first['cnt'] as int?) ?? 0;
  }

  /// 用药待办实例 + 它所属的提醒（滚动窗口用：一条 SQL 取回，避免 N+1）。
  static Future<List<MedicationDose>> getPendingDoseInstances() async {
    final db = await instance;
    final rows = await db.rawQuery('''
      SELECT ri.id AS ri_id, ri.reminder_id AS ri_reminder_id, ri.due_date AS ri_due_date,
             ri.completed AS ri_completed, ri.completed_at AS ri_completed_at,
             ri.occurrence_no AS ri_occurrence_no, ri.created_at AS ri_created_at,
             ri.is_deleted AS ri_is_deleted, ri.deleted_at AS ri_deleted_at,
             r.*
      FROM reminder_instances ri
      INNER JOIN reminders r ON ri.reminder_id = r.id
      INNER JOIN pets p ON r.pet_id = p.id
      WHERE ri.completed = 0
        AND ri.is_deleted = 0
        AND r.is_deleted = 0
        AND p.is_deleted = 0
        AND r.course_days IS NOT NULL
        AND r.dose_times IS NOT NULL
      ORDER BY ri.due_date ASC
    ''');
    final out = <MedicationDose>[];
    for (final row in rows) {
      out.add((
        instance: _instanceFromMap({
          'id': row['ri_id'],
          'reminder_id': row['ri_reminder_id'],
          'due_date': row['ri_due_date'],
          'completed': row['ri_completed'],
          'completed_at': row['ri_completed_at'],
          'occurrence_no': row['ri_occurrence_no'],
          'created_at': row['ri_created_at'],
          'is_deleted': row['ri_is_deleted'],
          'deleted_at': row['ri_deleted_at'],
        }),
        reminder: _reminderFromMap(row),
      ));
    }
    return out;
  }

  /// 某条提醒的**全部**实例（含软删），按计划时刻升序；用药的时间线视图用。
  static Future<List<ReminderInstance>> getInstanceHistoryForReminder(
    String reminderId,
  ) async {
    final db = await instance;
    final rows = await db.query(
      'reminder_instances',
      where: 'reminder_id = ?',
      whereArgs: [reminderId],
      orderBy: 'due_date ASC, occurrence_no ASC',
    );
    return rows.map(_instanceFromMap).toList();
  }

  /// 测试用：按提醒分组待办实例（键为 reminderId）。
  @visibleForTesting
  static Map<String, List<ReminderInstance>> debugGroupPendingByReminder(
    List<ReminderInstance> instances,
  ) {
    final grouped = <String, List<ReminderInstance>>{};
    for (final i in instances) {
      grouped.putIfAbsent(i.reminderId, () => []).add(i);
    }
    return grouped;
  }

  static Future<void> insertReminderInstance(ReminderInstance ri) async {
    final db = await instance;
    await db.insert('reminder_instances', _instanceToMap(ri));
    DataVersion.bump();
  }

  /// 标记实例完成。
  ///
  /// [completedAt] 用于**逾期项的校对**：用户在完成确认弹窗里选定完成日期后，
  /// 记录真实的完成时间；不传则用当前时间。
  static Future<void> completeInstance(
    String id, {
    DateTime? completedAt,
  }) async {
    final db = await instance;
    final doneMs = completedAt?.millisecondsSinceEpoch ?? nowMs();
    await db.transaction((txn) async {
      final rows = await txn.query(
        'reminder_instances',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty) return;
      final reminderId = rows.first['reminder_id'] as String;
      await txn.update(
        'reminder_instances',
        {'completed': 1, 'completed_at': doneMs},
        where: 'id = ?',
        whereArgs: [id],
      );
      // 记录上次实际完成时间（与实例完成时间一致：用户可在完成弹窗里核对）
      await txn.update(
        'reminders',
        {'last_done_date': doneMs, 'updated_at': nowMs()},
        where: 'id = ?',
        whereArgs: [reminderId],
      );
    });
    DataVersion.bump();
  }

  static Map<String, dynamic> _instanceToMap(ReminderInstance r) => {
    'id': r.id,
    'reminder_id': r.reminderId,
    'due_date': r.dueDate.millisecondsSinceEpoch,
    'completed': r.completed ? 1 : 0,
    'completed_at': r.completedAt?.millisecondsSinceEpoch,
    'occurrence_no': r.occurrenceNo,
    'created_at': r.createdAt.millisecondsSinceEpoch,
    'is_deleted': r.isDeleted ? 1 : 0,
    'deleted_at': r.deletedAt?.millisecondsSinceEpoch,
  };

  static ReminderInstance _instanceFromMap(Map<String, dynamic> m) =>
      ReminderInstance(
        id: m['id'] as String,
        reminderId: m['reminder_id'] as String,
        dueDate: DateTime.fromMillisecondsSinceEpoch(m['due_date'] as int),
        completed: (m['completed'] as int) == 1,
        completedAt: _toDateTime(m['completed_at']),
        occurrenceNo: (m['occurrence_no'] as int?) ?? 1,
        createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
        isDeleted: ((m['is_deleted'] as int?) ?? 0) == 1,
        deletedAt: _toDateTime(m['deleted_at']),
      );

  // ========================================
  // Virtual Pets  (V4)
  // ========================================

  /// Returns the virtual pet linked to a real pet, or null.
  static Future<VirtualPet?> getVirtualPetByRealPetId(String realPetId) async {
    final db = await instance;
    final rows = await db.query(
      'virtual_pets',
      where: 'real_pet_id = ?',
      whereArgs: [realPetId],
    );
    return rows.isEmpty ? null : _virtualPetFromMap(rows.first);
  }

  static Future<void> insertVirtualPet(VirtualPet vp) async {
    final db = await instance;
    await db.insert('virtual_pets', _virtualPetToMap(vp));
  }

  static Future<void> updateVirtualPet(VirtualPet vp) async {
    final db = await instance;
    await db.update(
      'virtual_pets',
      _virtualPetToMap(vp),
      where: 'id = ?',
      whereArgs: [vp.id],
    );
  }

  /// Deletes the virtual pet (and cascade: reward_log, checkin_history).
  static Future<void> deleteVirtualPet(String id) async {
    final db = await instance;
    await db.transaction((txn) async {
      await txn.delete(
        'reward_log',
        where: 'virtual_pet_id = ?',
        whereArgs: [id],
      );
      await txn.delete(
        'checkin_history',
        where: 'virtual_pet_id = ?',
        whereArgs: [id],
      );
      await txn.delete('virtual_pets', where: 'id = ?', whereArgs: [id]);
    });
  }

  // ========================================
  // Game Currencies  (V4)
  // ========================================

  /// Returns the single currencies row (creates it if missing).
  static Future<GameCurrencies> getOrCreateCurrencies() async {
    final db = await instance;
    final rows = await db.query('game_currencies', limit: 1);
    if (rows.isNotEmpty) return _currenciesFromMap(rows.first);
    final now = nowMs();
    // 固定主键 'main'：并发首次调用时主键冲突被 ignore 吸收，只产生一行
    // （旧实现用随机 uuid，并发会插出多行）。
    const id = 'main';
    await db.insert('game_currencies', {
      'id': id,
      'paw_coins': 0,
      'memory_fragments': 0,
      'consecutive_checkin_days': 0,
      'total_diaries_written': 0,
      'total_reminders_completed': 0,
      'total_adventures_completed': 0,
      'updated_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    // 重新查询（无论 insert 成功还是冲突，都能拿到结果）
    final retry = await db.query('game_currencies', limit: 1);
    if (retry.isNotEmpty) return _currenciesFromMap(retry.first);
    return GameCurrencies(
      id: id,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(now),
    );
  }

  static Future<void> updateCurrencies(GameCurrencies c) async {
    final db = await instance;
    await db.update(
      'game_currencies',
      _currenciesToMap(c),
      where: 'id = ?',
      whereArgs: [c.id],
    );
  }

  // ========================================
  // Reward Log  (V4)
  // ========================================

  static Future<void> insertRewardLog(RewardLog rl) async {
    final db = await instance;
    await db.insert('reward_log', _rewardLogToMap(rl));
  }

  /// Returns recent reward logs for a virtual pet (newest first).
  static Future<List<RewardLog>> getRewardLogs(
    String virtualPetId, {
    int limit = 50,
  }) async {
    final db = await instance;
    final rows = await db.query(
      'reward_log',
      where: 'virtual_pet_id = ?',
      whereArgs: [virtualPetId],
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return rows.map(_rewardLogFromMap).toList();
  }

  // ========================================
  // Check-in History  (V4)
  // ========================================

  static Future<void> insertCheckin(CheckinHistory ch) async {
    final db = await instance;
    await db.insert('checkin_history', _checkinToMap(ch));
  }

  /// Returns check-in dates for a virtual pet (newest first, max 31).
  static Future<List<CheckinHistory>> getRecentCheckins(
    String virtualPetId, {
    int days = 31,
  }) async {
    final db = await instance;
    final cutoff = nowMs() - days * 86400000;
    final rows = await db.rawQuery(
      'SELECT * FROM checkin_history '
      'WHERE virtual_pet_id = ? AND checkin_date >= ? '
      'ORDER BY checkin_date DESC',
      [virtualPetId, cutoff],
    );
    return rows.map(_checkinFromMap).toList();
  }

  // ========================================
  // Equipment  (V4)
  // ========================================

  static Future<List<Equipment>> getAllEquipment() async {
    final db = await instance;
    final rows = await db.query('equipment', orderBy: 'acquired_at DESC');
    return rows.map(_equipmentFromMap).toList();
  }

  /// Returns equipment currently equipped in each slot.
  static Future<List<Equipment>> getEquipped() async {
    final db = await instance;
    final rows = await db.query('equipment', where: 'equipped = 1');
    return rows.map(_equipmentFromMap).toList();
  }

  static Future<void> insertEquipment(Equipment eq) async {
    final db = await instance;
    await db.insert('equipment', _equipmentToMap(eq));
  }

  static Future<void> updateEquipment(Equipment eq) async {
    final db = await instance;
    await db.update(
      'equipment',
      _equipmentToMap(eq),
      where: 'id = ?',
      whereArgs: [eq.id],
    );
  }

  // ========================================
  // Adventure Log  (V4)
  // ========================================

  static Future<List<AdventureLog>> getAdventureLogs(
    String virtualPetId, {
    int limit = 20,
  }) async {
    final db = await instance;
    final rows = await db.query(
      'adventure_log',
      where: 'virtual_pet_id = ?',
      whereArgs: [virtualPetId],
      orderBy: 'started_at DESC',
      limit: limit,
    );
    return rows.map(_adventureLogFromMap).toList();
  }

  static Future<void> insertAdventureLog(AdventureLog al) async {
    final db = await instance;
    await db.insert('adventure_log', _adventureLogToMap(al));
  }

  // ========================================
  // Achievement Progress  (V4)
  // ========================================

  static Future<List<AchievementProgress>> getAllAchievements() async {
    final db = await instance;
    final rows = await db.query('achievement_progress');
    return rows.map(_achievementFromMap).toList();
  }

  static Future<void> upsertAchievement(AchievementProgress ap) async {
    final db = await instance;
    await db.insert(
      'achievement_progress',
      _achievementToMap(ap),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ========================================
  // Caught Pets  (V5 — 爪游)
  // ========================================

  /// Returns all caught pets for a virtual pet (for team + storage).
  static Future<List<CaughtPet>> getCaughtPets(String virtualPetId) async {
    final db = await instance;
    final rows = await db.query(
      'caught_pets',
      where: 'owner_virtual_pet_id = ?',
      whereArgs: [virtualPetId],
      orderBy: 'team_slot ASC, caught_at DESC',
    );
    return rows.map(_caughtPetFromMap).toList();
  }

  /// Returns team members only (is_in_team = 1).
  static Future<List<CaughtPet>> getTeamPets(String virtualPetId) async {
    final db = await instance;
    final rows = await db.query(
      'caught_pets',
      where: 'owner_virtual_pet_id = ? AND is_in_team = 1',
      whereArgs: [virtualPetId],
      orderBy: 'team_slot ASC',
    );
    return rows.map(_caughtPetFromMap).toList();
  }

  static Future<void> insertCaughtPet(CaughtPet pet) async {
    final db = await instance;
    await db.insert('caught_pets', _caughtPetToMap(pet));
  }

  static Future<void> updateCaughtPet(CaughtPet pet) async {
    final db = await instance;
    await db.update(
      'caught_pets',
      _caughtPetToMap(pet),
      where: 'id = ?',
      whereArgs: [pet.id],
    );
  }

  static Future<void> deleteCaughtPet(String id) async {
    final db = await instance;
    await db.delete('caught_pets', where: 'id = ?', whereArgs: [id]);
  }

  /// Reorders team slots (for party rearrangement).
  static Future<void> reorderTeam(List<CaughtPet> team) async {
    final db = await instance;
    await db.transaction((txn) async {
      for (var i = 0; i < team.length; i++) {
        await txn.update(
          'caught_pets',
          {'team_slot': i, 'is_in_team': 1, 'updated_at': nowMs()},
          where: 'id = ?',
          whereArgs: [team[i].id],
        );
      }
    });
  }

  // ========================================
  // Pokedex  (V5 — 爪游)
  // ========================================

  static Future<List<PokedexDbEntry>> getAllPokedexEntries() async {
    final db = await instance;
    final rows = await db.query('pokedex_entries', orderBy: 'species_id ASC');
    return rows.map(_pokedexFromMap).toList();
  }

  static Future<PokedexDbEntry?> getPokedexEntry(String speciesId) async {
    final db = await instance;
    final rows = await db.query(
      'pokedex_entries',
      where: 'species_id = ?',
      whereArgs: [speciesId],
    );
    return rows.isEmpty ? null : _pokedexFromMap(rows.first);
  }

  static Future<void> upsertPokedexEntry(PokedexDbEntry entry) async {
    final db = await instance;
    await db.insert(
      'pokedex_entries',
      _pokedexToMap(entry),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Marks a species as seen (increments times_seen).
  static Future<void> markSpeciesSeen(
    String speciesId,
    String speciesName,
  ) async {
    final existing = await getPokedexEntry(speciesId);
    if (existing != null) {
      await upsertPokedexEntry(
        existing.copyWith(seen: true, timesSeen: existing.timesSeen + 1),
      );
    } else {
      await upsertPokedexEntry(
        PokedexDbEntry(
          id: uuid(),
          speciesId: speciesId,
          speciesName: speciesName,
          seen: true,
          timesSeen: 1,
          updatedAt: DateTime.now(),
        ),
      );
    }
  }

  /// Marks a species as caught.
  static Future<void> markSpeciesCaught(
    String speciesId,
    String speciesName,
    int level,
  ) async {
    final existing = await getPokedexEntry(speciesId);
    if (existing != null) {
      await upsertPokedexEntry(
        existing.copyWith(
          seen: true,
          caught: true,
          timesSeen: existing.timesSeen + 1,
          timesCaught: existing.timesCaught + 1,
          firstCaughtLevel: existing.firstCaughtLevel ?? level,
          firstCaughtAt: existing.firstCaughtAt ?? DateTime.now(),
        ),
      );
    } else {
      await upsertPokedexEntry(
        PokedexDbEntry(
          id: uuid(),
          speciesId: speciesId,
          speciesName: speciesName,
          seen: true,
          caught: true,
          timesSeen: 1,
          timesCaught: 1,
          firstCaughtLevel: level,
          firstCaughtAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
    }
  }

  // ========================================
  // Gym Badges  (V5 — 爪游)
  // ========================================

  static Future<List<GymBadge>> getAllBadges() async {
    final db = await instance;
    final rows = await db.query('gym_badges', orderBy: 'badge_level ASC');
    return rows.map(_gymBadgeFromMap).toList();
  }

  static Future<List<String>> getEarnedBadgeIds() async {
    final badges = await getAllBadges();
    return badges.map((b) => b.gymId).toList();
  }

  static Future<void> insertBadge(GymBadge badge) async {
    final db = await instance;
    await db.insert('gym_badges', _gymBadgeToMap(badge));
  }

  // ========================================
  // Poke Balls  (V5 — 爪游)
  // ========================================

  static Future<Map<String, int>> getPokeBallQuantities() async {
    final db = await instance;
    final rows = await db.query('poke_balls');
    final map = <String, int>{};
    for (final row in rows) {
      map[row['ball_type'] as String] = row['quantity'] as int;
    }
    return map;
  }

  static Future<void> updatePokeBallQuantity(
    String ballType,
    int quantity,
  ) async {
    final db = await instance;
    await db.update(
      'poke_balls',
      {'quantity': quantity},
      where: 'ball_type = ?',
      whereArgs: [ballType],
    );
  }

  static Future<void> addPokeBalls(String ballType, int amount) async {
    final db = await instance;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'poke_balls',
        where: 'ball_type = ?',
        whereArgs: [ballType],
        limit: 1,
      );
      final current = rows.isNotEmpty ? rows.first['quantity'] as int? ?? 0 : 0;
      await txn.update(
        'poke_balls',
        {'quantity': current + amount},
        where: 'ball_type = ?',
        whereArgs: [ballType],
      );
    });
  }

  static Future<bool> usePokeBall(String ballType) async {
    final db = await instance;
    return db.transaction<bool>((txn) async {
      final rows = await txn.query(
        'poke_balls',
        where: 'ball_type = ?',
        whereArgs: [ballType],
        limit: 1,
      );
      final current = rows.isNotEmpty ? rows.first['quantity'] as int? ?? 0 : 0;
      if (current <= 0) return false;
      await txn.update(
        'poke_balls',
        {'quantity': current - 1},
        where: 'ball_type = ?',
        whereArgs: [ballType],
      );
      return true;
    });
  }

  // ========================================
  // Module Registry (V11) — 可选模块插口
  // ========================================
  static Future<void> registerModule(
    String moduleId, {
    bool enabled = true,
  }) async {
    final db = await instance;
    final now = nowMs();
    await db.insert('module_registry', {
      'module_id': moduleId,
      'enabled': enabled ? 1 : 0,
      'installed_at': now,
      'updated_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<List<ModuleEntry>> getModules() async {
    final db = await instance;
    final rows = await db.query('module_registry', orderBy: 'module_id ASC');
    return rows.map(_moduleEntryFromMap).toList();
  }

  static Future<bool> isModuleEnabled(String moduleId) async {
    final db = await instance;
    final rows = await db.query(
      'module_registry',
      where: 'module_id = ? AND enabled = 1',
      whereArgs: [moduleId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  static ModuleEntry _moduleEntryFromMap(Map<String, dynamic> m) => ModuleEntry(
    moduleId: m['module_id'] as String,
    enabled: (m['enabled'] as int) == 1,
    installedAt: DateTime.fromMillisecondsSinceEpoch(m['installed_at'] as int),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(m['updated_at'] as int),
  );

  // ========================================
  // Export / Import
  // ========================================
  /// 备份格式版本：导入时用于判断兼容性（只增，不兼容时导入侧给出提示）。
  static const backupFormatVersion = 1;

  /// 备份用的数据地图（**只含业务表**）。
  ///
  /// - 不含已废弃的游戏表（原导出会带上 10 张死表，见审计 P2-7）；
  /// - 只读数据库、不写文件：落盘/打包交给 `services/backup_service.dart`；
  /// - `media` 路径仍是设备绝对路径，打包/导入时由服务层重写。
  static Future<Map<String, dynamic>> buildExportMap() async {
    final db = await instance;
    return {
      'format_version': backupFormatVersion,
      'schema_version': VERSION,
      'exported_at': DateTime.now().toIso8601String(),
      'pets': await db.query('pets'),
      'diaries': await db.query('diaries'),
      'diary_images': await db.query('diary_images'),
      'tags': await db.query('tags'),
      'diary_tags': await db.query('diary_tags'),
      'reminders': await db.query('reminders'),
      'reminder_instances': await db.query('reminder_instances'),
    };
  }

  /// 导入结果统计（用于给用户如实的回执）。
  static Future<ImportSummary> importExportMap(
    Map<String, dynamic> data, {
    required Future<String?> Function(String archivePath) resolveMedia,
  }) async {
    final db = await instance;
    final pets = _rowsOf(data['pets']);
    final diaries = _rowsOf(data['diaries']);
    final images = _rowsOf(data['diary_images']);
    final tags = _rowsOf(data['tags']);
    final diaryTags = _rowsOf(data['diary_tags']);
    final reminders = _rowsOf(data['reminders']);
    final instances = _rowsOf(data['reminder_instances']);

    // 1) 媒体先落盘：IO 慢，放在事务外，避免长时间占写锁。
    final mediaPaths = <String>{
      for (final r in images)
        if ((r['local_path'] as String?)?.trim().isNotEmpty ?? false)
          (r['local_path'] as String).trim(),
      for (final r in pets)
        if ((r['avatar_path'] as String?)?.trim().isNotEmpty ?? false)
          (r['avatar_path'] as String).trim(),
    };
    final mediaMap = <String, String?>{};
    var skippedMedia = 0;
    for (final old in mediaPaths) {
      String? resolved;
      try {
        resolved = await resolveMedia(old);
      } catch (e) {
        debugPrint('导入媒体失败（跳过）: $old → $e');
      }
      mediaMap[old] = resolved;
      if (resolved == null) skippedMedia++;
    }

    final petIdMap = <String, String>{};
    final diaryIdMap = <String, String>{};
    final tagIdMap = <String, String>{};
    final reminderIdMap = <String, String>{};
    var nPets = 0,
        nDiaries = 0,
        nImages = 0,
        nTags = 0,
        nReminders = 0,
        nInstances = 0;

    await db.transaction((txn) async {
      // 各表的实际列（跨版本导入时，旧/新多出来的键一律丢弃，缺的走默认值）
      final cols = <String, Set<String>>{};
      for (final t in const [
        'pets',
        'diaries',
        'diary_images',
        'tags',
        'diary_tags',
        'reminders',
        'reminder_instances',
      ]) {
        cols[t] = (await txn.rawQuery(
          'PRAGMA table_info($t)',
        )).map((r) => r['name'] as String).toSet();
      }

      final existingTags = <String, String>{
        for (final r in await txn.query('tags', columns: ['id', 'name']))
          (r['name'] as String): r['id'] as String,
      };

      for (final r in pets) {
        if (_isDeletedRow(r)) continue;
        final oldId = r['id'] as String;
        final newId = uuid();
        petIdMap[oldId] = newId;
        final avatar = (r['avatar_path'] as String?)?.trim();
        await txn.insert('pets', {
          ..._pick(r, cols['pets']!),
          'id': newId,
          'avatar_path': (avatar == null || avatar.isEmpty)
              ? null
              : mediaMap[avatar],
          'is_deleted': 0,
        });
        nPets++;
      }

      for (final r in diaries) {
        if (_isDeletedRow(r)) continue;
        final newPetId = petIdMap[r['pet_id']];
        if (newPetId == null) continue;
        final newId = uuid();
        diaryIdMap[r['id'] as String] = newId;
        await txn.insert('diaries', {
          ..._pick(r, cols['diaries']!),
          'id': newId,
          'pet_id': newPetId,
          'is_deleted': 0,
        });
        nDiaries++;
      }

      for (final r in images) {
        final newDiaryId = diaryIdMap[r['diary_id']];
        if (newDiaryId == null) continue;
        final oldPath = (r['local_path'] as String?)?.trim();
        final newPath = oldPath == null || oldPath.isEmpty
            ? null
            : mediaMap[oldPath];
        // 文件没落地就不留这条图片记录：留着一个指向不存在文件的路径只会显示裂图
        if (newPath == null) continue;
        await txn.insert('diary_images', {
          ..._pick(r, cols['diary_images']!),
          'id': uuid(),
          'diary_id': newDiaryId,
          'local_path': newPath,
        });
        nImages++;
      }

      for (final r in tags) {
        final oldId = r['id'] as String;
        final name = r['name'] as String;
        final existing = existingTags[name];
        if (existing != null) {
          tagIdMap[oldId] = existing;
          continue;
        }
        final newId = uuid();
        tagIdMap[oldId] = newId;
        existingTags[name] = newId;
        await txn.insert('tags', {..._pick(r, cols['tags']!), 'id': newId});
        nTags++;
      }

      for (final r in diaryTags) {
        final d = diaryIdMap[r['diary_id']];
        final t = tagIdMap[r['tag_id']];
        if (d == null || t == null) continue;
        await txn.insert('diary_tags', {
          'diary_id': d,
          'tag_id': t,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }

      for (final r in reminders) {
        if (_isDeletedRow(r)) continue;
        final newPetId = petIdMap[r['pet_id']];
        if (newPetId == null) continue;
        final newId = uuid();
        reminderIdMap[r['id'] as String] = newId;
        await txn.insert('reminders', {
          ..._pick(r, cols['reminders']!),
          'id': newId,
          'pet_id': newPetId,
          'is_deleted': 0,
        });
        nReminders++;
      }

      for (final r in instances) {
        if (_isDeletedRow(r)) continue;
        final newReminderId = reminderIdMap[r['reminder_id']];
        if (newReminderId == null) continue;
        await txn.insert('reminder_instances', {
          ..._pick(r, cols['reminder_instances']!),
          'id': uuid(),
          'reminder_id': newReminderId,
          'is_deleted': 0,
          'deleted_with_pet': 0,
          'deleted_with_reminder': 0,
        });
        nInstances++;
      }
    });
    DataVersion.bump();

    return ImportSummary(
      pets: nPets,
      diaries: nDiaries,
      images: nImages,
      tags: nTags,
      reminders: nReminders,
      instances: nInstances,
      skippedMedia: skippedMedia,
    );
  }

  static List<Map<String, dynamic>> _rowsOf(dynamic v) => v is List
      ? v.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList()
      : const [];

  static bool _isDeletedRow(Map<String, dynamic> r) =>
      ((r['is_deleted'] as int?) ?? 0) == 1;

  /// 只保留目标表真实存在的列（跨版本导入的兼容层）。
  static Map<String, dynamic> _pick(
    Map<String, dynamic> row,
    Set<String> cols,
  ) => {
    for (final e in row.entries)
      if (cols.contains(e.key)) e.key: e.value,
  };

  /// 兼容旧调用：导出纯 JSON 文件（不含媒体）。新代码请用 buildExportMap + backup_service。
  static Future<String> exportToJson() async {
    final data = await buildExportMap();
    final dir = Directory(p.join((await getDatabasesPath()), 'exports'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final fileName =
        'clawtag_backup_${DateTime.now().millisecondsSinceEpoch}.json';
    final file = File(p.join(dir.path, fileName));
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(data),
      flush: true,
    );
    return file.path;
  }

  // ========================================
  // Virtual Pets — serialization
  // ========================================

  static Map<String, dynamic> _virtualPetToMap(VirtualPet v) => {
    'id': v.id,
    'real_pet_id': v.realPetId,
    'name': v.name,
    'level': v.level,
    'experience': v.experience,
    'evolution_stage': v.evolutionStage,
    'stat_str': v.statStr,
    'stat_int': v.statInt,
    'stat_dex': v.statDex,
    'stat_sta_max': v.statStaMax,
    'stat_hp_max': v.statHpMax,
    'stamina_current': v.staminaCurrent,
    'hp_current': v.hpCurrent,
    'weapon_id': v.weaponId,
    'armor_id': v.armorId,
    'accessory_id': v.accessoryId,
    'skill_levels': v.skillLevels,
    'mood': v.mood,
    'created_at': v.createdAt.millisecondsSinceEpoch,
    'updated_at': v.updatedAt.millisecondsSinceEpoch,
  };

  static VirtualPet _virtualPetFromMap(Map<String, dynamic> m) => VirtualPet(
    id: m['id'] as String,
    realPetId: m['real_pet_id'] as String,
    name: m['name'] as String,
    level: m['level'] as int,
    experience: m['experience'] as int,
    evolutionStage: m['evolution_stage'] as String,
    statStr: m['stat_str'] as int,
    statInt: m['stat_int'] as int,
    statDex: m['stat_dex'] as int,
    statStaMax: m['stat_sta_max'] as int,
    statHpMax: m['stat_hp_max'] as int,
    staminaCurrent: m['stamina_current'] as int,
    hpCurrent: m['hp_current'] as int,
    weaponId: m['weapon_id'] as String?,
    armorId: m['armor_id'] as String?,
    accessoryId: m['accessory_id'] as String?,
    skillLevels: m['skill_levels'] as String,
    mood: m['mood'] as int,
    createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(m['updated_at'] as int),
  );

  // ========================================
  // Game Currencies — serialization
  // ========================================

  static Map<String, dynamic> _currenciesToMap(GameCurrencies c) => {
    'id': c.id,
    'paw_coins': c.pawCoins,
    'memory_fragments': c.memoryFragments,
    'last_daily_refresh_date': c.lastDailyRefreshDate?.millisecondsSinceEpoch,
    'consecutive_checkin_days': c.consecutiveCheckinDays,
    'last_checkin_date': c.lastCheckinDate?.millisecondsSinceEpoch,
    'total_diaries_written': c.totalDiariesWritten,
    'total_reminders_completed': c.totalRemindersCompleted,
    'total_adventures_completed': c.totalAdventuresCompleted,
    'completed_quest_ids': c.completedQuestIds,
    'updated_at': c.updatedAt.millisecondsSinceEpoch,
  };

  static GameCurrencies _currenciesFromMap(Map<String, dynamic> m) =>
      GameCurrencies(
        id: m['id'] as String,
        pawCoins: m['paw_coins'] as int,
        memoryFragments: m['memory_fragments'] as int,
        lastDailyRefreshDate: _toDateTime(m['last_daily_refresh_date']),
        consecutiveCheckinDays: m['consecutive_checkin_days'] as int,
        lastCheckinDate: _toDateTime(m['last_checkin_date']),
        totalDiariesWritten: m['total_diaries_written'] as int,
        totalRemindersCompleted: m['total_reminders_completed'] as int,
        totalAdventuresCompleted: m['total_adventures_completed'] as int,
        completedQuestIds: (m['completed_quest_ids'] as String?) ?? '[]',
        updatedAt: DateTime.fromMillisecondsSinceEpoch(m['updated_at'] as int),
      );

  // ========================================
  // Reward Log — serialization
  // ========================================

  static Map<String, dynamic> _rewardLogToMap(RewardLog r) => {
    'id': r.id,
    'virtual_pet_id': r.virtualPetId,
    'source': r.source,
    'source_id': r.sourceId,
    'xp_earned': r.xpEarned,
    'coins_earned': r.coinsEarned,
    'fragments_earned': r.fragmentsEarned,
    'stat_str_gained': r.statStrGained,
    'stat_int_gained': r.statIntGained,
    'stat_dex_gained': r.statDexGained,
    'created_at': r.createdAt.millisecondsSinceEpoch,
  };

  static RewardLog _rewardLogFromMap(Map<String, dynamic> m) => RewardLog(
    id: m['id'] as String,
    virtualPetId: m['virtual_pet_id'] as String,
    source: m['source'] as String,
    sourceId: m['source_id'] as String?,
    xpEarned: m['xp_earned'] as int,
    coinsEarned: m['coins_earned'] as int,
    fragmentsEarned: m['fragments_earned'] as int,
    statStrGained: m['stat_str_gained'] as int,
    statIntGained: m['stat_int_gained'] as int,
    statDexGained: m['stat_dex_gained'] as int,
    createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
  );

  // ========================================
  // Check-in History — serialization
  // ========================================

  static Map<String, dynamic> _checkinToMap(CheckinHistory c) => {
    'id': c.id,
    'virtual_pet_id': c.virtualPetId,
    'checkin_date': c.checkinDate.millisecondsSinceEpoch,
    'diary_count': c.diaryCount,
    'reminder_count': c.reminderCount,
    'created_at': c.createdAt.millisecondsSinceEpoch,
  };

  static CheckinHistory _checkinFromMap(Map<String, dynamic> m) =>
      CheckinHistory(
        id: m['id'] as String,
        virtualPetId: m['virtual_pet_id'] as String,
        checkinDate: DateTime.fromMillisecondsSinceEpoch(
          m['checkin_date'] as int,
        ),
        diaryCount: m['diary_count'] as int,
        reminderCount: m['reminder_count'] as int,
        createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
      );

  // ========================================
  // Equipment — serialization
  // ========================================

  static Map<String, dynamic> _equipmentToMap(Equipment e) => {
    'id': e.id,
    'template_id': e.templateId,
    'equipped': e.equipped ? 1 : 0,
    'slot_type': e.slotType,
    'rarity': e.rarity,
    'level': e.level,
    'bonus_atk': e.bonusAtk,
    'bonus_def': e.bonusDef,
    'bonus_luk': e.bonusLuk,
    'bonus_str': e.bonusStr,
    'bonus_int': e.bonusInt,
    'bonus_dex': e.bonusDex,
    'acquired_at': e.acquiredAt.millisecondsSinceEpoch,
    'acquired_source': e.acquiredSource,
  };

  static Equipment _equipmentFromMap(Map<String, dynamic> m) => Equipment(
    id: m['id'] as String,
    templateId: m['template_id'] as String,
    equipped: (m['equipped'] as int) == 1,
    slotType: m['slot_type'] as String,
    rarity: m['rarity'] as String,
    level: m['level'] as int,
    bonusAtk: m['bonus_atk'] as int,
    bonusDef: m['bonus_def'] as int,
    bonusLuk: m['bonus_luk'] as int,
    bonusStr: m['bonus_str'] as int,
    bonusInt: m['bonus_int'] as int,
    bonusDex: m['bonus_dex'] as int,
    acquiredAt: DateTime.fromMillisecondsSinceEpoch(m['acquired_at'] as int),
    acquiredSource: m['acquired_source'] as String,
  );

  // ========================================
  // Adventure Log — serialization
  // ========================================

  static Map<String, dynamic> _adventureLogToMap(AdventureLog a) => {
    'id': a.id,
    'virtual_pet_id': a.virtualPetId,
    'map_id': a.mapId,
    'started_at': a.startedAt.millisecondsSinceEpoch,
    'completed_at': a.completedAt.millisecondsSinceEpoch,
    'duration_seconds': a.durationSeconds,
    'stamina_cost': a.staminaCost,
    'result': a.result,
    'monster_id': a.monsterId,
    'monster_name': a.monsterName,
    'monster_level': a.monsterLevel,
    'player_effective_atk': a.playerEffectiveAtk,
    'player_effective_def': a.playerEffectiveDef,
    'loot_json': a.lootJson,
    'coins_earned': a.coinsEarned,
    'xp_earned': a.xpEarned,
    'detailed_report': a.detailedReport,
  };

  static AdventureLog _adventureLogFromMap(Map<String, dynamic> m) =>
      AdventureLog(
        id: m['id'] as String,
        virtualPetId: m['virtual_pet_id'] as String,
        mapId: m['map_id'] as String,
        startedAt: DateTime.fromMillisecondsSinceEpoch(m['started_at'] as int),
        completedAt: DateTime.fromMillisecondsSinceEpoch(
          m['completed_at'] as int,
        ),
        durationSeconds: m['duration_seconds'] as int,
        staminaCost: m['stamina_cost'] as int,
        result: m['result'] as String,
        monsterId: m['monster_id'] as String?,
        monsterName: m['monster_name'] as String?,
        monsterLevel: m['monster_level'] as int?,
        playerEffectiveAtk: m['player_effective_atk'] as int,
        playerEffectiveDef: m['player_effective_def'] as int,
        lootJson: m['loot_json'] as String,
        coinsEarned: m['coins_earned'] as int,
        xpEarned: m['xp_earned'] as int,
        detailedReport: m['detailed_report'] as String?,
      );

  // ========================================
  // Achievement Progress — serialization
  // ========================================

  static Map<String, dynamic> _achievementToMap(AchievementProgress a) => {
    'id': a.id,
    'achievement_id': a.achievementId,
    'unlocked': a.unlocked ? 1 : 0,
    'unlocked_at': a.unlockedAt?.millisecondsSinceEpoch,
    'progress': a.progress,
    'target': a.target,
    'created_at': a.createdAt.millisecondsSinceEpoch,
  };

  static AchievementProgress _achievementFromMap(Map<String, dynamic> m) =>
      AchievementProgress(
        id: m['id'] as String,
        achievementId: m['achievement_id'] as String,
        unlocked: (m['unlocked'] as int) == 1,
        unlockedAt: _toDateTime(m['unlocked_at']),
        progress: m['progress'] as int,
        target: m['target'] as int,
        createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
      );

  // ========================================
  // Caught Pets — serialization  (V5)
  // ========================================

  static Map<String, dynamic> _caughtPetToMap(CaughtPet p) => {
    'id': p.id,
    'owner_virtual_pet_id': p.ownerVirtualPetId,
    'species_id': p.speciesId,
    'species_name': p.speciesName,
    'nickname': p.nickname,
    'level': p.level,
    'experience': p.experience,
    'current_hp': p.currentHp,
    'max_hp': p.maxHp,
    'atk': p.atk,
    'def': p.def,
    'spd': p.spd,
    'moves_json': p.movesJson,
    'status_effect': p.statusEffect,
    'is_in_team': p.isInTeam ? 1 : 0,
    'team_slot': p.teamSlot,
    'is_fainted': p.isFainted ? 1 : 0,
    'times_caught': p.timesCaught,
    'caught_at': p.caughtAt.millisecondsSinceEpoch,
    'updated_at': p.updatedAt.millisecondsSinceEpoch,
  };

  static CaughtPet _caughtPetFromMap(Map<String, dynamic> m) => CaughtPet(
    id: m['id'] as String,
    ownerVirtualPetId: m['owner_virtual_pet_id'] as String,
    speciesId: m['species_id'] as String,
    speciesName: m['species_name'] as String,
    nickname: m['nickname'] as String?,
    level: m['level'] as int,
    experience: m['experience'] as int,
    currentHp: m['current_hp'] as int,
    maxHp: m['max_hp'] as int,
    atk: m['atk'] as int,
    def: m['def'] as int,
    spd: m['spd'] as int,
    movesJson: m['moves_json'] as String,
    statusEffect: m['status_effect'] as String?,
    isInTeam: (m['is_in_team'] as int) == 1,
    teamSlot: m['team_slot'] as int?,
    isFainted: (m['is_fainted'] as int) == 1,
    timesCaught: m['times_caught'] as int,
    caughtAt: DateTime.fromMillisecondsSinceEpoch(m['caught_at'] as int),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(m['updated_at'] as int),
  );

  // ========================================
  // Pokedex — serialization  (V5)
  // ========================================

  static Map<String, dynamic> _pokedexToMap(PokedexDbEntry e) => {
    'id': e.id,
    'species_id': e.speciesId,
    'species_name': e.speciesName,
    'seen': e.seen ? 1 : 0,
    'caught': e.caught ? 1 : 0,
    'times_seen': e.timesSeen,
    'times_caught': e.timesCaught,
    'first_caught_level': e.firstCaughtLevel,
    'first_caught_at': e.firstCaughtAt?.millisecondsSinceEpoch,
    'updated_at': e.updatedAt.millisecondsSinceEpoch,
  };

  static PokedexDbEntry _pokedexFromMap(Map<String, dynamic> m) =>
      PokedexDbEntry(
        id: m['id'] as String,
        speciesId: m['species_id'] as String,
        speciesName: m['species_name'] as String,
        seen: (m['seen'] as int) == 1,
        caught: (m['caught'] as int) == 1,
        timesSeen: m['times_seen'] as int,
        timesCaught: m['times_caught'] as int,
        firstCaughtLevel: m['first_caught_level'] as int?,
        firstCaughtAt: _toDateTime(m['first_caught_at']),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(m['updated_at'] as int),
      );

  // ========================================
  // Gym Badges — serialization  (V5)
  // ========================================

  static Map<String, dynamic> _gymBadgeToMap(GymBadge b) => {
    'id': b.id,
    'gym_id': b.gymId,
    'gym_name': b.gymName,
    'badge_level': b.badgeLevel,
    'earned_at': b.earnedAt.millisecondsSinceEpoch,
  };

  static GymBadge _gymBadgeFromMap(Map<String, dynamic> m) => GymBadge(
    id: m['id'] as String,
    gymId: m['gym_id'] as String,
    gymName: m['gym_name'] as String,
    badgeLevel: m['badge_level'] as int,
    earnedAt: DateTime.fromMillisecondsSinceEpoch(m['earned_at'] as int),
  );

  // ========================================
  // Internal utilities
  // ========================================

  /// Safely deletes a file from disk — logs and swallows all errors so
  /// a missing or locked file never crashes the caller.
  static void _deleteFileSafe(String path) {
    try {
      final file = File(path);
      if (file.existsSync()) file.deleteSync();
    } catch (e) {
      // Intentionally swallowed — the file may already be gone or locked
      // by another process.  Physical cleanup is best-effort.
      debugPrint('⚠️ Failed to delete $path: $e');
    }
  }
}

// ========================================
// Data classes
// ========================================

class Pet {
  final String id;
  final String name;
  final String species;
  final String? breed;
  final String gender;
  final DateTime? birthDate;
  final DateTime meetDate;
  final String meetType;
  final String? avatarPath;
  final String? notes;
  final double? currentWeightKg;
  final DateTime? weightUpdatedAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int rowVersion;
  final bool isDeleted;

  const Pet({
    required this.id,
    required this.name,
    required this.species,
    this.breed,
    this.gender = 'unknown',
    this.birthDate,
    required this.meetDate,
    this.meetType = 'adopt',
    this.avatarPath,
    this.notes,
    this.currentWeightKg,
    this.weightUpdatedAt,
    required this.createdAt,
    required this.updatedAt,
    this.rowVersion = 1,
    this.isDeleted = false,
  });

  Pet copyWith({
    String? name,
    String? species,
    String? breed,
    bool clearBreed = false,
    String? gender,
    DateTime? birthDate,
    bool clearBirthDate = false,
    DateTime? meetDate,
    String? meetType,
    String? avatarPath,
    bool clearAvatarPath = false,
    String? notes,
    bool clearNotes = false,
    double? currentWeightKg,
    bool clearCurrentWeight = false,
    DateTime? weightUpdatedAt,
    int? rowVersion,
  }) => Pet(
    id: id,
    name: name ?? this.name,
    species: species ?? this.species,
    breed: clearBreed ? null : (breed ?? this.breed),
    gender: gender ?? this.gender,
    birthDate: clearBirthDate ? null : (birthDate ?? this.birthDate),
    meetDate: meetDate ?? this.meetDate,
    meetType: meetType ?? this.meetType,
    avatarPath: clearAvatarPath ? null : (avatarPath ?? this.avatarPath),
    notes: clearNotes ? null : (notes ?? this.notes),
    currentWeightKg: clearCurrentWeight
        ? null
        : (currentWeightKg ?? this.currentWeightKg),
    weightUpdatedAt: weightUpdatedAt ?? this.weightUpdatedAt,
    createdAt: createdAt,
    updatedAt: DateTime.now(),
    rowVersion: (rowVersion ?? this.rowVersion) + 1,
    isDeleted: isDeleted,
  );
}

class Diary {
  final String id;
  final String petId;
  final String title;
  final String content;
  final String? mood;
  final String? weather;
  final double? weight;
  final DateTime diaryDate;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int rowVersion;
  final bool isDeleted;

  const Diary({
    required this.id,
    required this.petId,
    required this.title,
    required this.content,
    this.mood,
    this.weather,
    this.weight,
    required this.diaryDate,
    required this.createdAt,
    required this.updatedAt,
    this.rowVersion = 1,
    this.isDeleted = false,
  });

  Diary copyWith({
    String? title,
    String? content,
    String? mood,
    String? weather,
    bool clearMood = false,
    bool clearWeather = false,
    double? weight,
    bool clearWeight = false,
    DateTime? diaryDate,
  }) => Diary(
    id: id,
    petId: petId,
    title: title ?? this.title,
    content: content ?? this.content,
    mood: clearMood ? null : (mood ?? this.mood),
    weather: clearWeather ? null : (weather ?? this.weather),
    weight: clearWeight ? null : (weight ?? this.weight),
    diaryDate: diaryDate ?? this.diaryDate,
    createdAt: createdAt,
    updatedAt: DateTime.now(),
    rowVersion: rowVersion + 1,
    isDeleted: isDeleted,
  );
}

class DiaryImage {
  final String id;
  final String diaryId;
  final String localPath;
  final String? remoteUrl;
  final int sortOrder;
  final DateTime createdAt;

  const DiaryImage({
    required this.id,
    required this.diaryId,
    required this.localPath,
    this.remoteUrl,
    this.sortOrder = 0,
    required this.createdAt,
  });
}

class Tag {
  final String id;
  final String name;
  final int? color;
  final DateTime createdAt;

  const Tag({
    required this.id,
    required this.name,
    this.color,
    required this.createdAt,
  });

  Tag copyWith({String? id, String? name, int? color, DateTime? createdAt}) =>
      Tag(
        id: id ?? this.id,
        name: name ?? this.name,
        color: color ?? this.color,
        createdAt: createdAt ?? this.createdAt,
      );
}

/// 导入结果统计（给用户如实回执：恢复了多少、跳过了多少）。
class ImportSummary {
  final int pets;
  final int diaries;
  final int images;
  final int tags;
  final int reminders;
  final int instances;
  final int skippedMedia;

  const ImportSummary({
    required this.pets,
    required this.diaries,
    required this.images,
    required this.tags,
    required this.reminders,
    required this.instances,
    required this.skippedMedia,
  });

  /// 是否什么都没导入（用来给「这份备份是空的 / 格式不对」的提示）。
  bool get isEmpty =>
      pets == 0 &&
      diaries == 0 &&
      tags == 0 &&
      reminders == 0 &&
      instances == 0;
}

class Reminder {
  final String id;
  final String petId;
  final String title;
  final String type;
  final String? description;
  final DateTime firstDueDate;
  final String repeatUnit;
  final int repeatInterval;
  final bool isRepeating;
  final String? notificationTime; // "HH:mm" or null (= use firstDueDate time)
  final bool soundEnabled;
  final bool vibrateEnabled;
  final DateTime? repeatEndDate;
  final DateTime? lastDoneDate; // 上次实际完成时间（完成实例时更新）

  /// 用药疗程天数；null = 普通提醒。
  final int? courseDays;

  /// 每天服药时刻（当日分钟数，升序）；空 = 普通提醒。
  final List<int> doseTimes;

  /// 是否是用药疗程提醒（两个字段都有效才算，缺一即降级为普通提醒）。
  bool get isMedicationCourse =>
      courseDays != null && courseDays! > 0 && doseTimes.isNotEmpty;

  final DateTime createdAt;
  final DateTime updatedAt;
  final int rowVersion;
  final bool isDeleted;

  const Reminder({
    required this.id,
    required this.petId,
    required this.title,
    required this.type,
    this.description,
    required this.firstDueDate,
    this.repeatUnit = 'once',
    this.repeatInterval = 1,
    this.isRepeating = false,
    this.notificationTime,
    this.soundEnabled = true,
    this.vibrateEnabled = true,
    this.repeatEndDate,
    this.lastDoneDate,
    this.courseDays,
    this.doseTimes = const [],
    required this.createdAt,
    required this.updatedAt,
    this.rowVersion = 1,
    this.isDeleted = false,
  });

  Reminder copyWith({
    String? petId,
    String? title,
    String? type,
    String? description,

    /// 置 true 时清空备注（传 null 会被 `??` 回退成旧值，无法删除已有备注）。
    bool clearDescription = false,
    DateTime? firstDueDate,
    String? repeatUnit,
    int? repeatInterval,
    bool? isRepeating,
    String? notificationTime,
    bool? soundEnabled,
    bool? vibrateEnabled,
    DateTime? repeatEndDate,
    DateTime? lastDoneDate,

    /// 置 true 时清空「上次完成时间」（传 null 会被 `??` 回退成旧值）。
    bool clearLastDoneDate = false,
    int? courseDays,
    List<int>? doseTimes,
  }) => Reminder(
    id: id,
    petId: petId ?? this.petId,
    title: title ?? this.title,
    type: type ?? this.type,
    description: clearDescription ? null : (description ?? this.description),
    firstDueDate: firstDueDate ?? this.firstDueDate,
    repeatUnit: repeatUnit ?? this.repeatUnit,
    repeatInterval: repeatInterval ?? this.repeatInterval,
    isRepeating: isRepeating ?? this.isRepeating,
    notificationTime: notificationTime ?? this.notificationTime,
    soundEnabled: soundEnabled ?? this.soundEnabled,
    vibrateEnabled: vibrateEnabled ?? this.vibrateEnabled,
    repeatEndDate: repeatEndDate ?? this.repeatEndDate,
    lastDoneDate: clearLastDoneDate
        ? null
        : (lastDoneDate ?? this.lastDoneDate),
    courseDays: courseDays ?? this.courseDays,
    doseTimes: doseTimes ?? this.doseTimes,
    createdAt: createdAt,
    updatedAt: DateTime.now(),
    rowVersion: rowVersion + 1,
    isDeleted: isDeleted,
  );
}

/// 一条用药待办：实例 + 它所属的提醒。
typedef MedicationDose = ({ReminderInstance instance, Reminder reminder});

class ReminderInstance {
  final String id;
  final String reminderId;
  final DateTime dueDate;
  final bool completed;
  final DateTime? completedAt;
  final int occurrenceNo;
  final DateTime createdAt;
  final bool isDeleted;
  final DateTime? deletedAt;

  const ReminderInstance({
    required this.id,
    required this.reminderId,
    required this.dueDate,
    this.completed = false,
    this.completedAt,
    this.occurrenceNo = 1,
    required this.createdAt,
    this.isDeleted = false,
    this.deletedAt,
  });
}

// ========================================
// V4 — Virtual Pet
// ========================================

class VirtualPet {
  final String id;
  final String realPetId;
  final String name;
  final int level;
  final int experience;
  final String evolutionStage;
  final int statStr;
  final int statInt;
  final int statDex;
  final int statStaMax;
  final int statHpMax;
  final int staminaCurrent;
  final int hpCurrent;
  final String? weaponId;
  final String? armorId;
  final String? accessoryId;
  final String skillLevels; // JSON
  final int mood;
  final DateTime createdAt;
  final DateTime updatedAt;

  const VirtualPet({
    required this.id,
    required this.realPetId,
    required this.name,
    this.level = 1,
    this.experience = 0,
    this.evolutionStage = 'baby',
    this.statStr = 5,
    this.statInt = 5,
    this.statDex = 5,
    this.statStaMax = 100,
    this.statHpMax = 100,
    this.staminaCurrent = 100,
    this.hpCurrent = 100,
    this.weaponId,
    this.armorId,
    this.accessoryId,
    this.skillLevels = '{}',
    this.mood = 50,
    required this.createdAt,
    required this.updatedAt,
  });

  VirtualPet copyWith({
    int? level,
    int? experience,
    String? evolutionStage,
    int? statStr,
    int? statInt,
    int? statDex,
    int? statStaMax,
    int? statHpMax,
    int? staminaCurrent,
    int? hpCurrent,
    String? weaponId,
    String? armorId,
    String? accessoryId,
    String? skillLevels,
    int? mood,
  }) => VirtualPet(
    id: id,
    realPetId: realPetId,
    name: name,
    level: level ?? this.level,
    experience: experience ?? this.experience,
    evolutionStage: evolutionStage ?? this.evolutionStage,
    statStr: statStr ?? this.statStr,
    statInt: statInt ?? this.statInt,
    statDex: statDex ?? this.statDex,
    statStaMax: statStaMax ?? this.statStaMax,
    statHpMax: statHpMax ?? this.statHpMax,
    staminaCurrent: staminaCurrent ?? this.staminaCurrent,
    hpCurrent: hpCurrent ?? this.hpCurrent,
    weaponId: weaponId ?? this.weaponId,
    armorId: armorId ?? this.armorId,
    accessoryId: accessoryId ?? this.accessoryId,
    skillLevels: skillLevels ?? this.skillLevels,
    mood: mood ?? this.mood,
    createdAt: createdAt,
    updatedAt: DateTime.now(),
  );
}

// ========================================
// V4 — Game Currencies
// ========================================

class GameCurrencies {
  final String id;
  final int pawCoins;
  final int memoryFragments;
  final DateTime? lastDailyRefreshDate;
  final int consecutiveCheckinDays;
  final DateTime? lastCheckinDate;
  final int totalDiariesWritten;
  final int totalRemindersCompleted;
  final int totalAdventuresCompleted;
  final String completedQuestIds;
  final DateTime updatedAt;

  const GameCurrencies({
    required this.id,
    this.pawCoins = 0,
    this.memoryFragments = 0,
    this.lastDailyRefreshDate,
    this.consecutiveCheckinDays = 0,
    this.lastCheckinDate,
    this.totalDiariesWritten = 0,
    this.totalRemindersCompleted = 0,
    this.totalAdventuresCompleted = 0,
    this.completedQuestIds = '[]',
    required this.updatedAt,
  });

  GameCurrencies copyWith({
    int? pawCoins,
    int? memoryFragments,
    DateTime? lastDailyRefreshDate,
    int? consecutiveCheckinDays,
    DateTime? lastCheckinDate,
    int? totalDiariesWritten,
    int? totalRemindersCompleted,
    int? totalAdventuresCompleted,
    String? completedQuestIds,
  }) => GameCurrencies(
    id: id,
    pawCoins: pawCoins ?? this.pawCoins,
    memoryFragments: memoryFragments ?? this.memoryFragments,
    lastDailyRefreshDate: lastDailyRefreshDate ?? this.lastDailyRefreshDate,
    consecutiveCheckinDays:
        consecutiveCheckinDays ?? this.consecutiveCheckinDays,
    lastCheckinDate: lastCheckinDate ?? this.lastCheckinDate,
    totalDiariesWritten: totalDiariesWritten ?? this.totalDiariesWritten,
    totalRemindersCompleted:
        totalRemindersCompleted ?? this.totalRemindersCompleted,
    totalAdventuresCompleted:
        totalAdventuresCompleted ?? this.totalAdventuresCompleted,
    completedQuestIds: completedQuestIds ?? this.completedQuestIds,
    updatedAt: DateTime.now(),
  );
}

// ========================================
// V4 — Equipment
// ========================================

class Equipment {
  final String id;
  final String templateId;
  final bool equipped;
  final String slotType;
  final String rarity;
  final int level;
  final int bonusAtk;
  final int bonusDef;
  final int bonusLuk;
  final int bonusStr;
  final int bonusInt;
  final int bonusDex;
  final DateTime acquiredAt;
  final String acquiredSource;

  const Equipment({
    required this.id,
    required this.templateId,
    this.equipped = false,
    required this.slotType,
    this.rarity = 'common',
    this.level = 1,
    this.bonusAtk = 0,
    this.bonusDef = 0,
    this.bonusLuk = 0,
    this.bonusStr = 0,
    this.bonusInt = 0,
    this.bonusDex = 0,
    required this.acquiredAt,
    required this.acquiredSource,
  });

  Equipment copyWith({
    bool? equipped,
    int? level,
    int? bonusAtk,
    int? bonusDef,
    int? bonusLuk,
    int? bonusStr,
    int? bonusInt,
    int? bonusDex,
  }) => Equipment(
    id: id,
    templateId: templateId,
    equipped: equipped ?? this.equipped,
    slotType: slotType,
    rarity: rarity,
    level: level ?? this.level,
    bonusAtk: bonusAtk ?? this.bonusAtk,
    bonusDef: bonusDef ?? this.bonusDef,
    bonusLuk: bonusLuk ?? this.bonusLuk,
    bonusStr: bonusStr ?? this.bonusStr,
    bonusInt: bonusInt ?? this.bonusInt,
    bonusDex: bonusDex ?? this.bonusDex,
    acquiredAt: acquiredAt,
    acquiredSource: acquiredSource,
  );
}

// ========================================
// V4 — Adventure Log
// ========================================

class AdventureLog {
  final String id;
  final String virtualPetId;
  final String mapId;
  final DateTime startedAt;
  final DateTime completedAt;
  final int durationSeconds;
  final int staminaCost;
  final String result;
  final String? monsterId;
  final String? monsterName;
  final int? monsterLevel;
  final int playerEffectiveAtk;
  final int playerEffectiveDef;
  final String lootJson;
  final int coinsEarned;
  final int xpEarned;
  final String? detailedReport;

  const AdventureLog({
    required this.id,
    required this.virtualPetId,
    required this.mapId,
    required this.startedAt,
    required this.completedAt,
    required this.durationSeconds,
    this.staminaCost = 0,
    this.result = 'pending',
    this.monsterId,
    this.monsterName,
    this.monsterLevel,
    this.playerEffectiveAtk = 0,
    this.playerEffectiveDef = 0,
    this.lootJson = '[]',
    this.coinsEarned = 0,
    this.xpEarned = 0,
    this.detailedReport,
  });
}

// ========================================
// V4 — Achievement Progress
// ========================================

class AchievementProgress {
  final String id;
  final String achievementId;
  final bool unlocked;
  final DateTime? unlockedAt;
  final int progress;
  final int target;
  final DateTime createdAt;

  const AchievementProgress({
    required this.id,
    required this.achievementId,
    this.unlocked = false,
    this.unlockedAt,
    this.progress = 0,
    this.target = 1,
    required this.createdAt,
  });

  AchievementProgress copyWith({
    bool? unlocked,
    DateTime? unlockedAt,
    int? progress,
    int? target,
  }) => AchievementProgress(
    id: id,
    achievementId: achievementId,
    unlocked: unlocked ?? this.unlocked,
    unlockedAt: unlockedAt ?? this.unlockedAt,
    progress: progress ?? this.progress,
    target: target ?? this.target,
    createdAt: createdAt,
  );
}

// ========================================
// V4 — Reward Log
// ========================================

class RewardLog {
  final String id;
  final String virtualPetId;
  final String source;
  final String? sourceId;
  final int xpEarned;
  final int coinsEarned;
  final int fragmentsEarned;
  final int statStrGained;
  final int statIntGained;
  final int statDexGained;
  final DateTime createdAt;

  const RewardLog({
    required this.id,
    required this.virtualPetId,
    required this.source,
    this.sourceId,
    this.xpEarned = 0,
    this.coinsEarned = 0,
    this.fragmentsEarned = 0,
    this.statStrGained = 0,
    this.statIntGained = 0,
    this.statDexGained = 0,
    required this.createdAt,
  });
}

// ========================================
// V4 — Check-in History
// ========================================

class CheckinHistory {
  final String id;
  final String virtualPetId;
  final DateTime checkinDate;
  final int diaryCount;
  final int reminderCount;
  final DateTime createdAt;

  const CheckinHistory({
    required this.id,
    required this.virtualPetId,
    required this.checkinDate,
    this.diaryCount = 0,
    this.reminderCount = 0,
    required this.createdAt,
  });
}

// ========================================
// V5 — Caught Pet (爪游 Pokémon team)
// ========================================

class CaughtPet {
  final String id;
  final String ownerVirtualPetId;
  final String speciesId;
  final String speciesName;
  final String? nickname;
  final int level;
  final int experience;
  final int currentHp;
  final int maxHp;
  final int atk;
  final int def;
  final int spd;
  final String movesJson; // JSON array of move IDs
  final String? statusEffect;
  final bool isInTeam;
  final int? teamSlot;
  final bool isFainted;
  final int timesCaught;
  final DateTime caughtAt;
  final DateTime updatedAt;

  const CaughtPet({
    required this.id,
    required this.ownerVirtualPetId,
    required this.speciesId,
    required this.speciesName,
    this.nickname,
    this.level = 1,
    this.experience = 0,
    this.currentHp = 100,
    this.maxHp = 100,
    this.atk = 10,
    this.def = 10,
    this.spd = 10,
    this.movesJson = '[]',
    this.statusEffect,
    this.isInTeam = false,
    this.teamSlot,
    this.isFainted = false,
    this.timesCaught = 1,
    required this.caughtAt,
    required this.updatedAt,
  });

  CaughtPet copyWith({
    int? level,
    int? experience,
    int? currentHp,
    int? maxHp,
    int? atk,
    int? def,
    int? spd,
    String? movesJson,
    String? statusEffect,
    bool? isInTeam,
    int? teamSlot,
    bool? isFainted,
    String? nickname,
  }) => CaughtPet(
    id: id,
    ownerVirtualPetId: ownerVirtualPetId,
    speciesId: speciesId,
    speciesName: speciesName,
    nickname: nickname ?? this.nickname,
    level: level ?? this.level,
    experience: experience ?? this.experience,
    currentHp: currentHp ?? this.currentHp,
    maxHp: maxHp ?? this.maxHp,
    atk: atk ?? this.atk,
    def: def ?? this.def,
    spd: spd ?? this.spd,
    movesJson: movesJson ?? this.movesJson,
    statusEffect: statusEffect ?? this.statusEffect,
    isInTeam: isInTeam ?? this.isInTeam,
    teamSlot: teamSlot ?? this.teamSlot,
    isFainted: isFainted ?? this.isFainted,
    timesCaught: timesCaught,
    caughtAt: caughtAt,
    updatedAt: DateTime.now(),
  );
}

// ========================================
// V5 — Pokedex Entry (爪游 图鉴)
// ========================================

class PokedexDbEntry {
  final String id;
  final String speciesId;
  final String speciesName;
  final bool seen;
  final bool caught;
  final int timesSeen;
  final int timesCaught;
  final int? firstCaughtLevel;
  final DateTime? firstCaughtAt;
  final DateTime updatedAt;

  const PokedexDbEntry({
    required this.id,
    required this.speciesId,
    required this.speciesName,
    this.seen = false,
    this.caught = false,
    this.timesSeen = 0,
    this.timesCaught = 0,
    this.firstCaughtLevel,
    this.firstCaughtAt,
    required this.updatedAt,
  });

  PokedexDbEntry copyWith({
    bool? seen,
    bool? caught,
    int? timesSeen,
    int? timesCaught,
    int? firstCaughtLevel,
    DateTime? firstCaughtAt,
  }) => PokedexDbEntry(
    id: id,
    speciesId: speciesId,
    speciesName: speciesName,
    seen: seen ?? this.seen,
    caught: caught ?? this.caught,
    timesSeen: timesSeen ?? this.timesSeen,
    timesCaught: timesCaught ?? this.timesCaught,
    firstCaughtLevel: firstCaughtLevel ?? this.firstCaughtLevel,
    firstCaughtAt: firstCaughtAt ?? this.firstCaughtAt,
    updatedAt: DateTime.now(),
  );
}

// ========================================
// V5 — Gym Badge (爪游 道馆徽章)
// ========================================

class GymBadge {
  final String id;
  final String gymId;
  final String gymName;
  final int badgeLevel;
  final DateTime earnedAt;

  const GymBadge({
    required this.id,
    required this.gymId,
    required this.gymName,
    required this.badgeLevel,
    required this.earnedAt,
  });
}

// ========================================
// V11 — Module Entry (可选模块注册表)
// ========================================

class ModuleEntry {
  final String moduleId;
  final bool enabled;
  final DateTime installedAt;
  final DateTime updatedAt;

  const ModuleEntry({
    required this.moduleId,
    required this.enabled,
    required this.installedAt,
    required this.updatedAt,
  });
}
