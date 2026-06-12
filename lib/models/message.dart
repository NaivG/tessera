import 'media_attachment.dart';
import 'stream_chunk.dart';

/// 消息角色
enum MessageRole { system, user, assistant, tool }

/// 消息状态
enum MessageStatus {
  /// 等待发送
  pending,

  /// 流式接收中
  streaming,

  /// 已完成
  completed,

  /// 发生错误
  error,
}

/// 单条对话消息
class Message {
  /// 原子性 ID 计数器，确保同一微秒内生成的 ID 也不重复
  static int _idCounter = 0;

  /// 生成全局唯一的消息/对话 ID
  /// 格式：微秒级时间戳 + 进程内自增计数器，保证唯一性
  static String generateId() {
    final ts = DateTime.now().microsecondsSinceEpoch;
    final seq = _idCounter++;
    return '$ts$seq';
  }

  final String id;
  final MessageRole role;
  final String content;
  final String? thinking;
  final List<ToolCall>? toolCalls;
  final String? toolCallId;
  final List<MediaAttachment>? mediaAttachments;

  /// 工具执行结果（运行时字段，不持久化）。
  ///
  /// Key 为 `ToolCall.id`，value 为工具返回的文本内容。
  final Map<String, String>? toolResults;

  /// 本次 LLM 调用的 token 用量（运行时字段，不持久化）。
  ///
  /// 由各 provider 在返回前从 SDK 响应中提取，传入统计系统。
  final TokenUsage? usage;

  final MessageStatus status;
  final String? errorMessage;
  final DateTime timestamp;

  const Message({
    required this.id,
    required this.role,
    this.content = '',
    this.thinking,
    this.toolCalls,
    this.toolCallId,
    this.mediaAttachments,
    this.toolResults,
    this.usage,
    this.status = MessageStatus.completed,
    this.errorMessage,
    required this.timestamp,
  });

  /// 创建一个流式接收中的 assistant 消息
  factory Message.streamingAssistant({required String id}) {
    return Message(
      id: id,
      role: MessageRole.assistant,
      status: MessageStatus.streaming,
      timestamp: DateTime.now(),
    );
  }

  /// 创建一个已完成的用户消息
  factory Message.user(String content) {
    return Message(
      id: generateId(),
      role: MessageRole.user,
      content: content,
      status: MessageStatus.completed,
      timestamp: DateTime.now(),
    );
  }

  /// 复制并修改部分字段
  Message copyWith({
    String? id,
    MessageRole? role,
    String? content,
    String? thinking,
    List<ToolCall>? toolCalls,
    String? toolCallId,
    List<MediaAttachment>? mediaAttachments,
    MessageStatus? status,
    String? errorMessage,
    Map<String, String>? toolResults,
    TokenUsage? usage,
    DateTime? timestamp,
    bool clearToolCalls = false,
    bool clearThinking = false,
    bool clearMediaAttachments = false,
  }) {
    return Message(
      id: id ?? this.id,
      role: role ?? this.role,
      content: content ?? this.content,
      thinking: clearThinking ? null : (thinking ?? this.thinking),
      toolCalls: clearToolCalls ? null : (toolCalls ?? this.toolCalls),
      toolCallId: toolCallId ?? this.toolCallId,
      mediaAttachments: clearMediaAttachments
          ? null
          : (mediaAttachments ?? this.mediaAttachments),
      toolResults: toolResults ?? this.toolResults,
      usage: usage ?? this.usage,
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  /// 从 JSON 反序列化
  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id'] as String,
      role: MessageRole.values.firstWhere((r) => r.name == json['role']),
      content: json['content'] as String? ?? '',
      thinking: json['thinking'] as String?,
      toolCalls: (json['tool_calls'] as List<dynamic>?)
          ?.map((e) => ToolCall.fromJson(e as Map<String, dynamic>))
          .toList(),
      toolCallId: json['tool_call_id'] as String?,
      mediaAttachments: (json['media_attachments'] as List<dynamic>?)
          ?.map((e) => MediaAttachment.fromJson(e as Map<String, dynamic>))
          .toList(),
      status: json['status'] != null
          ? MessageStatus.values.firstWhere((s) => s.name == json['status'])
          : MessageStatus.completed,
      errorMessage: json['error_message'] as String?,
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }

  /// 序列化为 JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'role': role.name,
      'content': content,
      if (thinking != null) 'thinking': thinking,
      'tool_calls': toolCalls?.map((e) => e.toJson()).toList(),
      'tool_call_id': toolCallId,
      if (mediaAttachments != null)
        'media_attachments': mediaAttachments!.map((e) => e.toJson()).toList(),
      'status': status.name,
      'error_message': errorMessage,
      'timestamp': timestamp.toIso8601String(),
    };
  }
}

/// 工具调用定义（在消息中使用）
class ToolCall {
  final String id;
  final String name;
  final Map<String, dynamic> arguments;

  const ToolCall({
    required this.id,
    required this.name,
    this.arguments = const {},
  });

  factory ToolCall.fromJson(Map<String, dynamic> json) {
    return ToolCall(
      id: json['id'] as String,
      name: json['name'] as String,
      arguments: (json['arguments'] is Map<String, dynamic>)
          ? json['arguments'] as Map<String, dynamic>
          : <String, dynamic>{},
    );
  }

  Map<String, dynamic> toJson() {
    return {'id': id, 'name': name, 'arguments': arguments};
  }
}
