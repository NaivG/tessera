import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'prompt_section.dart';

/// 缓存持久化存储 — 基于 sqflite
///
/// 管理 [PromptSection] 的本地持久化，支持按类型、ID、过期状态查询。
/// 与 [ConversationService] 共享同一数据库，使用独立的 `prompt_sections` 表。
class CacheStore {
  static Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'tessera_cache.db');

    return openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE prompt_sections (
            id TEXT PRIMARY KEY,
            type TEXT NOT NULL,
            content TEXT NOT NULL,
            content_hash TEXT NOT NULL,
            created_at TEXT NOT NULL,
            expires_at TEXT,
            cache_hint TEXT NOT NULL,
            metadata TEXT
          )
        ''');

        await db.execute('CREATE INDEX idx_ps_type ON prompt_sections(type)');
        await db.execute(
          'CREATE INDEX idx_ps_expires ON prompt_sections(expires_at)',
        );
        await db.execute(
          'CREATE INDEX idx_ps_hash ON prompt_sections(content_hash)',
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════
  // CRUD
  // ═══════════════════════════════════════════════════════

  /// 保存或更新单个分块
  Future<void> saveSection(PromptSection section) async {
    final db = await database;
    await db.insert(
      'prompt_sections',
      _sectionToRow(section),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 批量保存分块
  Future<void> saveSections(List<PromptSection> sections) async {
    final db = await database;
    final batch = db.batch();
    for (final section in sections) {
      batch.insert(
        'prompt_sections',
        _sectionToRow(section),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  /// 按 ID 获取分块
  Future<PromptSection?> getSection(String id) async {
    final db = await database;
    final rows = await db.query(
      'prompt_sections',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (rows.isEmpty) return null;
    return _rowToSection(rows.first);
  }

  /// 按类型获取所有分块（不含已过期）
  Future<List<PromptSection>> getSectionsByType(PromptSectionType type) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    final rows = await db.query(
      'prompt_sections',
      where: 'type = ? AND (expires_at IS NULL OR expires_at > ?)',
      whereArgs: [type.name, now],
      orderBy: 'created_at DESC',
    );
    return rows.map(_rowToSection).toList();
  }

  /// 获取所有未过期的分块
  Future<List<PromptSection>> getAllValid() async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    final rows = await db.query(
      'prompt_sections',
      where: 'expires_at IS NULL OR expires_at > ?',
      whereArgs: [now],
      orderBy: 'created_at DESC',
    );
    return rows.map(_rowToSection).toList();
  }

  /// 获取所有需要客户端缓存的分块（未过期且 cache_hint.clientCache == true）
  Future<List<PromptSection>> getClientCacheable() async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    final rows = await db.query(
      'prompt_sections',
      where: 'expires_at IS NULL OR expires_at > ?',
      whereArgs: [now],
      orderBy: 'created_at DESC',
    );
    return rows
        .map(_rowToSection)
        .where((s) => s.cacheHint.clientCache)
        .toList();
  }

  /// 删除指定分块
  Future<void> deleteSection(String id) async {
    final db = await database;
    await db.delete('prompt_sections', where: 'id = ?', whereArgs: [id]);
  }

  /// 清空所有已过期的分块
  Future<int> purgeExpired() async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    return db.delete(
      'prompt_sections',
      where: 'expires_at IS NOT NULL AND expires_at <= ?',
      whereArgs: [now],
    );
  }

  /// 清空所有分块
  Future<void> clear() async {
    final db = await database;
    await db.delete('prompt_sections');
  }

  /// 按类型清空分块
  Future<int> clearType(PromptSectionType type) async {
    final db = await database;
    return db.delete(
      'prompt_sections',
      where: 'type = ?',
      whereArgs: [type.name],
    );
  }

  // ═══════════════════════════════════════════════════════
  // 统计
  // ═══════════════════════════════════════════════════════

  /// 获取缓存统计信息
  Future<CacheStats> getStats() async {
    final db = await database;
    final now = DateTime.now().toIso8601String();

    final totalResult = await db.rawQuery(
      'SELECT COUNT(*) as cnt, SUM(LENGTH(content)) as bytes FROM prompt_sections',
    );
    final validResult = await db.rawQuery(
      'SELECT COUNT(*) as cnt FROM prompt_sections '
      'WHERE expires_at IS NULL OR expires_at > ?',
      [now],
    );
    final expiredResult = await db.rawQuery(
      'SELECT COUNT(*) as cnt FROM prompt_sections '
      'WHERE expires_at IS NOT NULL AND expires_at <= ?',
      [now],
    );

    final typeCounts = await db.rawQuery(
      'SELECT type, COUNT(*) as cnt FROM prompt_sections '
      'WHERE expires_at IS NULL OR expires_at > ? '
      'GROUP BY type',
      [now],
    );

    final byType = <PromptSectionType, int>{};
    for (final row in typeCounts) {
      final type = promptSectionTypeFromName(row['type'] as String);
      byType[type] = row['cnt'] as int;
    }

    return CacheStats(
      totalSections: totalResult.first['cnt'] as int,
      validSections: validResult.first['cnt'] as int,
      expiredSections: expiredResult.first['cnt'] as int,
      totalBytes: totalResult.first['bytes'] as int? ?? 0,
      byType: byType,
    );
  }

  // ═══════════════════════════════════════════════════════
  // 内部
  // ═══════════════════════════════════════════════════════

  Map<String, dynamic> _sectionToRow(PromptSection section) {
    return {
      'id': section.id,
      'type': section.type.name,
      'content': section.content,
      'content_hash': section.contentHash,
      'created_at': section.createdAt.toIso8601String(),
      'expires_at': section.expiresAt?.toIso8601String(),
      'cache_hint': jsonEncode(section.cacheHint.toJson()),
      'metadata': section.metadata != null
          ? jsonEncode(section.metadata)
          : null,
    };
  }

  PromptSection _rowToSection(Map<String, dynamic> row) {
    return PromptSection(
      id: row['id'] as String,
      type: promptSectionTypeFromName(row['type'] as String),
      content: row['content'] as String,
      contentHash: row['content_hash'] as String,
      createdAt: DateTime.parse(row['created_at'] as String),
      expiresAt: row['expires_at'] != null
          ? DateTime.parse(row['expires_at'] as String)
          : null,
      cacheHint: PromptCacheHint.fromJson(
        jsonDecode(row['cache_hint'] as String) as Map<String, dynamic>,
      ),
      metadata: row['metadata'] != null
          ? jsonDecode(row['metadata'] as String) as Map<String, dynamic>
          : null,
    );
  }
}

/// 缓存统计
class CacheStats {
  final int totalSections;
  final int validSections;
  final int expiredSections;
  final int totalBytes;
  final Map<PromptSectionType, int> byType;

  const CacheStats({
    required this.totalSections,
    required this.validSections,
    required this.expiredSections,
    required this.totalBytes,
    required this.byType,
  });

  @override
  String toString() =>
      'CacheStats(total: $totalSections, valid: $validSections, '
      'expired: $expiredSections, bytes: $totalBytes, byType: $byType)';
}
