import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'cache_store.dart';
import 'prompt_section.dart';

/// 缓存管理器 — 协调分块的生命周期、组装和失效
///
/// [CacheManager] 是缓存系统的中央调度器，负责：
/// 1. 将上下文分解为 [PromptSection] 集合
/// 2. 通过哈希检测内容变更
/// 3. 协调客户端持久化与服务端缓存提示
/// 4. 在请求间复用不变的内容块
///
/// 使用示例：
/// ```dart
/// final manager = CacheManager();
///
/// // 构建上下文分块
/// final collection = PromptSectionCollection([
///   manager.buildPromptSection(systemPrompt),
///   manager.buildToolSection(toolDefs),
///   manager.buildHistorySection(messages),
/// ]);
///
/// // 检测变更
/// final changed = collection.diffChanged(manager.lastCollection);
///
/// // 通知 Provider 缓存策略
/// final cacheHint = manager.getCacheHint(collection);
/// ```
class CacheManager {
  final CacheStore _store = CacheStore();
  static const _uuid = Uuid();

  /// 上一次请求的分块集合（用于 diff 检测）
  PromptSectionCollection _lastCollection = PromptSectionCollection.empty;

  /// 从存储加载的持久化分块
  PromptSectionCollection? _cached;

  /// 是否已初始化
  bool _initialized = false;

  /// 获取上一次请求的分块集合
  PromptSectionCollection get lastCollection => _lastCollection;

  /// 获取已缓存的持久化分块
  PromptSectionCollection get cached => _cached ?? PromptSectionCollection.empty;

  // ═══════════════════════════════════════════════════════
  // 初始化
  // ═══════════════════════════════════════════════════════

  /// 初始化：从持久化存储加载缓存分块并清理过期条目
  Future<void> init() async {
    if (_initialized) return;

    final sections = await _store.getAllValid();
    _cached = PromptSectionCollection(sections);

    // 后台清理过期数据
    unawaited(_store.purgeExpired());

    _initialized = true;
    debugPrint(
      '[CacheManager] 初始化完成：${sections.length} 个有效分块',
    );
  }

  // ═══════════════════════════════════════════════════════
  // 分块构建
  // ═══════════════════════════════════════════════════════

  /// 构建系统提示分块
  ///
  /// 系统提示通常是高频复用内容，默认使用 [PromptCacheHint.highPriority]。
  PromptSection buildPromptSection(
    String systemPrompt, {
    String? id,
    int? ttlSeconds,
  }) {
    final sectionId = id ?? 'system_prompt';
    final cachedSection = _cached?.sections.where((s) => s.id == sectionId);

    // 如果内容未变且未过期，直接复用
    if (cachedSection != null && cachedSection.isNotEmpty) {
      final cached = cachedSection.first;
      if (!cached.isExpired &&
          cached.content == systemPrompt) {
        return cached;
      }
    }

    return PromptSection.create(
      id: sectionId,
      type: PromptSectionType.prompt,
      content: systemPrompt,
      cacheHint: PromptCacheHint.highPriority,
      ttlSeconds: ttlSeconds,
    );
  }

  /// 构建工具定义分块
  PromptSection buildToolSection(
    String toolDefsJson, {
    String? id,
    int? ttlSeconds,
  }) {
    final sectionId = id ?? 'tool_defs';
    final cachedSection = _cached?.sections.where((s) => s.id == sectionId);

    if (cachedSection != null && cachedSection.isNotEmpty) {
      final cached = cachedSection.first;
      if (!cached.isExpired && cached.content == toolDefsJson) {
        return cached;
      }
    }

    return PromptSection.create(
      id: sectionId,
      type: PromptSectionType.tool,
      content: toolDefsJson,
      cacheHint: PromptCacheHint.standard,
      ttlSeconds: ttlSeconds,
    );
  }

  /// 构建记忆分块
  PromptSection buildMemorySection(
    String memoryContent, {
    String? id,
    int? ttlSeconds,
  }) {
    return PromptSection.create(
      id: id ?? 'mem_${_uuid.v4().substring(0, 8)}',
      type: PromptSectionType.memory,
      content: memoryContent,
      cacheHint: PromptCacheHint.clientOnly,
      ttlSeconds: ttlSeconds ?? 3600, // 默认 1 小时
    );
  }

