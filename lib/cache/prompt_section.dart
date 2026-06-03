import 'dart:convert';

import 'package:crypto/crypto.dart';

/// 客户端缓存系统 — 分块结构
///
/// [PromptSection] 是缓存系统的核心数据单元。它将 LLM 上下文分解为独立块，
/// 每个块有独立的内容、生命周期和缓存策略，为以下缓存类型提供统一复用基础：
///
/// - **Prompt Cache**：系统提示、指令模板
/// - **Tool Cache**：工具定义
/// - **Memory Cache**：上下文记忆片段
/// - **Summary Cache**：对话摘要
/// - **History Cache**：消息历史块

// ═══════════════════════════════════════════════════════════
// Section Type
// ═══════════════════════════════════════════════════════════

/// 分块类型枚举
///
/// 每个类型对应一种上下文用途，决定缓存策略和组装顺序。
enum PromptSectionType {
  /// 系统提示 / 指令块（通常放在上下文最前面）
  prompt,

  /// 工具定义块
  tool,

  /// 上下文记忆片段
  memory,

  /// 对话摘要块
  summary,

  /// 消息历史块（分段历史记录）
  history,

  /// 自定义块（用于扩展场景）
  custom,
}

/// 从字符串反序列化
PromptSectionType promptSectionTypeFromName(String name) {
  return PromptSectionType.values.firstWhere(
    (t) => t.name == name,
    orElse: () => PromptSectionType.custom,
  );
}

// ═══════════════════════════════════════════════════════════
// Cache Hint
// ═══════════════════════════════════════════════════════════

/// 缓存提示 — 通知 Provider 如何缓存该分块
///
/// 不同 LLM 提供商对缓存的实现方式不同：
/// - **Anthropic**：用 `cache_control: {"type": "ephemeral"}` 标记块
/// - **OpenAI**：自动缓存最近内容；部分模型支持手动断点标记
/// - **Google**：提供独立的 Context Cache API
/// - **Ollama**：本地部署，缓存由服务端控制
///
/// [PromptCacheHint] 作为跨提供商的抽象描述，由各 [LlmProvider] 适配层
/// 翻译为具体的 SDK 参数。
class PromptCacheHint {
  /// 是否建议服务端缓存此块
  final bool cacheable;

  /// 缓存 TTL（秒），null 表示使用默认值
  ///
  /// 不同提供商的默认 TTL 不同：
  /// - Anthropic: 5 分钟
  /// - OpenAI: 5-10 分钟（取决于负载）
  /// - Google: 由 Context Cache 配置控制
  final int? ttlSeconds;

  /// 优先级，数值越高越优先缓存。
  /// 当缓存预算有限时，低优先级块可能被跳过。
  final int priority;

  /// 客户端是否也需要本地缓存此块内容
  final bool clientCache;

  const PromptCacheHint({
    this.cacheable = false,
    this.ttlSeconds,
    this.priority = 0,
    this.clientCache = false,
  });

  /// 高优先级服务端缓存（适合系统提示、工具等频繁复用内容）
  static const highPriority = PromptCacheHint(
    cacheable: true,
    priority: 100,
    clientCache: true,
  );

  /// 标准服务端缓存
  static const standard = PromptCacheHint(
    cacheable: true,
    priority: 50,
    clientCache: true,
  );

  /// 仅客户端缓存
  static const clientOnly = PromptCacheHint(
    cacheable: false,
    clientCache: true,
  );

  /// 不缓存（每次请求重新计算）
  static const none = PromptCacheHint(
    cacheable: false,
    clientCache: false,
  );

  Map<String, dynamic> toJson() => {
        'cacheable': cacheable,
        'ttl_seconds': ttlSeconds,
        'priority': priority,
        'client_cache': clientCache,
      };

