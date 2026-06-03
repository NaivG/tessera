import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/media_attachment.dart';
import '../models/message.dart';
import '../models/model_info.dart';
import '../models/model_selection_config.dart';
import '../models/tool.dart';
import 'tool_registry.dart';
import 'llm_provider.dart';
import '../services/media_library.dart';

/// 能力转译适配器
///
/// 职责：
/// 1. 根据 [ModelSelectionConfig] 生成工具定义
///    - `vision`: 调用视觉模型查看图片
///    - `audible`: 调用音频模型分析音频
///    - `image_generate`: 调用文生图模型生成图片
///    - `speech_generate`: 调用文生语音模型生成语音
/// 2. 执行这些工具调用，路由到正确的模态模型
/// 3. 预处理输入：对于主模型不支持的模态，用专用模型生成文字描述
class CapabilityAdapter {
  final ModelSelectionConfig config;
  final dynamic state; // SettingsState，用于 buildConfig

  /// Provider 工厂：根据 providerId 返回 LlmProvider 实例
  final LlmProvider Function(String providerId) _providerFactory;

  CapabilityAdapter({
    required this.config,
    required this.state,
    required LlmProvider Function(String providerId) providerFactory,
  }) : _providerFactory = providerFactory;

  // ═══════════════════════════════════════════════════════════
  // 工具定义生成
  // ═══════════════════════════════════════════════════════════

  /// 构建应注入到主模型的所有工具定义
  List<ToolDefinition> buildTools() {
    final tools = <ToolDefinition>[];

    // vision 工具：有视觉输入模型且主模型不支持 vision
    final visionSlot = config.resolveInput(ModelTag.vision, state);
    if (visionSlot != null && visionSlot != config.mainModel) {
      tools.add(_visionTool);
    }

    // audible 工具：有音频输入模型且主模型不支持 audible
    final audibleSlot = config.resolveInput(ModelTag.audible, state);
    if (audibleSlot != null && audibleSlot != config.mainModel) {
      tools.add(_audibleTool);
    }

    // image_generate 工具：有文生图输出模型
    final ttiSlot = config.resolveOutput(ModelType.image, state);
    if (ttiSlot != null) {
      tools.add(_imageGenerateTool);
    }

    // speech_generate 工具：有文生语音输出模型
    final ttsSlot = config.resolveOutput(ModelType.speech, state);
    if (ttsSlot != null) {
      tools.add(_speechGenerateTool);
    }

    return tools;
  }

