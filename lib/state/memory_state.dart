import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/memory_entry.dart';
import '../models/memory_extraction.dart';
import '../models/memory_relation.dart';
import '../models/memory_type.dart';
import '../memory/simhash.dart';
import '../memory/memory_retriever.dart';
import '../services/memory_service.dart';

/// 记忆状态管理 — ChangeNotifier，供 UI 层使用
///
/// 管理：
/// - 最近检索结果缓存
/// - 当前对话的记忆 ID 跟踪
/// - 记忆统计信息
/// - 提取/检索触发协调
class MemoryState extends ChangeNotifier {
  final MemoryService _service;

  /// 公开 MemoryService 实例
  MemoryService get service => _service;

  late final MemoryRetriever _retriever;

  static const _uuid = Uuid();

  /// 最近一次检索结果
  List<ScoredMemory> _lastSearchResults = [];
  List<ScoredMemory> get lastSearchResults => List.unmodifiable(_lastSearchResults);

  /// 记忆总数
  int _totalEntries = 0;
  int get totalEntries => _totalEntries;

  /// 按类型统计
  Map<String, int> _typeCounts = {};
  Map<String, int> get typeCounts => Map.unmodifiable(_typeCounts);

  /// 当前对话关联的记忆 ID 列表
  final List<String> _currentConversationMemoryIds = [];
  List<String> get currentConversationMemoryIds =>
      List.unmodifiable(_currentConversationMemoryIds);

  /// 是否已初始化
  bool _initialized = false;
  bool get isInitialized => _initialized;

  MemoryState({MemoryService? service})
      : _service = service ?? MemoryService() {
    _retriever = MemoryRetriever(service: _service);
  }

  /// 初始化：确保 SimHash 分词器就绪，加载统计
  Future<void> init() async {
    if (_initialized) return;
    await SimHash.init();
    await _refreshStats();
    _initialized = true;
    debugPrint('[MemoryState] 初始化完成，总记忆数: $_totalEntries');
  }

  /// 刷新统计信息
  Future<void> _refreshStats() async {
    _totalEntries = await _service.getEntryCount();
    // 按类型统计（内存中维护）
    final all = await _service.getAllEntries();
    _typeCounts = {};
    for (final entry in all) {
      final key = entry.type.name;
      _typeCounts[key] = (_typeCounts[key] ?? 0) + 1;
    }
    notifyListeners();
  }

  // ── 检索 ──

  /// 检索相关记忆
  Future<List<ScoredMemory>> search(
    String queryText, {
    String? excludeConversationId,
  }) async {
    _lastSearchResults = await _retriever.search(
      queryText,
      excludeConversationId: excludeConversationId,
    );
    notifyListeners();
    return _lastSearchResults;
  }

  /// 获取最近检索的结果
  Future<List<ScoredMemory>> getRecentMemories({
    String? excludeConversationId,
    int limit = 5,
  }) async {
    final all = await _service.getAllEntries();
    final now = DateTime.now();
    final candidates = all.where((e) {
      if (excludeConversationId != null &&
          e.conversationId == excludeConversationId) {
        return false;
      }
      return true;
    }).toList();

    // 按 importance × recency 排序
    candidates.sort((a, b) {
      final scoreA = a.importance *
          (1.0 / (1.0 + now.difference(a.lastAccessed).inHours / 168.0));
      final scoreB = b.importance *
          (1.0 / (1.0 + now.difference(b.lastAccessed).inHours / 168.0));
      return scoreB.compareTo(scoreA);
    });

    return candidates.take(limit).map((e) => ScoredMemory(
      entry: e,
      score: e.importance,
      simSimilarity: 0,
      importance: e.importance,
      recency: 1.0 /
          (1.0 + now.difference(e.lastAccessed).inHours / 168.0),
    )).toList();
  }

  // ── 记忆写入 ──

