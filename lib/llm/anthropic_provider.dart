import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:anthropic_sdk_dart/anthropic_sdk_dart.dart' as anthropic;

import '../core/llm_provider.dart';
import '../models/llm_config.dart';
import '../models/message.dart';
import '../models/model_info.dart';
import '../models/stream_chunk.dart';
import '../models/tool.dart';
import '../services/media_library.dart';

/// Anthropic (Claude) 提供商适配器
class AnthropicProvider extends LlmProvider {
  @override
  String get providerId => 'anthropic';

  @override
  String get displayName => 'Anthropic';

  anthropic.AnthropicClient _buildClient(LlmConfig config) {
    return anthropic.AnthropicClient.withApiKey(
      config.apiKey ?? '',
      baseUrl: config.baseUrl,
    );
  }

  @override
  Future<List<ModelInfo>> listAvailableModels({
    String? apiKey,
    String? baseUrl,
  }) async {
    final client = anthropic.AnthropicClient.withApiKey(
      apiKey ?? '',
      baseUrl: baseUrl,
    );
    try {
      final response = await client.models.list();
      return response.data.map(_anthropicModelToModelInfo).toList();
    } catch (_) {
      return _fallbackAnthropicModels();
    }
  }

  @override
  Future<ModelInfo?> getModelInfo(
    String modelId, {
    String? apiKey,
    String? baseUrl,
  }) async {
    final client = anthropic.AnthropicClient.withApiKey(
      apiKey ?? '',
      baseUrl: baseUrl,
    );
    try {
      final model = await client.models.retrieve(modelId);
      return _anthropicModelToModelInfo(model);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> validateConfig(LlmConfig config) async {
    if (config.apiKey == null || config.apiKey!.isEmpty) return false;
    if (!config.apiKey!.startsWith('sk-ant-')) return false;
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
    final request = _buildRequest(config, history, systemPrompt, tools);

    final response = await client.messages.create(request);

    String content = '';
    List<ToolCall>? toolCalls;

    for (final block in response.content) {
      if (block is anthropic.TextBlock) {
        content += block.text;
      } else if (block is anthropic.ToolUseBlock) {
        toolCalls ??= [];
        debugPrint(
          '[Anthropic] chat ToolUseBlock: id=${block.id}, name=${block.name}, input=${block.input}',
        );
        toolCalls.add(
          ToolCall(id: block.id, name: block.name, arguments: block.input),
        );
      }
    }

    return Message(
      id: response.id,
      role: MessageRole.assistant,
      content: content,
      toolCalls: toolCalls,
      timestamp: DateTime.now(),
      status: MessageStatus.completed,
      usage: TokenUsage(
        promptTokens: response.usage.inputTokens,
        completionTokens: response.usage.outputTokens,
      ),
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

    final stream = client.messages.createStream(request);

    // 按 content block index 追踪 tool_use 块的增量 JSON 输入
    final Map<int, _PendingToolUse> pendingToolUses = {};

    // 从 MessageStartEvent 捕获 inputTokens（MessageDeltaEvent 仅含 outputTokens）
    int? startInputTokens;

    await for (final event in stream) {
      if (event is anthropic.MessageStartEvent) {
        // 记录初始 usage 中的 inputTokens，供流结束时合并到 StreamChunk.done
        startInputTokens = event.message.usage.inputTokens;
        debugPrint(
          '[Anthropic] chatStream MessageStart: '
          'inputTokens=$startInputTokens',
        );
      } else if (event is anthropic.ContentBlockStartEvent) {
        final block = event.contentBlock;
        if (block is anthropic.ToolUseBlock) {
          // 流式模式下 ToolUseBlock.input 恒为 {}，实际参数通过 InputJsonDelta 增量传输
          final pending = _PendingToolUse(id: block.id, name: block.name);
          pendingToolUses[event.index] = pending;
          debugPrint(
            '[Anthropic] chatStream ContentBlockStart: '
            'index=${event.index}, id=${block.id}, name=${block.name}',
          );
        }
      } else if (event is anthropic.ContentBlockDeltaEvent) {
        final delta = event.delta;
        if (delta is anthropic.TextDelta) {
          yield StreamChunk.content(delta.text);
        } else if (delta is anthropic.ThinkingDelta) {
          yield StreamChunk.thinking(delta.thinking);
        } else if (delta is anthropic.InputJsonDelta) {
          final pending = pendingToolUses[event.index];
          if (pending != null) {
            pending.inputJsonBuffer.write(delta.partialJson);
          }
          debugPrint(
            '[Anthropic] chatStream InputJsonDelta: '
            'index=${event.index}, partialJson=${delta.partialJson}',
          );
        }
        // SignatureDelta / CitationsDelta / CompactionDelta / Unknown: 当前工具调用场景不涉及，忽略
      } else if (event is anthropic.ContentBlockStopEvent) {
        final pending = pendingToolUses.remove(event.index);
        if (pending != null) {
          final parsedArgs = _parseToolInputJson(pending.inputJsonBuffer);
          debugPrint(
            '[Anthropic] chatStream ContentBlockStop: '
            'index=${event.index}, id=${pending.id}, name=${pending.name}, '
            'parsedArgs=$parsedArgs',
          );
          yield StreamChunk.tool(
            ToolCall(id: pending.id, name: pending.name, arguments: parsedArgs),
          );
        }
      } else if (event is anthropic.MessageDeltaEvent) {
        // 安全网：清空所有尚未完成的 tool use 块
        for (final entry in pendingToolUses.entries) {
          final pending = entry.value;
          final parsedArgs = _parseToolInputJson(pending.inputJsonBuffer);
          debugPrint(
            '[Anthropic] chatStream MessageDelta (draining): '
            'index=${entry.key}, id=${pending.id}, name=${pending.name}, '
            'parsedArgs=$parsedArgs',
          );
          yield StreamChunk.tool(
            ToolCall(id: pending.id, name: pending.name, arguments: parsedArgs),
          );
        }
        pendingToolUses.clear();

        yield StreamChunk.done(
          usage: TokenUsage(
            promptTokens: event.usage.inputTokens ?? startInputTokens,
            completionTokens: event.usage.outputTokens,
          ),
        );
      } else if (event is anthropic.ErrorEvent) {
        pendingToolUses.clear();
        yield StreamChunk.error(event.message);
        return;
      }
      // MessageStopEvent, PingEvent: 忽略
      // MessageStartEvent: 已在上方处理（捕获 inputTokens）
    }
  }

  // --- 内部辅助 ---

  anthropic.MessageCreateRequest _buildRequest(
    LlmConfig config,
    List<Message> history,
    String? systemPrompt,
    List<ToolDefinition>? tools,
  ) {
    final messages = history.map(_toAnthropicInputMessage).toList();

    return anthropic.MessageCreateRequest(
      model: config.modelId,
      maxTokens: config.maxTokens ?? 4096,
      messages: messages,
      system: systemPrompt != null && systemPrompt.isNotEmpty
          ? anthropic.SystemPrompt.text(systemPrompt)
          : null,
      temperature: config.temperature,
      topP: config.topP,
      tools: tools?.map((t) => _toAnthropicTool(t)).toList(),
      // 深度思考：Anthropic 部分模型默认启用，这里显式传递以确保开启
      thinking: config.deepThinking
          ? anthropic.ThinkingConfig.enabled(budgetTokens: 4096)
          : null,
    );
  }

  anthropic.InputMessage _toAnthropicInputMessage(Message msg) {
    final blocks = <anthropic.InputContentBlock>[];

    // 图像附件在文本内容之前添加
    if (msg.mediaAttachments != null && msg.mediaAttachments!.isNotEmpty) {
      for (final attachment in msg.mediaAttachments!) {
        if (!attachment.isImage) continue;
        final filePath = MediaLibrary.instance.filePathFor(
          attachment.libraryId,
        );
        if (filePath == null) continue;

        try {
          final bytes = File(filePath).readAsBytesSync();
          final base64 = base64Encode(bytes);
          final mime = attachment.mimeType ?? 'image/png';
          final mediaType = _toAnthropicImageMediaType(mime);
          if (mediaType != null) {
            blocks.add(
              anthropic.InputContentBlock.image(
                anthropic.ImageSource.base64(
                  data: base64,
                  mediaType: mediaType,
                ),
              ),
            );
          }
        } catch (_) {
          // 图片读取失败，静默跳过
        }
      }
    }

    if (msg.content.isNotEmpty) {
      blocks.add(anthropic.InputContentBlock.text(msg.content));
    }

    if (msg.toolCalls != null) {
      for (final tc in msg.toolCalls!) {
        blocks.add(
          anthropic.InputContentBlock.toolUse(
            id: tc.id,
            name: tc.name,
            input: tc.arguments,
          ),
        );
      }
    }

    switch (msg.role) {
      case MessageRole.assistant:
        return anthropic.InputMessage.assistantBlocks(blocks);
      case MessageRole.tool:
        // Anthropic 没有独立的 tool role — 工具结果必须放在 user 消息中
        // 以 tool_result content block 的形式返回，并关联 tool_use_id。
        if (msg.toolCallId != null) {
          return anthropic.InputMessage.userBlocks([
            anthropic.InputContentBlock.toolResultText(
              toolUseId: msg.toolCallId!,
              text: msg.content,
            ),
          ]);
        }
        // 缺少 toolCallId 时回退为普通文本（不应该发生，仅作防御）
        return anthropic.InputMessage.userBlocks(blocks);
      case MessageRole.user:
      default:
        return anthropic.InputMessage.userBlocks(blocks);
    }
  }

  /// MIME 类型 → Anthropic ImageMediaType
  anthropic.ImageMediaType? _toAnthropicImageMediaType(String mime) {
    return switch (mime) {
      'image/jpeg' || 'image/jpg' => anthropic.ImageMediaType.jpeg,
      'image/png' => anthropic.ImageMediaType.png,
      'image/gif' => anthropic.ImageMediaType.gif,
      'image/webp' => anthropic.ImageMediaType.webp,
      _ => null,
    };
  }

  /// 将 Anthropic SDK 的 ModelInfo 映射为项目 [ModelInfo]
  ModelInfo _anthropicModelToModelInfo(anthropic.ModelInfo model) {
    final id = model.id;
    final tags = <ModelTag>[ModelTag.text];

    // 从 capabilities 获取视觉支持
    if (model.capabilities?.imageInput.supported == true) {
      tags.add(ModelTag.vision);
    }
    // PDF 输入也视为视觉模态
    if (model.capabilities?.pdfInput.supported == true &&
        !tags.contains(ModelTag.vision)) {
      tags.add(ModelTag.vision);
    }

    return ModelInfo(id: id, type: ModelType.text, tags: tags);
  }

  /// 网络不通时的兜底模型列表
  List<ModelInfo> _fallbackAnthropicModels() {
    const ids = [
      'claude-sonnet-4-6',
      'claude-3-5-sonnet-20241022',
      'claude-3-5-haiku-20241022',
      'claude-3-opus-20240229',
      'claude-3-sonnet-20240229',
      'claude-3-haiku-20240307',
    ];
    return ids.map((id) {
      final tags = <ModelTag>[ModelTag.text];
      // Claude 3+ 全系列支持视觉
      if (id.startsWith('claude-3') || id.startsWith('claude-sonnet-4')) {
        tags.add(ModelTag.vision);
      }
      return ModelInfo(id: id, type: ModelType.text, tags: tags);
    }).toList();
  }

  anthropic.ToolDefinition _toAnthropicTool(ToolDefinition tool) {
    final params = tool.parameters;
    final properties = <String, Map<String, dynamic>>{};
    final required = <String>[];

    for (final entry in params.entries) {
      if (entry.key == 'required') continue;
      if (entry.value is Map) {
        final prop = Map<String, dynamic>.from(entry.value as Map);
        if (prop.remove('required') == true) {
          required.add(entry.key);
        }
        properties[entry.key] = prop;
      }
    }

    return anthropic.ToolDefinition.custom(
      anthropic.Tool(
        name: tool.name,
        description: tool.description,
        inputSchema: anthropic.InputSchema(
          properties: properties,
          required: required,
          extra: const {'additionalProperties': false},
        ),
      ),
    );
  }

  /// 解析 tool_use 累积的增量 JSON 字符串为 Map
  static Map<String, dynamic> _parseToolInputJson(StringBuffer buffer) {
    final str = buffer.toString();
    if (str.isEmpty) return const {};
    try {
      final decoded = jsonDecode(str);
      if (decoded is Map<String, dynamic>) return decoded;
      return const {};
    } on FormatException {
      return const {};
    }
  }
}

/// 流式 tool_use 临时状态：记录 id/name 并累积 InputJsonDelta 片段
class _PendingToolUse {
  final String id;
  final String name;
  final StringBuffer inputJsonBuffer = StringBuffer();

  _PendingToolUse({required this.id, required this.name});
}