  /// 构建对话摘要分块
  PromptSection buildSummarySection(
    String summary, {
    String? id,
    int? ttlSeconds,
  }) {
    return PromptSection.create(
      id: id ?? 'summary_${_uuid.v4().substring(0, 8)}',
      type: PromptSectionType.summary,
      content: summary,
      cacheHint: PromptCacheHint.standard,
      ttlSeconds: ttlSeconds,
    );
  }

  /// 构建消息历史分块
  ///
  /// 消息历史通常不需要服务端缓存（内容频繁变化），
  /// 但长对话可考虑分段缓存旧消息。
  PromptSection buildHistorySection(
    String historyText, {
    String? id,
    bool cacheable = false,
    int? ttlSeconds,
  }) {
    return PromptSection.create(
      id: id ?? 'history_${_uuid.v4().substring(0, 8)}',
      type: PromptSectionType.history,
      content: historyText,
      cacheHint: cacheable
          ? PromptCacheHint.standard
          : PromptCacheHint.none,
      ttlSeconds: ttlSeconds,
    );
  }

  // ═══════════════════════════════════════════════════════
  // 变更检测
  // ═══════════════════════════════════════════════════════

  /// 检测与上次请求相比哪些分块发生了变化
  Set<String> detectChanged(PromptSectionCollection current) {
    return current.diffChanged(_lastCollection);
  }

  /// 记录当前分块集合为"上次请求状态"
  void commitCollection(PromptSectionCollection collection) {
    _lastCollection = collection.pruneExpired();
  }

  // ═══════════════════════════════════════════════════════
  // 持久化
  // ═══════════════════════════════════════════════════════

  /// 持久化需要客户端缓存的分块
  Future<void> persistCacheable(PromptSectionCollection collection) async {
    final toPersist = collection.clientCacheableSections;
    if (toPersist.isEmpty) return;

    await _store.saveSections(toPersist);

    // 更新内存缓存
    _cached = _cached?.merge(PromptSectionCollection(toPersist)) ??
        PromptSectionCollection(toPersist);

    debugPrint(
      '[CacheManager] 持久化 ${toPersist.length} 个分块',
    );
  }

  /// 恢复持久化的分块（已从缓存加载可以复用的内容）
  Future<PromptSectionCollection> restoreCached() async {
    final sections = await _store.getClientCacheable();
    debugPrint(
      '[CacheManager] 从持久化恢复 ${sections.length} 个客户端缓存分块',
    );
    return PromptSectionCollection(sections);
  }

  // ═══════════════════════════════════════════════════════
  // Provider 缓存提示
  // ═══════════════════════════════════════════════════════

  /// 获取当前集合中可复用的非变更分块列表
  ///
  /// 返回在上次请求中已存在且内容未变的分块，Provider 可以据此
  /// 决定哪些内容可以跳过发送（或标记为缓存命中）。
  List<PromptSection> getReusableSections(PromptSectionCollection current) {
    final changed = detectChanged(current);
    return current.sections
        .where((s) => !changed.contains(s.id) && s.cacheHint.cacheable)
        .toList();
  }

  /// 获取 Provider 需要的缓存提示信息
  ///
  /// 返回一个 Map，key 为分块 ID，value 为是否需要服务端缓存。
  /// 当分块内容未变化时，value 为 true（表示可命中缓存）。
  Map<String, PromptCacheHint> getCacheHints(
    PromptSectionCollection current,
  ) {
    final hints = <String, PromptCacheHint>{};

    for (final s in current.sections) {
      if (s.cacheHint.cacheable) {
        hints[s.id] = s.cacheHint;
      }
    }

    return hints;
  }

  // ═══════════════════════════════════════════════════════
  // 生命周期管理
  // ═══════════════════════════════════════════════════════

  /// 清理过期分块
  Future<int> purgeExpired() async {
    return _store.purgeExpired();
  }

  /// 重置当前会话的追踪状态（不清除持久化缓存）
  void resetSession() {
    _lastCollection = PromptSectionCollection.empty;
    debugPrint('[CacheManager] 会话追踪状态已重置');
  }

  /// 清空所有缓存（含持久化）
  Future<void> clearAll() async {
    await _store.clear();
    _cached = null;
    _lastCollection = PromptSectionCollection.empty;
    debugPrint('[CacheManager] 所有缓存已清空');
  }

  /// 获取缓存统计
  Future<CacheStats> getStats() async {
    return _store.getStats();
  }
}
