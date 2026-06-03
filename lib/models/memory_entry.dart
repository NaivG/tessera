import 'memory_type.dart';

/// 记忆条目 — 记忆系统的核心数据模型
///
/// 每条记忆由 [content] 核心文本和 [hash]（128 位 SimHash 二进制字符串）唯一标识。
/// [importance] 和 [confidence] 共同决定记忆的权重和存留。
class MemoryEntry {
  /// UUID 主键
  final String id;

  /// 记忆类型
  final MemoryType type;

  /// 核心内容文本
  final String content;

  /// 128 位 SimHash 二进制字符串（如 "0110...1011"）
  final String hash;

  /// 重要性评分 0.0 ~ 1.0，越高越重要
  final double importance;

  /// 置信度 0.0 ~ 1.0（被印证次数 / 总引用次数）
  final double confidence;

  /// 关联的对话 ID（conversational 类型必填）
  final String? conversationId;

  /// 来源消息 ID（可追溯）
  final String? sourceMessageId;

  /// 被检索次数
  final int accessCount;

  /// 创建时间
  final DateTime createdAt;

  /// 更新时间
  final DateTime updatedAt;

  /// 最后访问时间
  final DateTime lastAccessed;

  const MemoryEntry({
    required this.id,
    required this.type,
    required this.content,
    required this.hash,
    this.importance = 0.5,
    this.confidence = 0.5,
    this.conversationId,
    this.sourceMessageId,
    this.accessCount = 0,
    required this.createdAt,
    required this.updatedAt,
    required this.lastAccessed,
  });

  /// 创建一条新的记忆条目（自动填充时间戳）
  factory MemoryEntry.create({
    required String id,
    required MemoryType type,
    required String content,
    required String hash,
    double importance = 0.5,
    double confidence = 0.5,
    String? conversationId,
    String? sourceMessageId,
  }) {
    final now = DateTime.now();
    return MemoryEntry(
      id: id,
      type: type,
      content: content,
      hash: hash,
      importance: importance,
      confidence: confidence,
      conversationId: conversationId,
      sourceMessageId: sourceMessageId,
      accessCount: 0,
      createdAt: now,
      updatedAt: now,
      lastAccessed: now,
    );
  }

  /// 从数据库行创建
  factory MemoryEntry.fromDb(Map<String, dynamic> row) {
    return MemoryEntry(
      id: row['id'] as String,
      type: memoryTypeFromName(row['type'] as String),
      content: row['content'] as String,
      hash: row['hash'] as String,
      importance: (row['importance'] as num).toDouble(),
      confidence: (row['confidence'] as num).toDouble(),
      conversationId: row['conversation_id'] as String?,
      sourceMessageId: row['source_message_id'] as String?,
      accessCount: (row['access_count'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
      lastAccessed: DateTime.parse(row['last_accessed'] as String),
    );
  }

  /// 转换为数据库 Map
  Map<String, dynamic> toDb() {
    return {
      'id': id,
      'type': type.name,
      'content': content,
      'hash': hash,
      'importance': importance,
      'confidence': confidence,
      'conversation_id': conversationId,
      'source_message_id': sourceMessageId,
      'access_count': accessCount,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'last_accessed': lastAccessed.toIso8601String(),
    };
  }

  /// 复制并更新字段
  MemoryEntry copyWith({
    String? id,
    MemoryType? type,
    String? content,
    String? hash,
    double? importance,
    double? confidence,
    String? conversationId,
    String? sourceMessageId,
    int? accessCount,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? lastAccessed,
  }) {
    return MemoryEntry(
      id: id ?? this.id,
      type: type ?? this.type,
      content: content ?? this.content,
      hash: hash ?? this.hash,
      importance: importance ?? this.importance,
      confidence: confidence ?? this.confidence,
      conversationId: conversationId ?? this.conversationId,
      sourceMessageId: sourceMessageId ?? this.sourceMessageId,
      accessCount: accessCount ?? this.accessCount,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastAccessed: lastAccessed ?? this.lastAccessed,
    );
  }

  @override
  String toString() =>
      'MemoryEntry(id: $id, type: ${type.name}, importance: $importance, '
      'confidence: $confidence, content: "${content.length > 60 ? '${content.substring(0, 60)}...' : content}")';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is MemoryEntry && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
