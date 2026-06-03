import 'dart:math';

import '../models/memory_entry.dart';
import '../services/memory_service.dart';
import 'simhash.dart';

/// 检索结果 — 包含记忆条目和综合评分
class ScoredMemory {
  final MemoryEntry entry;
  final double score;
  final double simSimilarity;
  final double importance;
  final double recency;

  const ScoredMemory({
    required this.entry,
    required this.score,
    required this.simSimilarity,
    required this.importance,
    required this.recency,
  });

  @override
  String toString() =>
      'ScoredMemory(${entry.id}, score=$score, sim=$simSimilarity, '
      'imp=$importance, rec=$recency)';
}

/// 记忆检索器 — 基于 SimHash 分桶 + 汉明距离 + 综合评分
///
/// 检索流程：
/// ```
/// 当前用户输入
///   ↓ 计算 SimHash
///   ↓ 取前 16 位定位桶
///   ↓ SQL 查询桶内条目
///   ↓ 桶内逐条计算汉明距离
///   ↓ 综合评分：score = α×simSimilarity + β×importance + γ×recency
///   ↓ 取 Top-K
/// ```
class MemoryRetriever {
  final MemoryService _service;

  /// 加权系数
  final double alpha; // simSimilarity 权重
  final double beta; // importance 权重
  final double gamma; // recency 权重

  /// 最大返回条数
  final int topK;

  /// 全桶检索阈值：当桶内条目数小于此值时，扩展到相邻桶
  final int minBucketSize;

  /// 是否需要扩展桶的范围(低量时)
  final int expandBits;

  /// 上次检索缓存（防止同一查询重复检索）
  String? _lastQueryHash;
  List<ScoredMemory>? _lastResults;

  MemoryRetriever({
    required MemoryService service,
    this.alpha = 0.5,
    this.beta = 0.3,
    this.gamma = 0.2,
    this.topK = 5,
    this.minBucketSize = 3,
    this.expandBits = 8,
  }) : _service = service;

  /// 根据用户输入检索相关记忆
  ///
  /// [queryText] 当前用户输入文本
  /// [excludeConversationId] 排除的对话 ID（可选，避免当前对话的记忆干扰）
  Future<List<ScoredMemory>> search(
    String queryText, {
    String? excludeConversationId,
  }) async {
    if (queryText.isEmpty) return [];

    // 计算查询的 SimHash
    final queryHash = SimHash.compute(queryText);

    // 缓存检查：相同 hash 直接返回缓存
    if (queryHash == _lastQueryHash && _lastResults != null) {
      return _lastResults!;
    }
    _lastQueryHash = queryHash;

    // 分桶检索
    var candidates = await _bucketSearch(queryHash);

    // 桶内条目太少，扩展检索
    if (candidates.length < minBucketSize) {
      final expanded = await _expandedBucketSearch(queryHash);
      // 合并去重
      final seen = candidates.map((e) => e.id).toSet();
      for (final e in expanded) {
        if (!seen.contains(e.id)) {
          candidates.add(e);
        }
      }
    }

    // 排除指定对话的记忆
    if (excludeConversationId != null) {
      candidates.removeWhere((e) => e.conversationId == excludeConversationId);
    }

    // 计算综合评分
    final now = DateTime.now();
    final scored = <ScoredMemory>[];

    for (final entry in candidates) {
      final distance = SimHash.hammingDistance(queryHash, entry.hash);
      final simSimilarity = 1.0 - (distance / SimHash.dimensions);

      // recency：一周半衰期
      final hoursSinceAccess = now
          .difference(entry.lastAccessed)
          .inHours
          .clamp(0, 8760);
      final recency = 1.0 / (1.0 + hoursSinceAccess / 168.0);

      final score =
          alpha * simSimilarity + beta * entry.importance + gamma * recency;

      scored.add(
        ScoredMemory(
          entry: entry,
          score: score,
          simSimilarity: simSimilarity,
          importance: entry.importance,
          recency: recency,
        ),
      );
    }

    // 按评分降序排序，取 Top-K
    scored.sort((a, b) => b.score.compareTo(a.score));
    final results = scored.take(topK).toList();

    // 更新被检索条目的访问计数
    for (final r in results) {
      await _service.updateAccess(r.entry.id);
    }

    _lastResults = results;
    return results;
  }

  /// 16bit 分桶检索
  Future<List<MemoryEntry>> _bucketSearch(String queryHash) async {
    final prefix = SimHash.bucketPrefix(queryHash);
    return _service.getByBucketPrefix(prefix);
  }

  /// 扩展桶检索：使用更短的桶前缀（8bit）扩大搜索范围
  Future<List<MemoryEntry>> _expandedBucketSearch(String queryHash) async {
    final prefix = SimHash.bucketPrefix(queryHash, bits: expandBits);
    return _service.getByBucketPrefix(prefix);
  }

  /// 根据文本查找最相似的 Top-1 记忆（用于去重）
  ///
  /// 返回距离最近的记忆和距离值
  Future<(MemoryEntry?, int)> findClosest(String text) async {
    final hash = SimHash.compute(text);
    final candidates = await _bucketSearch(hash);

    if (candidates.isEmpty) {
      return (null, 128);
    }

    var best = candidates.first;
    var bestDist = SimHash.hammingDistance(hash, best.hash);

    for (var i = 1; i < candidates.length; i++) {
      final dist = SimHash.hammingDistance(hash, candidates[i].hash);
      if (dist < bestDist) {
        bestDist = dist;
        best = candidates[i];
      }
    }

    return (best, bestDist);
  }

  /// 清除检索缓存
  void clearCache() {
    _lastQueryHash = null;
    _lastResults = null;
  }
}
