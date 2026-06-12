import 'message.dart';

/// 流式响应的块类型
enum StreamChunkType {
  /// 文本增量
  contentDelta,

  /// 思考过程增量
  thinkingDelta,

  /// 工具调用
  toolCall,

  /// 流结束
  done,

  /// 错误
  error,
}

/// Token 用量信息
class TokenUsage {
  final int? promptTokens;
  final int? completionTokens;
  final int? totalTokens;

  const TokenUsage({
    this.promptTokens,
    this.completionTokens,
    this.totalTokens,
  });

  @override
  String toString() =>
      'TokenUsage(prompt: $promptTokens, completion: $completionTokens, total: $totalTokens)';
}

/// 流式响应中的一个数据块
class StreamChunk {
  final StreamChunkType type;

  /// 文本内容增量
  final String? contentDelta;

  /// 思考过程增量
  final String? thinkingDelta;

  /// 工具调用（可能是增量）
  final ToolCall? toolCall;

  /// 流结束时的用量信息
  final TokenUsage? usage;

  /// 错误信息
  final String? error;

  const StreamChunk({
    required this.type,
    this.contentDelta,
    this.thinkingDelta,
    this.toolCall,
    this.usage,
    this.error,
  });

  /// 创建文本增量块
  factory StreamChunk.content(String delta) {
    return StreamChunk(type: StreamChunkType.contentDelta, contentDelta: delta);
  }

  /// 创建思考增量块
  factory StreamChunk.thinking(String delta) {
    return StreamChunk(
      type: StreamChunkType.thinkingDelta,
      thinkingDelta: delta,
    );
  }

  /// 创建工具调用块
  factory StreamChunk.tool(ToolCall toolCall) {
    return StreamChunk(type: StreamChunkType.toolCall, toolCall: toolCall);
  }

  /// 创建流结束块
  factory StreamChunk.done({TokenUsage? usage}) {
    return StreamChunk(type: StreamChunkType.done, usage: usage);
  }

  /// 创建错误块
  factory StreamChunk.error(String message) {
    return StreamChunk(type: StreamChunkType.error, error: message);
  }
}
