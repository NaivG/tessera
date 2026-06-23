import 'conversation_mode.dart';

/// Session 类型
enum SessionType {
  /// 主 Session（每个对话有且仅有一个）
  main,

  /// 子 Agent Session
  subAgent;

  static SessionType fromName(String name) {
    return SessionType.values.firstWhere(
      (t) => t.name == name,
      orElse: () => SessionType.main,
    );
  }
}

/// Session 状态
enum SessionStatus {
  /// 活跃（主 Session 默认状态）
  active,

  /// 运行中（子 Agent 正在执行）
  running,

  /// 已完成
  completed,

  /// 失败
  failed;

  static SessionStatus fromName(String name) {
    return SessionStatus.values.firstWhere(
      (s) => s.name == name,
      orElse: () => SessionStatus.active,
    );
  }
}

/// 会话（Session）— 对话内的独立执行上下文
class Session {
  final String id;

  /// 父对话 ID
  final String conversationId;

  /// 父 Session ID（子 Agent 才有，指向主 Session）
  final String? parentSessionId;

  /// Session 类型
  final SessionType type;

  /// 标题（子 Agent 为任务标题，主 Session 为对话标题）
  final String title;

  /// 对话模式（继承自对话）
  final ConversationMode mode;

  /// 状态
  final SessionStatus status;

  /// 排序序号
  final int sortOrder;

  final DateTime createdAt;
  final DateTime updatedAt;

  const Session({
    required this.id,
    required this.conversationId,
    this.parentSessionId,
    required this.type,
    required this.title,
    required this.mode,
    this.status = SessionStatus.active,
    this.sortOrder = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  Session copyWith({
    String? id,
    String? conversationId,
    String? parentSessionId,
    SessionType? type,
    String? title,
    ConversationMode? mode,
    SessionStatus? status,
    int? sortOrder,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Session(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      parentSessionId: parentSessionId ?? this.parentSessionId,
      type: type ?? this.type,
      title: title ?? this.title,
      mode: mode ?? this.mode,
      status: status ?? this.status,
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory Session.fromJson(Map<String, dynamic> json) {
    return Session(
      id: json['id'] as String,
      conversationId: json['conversation_id'] as String,
      parentSessionId: json['parent_session_id'] as String?,
      type: SessionType.fromName(json['type'] as String? ?? 'main'),
      title: json['title'] as String? ?? '',
      mode: ConversationMode.fromName(json['mode'] as String? ?? 'normal'),
      status: SessionStatus.fromName(json['status'] as String? ?? 'active'),
      sortOrder: json['sort_order'] as int? ?? 0,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'conversation_id': conversationId,
      'parent_session_id': parentSessionId,
      'type': type.name,
      'title': title,
      'mode': mode.name,
      'status': status.name,
      'sort_order': sortOrder,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}
