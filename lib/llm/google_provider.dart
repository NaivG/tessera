import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:googleai_dart/googleai_dart.dart' as google;

import '../core/llm_provider.dart';
import '../models/llm_config.dart';
import '../models/message.dart';
import '../models/model_info.dart';
import '../models/stream_chunk.dart';
import '../models/tool.dart';

/// Google AI (Gemini) 提供商适配器
class GoogleProvider extends LlmProvider {
  @override
  String get providerId => 'google';

  @override
  String get displayName => 'Google AI';

  google.GoogleAIClient _buildClient(LlmConfig config) {
    return google.GoogleAIClient.withApiKey(config.apiKey ?? '');
  }

  @override
  Future<List<ModelInfo>> listAvailableModels({
    String? apiKey,
    String? baseUrl,
  }) async {
    final client = google.GoogleAIClient.withApiKey(
      apiKey ?? '',
      baseUrl: baseUrl,
    );
    try {
      final response = await client.models.list();
      return response.models.map(_googleModelToModelInfo).toList();
    } catch (_) {
      return _fallbackGoogleModels();
    }
  }

  @override
  Future<ModelInfo?> getModelInfo(
    String modelId, {
    String? apiKey,
    String? baseUrl,
  }) async {
    final client = google.GoogleAIClient.withApiKey(
      apiKey ?? '',
      baseUrl: baseUrl,
    );
    try {
      final model = await client.models.get(model: modelId);
      return _googleModelToModelInfo(model);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> validateConfig(LlmConfig config) async {
    if (config.apiKey == null || config.apiKey!.isEmpty) return false;
    if (!config.apiKey!.startsWith('AIza')) return false;
    return true;
  }

  @override
  Future<Message> chat({
    required LlmConfig config,
    required List<Message> history,
    String? systemPrompt,
    List<ToolDefinition>? tools,
  }) async {
    final client = _buildClient(config);

    final request = google.GenerateContentRequest(
      contents: _buildContents(history),
      systemInstruction: systemPrompt != null && systemPrompt.isNotEmpty
          ? google.Content.text(systemPrompt)
          : null,
      tools: tools?.map((t) => _toGoogleTool(t)).toList(),
      generationConfig: google.GenerationConfig(
        temperature: config.temperature,
        maxOutputTokens: config.maxTokens ?? 8192,
        topP: config.topP,
        thinkingConfig: config.deepThinking
            ? google.ThinkingConfig(thinkingBudget: 1024)
            : null,
      ),
    );

    final response = await client.models.generateContent(
      model: config.modelId,
      request: request,
    );

    final text = response.text ?? '';
    final toolCalls = _extractToolCalls(response);

    return Message(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      role: MessageRole.assistant,
      content: text,
      toolCalls: toolCalls,
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

    final request = google.GenerateContentRequest(
      contents: _buildContents(history),
      systemInstruction: systemPrompt != null && systemPrompt.isNotEmpty
          ? google.Content.text(systemPrompt)
          : null,
      tools: tools?.map((t) => _toGoogleTool(t)).toList(),
      generationConfig: google.GenerationConfig(
        temperature: config.temperature,
        maxOutputTokens: config.maxTokens ?? 8192,
        topP: config.topP,
        thinkingConfig: config.deepThinking
            ? google.ThinkingConfig(thinkingBudget: 1024)
            : null,
      ),
    );

    final stream = client.models.streamGenerateContent(
      model: config.modelId,
      request: request,
    );

    // 用于累积工具调用
    final toolCallParts = <String, _GeminiToolCallAcc>{};

    await for (final response in stream) {
      if (response.candidates == null || response.candidates!.isEmpty) continue;
      final candidate = response.candidates!.first;
      if (candidate.content == null) continue;

      for (final part in candidate.content!.parts) {
        // 思考内容（Gemini thinking）
        if (part is google.TextPart &&
            part.thought == true &&
            part.text.isNotEmpty) {
          yield StreamChunk.thinking(part.text);
          continue;
        }

        if (part is google.TextPart && part.text.isNotEmpty) {
          yield StreamChunk.content(part.text);
        }

        if (part is google.FunctionCallPart) {
          final fc = part.functionCall;
          // 使用 functionCall.id（唯一标识一次调用）或 name 作为稳定 key，
          // 避免因 args 增量变化导致 hash 改变而产生重复 accumulator
          final key = fc.id ?? fc.name;

          final acc = toolCallParts.putIfAbsent(
            key,
            () => _GeminiToolCallAcc(name: fc.name),
          );

          debugPrint('[Google] chatStream FunctionCallPart: '
              'id=${fc.id}, name=${fc.name}, args=${fc.args}, '
              'argsType=${fc.args.runtimeType}');

          if (fc.args != null) {
            acc.arguments.addAll(fc.args!);
          }
        }
      }

      // 检查是否结束
      if (candidate.finishReason != null) {
        break;
      }
    }

    // 输出累积的工具调用
    debugPrint('[Google] chatStream tool accumulators: count=${toolCallParts.length}');
    for (final acc in toolCallParts.values) {
      final args = Map<String, dynamic>.from(acc.arguments);
      debugPrint('[Google] chatStream yielding StreamChunk.tool: name=${acc.name}, args=$args');
      yield StreamChunk.tool(
        ToolCall(
          id: acc.name,
          name: acc.name,
          arguments: args,
        ),
      );
    }

    yield StreamChunk.done();
  }

  // --- 内部辅助 ---

  List<google.Content> _buildContents(List<Message> history) {
    final contents = <google.Content>[];

    for (final msg in history) {
      final parts = <google.Part>[];

      if (msg.content.isNotEmpty) {
        parts.add(google.Part.text(msg.content));
      }

      if (msg.toolCalls != null) {
        for (final tc in msg.toolCalls!) {
          parts.add(google.Part.functionCall(tc.name, args: tc.arguments));
        }
      }

      contents.add(
        google.Content(
          role: msg.role == MessageRole.assistant ? 'model' : 'user',
          parts: parts,
        ),
      );
    }

    return contents;
  }

  /// 将 Google AI SDK 的 Model 映射为项目 [ModelInfo]
  ModelInfo _googleModelToModelInfo(google.Model model) {
    // Google model name 格式为 "models/gemini-2.0-flash"，提取 ID
    final id = model.name.startsWith('models/')
        ? model.name.substring('models/'.length)
        : model.name;
    final type = _inferGoogleModelType(id, model);
    final tags = _inferGoogleModelTags(id, model);
    return ModelInfo(id: id, type: type, tags: tags);
  }

  ModelType _inferGoogleModelType(String id, google.Model model) {
    final lower = id.toLowerCase();
    // 嵌入模型
    if (lower.contains('embedding') || lower.contains('text-embedding')) {
      return ModelType.embedding;
    }
    // 图像生成模型
    if (lower.contains('imagen')) {
      return ModelType.image;
    }
    // 视频生成模型
    if (lower.contains('veo') || lower.contains('video')) {
      return ModelType.video;
    }
    // 语音模型
    if (lower.contains('chirp') ||
        lower.contains('speech') ||
        lower.contains('tts')) {
      return ModelType.speech;
    }
    // 默认文本生成
    return ModelType.text;
  }

  List<ModelTag> _inferGoogleModelTags(String id, google.Model model) {
    final lower = id.toLowerCase();
    final tags = <ModelTag>[ModelTag.text];

    // Gemini 多模态模型都支持视觉
    if (lower.startsWith('gemini-') &&
        (lower.contains('pro') ||
            lower.contains('flash') ||
            lower.contains('ultra'))) {
      tags.add(ModelTag.vision);
    }
    // 明确标注 vision 的模型
    if (lower.contains('vision')) {
      tags.add(ModelTag.vision);
    }
    // 音频模型
    if (lower.contains('chirp') ||
        lower.contains('speech') ||
        lower.contains('tts')) {
      tags.add(ModelTag.audible);
    }
    // 视频
    if (lower.contains('veo') || lower.contains('video')) {
      tags.add(ModelTag.video);
    }
    // 从 supportedGenerationMethods 推断
    final methods = model.supportedGenerationMethods;
    if (methods != null) {
      if (methods.any(
        (m) => m.contains('generateContent') || m.contains('chat'),
      )) {
        // 已默认包含 text
      }
    }

    return tags;
  }

  /// 网络不通时的兜底模型列表
  List<ModelInfo> _fallbackGoogleModels() {
    const ids = [
      'gemini-2.5-flash',
      'gemini-2.5-pro',
      'gemini-2.0-flash',
      'gemini-2.0-flash-lite',
      'gemini-1.5-pro',
      'gemini-1.5-flash',
      'gemini-1.0-pro',
    ];
    return ids.map((id) {
      final tags = <ModelTag>[ModelTag.text];
      if (id.contains('pro') || id.contains('flash') || id.contains('ultra')) {
        tags.add(ModelTag.vision);
      }
      return ModelInfo(id: id, type: ModelType.text, tags: tags);
    }).toList();
  }

  google.Tool _toGoogleTool(ToolDefinition def) {
    if (def.parameters.isEmpty) {
      return google.Tool(
        functionDeclarations: [
          google.FunctionDeclaration(
            name: def.name,
            description: def.description,
          ),
        ],
      );
    }

    final properties = <String, google.Schema>{};
    final required = <String>[];

    for (final entry in def.parameters.entries) {
      if (entry.value is! Map) continue;
      final prop = entry.value as Map;
      if (prop['required'] == true) {
        required.add(entry.key);
      }
      properties[entry.key] = google.Schema(
        type: google.schemaTypeFromString(prop['type'] as String?),
        description: prop['description'] as String?,
        enumValues: (prop['enum'] as List?)?.cast<String>(),
      );
    }

    return google.Tool(
      functionDeclarations: [
        google.FunctionDeclaration(
          name: def.name,
          description: def.description,
          parameters: google.Schema(
            type: google.SchemaType.object,
            properties: properties,
            required: required.isNotEmpty ? required : null,
          ),
        ),
      ],
    );
  }

  List<ToolCall>? _extractToolCalls(google.GenerateContentResponse response) {
    final parts = response.candidates?.firstOrNull?.content?.parts;
    if (parts == null) return null;

    final toolCalls = <ToolCall>[];
    for (final part in parts) {
      if (part is google.FunctionCallPart) {
        final fc = part.functionCall;
        final args = fc.args is Map<String, dynamic>
            ? fc.args as Map<String, dynamic>
            : <String, dynamic>{};
        debugPrint('[Google] _extractToolCalls: name=${fc.name}, args=$args, argsType=${fc.args.runtimeType}');
        toolCalls.add(
          ToolCall(
            id: fc.name,
            name: fc.name,
            arguments: args,
          ),
        );
      }
    }
    return toolCalls.isNotEmpty ? toolCalls : null;
  }
}

class _GeminiToolCallAcc {
  final String name;
  final Map<String, dynamic> arguments = {};

  _GeminiToolCallAcc({required this.name});
}
