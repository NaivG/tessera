import 'conversation_mode.dart';
import 'llm_config.dart';
import 'message.dart';
import 'session.dart';

/// 对话
class Conversation {
  final String id;
  String title;
  final List<Message> messages;
  final LlmConfig config;
  final String? systemPrompt;
  final DateTime createdAt;
  DateTime updatedAt;

  /// 对话模式（默认 normal，向后兼容）
  final ConversationMode mode;

  /// 当前正在查看的 Session ID（默认为主 Session ID）
  String? activeSessionId;

  /// 该对话下的所有 Session（懒加载，默认空列表）
  final List<Session> sessions;

  Conversation({
    required this.id,
    required this.title,
    List<Message>? messages,
    required this.config,
    this.systemPrompt,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.mode = ConversationMode.normal,
    this.activeSessionId,
    List<Session>? sessions,
  }) : messages = messages ?? [],
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now(),
       sessions = sessions ?? [];

  /// 添加消息并更新时间戳
  void addMessage(Message message) {
    messages.add(message);
    updatedAt = DateTime.now();
  }

  /// 更新最后一条消息（用于流式更新）
  void updateLastMessage(Message message) {
    if (messages.isNotEmpty) {
      messages[messages.length - 1] = message;
    }
    updatedAt = DateTime.now();
  }

  /// 移除最后一条消息
  void removeLastMessage() {
    if (messages.isNotEmpty) {
      messages.removeLast();
    }
    updatedAt = DateTime.now();
  }

  /// 复制
  Conversation copyWith({
    String? id,
    String? title,
    List<Message>? messages,
    LlmConfig? config,
    String? systemPrompt,
    DateTime? createdAt,
    DateTime? updatedAt,
    ConversationMode? mode,
    String? activeSessionId,
    List<Session>? sessions,
  }) {
    return Conversation(
      id: id ?? this.id,
      title: title ?? this.title,
      messages: messages ?? List<Message>.from(this.messages),
      config: config ?? this.config,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      mode: mode ?? this.mode,
      activeSessionId: activeSessionId ?? this.activeSessionId,
      sessions: sessions ?? List<Session>.from(this.sessions),
    );
  }

  /// 从 JSON 反序列化
  factory Conversation.fromJson(Map<String, dynamic> json) {
    return Conversation(
      id: json['id'] as String,
      title: json['title'] as String,
      messages:
          (json['messages'] as List<dynamic>?)
              ?.map((e) => Message.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      config: LlmConfig.fromJson(json['config'] as Map<String, dynamic>),
      systemPrompt: json['system_prompt'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      mode: json['mode'] != null
          ? ConversationMode.fromName(json['mode'] as String)
          : ConversationMode.normal,
    );
  }

  /// 序列化为 JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'messages': messages.map((e) => e.toJson()).toList(),
      'config': config.toJson(),
      'system_prompt': systemPrompt,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'mode': mode.name,
    };
  }
}