  factory PromptCacheHint.fromJson(Map<String, dynamic> json) {
    return PromptCacheHint(
      cacheable: json['cacheable'] as bool? ?? false,
      ttlSeconds: json['ttl_seconds'] as int?,
      priority: json['priority'] as int? ?? 0,
      clientCache: json['client_cache'] as bool? ?? false,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PromptCacheHint &&
      other.cacheable == cacheable &&
      other.ttlSeconds == ttlSeconds &&
      other.priority == priority &&
      other.clientCache == clientCache;

  @override
  int get hashCode => Object.hash(cacheable, ttlSeconds, priority, clientCache);

  @override
  String toString() =>
      'PromptCacheHint(cacheable: $cacheable, ttl: $ttlSeconds, '
      'priority: $priority, client: $clientCache)';
}

// ═══════════════════════════════════════════════════════════
// PromptSection
// ═══════════════════════════════════════════════════════════

/// 上下文分块 — 缓存系统的基本单元
///
/// 每个 [PromptSection] 代表 LLM 上下文中一段独立可替换的内容，
/// 通过 [contentHash] 实现内容变更检测和缓存失效。
class PromptSection {
  /// 唯一标识符
  final String id;

  /// 分块类型
  final PromptSectionType type;

  /// 块内容（文本）
  final String content;

  /// 内容 SHA-256 哈希，用于缓存失效检测
  final String contentHash;

  /// 创建时间
  final DateTime createdAt;

  /// 过期时间。null 表示永不过期（或由 [cacheHint.ttlSeconds] 控制）
  final DateTime? expiresAt;

  /// 缓存策略提示
  final PromptCacheHint cacheHint;

  /// 扩展元数据
  final Map<String, dynamic>? metadata;

  const PromptSection({
    required this.id,
    required this.type,
    required this.content,
    required this.contentHash,
    required this.createdAt,
    this.expiresAt,
    this.cacheHint = PromptCacheHint.none,
    this.metadata,
  });

  // ── 工厂构造函数 ──

  /// 从内容和类型创建分块（自动计算哈希）
  factory PromptSection.create({
    required String id,
    required PromptSectionType type,
    required String content,
    PromptCacheHint? cacheHint,
    int? ttlSeconds,
    Map<String, dynamic>? metadata,
  }) {
    final hint = cacheHint ?? _defaultCacheHint(type);
    final effectiveTtl = ttlSeconds ?? hint.ttlSeconds;

    return PromptSection(
      id: id,
      type: type,
      content: content,
      contentHash: _computeHash(content),
      createdAt: DateTime.now(),
      expiresAt: effectiveTtl != null
          ? DateTime.now().add(Duration(seconds: effectiveTtl))
          : null,
      cacheHint: hint,
      metadata: metadata,
    );
  }

  /// 从 JSON 反序列化
  factory PromptSection.fromJson(Map<String, dynamic> json) {
    return PromptSection(
      id: json['id'] as String,
      type: promptSectionTypeFromName(json['type'] as String? ?? 'custom'),
      content: json['content'] as String,
      contentHash: json['content_hash'] as String? ?? _computeHash(json['content'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
      expiresAt: json['expires_at'] != null
          ? DateTime.parse(json['expires_at'] as String)
          : null,
      cacheHint: json['cache_hint'] != null
          ? PromptCacheHint.fromJson(json['cache_hint'] as Map<String, dynamic>)
          : PromptCacheHint.none,
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }

  /// 序列化为 JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.name,
      'content': content,
      'content_hash': contentHash,
      'created_at': createdAt.toIso8601String(),
      if (expiresAt != null) 'expires_at': expiresAt!.toIso8601String(),
      'cache_hint': cacheHint.toJson(),
      if (metadata != null) 'metadata': metadata,
    };
  }

  // ── 辅助方法 ──

  /// 是否已过期
  bool get isExpired =>
      expiresAt != null && DateTime.now().isAfter(expiresAt!);

  /// 内容是否匹配给定哈希
  bool matchesHash(String hash) => contentHash == hash;

  /// 复制并修改部分字段
  PromptSection copyWith({
    String? id,
    PromptSectionType? type,
    String? content,
    String? contentHash,
    DateTime? createdAt,
    DateTime? expiresAt,
    PromptCacheHint? cacheHint,
    Map<String, dynamic>? metadata,
    bool recalculateHash = false,
  }) {
    final newContent = content ?? this.content;
    return PromptSection(
      id: id ?? this.id,
      type: type ?? this.type,
      content: newContent,
      contentHash: recalculateHash
          ? _computeHash(newContent)
          : (contentHash ?? this.contentHash),
      createdAt: createdAt ?? this.createdAt,
      expiresAt: expiresAt ?? this.expiresAt,
      cacheHint: cacheHint ?? this.cacheHint,
      metadata: metadata ?? this.metadata,
    );
  }

  /// 更新内容并重新计算哈希
  PromptSection updateContent(String newContent, {PromptCacheHint? cacheHint}) {
    return PromptSection(
      id: id,
      type: type,
      content: newContent,
      contentHash: _computeHash(newContent),
      createdAt: DateTime.now(),
      expiresAt: cacheHint?.ttlSeconds != null
          ? DateTime.now().add(Duration(seconds: cacheHint!.ttlSeconds!))
          : expiresAt,
      cacheHint: cacheHint ?? this.cacheHint,
      metadata: metadata,
    );
  }

  // ── 私有 ──

  /// 计算内容的 SHA-256 哈希
  static String _computeHash(String content) {
    final bytes = utf8.encode(content);
    return sha256.convert(bytes).toString();
  }

  /// 根据类型获取默认缓存策略
  static PromptCacheHint _defaultCacheHint(PromptSectionType type) {
    return switch (type) {
      PromptSectionType.prompt => PromptCacheHint.highPriority,
      PromptSectionType.tool => PromptCacheHint.standard,
      PromptSectionType.memory => PromptCacheHint.clientOnly,
      PromptSectionType.summary => PromptCacheHint.standard,
      PromptSectionType.history => PromptCacheHint.none,
      PromptSectionType.custom => PromptCacheHint.none,
    };
  }

  @override
  bool operator ==(Object other) =>
      other is PromptSection &&
      other.id == id &&
      other.contentHash == contentHash;

  @override
  int get hashCode => Object.hash(id, contentHash);

  @override
  String toString() =>
      'PromptSection(id: $id, type: ${type.name}, hash: '
      '${contentHash.substring(0, 8)}..., expires: $expiresAt)';
}

// ═══════════════════════════════════════════════════════════
// Section Collection
// ═══════════════════════════════════════════════════════════

/// 有序分块集合 — 按类型分组并维护组装顺序
///
/// 组装顺序（供 LLM Provider 构建最终 prompt 使用）：
/// 1. [PromptSectionType.prompt]    — 系统提示/指令
/// 2. [PromptSectionType.memory]    — 上下文记忆
/// 3. [PromptSectionType.summary]   — 对话摘要
/// 4. [PromptSectionType.tool]      — 工具定义
/// 5. [PromptSectionType.history]   — 消息历史
/// 6. [PromptSectionType.custom]    — 自定义
class PromptSectionCollection {
  final List<PromptSection> sections;

  const PromptSectionCollection(this.sections);

  /// 空集合
  static const empty = PromptSectionCollection([]);

  /// 按组装顺序排序
  List<PromptSection> get ordered {
    final sorted = List<PromptSection>.from(sections);
    sorted.sort((a, b) => _orderKey(a.type).compareTo(_orderKey(b.type)));
    return sorted;
  }

  /// 按类型筛选
  List<PromptSection> ofType(PromptSectionType type) {
    return sections.where((s) => s.type == type).toList();
  }

  /// 移除所有指定类型的分块
  PromptSectionCollection removeType(PromptSectionType type) {
    return PromptSectionCollection(
      sections.where((s) => s.type != type).toList(),
    );
  }

  /// 合并另一个集合（去重：同 id 保留较新的）
  PromptSectionCollection merge(PromptSectionCollection other) {
    final map = <String, PromptSection>{};
    for (final s in sections) {
      map[s.id] = s;
    }
    for (final s in other.sections) {
      final existing = map[s.id];
      if (existing == null || s.createdAt.isAfter(existing.createdAt)) {
        map[s.id] = s;
      }
    }
    return PromptSectionCollection(map.values.toList());
  }

  /// 移除过期的分块
  PromptSectionCollection pruneExpired() {
    return PromptSectionCollection(
      sections.where((s) => !s.isExpired).toList(),
    );
  }

  /// 需要服务端缓存的分块（按优先级降序）
  List<PromptSection> get cacheableSections {
    return sections
        .where((s) => s.cacheHint.cacheable && !s.isExpired)
        .toList()
      ..sort((a, b) => b.cacheHint.priority.compareTo(a.cacheHint.priority));
  }

  /// 需要客户端缓存的分块
  List<PromptSection> get clientCacheableSections {
    return sections
        .where((s) => s.cacheHint.clientCache && !s.isExpired)
        .toList();
  }

  /// 检测哪些分块相比给定集合发生了变化
  Set<String> diffChanged(PromptSectionCollection previous) {
    final prevMap = <String, String>{};
    for (final s in previous.sections) {
      prevMap[s.id] = s.contentHash;
    }

    final changed = <String>{};
    for (final s in sections) {
      final prevHash = prevMap[s.id];
      if (prevHash == null || prevHash != s.contentHash) {
        changed.add(s.id);
      }
    }
    return changed;
  }

  /// 组装为最终 prompt 文本
  String assemblePrompt() {
    final buffer = StringBuffer();
    for (final section in ordered) {
      buffer.writeln(section.content);
    }
    return buffer.toString().trimRight();
  }

  /// 是否为空
  bool get isEmpty => sections.isEmpty;

  /// 是否非空
  bool get isNotEmpty => sections.isNotEmpty;

  /// 分块数量
  int get length => sections.length;

  static int _orderKey(PromptSectionType type) {
    return switch (type) {
      PromptSectionType.prompt => 0,
      PromptSectionType.memory => 1,
      PromptSectionType.summary => 2,
      PromptSectionType.tool => 3,
      PromptSectionType.history => 4,
      PromptSectionType.custom => 5,
    };
  }

  @override
  String toString() =>
      'PromptSectionCollection(${sections.length} sections)';
}
