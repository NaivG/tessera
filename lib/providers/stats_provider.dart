import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/provider_usage.dart';
import '../services/usage_stats_service.dart';

/// Provider 用量统计状态
class StatsNotifier extends Notifier<Map<String, ProviderUsage>> {
  final UsageStatsService _service = UsageStatsService();

  @override
  Map<String, ProviderUsage> build() {
    _load();
    return {};
  }

  Future<void> _load() async {
    final stats = await _service.loadAll();
    state = stats;
  }

  /// 刷新统计（从持久化重新加载）
  Future<void> refresh() async {
    await _load();
  }

  /// 记录一次 provider 调用
  Future<void> recordUsage({
    required String providerId,
    required String providerName,
    int promptTokens = 0,
    int completionTokens = 0,
  }) async {
    final stats = await _service.recordUsage(
      providerId: providerId,
      providerName: providerName,
      promptTokens: promptTokens,
      completionTokens: completionTokens,
    );
    state = stats;
  }

  /// 记录缓存命中
  Future<void> recordCacheHit({
    required String providerId,
    required String providerName,
  }) async {
    final stats = await _service.recordCacheHit(
      providerId: providerId,
      providerName: providerName,
    );
    state = stats;
  }

  /// 记录缓存未命中
  Future<void> recordCacheMiss({
    required String providerId,
    required String providerName,
  }) async {
    final stats = await _service.recordCacheMiss(
      providerId: providerId,
      providerName: providerName,
    );
    state = stats;
  }

  /// 重置所有统计
  Future<void> resetStats() async {
    await _service.resetAll();
    state = {};
  }
}

final statsProvider = NotifierProvider<StatsNotifier, Map<String, ProviderUsage>>(
  StatsNotifier.new,
);
