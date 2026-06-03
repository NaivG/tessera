import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:ollama_dart/ollama_dart.dart' as ollama;

import '../core/llm_provider.dart';
import '../models/llm_config.dart';
import '../models/message.dart';
import '../models/model_info.dart';
import '../models/stream_chunk.dart';
import '../models/tool.dart';

/// Ollama 本地模型提供商适配器
class OllamaProvider extends LlmProvider {
  @override
  String get providerId => 'ollama';

  @override
  String get displayName => 'Ollama';

  ollama.OllamaClient _buildClient(LlmConfig config) {
    return ollama.OllamaClient(
      config: ollama.OllamaConfig(
        baseUrl: config.baseUrl ?? 'http://localhost:11434',
      ),
    );
  }

  @override
  Future<List<ModelInfo>> listAvailableModels({
    String? apiKey,
    String? baseUrl,
  }) async {
    final client = ollama.OllamaClient(
      config: ollama.OllamaConfig(baseUrl: baseUrl ?? 'http://localhost:11434'),
    );
    try {
      final response = await client.models.list();
      final models = response.models;
      if (models == null || models.isEmpty) return [];
      return models.map(_ollamaModelToModelInfo).toList();
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
    final client = ollama.OllamaClient(
      config: ollama.OllamaConfig(baseUrl: baseUrl ?? 'http://localhost:11434'),
    );
    try {
      final response = await client.models.show(
        request: ollama.ShowRequest(model: modelId),
      );
      // Ollama show 返回的是详细配置，整合到 ModelInfo
      final tags = <ModelTag>[ModelTag.text];
      if (response.details != null) {
        final family = response.details!['family'] as String? ?? '';
        if (family.contains('vision') || family.contains('llava')) {
          tags.add(ModelTag.vision);
        }
      }
      return ModelInfo(id: modelId, type: ModelType.text, tags: tags);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> validateConfig(LlmConfig config) async {
    try {
      final client = ollama.OllamaClient(
        config: ollama.OllamaConfig(
          baseUrl: config.baseUrl ?? 'http://localhost:11434',
        ),
      );
      await client.models.list();
      return true;
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

    final request = ollama.ChatRequest(
      model: config.modelId,
      messages: _buildMessages(history, systemPrompt),
      stream: false,
      options: ollama.ModelOptions(
        temperature: config.temperature,
        numPredict: config.maxTokens,
        topP: config.topP,
      ),
      think: config.deepThinking ? ollama.ThinkValue.enabled(true) : null,
      tools: tools
          ?.map(
            (t) => ollama.ToolDefinition(
              function: ollama.ToolFunction(
                name: t.name,
                description: t.description,
                parameters: t.parameters.isNotEmpty ? t.toParametersSchema() : const {},
              ),
            ),
          )
          .toList(),
    );

    final response = await client.chat.create(request: request);

    return Message(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      role: MessageRole.assistant,
      content: response.message?.content ?? '',
      toolCalls: _mapToolCalls(response.message?.toolCalls),
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

    final request = ollama.ChatRequest(
      model: config.modelId,
      messages: _buildMessages(history, systemPrompt),
      stream: true,
      options: ollama.ModelOptions(
        temperature: config.temperature,
        numPredict: config.maxTokens,
        topP: config.topP,
      ),
      think: config.deepThinking ? ollama.ThinkValue.enabled(true) : null,
      tools: tools
          ?.map(
            (t) => ollama.ToolDefinition(
              function: ollama.ToolFunction(
                name: t.name,
                description: t.description,
                parameters: t.parameters.isNotEmpty ? t.toParametersSchema() : const {},
              ),
            ),
          )
          .toList(),
    );

    final stream = client.chat.createStream(request: request);

    // 按函数名累积工具调用，避免跨 chunk 重复 yield
    final toolCallAccumulator = <String, _OllamaToolCallAcc>{};

    await for (final event in stream) {
      final message = event.message;
      if (message == null) continue;

      // 思考内容增量
      if (message.thinking != null && message.thinking!.isNotEmpty) {
        yield StreamChunk.thinking(message.thinking!);
      }

      if (message.content != null && message.content!.isNotEmpty) {
        yield StreamChunk.content(message.content!);
      }

      // 累积工具调用（不立即 yield，统一在流结束时输出）
      if (message.toolCalls != null && message.toolCalls!.isNotEmpty) {
        for (final tc in message.toolCalls!) {
          final name = tc.function?.name ?? '';
          if (name.isEmpty) continue;

          final acc = toolCallAccumulator.putIfAbsent(
            name,
            () => _OllamaToolCallAcc(name: name),
          );

          final args = tc.function?.arguments;
          if (args != null) {
            acc.arguments.addAll(args);
          }
          debugPrint('[Ollama] chatStream tool chunk: '
              'name=$name, args=${tc.function?.arguments}, '
              'argsType=${tc.function?.arguments.runtimeType}');
        }
      }

      if (event.done == true) {
        // 输出累积的工具调用
        for (final acc in toolCallAccumulator.values) {
          final args = Map<String, dynamic>.from(acc.arguments);
          debugPrint('[Ollama] chatStream yielding StreamChunk.tool: '
              'name=${acc.name}, args=$args');
          yield StreamChunk.tool(
            ToolCall(
              id: acc.name,
              name: acc.name,
              arguments: args,
            ),
          );
        }
        toolCallAccumulator.clear();

        yield StreamChunk.done(
          usage: TokenUsage(
            promptTokens: event.promptEvalCount,
            completionTokens: event.evalCount,
          ),
        );
      }
    }
  }

  // --- 内部辅助 ---

  /// 将 Ollama SDK 的 ModelSummary 映射为项目 [ModelInfo]
  ModelInfo _ollamaModelToModelInfo(ollama.ModelSummary summary) {
    final id = summary.name ?? summary.model ?? '';
    final tags = <ModelTag>[ModelTag.text];

    // 从 details.family 推断视觉支持
    if (summary.details != null) {
      final family = summary.details!.family ?? '';
      if (family.contains('vision') ||
          family.contains('llava') ||
          family.contains('bakllava')) {
        tags.add(ModelTag.vision);
      }
    }
    // 从名称推断
    final lower = id.toLowerCase();
    if (lower.contains('vision') ||
        lower.contains('llava') ||
        lower.contains('bakllava')) {
      if (!tags.contains(ModelTag.vision)) {
        tags.add(ModelTag.vision);
      }
    }

    return ModelInfo(id: id, type: ModelType.text, tags: tags);
  }

  List<ollama.ChatMessage> _buildMessages(
    List<Message> history,
    String? systemPrompt,
  ) {
    final messages = <ollama.ChatMessage>[];

    if (systemPrompt != null && systemPrompt.isNotEmpty) {
      messages.add(ollama.ChatMessage.system(systemPrompt));
    }

    for (final msg in history) {
      switch (msg.role) {
        case MessageRole.user:
          messages.add(ollama.ChatMessage.user(msg.content));
          break;
        case MessageRole.assistant:
          messages.add(
            ollama.ChatMessage.assistant(
              msg.content,
              toolCalls: msg.toolCalls
                  ?.map(
                    (tc) => ollama.ToolCall(
                      function: ollama.ToolCallFunction(
                        name: tc.name,
                        arguments: tc.arguments,
                      ),
                    ),
                  )
                  .toList(),
            ),
          );
          break;
        case MessageRole.tool:
          messages.add(ollama.ChatMessage.tool(msg.content));
          break;
        case MessageRole.system:
          messages.add(ollama.ChatMessage.system(msg.content));
          break;
      }
    }

    return messages;
  }

  List<ToolCall>? _mapToolCalls(List<ollama.ToolCall>? calls) {
    if (calls == null || calls.isEmpty) return null;
    debugPrint('[Ollama] _mapToolCalls: count=${calls.length}');
    return calls
        .map(
          (tc) {
            final args = tc.function?.arguments ?? {};
            debugPrint('[Ollama] _mapToolCalls: name=${tc.function?.name}, args=$args, argsType=${args.runtimeType}');
            return ToolCall(
              id: tc.function?.name ?? '',
              name: tc.function?.name ?? '',
              arguments: args,
            );
          },
        )
        .toList();
  }
}

/// Ollama 流式 tool_use 临时状态：按函数名累积增量 arguments
class _OllamaToolCallAcc {
  final String name;
  final Map<String, dynamic> arguments = {};

  _OllamaToolCallAcc({required this.name});
}