  /// 将工具注册到 [ToolRegistry]
  void registerTools(ToolRegistry registry) {
    for (final tool in buildTools()) {
      registry.register(tool, (call) => executeTool(call));
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 工具执行
  // ═══════════════════════════════════════════════════════════

  /// 执行工具调用，路由到正确的模态模型
  Future<ToolResult> executeTool(ToolCall call) async {
    switch (call.name) {
      case 'vision':
        return _executeVision(call);
      case 'audible':
        return _executeAudible(call);
      case 'image_generate':
        return _executeImageGenerate(call);
      case 'speech_generate':
        return _executeSpeechGenerate(call);
      default:
        return ToolResult(
          toolCallId: call.id,
          content: 'Unknown capability tool: ${call.name}',
          isError: true,
        );
    }
  }

  // ── Vision ──

  static const _visionTool = ToolDefinition(
    name: 'vision',
    description:
        'Your visual extension for image or video. It is your third eye to see the world. '
        'Provide the object reference (object key/filename/URL) and a question whose content you want to know.',
    parameters: {
      'type': {
        'type': 'string',
        'enum': ['image', 'video'],
        'description': 'Media type to analyze',
        'required': true,
      },
      'object': {
        'type': 'string',
        'description': 'Reference to the image or video ([object key]/filename/URL/data URI)',
        'required': true,
      },
      'question': {
        'type': 'string',
        'description': 'What do you want to know about this media?',
        'required': true,
      },
    },
  );

  Future<ToolResult> _executeVision(ToolCall call) async {
    final slot = config.resolveInput(ModelTag.vision, state);
    if (slot == null) {
      return ToolResult(
        toolCallId: call.id,
        content: 'No vision model configured.',
        isError: true,
      );
    }

    final llmConfig = slot.buildConfig(state);
    if (llmConfig == null) {
      return ToolResult(
        toolCallId: call.id,
        content: 'Vision model configuration is invalid.',
        isError: true,
      );
    }

    final question = call.arguments['question'] as String? ?? '';
    final object = call.arguments['object'] as String? ?? '';
    final mediaType = call.arguments['type'] as String? ?? 'image';

    debugPrint('[CapabilityAdapter] _executeVision: object="$object", question="$question", type="$mediaType"');

    if (object.isEmpty) {
      return ToolResult(
        toolCallId: call.id,
        content: 'vision tool called without an object parameter. '
            'Arguments received: ${call.arguments}. ',
        isError: true,
      );
    }

    // 查找媒体文件：libraryId > 文件名 > URL/data URI
    final (attachment, filePath) = await _resolveMediaObject(object);

    if (attachment == null) {
      return ToolResult(
        toolCallId: call.id,
        content: 'Media object not found: "$object". '
            'MediaLibrary has ${MediaLibrary.instance.entries.length} entries: '
            '${MediaLibrary.instance.entries.map((e) => e.attachment.fileName).toList()}. '
            'Make sure the object name matches a filename in your library.',
        isError: true,
      );
    }

    final prompt = question.isNotEmpty
        ? "$question DO NOT distort the facts; just state what you see."
        : 'Describe this $mediaType in general. DO NOT distort the facts; just state what you see.';

    try {
      final provider = _providerFactory(llmConfig.providerId);
      final response = await provider.chat(
        config: llmConfig,
        history: [
          Message(
            id: DateTime.now().microsecondsSinceEpoch.toString(),
            role: MessageRole.user,
            content: prompt,
            mediaAttachments: [attachment],
            timestamp: DateTime.now(),
          ),
        ],
      );
      return ToolResult(
        toolCallId: call.id,
        content: response.content,
      );
    } catch (e) {
      return ToolResult(
        toolCallId: call.id,
        content: 'Vision analysis failed: $e',
        isError: true,
      );
    }
  }

  // ── Audible ──

  static const _audibleTool = ToolDefinition(
    name: 'audible',
    description:
        'Your audible extension for audio analysis. It is your ear to listen to the world. '
        'Provide the audio reference and a question whose content you want to know.',
    parameters: {
      'object': {
        'type': 'string',
        'description': 'Reference to the audio ([object key]/filename/URL/data URI)',
        'required': true,
      },
      'question': {
        'type': 'string',
        'description': 'What do you want to know about this audio?',
        'required': true,
      },
    },
  );

  Future<ToolResult> _executeAudible(ToolCall call) async {
    final slot = config.resolveInput(ModelTag.audible, state);
    if (slot == null) {
      return ToolResult(
        toolCallId: call.id,
        content: 'No audible model configured.',
        isError: true,
      );
    }

    final llmConfig = slot.buildConfig(state);
    if (llmConfig == null) {
      return ToolResult(
        toolCallId: call.id,
        content: 'Audible model configuration is invalid.',
        isError: true,
      );
    }

    final question = call.arguments['question'] as String? ?? '';
    final object = call.arguments['object'] as String? ?? '';

    debugPrint('[CapabilityAdapter] _executeAudible: object="$object", question="$question"');

    if (object.isEmpty) {
      return ToolResult(
        toolCallId: call.id,
        content: 'audible tool called without an object parameter. '
            'Arguments received: ${call.arguments}. ',
        isError: true,
      );
    }

    final (attachment, filePath) = await _resolveMediaObject(object);

    if (attachment == null) {
      return ToolResult(
        toolCallId: call.id,
        content: 'Media object not found: "$object". '
            'MediaLibrary has ${MediaLibrary.instance.entries.length} entries: '
            '${MediaLibrary.instance.entries.map((e) => e.attachment.fileName).toList()}.',
        isError: true,
      );
    }

    final prompt = question.isNotEmpty
        ? '$question DO NOT distort the facts; just state what you heard.'
        : 'Transcribe or describe this audio in general. DO NOT distort the facts; just state what you see.';

    try {
      final provider = _providerFactory(llmConfig.providerId);
      final response = await provider.chat(
        config: llmConfig,
        history: [
          Message(
            id: DateTime.now().microsecondsSinceEpoch.toString(),
            role: MessageRole.user,
            content: prompt,
            mediaAttachments: [attachment],
            timestamp: DateTime.now(),
          ),
        ],
      );
      return ToolResult(
        toolCallId: call.id,
        content: response.content,
      );
    } catch (e) {
      return ToolResult(
        toolCallId: call.id,
        content: 'Audio analysis failed: $e',
        isError: true,
      );
    }
  }

  // ── Image Generate ──

  static const _imageGenerateTool = ToolDefinition(
    name: 'image_generate',
    description:
        'Your image generation extension. It is your imagination to create visuals. '
        'Provide a detailed prompt describing what to draw.',
    parameters: {
      'prompt': {
        'type': 'string',
        'description': 'Detailed image generation prompt',
        'required': true,
      },
      'style': {
        'type': 'string',
        'description':
            'Optional style hint (e.g., photorealistic, anime, oil painting)',
      },
    },
  );

  Future<ToolResult> _executeImageGenerate(ToolCall call) async {
    final slot = config.resolveOutput(ModelType.image, state);
    if (slot == null) {
      return ToolResult(
        toolCallId: call.id,
        content: 'No image generation model configured.',
        isError: true,
      );
    }

    final llmConfig = slot.buildConfig(state);
    if (llmConfig == null) {
      return ToolResult(
        toolCallId: call.id,
        content: 'Image generation model configuration is invalid.',
        isError: true,
      );
    }

    final prompt = call.arguments['prompt'] as String? ?? '';
    final style = call.arguments['style'] as String?;

    final fullPrompt = style != null && style.isNotEmpty
        ? 'Generate an image in $style style: $prompt'
        : 'Generate an image: $prompt';

    try {
      final provider = _providerFactory(llmConfig.providerId);
      final response = await provider.chat(
        config: llmConfig,
        history: [Message.user(fullPrompt)],
      );
      return ToolResult(
        toolCallId: call.id,
        content:
            '[Image generated from prompt: "$prompt"]\n${response.content}',
      );
    } catch (e) {
      return ToolResult(
        toolCallId: call.id,
        content: 'Image generation failed: $e',
        isError: true,
      );
    }
  }

  // ── Speech Generate ──

  static const _speechGenerateTool = ToolDefinition(
    name: 'speech_generate',
    description:
        'Your speech generation extension. It is your voice to speak the world. '
        'Provide the text to be spoken.',
    parameters: {
      'text': {
        'type': 'string',
        'description': 'Text to convert to speech',
        'required': true,
      },
      'voice': {
        'type': 'string',
        'description': 'Optional voice style (e.g., male, female, narrator)',
      },
    },
  );

  Future<ToolResult> _executeSpeechGenerate(ToolCall call) async {
    final slot = config.resolveOutput(ModelType.speech, state);
    if (slot == null) {
      return ToolResult(
        toolCallId: call.id,
        content: 'No speech generation model configured.',
        isError: true,
      );
    }

    final llmConfig = slot.buildConfig(state);
    if (llmConfig == null) {
      return ToolResult(
        toolCallId: call.id,
        content: 'Speech generation model configuration is invalid.',
        isError: true,
      );
    }

    final text = call.arguments['text'] as String? ?? '';

    try {
      final provider = _providerFactory(llmConfig.providerId);
      final response = await provider.chat(
        config: llmConfig,
        history: [
          Message.user('Convert the following text to speech: $text'),
        ],
      );
      return ToolResult(
        toolCallId: call.id,
        content:
            '[Speech generated from text: "${text.length > 50 ? "${text.substring(0, 50)}..." : text}"]\n${response.content}',
      );
    } catch (e) {
      return ToolResult(
        toolCallId: call.id,
        content: 'Speech generation failed: $e',
        isError: true,
      );
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 媒体对象解析
  // ═══════════════════════════════════════════════════════════

  /// 解析工具调用中的 `object` 参数，查找对应的媒体文件。
  ///
  /// 查找策略：
  /// 1. libraryId 直接匹配
  /// 2. 文件名匹配（遍历 MediaLibrary 条目）
  /// 3. URL / data URI
  ///
  /// 返回 ([MediaAttachment]?, [String]?) 元组 —
  /// attachment 用于附加到消息中，filePath 用于日志/诊断。
  Future<(MediaAttachment?, String?)> _resolveMediaObject(String object) async {
    if (object.isEmpty) return (null, null);
    final lib = MediaLibrary.instance;

    // 1. 直接作为 libraryId 查找
    var filePath = lib.filePathFor(object);
    if (filePath != null) {
      return (lib.attachmentFor(object), filePath);
    }

    // 2. 按文件名搜索
    for (final entry in lib.entries) {
      if (entry.attachment.fileName == object) {
        return (entry.attachment, entry.filePath);
      }
    }

    // 3. URL / data URI 下载并导入
    if (object.startsWith('http://') || object.startsWith('https://')) {
      try {
        final response = await http.get(Uri.parse(object)).timeout(const Duration(seconds: 10));
        if (response.statusCode == 200) {
          final bytes = response.bodyBytes;
          final uri = Uri.parse(object);
          final fileName = uri.pathSegments.isNotEmpty
              ? uri.pathSegments.last
              : 'downloaded_file';
          final attachment = await lib.importBytes(bytes, fileName);
          filePath = lib.filePathFor(attachment.libraryId);
          return (attachment, filePath);
        }
      } catch (e) {
        debugPrint('Failed to download media from URL "$object": $e');
        return (null, null);
      }
    }

    return (null, null);
  }

  // ═══════════════════════════════════════════════════════════
  // 输入预处理
  // ═══════════════════════════════════════════════════════════

  /// 预处理用户输入：对于主模型不支持的模态内容，
  /// 使用专用模型生成文字描述后替换为占位标记。
  ///
  /// - 主模型支持该模态 → 附件直接透传给 provider，不预处理
  /// - 特定模态模型可用且 ≠ 主模型 → 用模态模型生成描述并替换
  /// - 都不满足 → 生成简单的文件名占位
  ///
  /// 注意：经预处理后，[userMessage] 末尾会追加 `[Media: ...]` 占位符，
  /// 已处理的附件会从 [attachments] 中移除，剩余附件由 provider 直接处理。
  Future<String> adaptInput(
    String userMessage,
    List<MediaAttachment> attachments,
  ) async {
    if (attachments.isEmpty) return userMessage;
    debugPrint('[Adapter] Adapting input with ${attachments.length} attachments for main model "${config.mainModel}"');

    final mainModelInfo = config.mainModel.getModelInfo(state);
    final mainTags = mainModelInfo?.tags ?? [ModelTag.text];

    final placeholders = <String>[];

    for (final attachment in attachments) {
      final tag = _tagForMediaType(attachment.type);
      final supportedByMain =
          tag == null || mainTags.contains(tag);

      if (supportedByMain) {
        // 主模型支持该模态：附件由 provider 直接加入 API 请求，
        // 但仍然生成一个轻量占位符，帮助纯文本模型理解上下文
        continue;
      }
      debugPrint(
        '[Adapter] Attachment "${attachment.fileName}" is not supported by main model, generating description placeholder',
      );
      // 尝试用专用模态模型生成描述
      final description = await _describeAttachment(attachment);
      final typeName = attachment.type.name;
      debugPrint(
        '[Adapter] Generated description for "${attachment.fileName}": $description',
      );
      placeholders.add(
        formatMediaPlaceholder(
          type: typeName,
          name: attachment.fileName,
          description: description ??
              '[File: object: ${attachment.fileName}, type: ${attachment.type}, description: an error was encountered while trying to get description]',
          toolName: tag == ModelTag.vision ? 'vision' : 'audible',
        ),
      );
    }

    if (placeholders.isEmpty) return userMessage;

    final joined = placeholders.join('\n');
    return '$userMessage\n\n$joined';
  }

  /// 获取 [MediaType] 对应的 [ModelTag]
  ModelTag? _tagForMediaType(MediaType type) {
    return switch (type) {
      MediaType.image => ModelTag.vision,
      MediaType.video => ModelTag.vision,
      MediaType.audio => ModelTag.audible,
      MediaType.file => null, // 普通文件没有对应模态
    };
  }

  /// 调用专用模态模型获取附件内容的文字描述
  Future<String?> _describeAttachment(MediaAttachment attachment) async {
    final tag = _tagForMediaType(attachment.type);
    if (tag == null) {
      // 普通文件：返回基本信息
      return '文件 "${attachment.fileName}"'
          '${attachment.fileSizeLabel != null ? ' (${attachment.fileSizeLabel})' : ''}';
    }

    // 查找可用的模态模型
    final slot = config.resolveInput(tag, state);
    if (slot == null) {
      // 没有配置专用模态模型，返回文件名占位
      return '${attachment.type.name}: "${attachment.fileName}"';
    }

    final llmConfig = slot.buildConfig(state);
    if (llmConfig == null) return null;

    final filePath = MediaLibrary.instance.filePathFor(attachment.libraryId);
    final prompt = tag == ModelTag.vision
        ? 'Describe this ${attachment.type.name} ("${attachment.fileName}") '
            'in general. What is it mainly shown? No more than 300 words. DO NOT distort the facts; just state what you see.'
        : 'Transcribe or describe this audio file ("${attachment.fileName}") '
            'in general. What is being said or heard? DO NOT distort the facts; just state what you heard.';

    try {
      final provider = _providerFactory(llmConfig.providerId);
      // 使用带图片的 chat 调用（图片路径通过 media_attachments 传入）
      final response = await provider.chat(
        config: llmConfig,
        history: [
          Message(
            id: DateTime.now().microsecondsSinceEpoch.toString(),
            role: MessageRole.user,
            content: prompt,
            mediaAttachments: filePath != null
                ? [attachment.copyWith()]
                : null,
            timestamp: DateTime.now(),
          ),
        ],
      );
      return response.content.isNotEmpty ? response.content : null;
    } catch (_) {
      return null;
    }
  }

  /// 为不支持的模态生成描述占位标记
  ///
  /// 示例输出：
  /// ```
  /// [Image: object: "photo.jpg", description: "一只猫坐在桌子上", tip: "call `vision` tool with given object for more info"]
  /// ```
  static String formatMediaPlaceholder({
    required String type,
    required String name,
    required String description,
    String toolName = 'vision',
  }) {
    return '[${type.substring(0, 1).toUpperCase()}${type.substring(1)}: '
        'object: "$name", description: "$description", '
        'tip: "if the imformation is not clear, you can call `$toolName` tool with given object for more info"]';
  }
}