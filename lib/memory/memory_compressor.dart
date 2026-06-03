import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../core/llm_provider.dart';
import '../models/llm_config.dart';
import '../models/message.dart';
import '../models/memory_entry.dart';
import '../models/memory_relation.dart';
import '../models/memory_type.dart';
import '../services/memory_service.dart';
import 'simhash.dart';

/// 记忆压缩器 — 聚类合并相似记忆
class MemoryCompressor {
  final MemoryService _service;
  static const _uuid = Uuid();

  final int clusterDistance;

  static const _mergePrompt = '''
你是一个信息精炼助手。请将以下多条相似记忆合并概括为一条精炼记忆。

要求：
1. 保留所有关键信息，不遗漏任何事实
2. 语言简洁精炼，去除冗余表述
3. 如果原始记忆较多，提炼最核心的内容
4. 只返回合并后的精炼文本，不要添加任何额外说明

原始记忆：
''';

  MemoryCompressor({
    required MemoryService service,
    this.clusterDistance = 10,
  }) : _service = service;

  /// 全局压缩：对所有记忆执行聚类和合并
  Future<Map<String, int>> compressAll({
    LlmProvider? provider,
    LlmConfig? config,
  }) async {
    final entries = await _service.getAllEntries();
    if (entries.isEmpty) return {'merged': 0, 'deleted': 0};

    final candidates = entries
        .where((e) => e.type != MemoryType.conversational)
        .toList();

    if (candidates.length < 2) return {'merged': 0, 'deleted': 0};

    final clusters = _cluster(candidates);
    debugPrint('[MemoryCompressor] 发现 ${clusters.length} 个聚类');

    int merged = 0;
    int deleted = 0;

    for (final cluster in clusters) {
      if (cluster.length < 2) continue;

      cluster.sort((a, b) => b.importance.compareTo(a.importance));
      final primary = cluster.first;
      final toMerge = cluster.sublist(1);

      if (provider != null && config != null) {
        final mergedContent = await _llmMerge(
          provider: provider,
          config: config,
          primary: primary,
          others: toMerge,
        );

        if (mergedContent != null) {
          final updated = primary.copyWith(
            content: mergedContent,
            confidence: cluster
                .map((e) => e.confidence)
                .reduce((a, b) => a > b ? a : b),
            importance: cluster
                .map((e) => e.importance)
                .reduce((a, b) => a > b ? a : b),
            updatedAt: DateTime.now(),
          );
          await _service.updateEntry(updated);
        }
      }

      for (final other in toMerge) {
        await _service.insertRelation(MemoryRelation.create(
          id: _uuid.v4(),
          sourceId: other.id,
          targetId: primary.id,
          relationType: MemoryRelation.mergedInto,
          weight: 1.0,
        ));
        merged++;
      }
    }

    final now = DateTime.now();
    final thirtyDaysAgo = now.subtract(const Duration(days: 30));
    for (final entry in entries) {
      if (entry.type == MemoryType.event &&
          entry.importance < 0.3 &&
          entry.updatedAt.isBefore(thirtyDaysAgo)) {
        await _service.deleteEntry(entry.id);
        deleted++;
      }
    }

    debugPrint('[MemoryCompressor] 压缩完成: merged=$merged, deleted=$deleted');
    return {'merged': merged, 'deleted': deleted};
  }

  /// 对指定对话的 conversational 类型记忆压缩
  Future<void> compressConversational(String convId, {
    LlmProvider? provider,
    LlmConfig? config,
  }) async {
    final entries = await _service.getByConversationId(convId);
    final convEntries = entries
        .where((e) => e.type == MemoryType.conversational)
        .toList();

    if (convEntries.length < 2) return;

    if (provider != null && config != null) {
      final merged = await _summaryMerge(provider, config, convEntries);
      if (merged != null) {
        final primary = convEntries.first;
        await _service.updateEntry(primary.copyWith(
          content: merged,
          updatedAt: DateTime.now(),
        ));
        for (var i = 1; i < convEntries.length; i++) {
          await _service.insertRelation(MemoryRelation.create(
            id: _uuid.v4(),
            sourceId: convEntries[i].id,
            targetId: primary.id,
            relationType: MemoryRelation.mergedInto,
          ));
        }
      }
    }
  }

  /// 简化 DBSCAN 聚类
  List<List<MemoryEntry>> _cluster(List<MemoryEntry> entries) {
    final visited = <String>{};
    final clusters = <List<MemoryEntry>>[];

    for (final entry in entries) {
      if (visited.contains(entry.id)) continue;
      visited.add(entry.id);

      final cluster = <MemoryEntry>[entry];
      final queue = <MemoryEntry>[entry];

      while (queue.isNotEmpty) {
        final current = queue.removeAt(0);
        for (final other in entries) {
          if (visited.contains(other.id)) continue;
          final dist = SimHash.hammingDistance(current.hash, other.hash);
          if (dist <= clusterDistance) {
            visited.add(other.id);
            cluster.add(other);
            queue.add(other);
          }
        }
      }

      clusters.add(cluster);
    }

    return clusters;
  }

  /// LLM 合并多条记忆为一条
  Future<String?> _llmMerge({
    required LlmProvider provider,
    required LlmConfig config,
    required MemoryEntry primary,
    required List<MemoryEntry> others,
  }) async {
    final sb = StringBuffer();
    sb.writeln('主记忆: ${primary.content}');
    for (final e in others) {
      sb.writeln('- ${e.content}');
    }

    final history = <Message>[
      Message(
        id: 'merge-1',
        role: MessageRole.user,
        content: '$_mergePrompt\n\n${sb.toString()}',
        status: MessageStatus.completed,
        timestamp: DateTime.now(),
      ),
    ];

    try {
      final response = await provider.chat(
        config: config,
        history: history,
        systemPrompt: '你是一个信息精炼助手。只返回合并后的精炼文本。',
      );
      return response.content.trim().isNotEmpty ? response.content.trim() : null;
    } catch (e) {
      debugPrint('[MemoryCompressor] LLM 合并失败: $e');
      return null;
    }
  }

  /// LLM 摘要合并 conversational 记忆
  Future<String?> _summaryMerge(
    LlmProvider provider,
    LlmConfig config,
    List<MemoryEntry> entries,
  ) async {
    final sb = StringBuffer();
    sb.writeln('请将以下对话阶段摘要合并为一段连贯的摘要：');
    for (final e in entries) {
      sb.writeln('- [摘要] ${e.content}');
    }

    final history = <Message>[
      Message(
        id: 'summary-merge-1',
        role: MessageRole.user,
        content: sb.toString(),
        status: MessageStatus.completed,
        timestamp: DateTime.now(),
      ),
    ];

    try {
      final response = await provider.chat(
        config: config,
        history: history,
        systemPrompt: '你是一个信息精炼助手。请合并以下摘要为一段精炼连贯的对话摘要。只返回摘要文本。',
      );
      return response.content.trim().isNotEmpty ? response.content.trim() : null;
    } catch (e) {
      debugPrint('[MemoryCompressor] 摘要合并失败: $e');
      return null;
    }
  }
}
