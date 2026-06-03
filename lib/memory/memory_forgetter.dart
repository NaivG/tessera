import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/memory_entry.dart';
import '../models/memory_type.dart';
import '../services/memory_service.dart';

/// 遗忘策略引擎
///
/// 遗忘不是简单删除，而是降权 + 归档：
///
/// ```
/// 遗忘评分 = importance × confidence × timeDecay × accessDecay
///
/// timeDecay = e^(-λt)    # λ = 0.01/天，约 70 天半衰期
/// accessDecay = e^(-μ × daysSinceLastAccess)   # μ = 0.05/天
/// ```
///
/// 当遗忘评分 < 阈值时，移入归档表（当前简化为直接删除，
/// 未来可扩展为 memory_archived 表）。
class MemoryForgetter {
  final MemoryService _service;

  /// 时间衰减系数 λ（每天）
  final double lambda;

  /// 访问衰减系数 μ（每天）
  final double mu;

  MemoryForgetter({
    required MemoryService service,
    this.lambda = 0.01,
    this.mu = 0.05,
  }) : _service = service;

  /// 对所有非 conversational 记忆执行遗忘评估
  ///
  /// 返回被遗忘（删除）的条目数量。
  Future<int> run() async {
    final entries = await _service.getAllEntries();
    final now = DateTime.now();
    int forgotten = 0;

    for (final entry in entries) {
      // conversational 类型不参与遗忘评分
      if (entry.type == MemoryType.conversational) continue;

      final daysSinceCreated =
          now.difference(entry.createdAt).inDays.clamp(0, 365000);
      final daysSinceAccess =
          now.difference(entry.lastAccessed).inDays.clamp(0, 365000);

      final timeDecay = exp(-lambda * daysSinceCreated);
      final accessDecay = exp(-mu * daysSinceAccess);

      final forgettingScore =
          entry.importance * entry.confidence * timeDecay * accessDecay;

      final threshold = entry.type.forgettingThreshold;

      if (forgettingScore < threshold) {
        debugPrint(
          '[MemoryForgetter] 遗忘: ${entry.id} '
          '(${entry.type.name}), score=$forgettingScore, threshold=$threshold',
        );
        await _service.deleteEntry(entry.id);
        forgotten++;
      }
    }

    if (forgotten > 0) {
      debugPrint('[MemoryForgetter] 共遗忘 $forgotten 条记忆');
    }
    return forgotten;
  }

  /// 计算遗忘评分（用于调试/展示）
  static double calculateForgettingScore(
    MemoryEntry entry, {
    double lambda = 0.01,
    double mu = 0.05,
  }) {
    final now = DateTime.now();
    final daysSinceCreated =
        now.difference(entry.createdAt).inDays.clamp(0, 365000);
    final daysSinceAccess =
        now.difference(entry.lastAccessed).inDays.clamp(0, 365000);

    final timeDecay = exp(-lambda * daysSinceCreated);
    final accessDecay = exp(-mu * daysSinceAccess);

    return entry.importance * entry.confidence * timeDecay * accessDecay;
  }
}