  /// 从提取结果创建并存储记忆条目（含去重）
  ///
  /// [conversationId] 当前对话 ID
  /// [sourceMessageId] 来源消息 ID
  /// 返回实际插入的条目数量（去重后可能有减少）
  Future<int> insertExtractions(
    List<MemoryExtraction> extractions, {
    String? conversationId,
    String? sourceMessageId,
  }) async {
    int inserted = 0;

    for (final extraction in extractions) {
      final hash = SimHash.compute(extraction.content);

      // 去重：查找桶内最相似记忆
      final (closest, distance) = await _retriever.findClosest(extraction.content);

      if (closest != null && distance <= 8) {
        // 同一记忆：提升 confidence，更新时间
        final updated = closest.copyWith(
          confidence: (closest.confidence * 0.7 + 0.3).clamp(0.0, 1.0),
          importance: ((closest.importance + extraction.importance) / 2)
              .clamp(0.0, 1.0),
          updatedAt: DateTime.now(),
        );
        await _service.updateEntry(updated);
      } else if (closest != null && distance <= 16) {
        // 可能相关：创建关联
        final entry = MemoryEntry.create(
          id: _uuid.v4(),
          type: extraction.type,
          content: extraction.content,
          hash: hash,
          importance: extraction.importance,
          conversationId: conversationId,
          sourceMessageId: sourceMessageId,
        );
        await _service.insertEntry(entry);
        await _service.insertRelation(MemoryRelation.create(
          id: _uuid.v4(),
          sourceId: entry.id,
          targetId: closest.id,
          relationType: MemoryRelation.supports,
          weight: 1.0 - distance / 16.0,
        ));
        inserted++;
      } else {
        // 独立新记忆
        final entry = MemoryEntry.create(
          id: _uuid.v4(),
          type: extraction.type,
          content: extraction.content,
          hash: hash,
          importance: extraction.importance,
          conversationId: conversationId,
          sourceMessageId: sourceMessageId,
        );
        await _service.insertEntry(entry);
        inserted++;
      }
    }

    await _refreshStats();
    return inserted;
  }

  /// 手动创建一条长期记忆
  Future<MemoryEntry> createLongTermMemory(
    String content, {
    double importance = 0.8,
    double confidence = 1.0,
  }) async {
    final hash = SimHash.compute(content);
    final entry = MemoryEntry.create(
      id: _uuid.v4(),
      type: MemoryType.longTerm,
      content: content,
      hash: hash,
      importance: importance,
      confidence: confidence,
    );
    await _service.insertEntry(entry);
    await _refreshStats();
    return entry;
  }

  /// 更新记忆（用户编辑）
  Future<void> updateMemory(MemoryEntry entry) async {
    final updated = entry.copyWith(updatedAt: DateTime.now());
    await _service.updateEntry(updated);
    await _refreshStats();
  }

  /// 删除记忆
  Future<void> deleteMemory(String id) async {
    await _service.deleteEntry(id);
    await _refreshStats();
  }

  // ── 对话管理 ──

  /// 标记当前对话开始
  void beginConversation(String convId) {
    _currentConversationMemoryIds.clear();
  }

  /// 添加记忆到当前对话跟踪列表
  void trackMemoryForConversation(String memoryId) {
    if (!_currentConversationMemoryIds.contains(memoryId)) {
      _currentConversationMemoryIds.add(memoryId);
    }
  }

  /// 清理当前对话的 conversational 类型记忆
  Future<void> endConversation(String convId) async {
    // 删除 conversational 类型记忆
    final convMemories = await _service.getByConversationId(convId);
    for (final entry in convMemories) {
      if (entry.type == MemoryType.conversational) {
        await _service.deleteEntry(entry.id);
      }
    }
    _currentConversationMemoryIds.clear();
    await _refreshStats();
  }

  /// 将 conversational 记忆提升为长期记忆（用户确认）
  Future<void> promoteToLongTerm(List<String> memoryIds) async {
    for (final id in memoryIds) {
      final entry = await _service.getEntry(id);
      if (entry != null) {
        final promoted = entry.copyWith(
          type: MemoryType.longTerm,
          confidence: 1.0,
          updatedAt: DateTime.now(),
        );
        await _service.updateEntry(promoted);
      }
    }
    await _refreshStats();
  }

  // ── 查询 ──

  /// 获取所有记忆
  Future<List<MemoryEntry>> getAllMemories() async {
    return _service.getAllEntries();
  }

  /// 按类型获取记忆
  Future<List<MemoryEntry>> getMemoriesByType(MemoryType type) async {
    return _service.getByType(type.name);
  }

  /// 获取可注入上下文的记忆文本（用于 System Prompt 的 Memory Context 块）
  ///
  /// 将检索结果格式化为短文本，控制在 ~800 tokens 内。
  String formatMemoryContext(List<ScoredMemory> memories) {
    if (memories.isEmpty) return '';

    final sb = StringBuffer();
    sb.writeln('--- BEGIN MEMORY CONTEXT ---');
    sb.writeln('以下是从记忆系统中检索到的可能与当前对话相关的信息：');

    for (var i = 0; i < memories.length; i++) {
      final m = memories[i];
      sb.writeln('[${m.entry.type.name}] ${m.entry.content}');
    }

    sb.writeln('--- END MEMORY CONTEXT ---');
    return sb.toString();
  }

  /// 清除检索缓存
  void clearCache() {
    _retriever.clearCache();
  }

  @override
  void dispose() {
    _service.close();
    super.dispose();
  }
}
