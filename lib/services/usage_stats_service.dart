import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/provider_usage.dart';

/// 持久化 Provider 用量统计 — 基于 SharedPreferences
class UsageStatsService {
  static const _key = 'provider_usage_stats';

  /// 加载所有 provider 的用量统计
  Future<Map<String, ProviderUsage>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return {};

    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      final map = <String, ProviderUsage>{};
      for (final item in decoded) {
        final usage =
            ProviderUsage.fromJson(item as Map<String, dynamic>);
        map[usage.providerId] = usage;
      }
      return map;
    } catch (e) {
      debugPrint('[UsageStatsService] 加载失败: $e');
      return {};
    }
  }

  /// 保存所有 provider 的用量统计
  Future<void> saveAll(Map<String, ProviderUsage> stats) async {
    final prefs = await SharedPreferences.getInstance();
    final list = stats.values.map((u) => u.toJson()).toList();
    await prefs.setString(_key, jsonEncode(list));
  }

  /// 记录一次调用
  Future<Map<String, ProviderUsage>> recordUsage({
    required String providerId,
    required String providerName,
    int promptTokens = 0,
    int completionTokens = 0,
  }) async {
    final stats = await loadAll();
    final existing = stats[providerId] ??
        ProviderUsage(
          providerId: providerId,
          providerName: providerName,
        );
    stats[providerId] = existing.copyWith(
      totalPromptTokens: existing.totalPromptTokens + promptTokens,
      totalCompletionTokens: existing.totalCompletionTokens + completionTokens,
      totalRequests: existing.totalRequests + 1,
    );
    await saveAll(stats);
    return stats;
  }

  /// 记录缓存命中（仅更新缓存计数，不影响 totalRequests）
  Future<Map<String, ProviderUsage>> recordCacheHit({
    required String providerId,
    required String providerName,
  }) async {
    final stats = await loadAll();
    final existing = stats[providerId] ??
        ProviderUsage(
          providerId: providerId,
          providerName: providerName,
        );
    stats[providerId] = existing.copyWith(
      cacheHitCount: existing.cacheHitCount + 1,
    );
    await saveAll(stats);
    return stats;
  }

  /// 记录缓存未命中（仅更新缓存计数，不影响 totalRequests）
  Future<Map<String, ProviderUsage>> recordCacheMiss({
    required String providerId,
    required String providerName,
  }) async {
    final stats = await loadAll();
    final existing = stats[providerId] ??
        ProviderUsage(
          providerId: providerId,
          providerName: providerName,
        );
    stats[providerId] = existing.copyWith(
      cacheMissCount: existing.cacheMissCount + 1,
    );
    await saveAll(stats);
    return stats;
  }

  /// 重置所有统计
  Future<void> resetAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
