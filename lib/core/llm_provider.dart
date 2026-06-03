import '../models/llm_config.dart';
import '../models/message.dart';
import '../models/model_info.dart';
import '../models/stream_chunk.dart';
import '../models/tool.dart';

/// 抽象 LLM 提供商接口
///
/// 所有 LLM 提供商（OpenAI、Anthropic、Ollama、Google）都实现此接口，
/// 使上层业务逻辑与具体 SDK 解耦。
abstract class LlmProvider {
  /// 提供商标识，如 "openai"、"anthropic"、"ollama"、"google"
  String get providerId;

  /// 提供商显示名
  String get displayName;

  /// 获取可用模型列表（含模型类型、模态等元数据）
  Future<List<ModelInfo>> listAvailableModels({
    String? apiKey,
    String? baseUrl,
  });

  /// 获取单个模型详细信息
  Future<ModelInfo?> getModelInfo(
    String modelId, {
    String? apiKey,
    String? baseUrl,
  });

  /// 验证配置是否有效（如 API key 格式、网络连通性）
  Future<bool> validateConfig(LlmConfig config);

  /// 非流式聊天 — 发送消息并获取完整回复
  Future<Message> chat({
    required LlmConfig config,
    required List<Message> history,
    String? systemPrompt,
    List<ToolDefinition>? tools,
  });

  /// 流式聊天 — 发送消息并以 Stream 形式返回增量块
  ///
  /// 返回的 [StreamChunk] 可能包含：
  /// - [StreamChunkType.contentDelta] 文本增量
  /// - [StreamChunkType.thinkingDelta] 思考过程增量
  /// - [StreamChunkType.toolCall] 工具调用
  /// - [StreamChunkType.done] 流结束（含 token 用量）
  /// - [StreamChunkType.error] 错误
  Stream<StreamChunk> chatStream({
    required LlmConfig config,
    required List<Message> history,
    String? systemPrompt,
    List<ToolDefinition>? tools,
  });
}
