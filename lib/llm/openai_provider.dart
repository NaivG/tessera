import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:openai_dart/openai_dart.dart' as openai;

import '../core/llm_provider.dart';
import '../models/llm_config.dart';
import '../models/message.dart';
import '../models/model_info.dart';
import '../models/stream_chunk.dart';
import '../models/tool.dart';
import '../services/media_library.dart';

/// OpenAI 提供商适配器
class OpenAiProvider extends LlmProvider {
  @override
  String get providerId => 'openai';

  @override
  String get displayName => 'OpenAI';

  openai.OpenAIClient _buildClient(LlmConfig config) {
    return openai.OpenAIClient.withApiKey(
      config.apiKey ?? '',
      baseUrl: config.baseUrl,
    );
  }

  @override
  Future<List<ModelInfo>> listAvailableModels({
    String? apiKey,
    String? baseUrl,
  }) async {
    final client = openai.OpenAIClient.withApiKey(
      apiKey ?? '',
      baseUrl: baseUrl,
    );
    try {
      final response = await client.models.list();
      return response.data
          .where((m) => m.id.isNotEmpty)
          .map(_openAiModelToModelInfo)
          .toList();
    } catch (_) {
      return [];
    }
  }

  @override
  Future<ModelInfo?> getModelInfo(
    String modelId, {
    String? apiKey,
    String? baseUrl,
  }) async {
    final client = openai.OpenAIClient.withApiKey(
      apiKey ?? '',
      baseUrl: baseUrl,
    );
    try {
      final model = await client.models.retrieve(modelId);
      return _openAiModelToModelInfo(model);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> validateConfig(LlmConfig config) async {
    try {
      final models = await listAvailableModels(
        apiKey: config.apiKey,
        baseUrl: config.baseUrl,
      );
      return models.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<Message> chat({
    required LlmConfig config,
    required List<Message> history,
    String? systemPrompt,
    List<ToolDefinition>? tools,
  }) async {
    final client = _buildClient(config);
    final request = _buildRequest(config, history, systemPrompt, tools);

    final response = await client.chat.completions.create(request);
    final choice = response.choices.first;

    return Message(
      id: response.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      role: MessageRole.assistant,
      content: choice.message.content ?? '',
      toolCalls: _mapToolCalls(choice.message.toolCalls),
      timestamp: DateTime.now(),
      status: MessageStatus.completed,
    );
  }

  @override
  Stream<StreamChunk> chatStream({
    required LlmConfig config,
    required List<Message> history,
    String? systemPrompt,
    List<ToolDefinition>? tools,
  }) async* {
    final client = _buildClient(config);
    final request = _buildRequest(config, history, systemPrompt, tools);

    final stream = client.chat.completions.createStream(request);

    // 累积工具调用信息
    final toolCallAccumulator = <int, _PartialToolCall>{};

    await for (final event in stream) {
      final choices = event.choices;
      if (choices == null || choices.isEmpty) continue;
      final delta = choices.first.delta;

      // 思考过程增量（DeepSeek reasoning_content / OpenRouter reasoning）
      final reasoningContent = delta.reasoningContent;
      if (reasoningContent != null && reasoningContent.isNotEmpty) {
        yield StreamChunk.thinking(reasoningContent);
      }
      final reasoning = delta.reasoning;
      if (reasoning != null && reasoning.isNotEmpty) {
        yield StreamChunk.thinking(reasoning);
      }

      // 文本增量
      final content = delta.content;
      if (content != null && content.isNotEmpty) {
        yield StreamChunk.content(content);
      }

      // 工具调用增量
      if (delta.toolCalls != null) {
        for (final tc in delta.toolCalls!) {
          final idx = tc.index;
          final entry = toolCallAccumulator.putIfAbsent(
            idx,
            () => _PartialToolCall(name: '', arguments: ''),
          );

          if (tc.id != null) entry.id = tc.id!;
          if (tc.function?.name != null) entry.name += tc.function!.name!;
          if (tc.function?.arguments != null) {
            entry.arguments += tc.function!.arguments!;
          }
          debugPrint('[OpenAI] chatStream tool delta: idx=$idx, id=${tc.id}, name=${tc.function?.name}, argsChunk=${tc.function?.arguments}');
        }
      }

      // 检查是否结束
      if (choices.first.finishReason != null) {
        break;
      }
    }

    // 输出累积的工具调用
    debugPrint('[OpenAI] chatStream tool accumulators: count=${toolCallAccumulator.length}');
    for (final entry in toolCallAccumulator.values) {
      debugPrint('[OpenAI] chatStream tool acc: id=${entry.id}, name=${entry.name}, rawArgs=${entry.arguments}');
      if (entry.name.isNotEmpty) {
        final args = _safeParseJson(entry.arguments);
        debugPrint('[OpenAI] chatStream yielding StreamChunk.tool: id=${entry.id}, name=${entry.name}, args=$args');
        yield StreamChunk.tool(
          ToolCall(id: entry.id, name: entry.name, arguments: args),
        );
      }
    }

    yield StreamChunk.done();
  }

  // --- 内部辅助 ---

  openai.ChatCompletionCreateRequest _buildRequest(
    LlmConfig config,
    List<Message> history,
    String? systemPrompt,
    List<ToolDefinition>? tools,
  ) {
    final messages = <openai.ChatMessage>[];

    // 系统提示
    if (systemPrompt != null && systemPrompt.isNotEmpty) {
      messages.add(openai.ChatMessage.system(systemPrompt));
    }

    // 历史消息
    for (final msg in history) {
      messages.add(_toOpenAiMessage(msg));
    }

    return openai.ChatCompletionCreateRequest(
      model: config.modelId,
      messages: messages,
      temperature: config.temperature,
      maxTokens: config.maxTokens,
      topP: config.topP,
      tools: tools
          ?.map(
            (t) => openai.Tool.function(
              name: t.name,
              description: t.description,
              parameters: t.parameters.isNotEmpty ? t.toParametersSchema() : null,
            ),
          )
          .toList(),
      // 深度思考：通过 OpenRouter/DeepSeek 兼容的 reasoning 参数启用
      openRouterReasoning: config.deepThinking
          ? openai.OpenRouterReasoning(enabled: true)
          : null,
    );
  }

  openai.ChatMessage _toOpenAiMessage(Message msg) {
    switch (msg.role) {
      case MessageRole.system:
        return openai.ChatMessage.system(msg.content);
      case MessageRole.user:
        return _toOpenAiUserMessage(msg);
      case MessageRole.assistant:
        return openai.ChatMessage.assistant(
          content: msg.content.isEmpty ? null : msg.content,
          toolCalls: msg.toolCalls
              ?.map(
                (tc) => openai.ToolCall(
                  id: tc.id,
                  type: 'function',
                  function: openai.FunctionCall(
                    name: tc.name,
                    arguments: jsonEncode(tc.arguments),
                  ),
                ),
              )
              .toList(),
        );
      case MessageRole.tool:
        return openai.ChatMessage.tool(
          toolCallId: msg.toolCallId ?? '',
          content: msg.content,
        );
    }
  }

  /// 构建带媒体附件的用户消息（支持图像 base64 内联）
  openai.ChatMessage _toOpenAiUserMessage(Message msg) {
    final attachments = msg.mediaAttachments;
    if (attachments == null || attachments.isEmpty) {
      return openai.ChatMessage.user(msg.content);
    }

    final parts = <openai.ContentPart>[];
    if (msg.content.isNotEmpty) {
      parts.add(openai.ContentPart.text(msg.content));
    }

    for (final attachment in attachments) {
      final filePath =
          MediaLibrary.instance.filePathFor(attachment.libraryId);
      if (filePath == null) continue;

      if (attachment.isImage) {
        try {
          final bytes = File(filePath).readAsBytesSync();
          final base64 = base64Encode(bytes);
          final mime = attachment.mimeType ?? 'image/png';
          parts.add(openai.ContentPart.imageBase64(data: base64, mediaType: mime));
        } catch (_) {
          // 图片读取失败，静默跳过
        }
      } else if (attachment.isAudio) {
        try {
          final bytes = File(filePath).readAsBytesSync();
          final base64 = base64Encode(bytes);
          parts.add(
            openai.ContentPart.inputAudio(
              data: base64,
              format: openai.AudioFormat.wav,
            ),
          );
        } catch (_) {
          // 音频读取失败，静默跳过
        }
      }
      // 视频和普通文件暂不支持直接内联，由预处理占位符处理
    }

    // 如果所有附件都处理失败，回退到纯文本
    if (parts.isEmpty) {
      return openai.ChatMessage.user(msg.content);
    }

    return openai.ChatMessage.user(parts);
  }

  List<ToolCall>? _mapToolCalls(List<openai.ToolCall>? toolCalls) {
    if (toolCalls == null || toolCalls.isEmpty) return null;
    debugPrint('[OpenAI] _mapToolCalls: count=${toolCalls.length}');
    for (final tc in toolCalls) {
      debugPrint('[OpenAI] _mapToolCalls: id=${tc.id}, name=${tc.function.name}, rawArgs=${tc.function.arguments}');
    }
    return toolCalls
        .map(
          (tc) => ToolCall(
            id: tc.id,
            name: tc.function.name,
            arguments: _safeParseJson(tc.function.arguments),
          ),
        )
        .toList();
  }

  Map<String, dynamic> _safeParseJson(String raw) {
    try {
      final result = jsonDecode(raw) as Map<String, dynamic>;
      debugPrint('[OpenAI] _safeParseJson: raw="$raw" → parsed keys=${result.keys.toList()}');
      return result;
    } catch (e) {
      debugPrint('[OpenAI] _safeParseJson FAILED: raw="$raw", error=$e');
      return {};
    }
  }

  /// 将 OpenAI SDK 的 Model 映射为项目 [ModelInfo]
  ModelInfo _openAiModelToModelInfo(openai.Model model) {
    final id = model.id;
    final type = _inferOpenAiModelType(id);
    final tags = _inferOpenAiModelTags(id);
    return ModelInfo(id: id, type: type, tags: tags);
  }

  /// 从模型 ID 推断 [ModelType]
  ModelType _inferOpenAiModelType(String id) {
    final lower = id.toLowerCase();
    if (lower.startsWith('dall-e') || lower.contains('image')) {
      return ModelType.image;
    }
    if (lower.startsWith('whisper') ||
        lower.startsWith('tts') ||
        lower.contains('speech')) {
      return ModelType.speech;
    }
    if (lower.contains('embedding') || lower.contains('text-embedding')) {
      return ModelType.embedding;
    }
    if (lower.startsWith('sora') || lower.contains('video')) {
      return ModelType.video;
    }
    // 默认文本生成
    return ModelType.text;
  }

  /// 从模型 ID 推断模态标签
  List<ModelTag> _inferOpenAiModelTags(String id) {
    final lower = id.toLowerCase();
    final tags = <ModelTag>[ModelTag.text];

    // GPT-4o / GPT-4-turbo 系列支持视觉
    if (lower.startsWith('gpt-4o') ||
        lower.startsWith('gpt-4-turbo') ||
        lower.startsWith('gpt-4.1') ||
        lower.startsWith('o1') ||
        lower.startsWith('o3') ||
        lower.startsWith('o4') ||
        lower.contains('vision')) {
      tags.add(ModelTag.vision);
    }
    // GPT-4V 明确视觉
    if (lower.contains('-vision') || lower.contains('gpt-4v') || lower.contains('-vl')) {
      tags.add(ModelTag.vision);
    }

    // 语音模型
    if (lower.startsWith('whisper') || lower.startsWith('tts')) {
      tags.add(ModelTag.audible);
    }

    // 视频模型
    if (lower.startsWith('sora') || lower.contains('video')) {
      tags.add(ModelTag.video);
    }

    if (lower.contains('-omni')) {
      // 多模态
      return [ModelTag.text, ModelTag.vision, ModelTag.audible, ModelTag.video];
    }

    return tags;
  }
}

/// 工具调用增量累积辅助
class _PartialToolCall {
  String id = '';
  String name;
  String arguments;

  _PartialToolCall({required this.name, required this.arguments});
}
