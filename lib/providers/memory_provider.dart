import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../memory/simhash.dart';
import '../memory/memory_retriever.dart';
import '../models/memory_entry.dart';
import '../models/memory_extraction.dart';
import '../models/memory_relation.dart';
import '../models/memory_type.dart';
import '../services/memory_service.dart';
import 'memory_service_provider.dart';

// =============================================================================
// 不可变数据类
// =============================================================================

class MemoryData {
  final List<ScoredMemory> lastSearchResults;
  final int totalEntries;
  final Map<String, int> typeCounts;
  final List<String> currentConversationMemoryIds;
  final bool initialized;

  const MemoryData({
    this.lastSearchResults = const [],
    this.totalEntries = 0,
    this.typeCounts = const {},
    this.currentConversationMemoryIds = const [],
    this.initialized = false,
  });

  MemoryData copyWith({
    List<ScoredMemory>? lastSearchResults,
    int? totalEntries,
    Map<String, int>? typeCounts,
    List<String>? currentConversationMemoryIds,
    bool? initialized,
  }) {
    return MemoryData(
      lastSearchResults: lastSearchResults ?? this.lastSearchResults,
      totalEntries: totalEntries ?? this.totalEntries,
      typeCounts: typeCounts ?? this.typeCounts,
      currentConversationMemoryIds:
          currentConversationMemoryIds ?? this.currentConversationMemoryIds,
      initialized: initialized ?? this.initialized,
    );
  }
}

// =============================================================================
// MemoryNotifier
// =============================================================================

/// 记忆状态 Notifier — 替代 [MemoryState] (ChangeNotifier)
class MemoryNotifier extends Notifier<MemoryData> {
  static const _uuid = Uuid();

  MemoryService get _service => ref.read(memoryServiceProvider);
  late final MemoryRetriever _retriever;

  @override
  MemoryData build() {
    _retriever = MemoryRetriever(service: _service);
    return const MemoryData();
  }

  // ── 初始化 ──

  /// 确保 SimHash 分词器就绪，加载统计
  Future<void> init() async {
    if (state.initialized) return;
    await SimHash.init();
    await _refreshStats();
    state = state.copyWith(initialized: true);
    debugPrint('[MemoryNotifier] 初始化完成，总记忆数: ${state.totalEntries}');
  }

  Future<void> _refreshStats() async {
    final totalEntries = await _service.getEntryCount();
    final all = await _service.getAllEntries();
    final typeCounts = <String, int>{};
    for (final entry in all) {
      final key = entry.type.name;
      typeCounts[key] = (typeCounts[key] ?? 0) + 1;
    }
    state = state.copyWith(totalEntries: totalEntries, typeCounts: typeCounts);
  }

  // ── 检索 ──

  Future<List<ScoredMemory>> search(
    String queryText, {
    String? excludeConversationId,
  }) async {
    final results = await _retriever.search(
      queryText,
      excludeConversationId: excludeConversationId,
    );
    state = state.copyWith(lastSearchResults: results);
    return results;
  }

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

    candidates.sort((a, b) {
      final scoreA = a.importance *
          (1.0 / (1.0 + now.difference(a.lastAccessed).inHours / 168.0));
      final scoreB = b.importance *
          (1.0 / (1.0 + now.difference(b.lastAccessed).inHours / 168.0));
      return scoreB.compareTo(scoreA);
    });

    return candidates
        .take(limit)
        .map(
          (e) => ScoredMemory(
            entry: e,
            score: e.importance,
            simSimilarity: 0,
            importance: e.importance,
            recency:
                1.0 / (1.0 + now.difference(e.lastAccessed).inHours / 168.0),
          ),
        )
        .toList();
  }

  // ── 记忆写入 ──

  Future<int> insertExtractions(
    List<MemoryExtraction> extractions, {
    String? conversationId,
    String? sourceMessageId,
  }) async {
    int inserted = 0;

    for (final extraction in extractions) {
      final hash = SimHash.compute(extraction.content);
      final (closest, distance) = await _retriever.findClosest(
        extraction.content,
      );

      if (closest != null && distance <= 8) {
        final updated = closest.copyWith(
          confidence: (closest.confidence * 0.7 + 0.3).clamp(0.0, 1.0),
          importance:
              ((closest.importance + extraction.importance) / 2).clamp(0.0, 1.0),
          updatedAt: DateTime.now(),
        );
        await _service.updateEntry(updated);
      } else if (closest != null && distance <= 16) {
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
        await _service.insertRelation(
          MemoryRelation.create(
            id: _uuid.v4(),
            sourceId: entry.id,
            targetId: closest.id,
            relationType: MemoryRelation.supports,
            weight: 1.0 - distance / 16.0,
          ),
        );
        inserted++;
      } else {
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

  Future<void> updateMemory(MemoryEntry entry) async {
    final updated = entry.copyWith(updatedAt: DateTime.now());
    await _service.updateEntry(updated);
    await _refreshStats();
  }

  Future<void> deleteMemory(String id) async {
    await _service.deleteEntry(id);
    await _refreshStats();
  }

  // ── 对话管理 ──

  void beginConversation(String convId) {
    state = state.copyWith(currentConversationMemoryIds: []);
  }

  void trackMemoryForConversation(String memoryId) {
    if (!state.currentConversationMemoryIds.contains(memoryId)) {
      state = state.copyWith(
        currentConversationMemoryIds: [
          ...state.currentConversationMemoryIds,
          memoryId,
        ],
      );
    }
  }

  Future<void> endConversation(String convId) async {
    final convMemories = await _service.getByConversationId(convId);
    for (final entry in convMemories) {
      if (entry.type == MemoryType.conversational) {
        await _service.deleteEntry(entry.id);
      }
    }
    state = state.copyWith(currentConversationMemoryIds: []);
    await _refreshStats();
  }

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

  Future<List<MemoryEntry>> getAllMemories() async {
    return _service.getAllEntries();
  }

  Future<List<MemoryEntry>> getMemoriesByType(MemoryType type) async {
    return _service.getByType(type.name);
  }

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

  void clearCache() {
    _retriever.clearCache();
  }
}

// =============================================================================
// Provider
// =============================================================================

final memoryProvider =
    NotifierProvider<MemoryNotifier, MemoryData>(MemoryNotifier.new);
