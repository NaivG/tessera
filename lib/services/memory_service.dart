import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

import '../models/memory_entry.dart';
import '../models/memory_relation.dart';

/// 记忆系统 SQLite 持久化服务
///
/// 使用独立的 `memory.db` 数据库文件，与主 `tessera.db` 分离。
class MemoryService {
  static Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'memory.db');

    return openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE memory_entries (
            id TEXT PRIMARY KEY,
            type TEXT NOT NULL,
            content TEXT NOT NULL,
            hash TEXT NOT NULL,
            importance REAL NOT NULL DEFAULT 0.5,
            confidence REAL NOT NULL DEFAULT 0.5,
            conversation_id TEXT,
            source_message_id TEXT,
            access_count INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            last_accessed TEXT NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE memory_relations (
            id TEXT PRIMARY KEY,
            source_id TEXT NOT NULL,
            target_id TEXT NOT NULL,
            relation_type TEXT NOT NULL,
            weight REAL NOT NULL DEFAULT 1.0,
            FOREIGN KEY (source_id) REFERENCES memory_entries(id) ON DELETE CASCADE,
            FOREIGN KEY (target_id) REFERENCES memory_entries(id) ON DELETE CASCADE
          )
        ''');

        // 索引
        await db.execute(
          'CREATE INDEX idx_memory_type ON memory_entries(type)',
        );
        await db.execute(
          'CREATE INDEX idx_memory_hash ON memory_entries(hash)',
        );
        await db.execute(
          'CREATE INDEX idx_memory_hash16 ON memory_entries(SUBSTR(hash, 1, 16))',
        );
        await db.execute(
          'CREATE INDEX idx_memory_hash32 ON memory_entries(SUBSTR(hash, 1, 32))',
        );
        await db.execute(
          'CREATE INDEX idx_memory_conv ON memory_entries(conversation_id)',
        );
        await db.execute(
          'CREATE INDEX idx_memory_importance ON memory_entries(importance DESC)',
        );
        await db.execute(
          'CREATE INDEX idx_memory_last_accessed ON memory_entries(last_accessed DESC)',
        );
        await db.execute(
          'CREATE INDEX idx_memory_rel_source ON memory_relations(source_id)',
        );
        await db.execute(
          'CREATE INDEX idx_memory_rel_target ON memory_relations(target_id)',
        );

        debugPrint('[MemoryService] memory.db 创建完成');
      },
    );
  }

  // ── 记忆条目 CRUD ──

  /// 插入一条记忆条目
  Future<void> insertEntry(MemoryEntry entry) async {
    final db = await database;
    await db.insert(
      'memory_entries',
      entry.toDb(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 批量插入记忆条目
  Future<void> insertEntries(List<MemoryEntry> entries) async {
    final db = await database;
    final batch = db.batch();
    for (final entry in entries) {
      batch.insert(
        'memory_entries',
        entry.toDb(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  /// 更新记忆条目
  Future<void> updateEntry(MemoryEntry entry) async {
    final db = await database;
    await db.update(
      'memory_entries',
      entry.toDb(),
      where: 'id = ?',
      whereArgs: [entry.id],
    );
  }

  /// 批量更新 access_count 和 last_accessed
  Future<void> updateAccess(String id) async {
    final db = await database;
    await db.rawUpdate(
      'UPDATE memory_entries SET access_count = access_count + 1, '
      'last_accessed = ? WHERE id = ?',
      [DateTime.now().toIso8601String(), id],
    );
  }

  /// 删除记忆条目
  Future<void> deleteEntry(String id) async {
    final db = await database;
    await db.delete('memory_entries', where: 'id = ?', whereArgs: [id]);
    // 同时删除关联关系
    await db.delete(
      'memory_relations',
      where: 'source_id = ? OR target_id = ?',
      whereArgs: [id, id],
    );
  }

  /// 按对话 ID 删除所有关联记忆（conversational 类型 + 其他类型）
  Future<void> deleteByConversationId(String convId) async {
    final db = await database;
    // 先删除关联
    await db.rawDelete(
      'DELETE FROM memory_relations WHERE source_id IN '
      '(SELECT id FROM memory_entries WHERE conversation_id = ?) '
      'OR target_id IN (SELECT id FROM memory_entries WHERE conversation_id = ?)',
      [convId, convId],
    );
    await db.delete(
      'memory_entries',
      where: 'conversation_id = ?',
      whereArgs: [convId],
    );
  }

  // ── 查询 ──

  /// 按 ID 获取单条记忆
  Future<MemoryEntry?> getEntry(String id) async {
    final db = await database;
    final rows = await db.query(
      'memory_entries',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (rows.isEmpty) return null;
    return MemoryEntry.fromDb(rows.first);
  }

  /// 按分桶前缀查询记忆（16bit 粗桶）
  ///
  /// 使用 SUBSTR 索引，返回桶内所有条目，按 importance 降序。
  Future<List<MemoryEntry>> getByBucketPrefix(String prefix) async {
    final db = await database;
    final rows = await db.query(
      'memory_entries',
      where: 'SUBSTR(hash, 1, ?) = ?',
      whereArgs: [prefix.length, prefix],
      orderBy: 'importance DESC',
    );
    return rows.map(MemoryEntry.fromDb).toList();
  }

  /// 获取所有记忆（按更新时间降序）
  Future<List<MemoryEntry>> getAllEntries() async {
    final db = await database;
    final rows = await db.query(
      'memory_entries',
      orderBy: 'updated_at DESC',
    );
    return rows.map(MemoryEntry.fromDb).toList();
  }

  /// 按类型获取记忆
  Future<List<MemoryEntry>> getByType(String type) async {
    final db = await database;
    final rows = await db.query(
      'memory_entries',
      where: 'type = ?',
      whereArgs: [type],
      orderBy: 'importance DESC',
    );
    return rows.map(MemoryEntry.fromDb).toList();
  }

  /// 按对话 ID 获取记忆
  Future<List<MemoryEntry>> getByConversationId(String convId) async {
    final db = await database;
    final rows = await db.query(
      'memory_entries',
      where: 'conversation_id = ?',
      whereArgs: [convId],
      orderBy: 'created_at ASC',
    );
    return rows.map(MemoryEntry.fromDb).toList();
  }

  /// 获取条目总数
  Future<int> getEntryCount() async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as cnt FROM memory_entries',
    );
    return (result.first['cnt'] as int?) ?? 0;
  }

  // ── 记忆关联 CRUD ──

  /// 插入关联
  Future<void> insertRelation(MemoryRelation relation) async {
    final db = await database;
    await db.insert(
      'memory_relations',
      relation.toDb(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 查询某条记忆的所有关联
  Future<List<MemoryRelation>> getRelations(String entryId) async {
    final db = await database;
    final rows = await db.query(
      'memory_relations',
      where: 'source_id = ? OR target_id = ?',
      whereArgs: [entryId, entryId],
    );
    return rows.map(MemoryRelation.fromDb).toList();
  }

  /// 删除关联
  Future<void> deleteRelation(String id) async {
    final db = await database;
    await db.delete('memory_relations', where: 'id = ?', whereArgs: [id]);
  }

  // ── 关闭 ──

  /// 关闭数据库连接
  Future<void> close() async {
    if (_db != null) {
      await _db!.close();
      _db = null;
    }
  }
}
