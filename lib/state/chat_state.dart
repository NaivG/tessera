import 'dart:async';

import 'package:flutter/material.dart';

import '../core/core.dart';
import '../memory/memory.dart';
import '../llm/provider_factory.dart';
import '../services/conversation_service.dart';
import '../utils/json_extractor.dart';
import 'settings_state.dart';

/// 聊天状态 — 管理当前对话的消息流和发送逻辑
class ChatState extends ChangeNotifier {
  final ConversationService _convService = ConversationService();
  final ToolRegistry _toolRegistry = ToolRegistry();
  final CacheManager _cacheManager = CacheManager();

  Conversation? _conversation;
  bool _isStreaming = false;
  String? _error;

  /// 系统提示词构建器（从 asset 延迟加载）
  SystemPromptBuilder? _promptBuilder;

  /// 缓存的设置状态引用
  SettingsState? _settingsState;

  bool _initialized = false;

  bool _isPreprocessing = false;
  String _preprocessingTitle = '正在分析附件...';
  String _preprocessingText = '';

  final StreamController<String> _preprocessingStreamController =
      StreamController<String>.broadcast();

  CapabilityAdapter? _adapter;

  // 记忆系统
  final MemoryState _memoryState = MemoryState();
  final MemoryExtractor _memoryExtractor = MemoryExtractor(
    extractRoundCount: 5,
  );
  late final ConversationalMemoryManager _convMemManager;
  String _memoryContextText = '';
  bool _memoryInitialized = false;

  StreamSubscription<StreamChunk>? _streamSubscription;
  final Map<String, StreamController<String>> _activeStreams = {};
  final Map<String, StreamController<String>> _activeThinkingStreams = {};

  Conversation? get conversation => _conversation;
  List<Message> get messages => _conversation?.messages ?? [];

  List<Message> get displayMessages {
    final all = messages;
    if (all.isEmpty) return all;
    return all.where((m) => m.role != MessageRole.tool).toList();
  }

  bool get isStreaming => _isStreaming;
  bool get isPreprocessing => _isPreprocessing;
  String get preprocessingTitle => _preprocessingTitle;
  String get preprocessingText => _preprocessingText;
  Stream<String> get preprocessingStream =>
      _preprocessingStreamController.stream;
  String? get error => _error;
  bool get hasConversation => _conversation != null;

  CacheManager get cacheManager => _cacheManager;
  MemoryState get memoryState => _memoryState;
  String get memoryContextText => _memoryContextText;
  String? get conversationSummary => _convMemManager.currentSummary;

  Stream<String>? getContentStream(String messageId) {
    return _activeStreams[messageId]?.stream;
  }

  Stream<String>? getThinkingStream(String messageId) {
    return _activeThinkingStreams[messageId]?.stream;
  }

  void configureCapabilities(SettingsState settings) {
    _settingsState = settings;
    final config = settings.modelSelectionConfig;
    _adapter = CapabilityAdapter(
      config: config,
      state: settings,
      providerFactory: (id) => ProviderFactory.get(id),
    );
    _toolRegistry.clear();
    _adapter!.registerTools(_toolRegistry);
  }

  Future<void> init() async {
    if (_initialized) return;
    await _cacheManager.init();
    _promptBuilder = await SystemPromptBuilder.load();

    if (!_memoryInitialized) {
      await _memoryState.init();
      _convMemManager = ConversationalMemoryManager(memoryState: _memoryState);
      _memoryInitialized = true;
    }

    _initialized = true;
    debugPrint('[ChatState] 初始化完成：${_promptBuilder!.toString()}，记忆系统就绪');
  }

  Future<void> _ensurePromptBuilder() async {
    if (_promptBuilder != null) return;
    _promptBuilder = await SystemPromptBuilder.load();
  }

  String _buildSystemPromptString() {
    if (_promptBuilder == null) return '';
    if (_settingsState?.lightweightSystemPrompt == true) {
      final base = _promptBuilder!.buildLightweightSystemPromptString(
        customPrompt: _settingsState?.userCustomPrompt,
      );
      return base;
    }
    final base = _promptBuilder!.buildSystemPromptString(
      displayName: _settingsState?.userDisplayName,
      alias: _settingsState?.userAlias,
      role: _settingsState?.userRole,
      preferences: _settingsState?.userPreferences,
      facts: _settingsState?.userFacts,
      customPrompt: _settingsState?.userCustomPrompt,
    );
    if (_memoryContextText.isNotEmpty) {
      return '$base\n\n$_memoryContextText';
    }
    return base;
  }

  void createConversation({
    required LlmConfig config,
    String? systemPrompt,
    String title = '新对话',
  }) {
    debugPrint('[ChatState] 创建新对话：$title');
    _streamSubscription?.cancel();
    _conversation = Conversation(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: title,
      config: config,
      systemPrompt: systemPrompt,
    );
    _isStreaming = false;
    _error = null;
    _cacheManager.resetSession();
    _convMemManager.reset();
    _memoryExtractor.clear();
    _memoryContextText = '';
    _memoryState.beginConversation(_conversation!.id);
    notifyListeners();
  }

  Future<void> loadConversation(String id) async {
    _streamSubscription?.cancel();
    final conv = await _convService.getConversation(id);
    if (conv != null) {
      _conversation = conv;
      _isStreaming = false;
      _error = null;
      await _ensurePromptBuilder();
      _convMemManager.reset();
      _memoryExtractor.clear();
      _memoryContextText = '';
      notifyListeners();
    }
  }

  Future<void> sendMessage(
    String content, {
    List<MediaAttachment>? attachments,
    bool streamEnabled = true,
    LlmConfig? config,
  }) async {
    if (_isStreaming) return;

    _error = null;
    debugPrint('[ChatState] 发送用户消息：$content');

    if (_conversation == null) {
      if (config == null) {
        _error = '无法创建对话：缺少 LLM 配置';
        notifyListeners();
        return;
      }

      await _ensurePromptBuilder();

      final title = _fallbackTopic(content);
      final systemPrompt = _buildSystemPromptString();
      createConversation(
        config: config,
        title: title,
        systemPrompt: systemPrompt.isNotEmpty ? systemPrompt : null,
      );
      await _convService.saveConversation(_conversation!);
      debugPrint('[ChatState] 新对话已保存: id=${_conversation!.id}');

      unawaited(_generateAndUpdateTopic(content, config));
    }

    // 记忆检索
    if (_memoryInitialized) {
      final memories = await _memoryState.search(
        content,
        excludeConversationId: _conversation?.id,
      );
      _memoryContextText = _memoryState.formatMemoryContext(memories);
      if (_memoryContextText.isNotEmpty) {
        debugPrint('[ChatState] 检索到 ${memories.length} 条相关记忆');
      }
      if (_conversation != null && _promptBuilder != null) {
        _conversation = _conversation!.copyWith(
          systemPrompt: _buildSystemPromptString(),
        );
      }
    }

    final effectiveAttachments = attachments != null && attachments.isNotEmpty
        ? attachments
        : null;
    if (effectiveAttachments != null) {
      _isPreprocessing = true;
      _preprocessingTitle = '正在分析附件...';
      _preprocessingText = '正在分析 ${effectiveAttachments.length} 个附件...';
      _preprocessingStreamController.add('开始分析附件...\n');
      notifyListeners();
    }

    String adaptedContent;
    try {
      adaptedContent = effectiveAttachments != null
          ? await (_adapter?.adaptInput(content, effectiveAttachments) ??
                Future.value(content))
          : content;
    } finally {
      if (effectiveAttachments != null) {
        _preprocessingStreamController.add('附件分析完成。\n');
        _isPreprocessing = false;
        _preprocessingTitle = '';
        _preprocessingText = '';
        notifyListeners();
      }
    }

    final userMsg = Message(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      role: MessageRole.user,
      content: adaptedContent,
      mediaAttachments: attachments,
      status: MessageStatus.completed,
      timestamp: DateTime.now(),
    );
    _conversation!.addMessage(userMsg);
    notifyListeners();

    final assistantId = DateTime.now().microsecondsSinceEpoch.toString();
    final streamingMsg = Message.streamingAssistant(id: assistantId);
    _conversation!.addMessage(streamingMsg);
    _isStreaming = true;
    notifyListeners();

    if (streamEnabled) {
      await _sendStreaming(assistantId);
    } else {
      await _sendNonStreaming(assistantId);
    }
  }

  List<ToolDefinition> get _currentTools {
    return _adapter?.buildTools() ?? [];
  }

  Future<void> _sendStreaming(String assistantId) async {
    final contentController = StreamController<String>.broadcast();
    _activeStreams[assistantId] = contentController;
    final thinkingController = StreamController<String>.broadcast();
    _activeThinkingStreams[assistantId] = thinkingController;

    try {
      final provider = ProviderFactory.get(_conversation!.config.providerId);
      final tools = _currentTools;
      final stream = provider.chatStream(
        config: _conversation!.config,
        history: _conversation!.messages.sublist(
          0,
          _conversation!.messages.length - 1,
        ),
        systemPrompt: _conversation!.systemPrompt,
        tools: tools.isNotEmpty ? tools : null,
      );

      String accumulatedContent = '';
      String accumulatedThinking = '';
      final accumulatedToolCalls = <ToolCall>[];

      _streamSubscription = stream.listen(
        (chunk) {
          switch (chunk.type) {
            case StreamChunkType.contentDelta:
              final delta = chunk.contentDelta ?? '';
              accumulatedContent += delta;
              contentController.add(delta);
              _updateAssistant(
                assistantId,
                content: accumulatedContent,
                thinking: accumulatedThinking.isNotEmpty
                    ? accumulatedThinking
                    : null,
              );
              break;

            case StreamChunkType.thinkingDelta:
              final delta = chunk.thinkingDelta ?? '';
              accumulatedThinking += delta;
              thinkingController.add(delta);
              _updateAssistant(
                assistantId,
                content: accumulatedContent,
                thinking: accumulatedThinking,
              );
              break;

            case StreamChunkType.toolCall:
              if (chunk.toolCall != null) {
                accumulatedToolCalls.add(chunk.toolCall!);
                _updateAssistant(
                  assistantId,
                  content: accumulatedContent,
                  thinking: accumulatedThinking.isNotEmpty
                      ? accumulatedThinking
                      : null,
                  toolCalls: accumulatedToolCalls,
                );
              }
              break;

            case StreamChunkType.done:
              unawaited(
                _finishStreaming(
                  assistantId,
                  accumulatedContent,
                  accumulatedToolCalls,
                  accumulatedThinking.isNotEmpty ? accumulatedThinking : null,
                ),
              );
              break;

            case StreamChunkType.error:
              _setError(chunk.error ?? '未知错误', assistantId);
              break;
          }
        },
        onError: (e) {
          _setError('连接错误: $e', assistantId);
        },
        onDone: () {
          unawaited(
            _finishStreaming(
              assistantId,
              accumulatedContent,
              accumulatedToolCalls,
              accumulatedThinking.isNotEmpty ? accumulatedThinking : null,
            ),
          );
        },
      );
    } catch (e) {
      _setError('发送失败: $e', assistantId);
    }
  }

  Future<void> _sendNonStreaming(String assistantId) async {
    try {
      final provider = ProviderFactory.get(_conversation!.config.providerId);
      final tools = _currentTools;
      final response = await provider.chat(
        config: _conversation!.config,
        history: _conversation!.messages.sublist(
          0,
          _conversation!.messages.length - 1,
        ),
        systemPrompt: _conversation!.systemPrompt,
        tools: tools.isNotEmpty ? tools : null,
      );

      final toolCalls = response.toolCalls ?? [];
      final messages = _conversation!.messages;
      for (int i = messages.length - 1; i >= 0; i--) {
        if (messages[i].id == assistantId) {
          messages[i] = response.copyWith(status: MessageStatus.completed);
          break;
        }
      }

      if (toolCalls.isNotEmpty) {
        await _handleToolCallsAndContinue(
          assistantId,
          toolCalls,
          streamEnabled: false,
        );
        return;
      }

      _isStreaming = false;
      _convService.saveConversation(_conversation!);
      unawaited(_commitCache());
      await _triggerMemoryPipeline(assistantId);
      notifyListeners();
    } catch (e) {
      _setError('发送失败: $e', assistantId);
    }
  }

  void _findAndUpdateMessage(
    String messageId,
    Message Function(Message old) transform,
  ) {
    if (_conversation == null) return;
    final messages = _conversation!.messages;
    for (int i = messages.length - 1; i >= 0; i--) {
      if (messages[i].id == messageId) {
        messages[i] = transform(messages[i]);
        break;
      }
    }
  }

  void _updateAssistant(
    String assistantId, {
    String? content,
    String? thinking,
    List<ToolCall>? toolCalls,
  }) {
    if (_conversation == null) return;
    final messages = _conversation!.messages;
    for (int i = messages.length - 1; i >= 0; i--) {
      if (messages[i].id == assistantId) {
        messages[i] = messages[i].copyWith(
          content: content ?? messages[i].content,
          thinking: thinking ?? messages[i].thinking,
          toolCalls: toolCalls ?? messages[i].toolCalls,
          clearToolCalls: toolCalls == null && messages[i].toolCalls == null,
        );
        break;
      }
    }
    notifyListeners();
  }

  Future<bool> _handleToolCallsAndContinue(
    String assistantId,
    List<ToolCall> toolCalls, {
    bool streamEnabled = true,
  }) async {
    if (toolCalls.isEmpty) return false;

    debugPrint(
      '[ChatState] _handleToolCallsAndContinue: count=${toolCalls.length}',
    );

    final results = await _toolRegistry.executeAll(toolCalls);

    final toolResults = <String, String>{};
    for (final result in results) {
      toolResults[result.toolCallId] = result.content;
    }
    _findAndUpdateMessage(
      assistantId,
      (msg) => msg.copyWith(toolResults: toolResults),
    );

    for (final result in results) {
      _conversation!.addMessage(
        Message(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          role: MessageRole.tool,
          content: result.content,
          toolCallId: result.toolCallId,
          status: MessageStatus.completed,
          timestamp: DateTime.now(),
        ),
      );
    }
    notifyListeners();

    final newAssistantId = DateTime.now().microsecondsSinceEpoch.toString();
    _conversation!.addMessage(Message.streamingAssistant(id: newAssistantId));
    _isStreaming = true;
    notifyListeners();

    if (streamEnabled) {
      await _sendStreaming(newAssistantId);
    } else {
      await _sendNonStreaming(newAssistantId);
    }
    return true;
  }

  Future<void> _finishStreaming(
    String assistantId,
    String content,
    List<ToolCall> toolCalls, [
    String? thinking,
  ]) async {
    if (_conversation == null) return;

    final messages = _conversation!.messages;
    int targetIdx = -1;
    for (int i = messages.length - 1; i >= 0; i--) {
      if (messages[i].id == assistantId) {
        targetIdx = i;
        break;
      }
    }
    if (targetIdx < 0) return;
    if (messages[targetIdx].status == MessageStatus.completed) return;

    messages[targetIdx] = messages[targetIdx].copyWith(
      content: content,
      thinking: thinking,
      toolCalls: toolCalls.isNotEmpty ? toolCalls : null,
      status: MessageStatus.completed,
    );

    _activeStreams.remove(assistantId)?.close();
    _activeThinkingStreams.remove(assistantId)?.close();

    if (toolCalls.isNotEmpty) {
      await _handleToolCallsAndContinue(
        assistantId,
        toolCalls,
        streamEnabled: true,
      );
      return;
    }

    _isStreaming = false;
    _streamSubscription = null;
    _convService.saveConversation(_conversation!);
    unawaited(_commitCache());
    await _triggerMemoryPipeline(assistantId);
    notifyListeners();
  }

  Future<void> _triggerMemoryPipeline(String assistantId) async {
    if (!_memoryInitialized || _conversation == null) return;

    final messages = _conversation!.messages;
    Message? userMsg;
    Message? assistantMsg;
    for (int i = messages.length - 1; i >= 0; i--) {
      final msg = messages[i];
      if (msg.id == assistantId && msg.role == MessageRole.assistant) {
        assistantMsg = msg;
      } else if (msg.role == MessageRole.user && userMsg == null) {
        userMsg = msg;
      }
      if (userMsg != null && assistantMsg != null) break;
    }
    if (userMsg == null || assistantMsg == null) return;

    _memoryExtractor.addTurn(userMsg, assistantMsg);
    _convMemManager.incrementTurn();

    if (_memoryExtractor.shouldExtract) {
      final convId = _conversation!.id;
      final convConfig = _conversation!.config;
      final provider = ProviderFactory.get(convConfig.providerId);
      final srcMsgId = assistantMsg.id;
      unawaited(
        _memoryExtractor.extract(provider: provider, config: convConfig).then((
          extractions,
        ) {
          if (extractions.isNotEmpty) {
            _memoryExtractor.bufferExtractions(extractions);
            if (_memoryExtractor.shouldFlush) {
              unawaited(
                _memoryExtractor.flushToMemory(
                  memoryState: _memoryState,
                  conversationId: convId,
                  sourceMessageId: srcMsgId,
                ),
              );
            }
          }
          _memoryExtractor.resetRoundCount();
        }),
      );
    }

    if (_convMemManager.shouldSummarize) {
      final convId = _conversation!.id;
      final convConfig = _conversation!.config;
      final provider = ProviderFactory.get(convConfig.providerId);
      final recentMessages = messages.sublist(
        (messages.length - _convMemManager.turnsSinceLastSummary * 2).clamp(
          0,
          messages.length,
        ),
      );

      if (_convMemManager.hasSummary) {
        unawaited(
          _convMemManager.updateSummary(
            provider: provider,
            config: convConfig,
            messages: recentMessages,
            conversationId: convId,
          ),
        );
      } else {
        unawaited(
          _convMemManager.generateInitialSummary(
            provider: provider,
            config: convConfig,
            messages: recentMessages,
            conversationId: convId,
          ),
        );
      }
    }
  }

  void _setError(String message, String assistantId) {
    _error = message;
    _isStreaming = false;

    if (_conversation != null) {
      final messages = _conversation!.messages;
      for (int i = messages.length - 1; i >= 0; i--) {
        if (messages[i].id == assistantId) {
          messages[i] = messages[i].copyWith(
            status: MessageStatus.error,
            errorMessage: message,
          );
          break;
        }
      }
    }

    _streamSubscription = null;
    _activeStreams.remove(assistantId)?.close();
    _activeThinkingStreams.remove(assistantId)?.close();
    notifyListeners();
  }

  Future<void> retry({bool streamEnabled = true}) async {
    if (_conversation == null || _isStreaming) return;
    final messages = _conversation!.messages;
    if (messages.length < 2) return;

    final lastAssistantIdx = messages.lastIndexWhere(
      (m) => m.role == MessageRole.assistant,
    );
    if (lastAssistantIdx < 0) return;

    final lastUserIdx = messages.lastIndexWhere(
      (m) => m.role == MessageRole.user,
    );
    _conversation!.removeLastMessage();
    notifyListeners();

    if (lastUserIdx >= 0) {
      final lastUserContent = messages[lastUserIdx].content;
      await sendMessage(lastUserContent, streamEnabled: streamEnabled);
    }
  }

  Future<void> modifyAndResend(
    String messageId,
    String newContent, {
    bool streamEnabled = true,
  }) async {
    if (_conversation == null || _isStreaming) return;

    final messages = _conversation!.messages;
    final index = messages.indexWhere((m) => m.id == messageId);
    if (index < 0 || messages[index].role != MessageRole.user) return;
    messages[index] = messages[index].copyWith(content: newContent);
    _conversation!.updatedAt = DateTime.now();
    messages.removeRange(index + 1, messages.length);
    notifyListeners();
    await sendMessage(newContent, streamEnabled: streamEnabled);
  }

  void stopStreaming() {
    _streamSubscription?.cancel();
    _streamSubscription = null;
    _isStreaming = false;
    _isPreprocessing = false;
    _preprocessingTitle = '';
    _preprocessingText = '';
    _closeAllStreams();
    notifyListeners();
  }

  // 缓存管理
  Future<void> initCache() async {
    await _cacheManager.init();
  }

  PromptSectionCollection _buildCacheCollection() {
    final sections = <PromptSection>[];

    final isLightweight = _settingsState?.lightweightSystemPrompt == true;

    if (_promptBuilder != null) {
      final spSections = isLightweight
          ? _promptBuilder!.buildLightweightSystemPrompt(
              customPrompt: _settingsState?.userCustomPrompt,
            )
          : _promptBuilder!.buildSystemPrompt(
              displayName: _settingsState?.userDisplayName,
              alias: _settingsState?.userAlias,
              role: _settingsState?.userRole,
              preferences: _settingsState?.userPreferences,
              facts: _settingsState?.userFacts,
              customPrompt: _settingsState?.userCustomPrompt,
            );
      for (final section in spSections.sections) {
        final existingSection = _cacheManager.cached.sections.where(
          (s) => s.id == section.id,
        );
        if (existingSection.isNotEmpty &&
            !existingSection.first.isExpired &&
            existingSection.first.content == section.content) {
          sections.add(existingSection.first);
        } else {
          sections.add(section);
        }
      }
    } else if (_conversation?.systemPrompt != null &&
        _conversation!.systemPrompt!.isNotEmpty) {
      sections.add(
        _cacheManager.buildPromptSection(
          _conversation!.systemPrompt!,
          ttlSeconds: 300,
        ),
      );
    }

    if (!isLightweight && _memoryContextText.isNotEmpty) {
      sections.add(
        PromptSection.create(
          id: 'system.block4.memory_context',
          type: PromptSectionType.memory,
          content: _memoryContextText,
          cacheHint: PromptCacheHint(
            cacheable: false,
            clientCache: true,
            priority: 10,
          ),
        ),
      );
    }

    final tools = _currentTools;
    if (tools.isNotEmpty) {
      final toolDefsMap = tools.map((t) => t.toOpenAiSchema()).toList();
      sections.add(
        _cacheManager.buildToolSection(toolDefsMap.toString(), ttlSeconds: 300),
      );
    }

    return PromptSectionCollection(sections);
  }

  Future<void> _commitCache() async {
    final collection = _buildCacheCollection();
    _cacheManager.commitCollection(collection);
    await _cacheManager.persistCacheable(collection);
  }

  void clear() {
    _streamSubscription?.cancel();
    _conversation = null;
    _isStreaming = false;
    _isPreprocessing = false;
    _preprocessingTitle = '';
    _preprocessingText = '';
    _error = null;
    _memoryContextText = '';
    _convMemManager.reset();
    _memoryExtractor.clear();
    _memoryState.clearCache();
    _closeAllStreams();
    _preprocessingStreamController.add('');
    notifyListeners();
  }

  void _closeAllStreams() {
    for (final c in _activeStreams.values) {
      c.close();
    }
    _activeStreams.clear();
    for (final c in _activeThinkingStreams.values) {
      c.close();
    }
    _activeThinkingStreams.clear();
  }

  Future<void> _generateAndUpdateTopic(
    String userInput,
    LlmConfig config,
  ) async {
    try {
      final provider = ProviderFactory.get(config.providerId);
      final prompt = PromptTemplateStore.instance.render('topic_generation', {
        'user_input': userInput,
      });
      final topicConfig = config.copyWith(maxTokens: 50);
      final response = await provider.chat(
        config: topicConfig,
        history: [Message.user(prompt)],
      );
      final topic = JsonExtractor.tryExtractField(response.content, 'topic') ??
          response.content.trim();
      if (topic.isEmpty) return;
      final sanitized = topic.length > 25 ? topic.substring(0, 25) : topic;
      if (_conversation != null) {
        _conversation!.title = sanitized;
        await _convService.renameConversation(_conversation!.id, sanitized);
        notifyListeners();
      }
    } catch (_) {}
  }

  String _fallbackTopic(String input) {
    final match = RegExp(r'[。.]').firstMatch(input);
    if (match != null && match.start > 0) {
      final truncated = input.substring(0, match.start);
      if (truncated.length > 15) return '${truncated.substring(0, 15)}…';
      return truncated;
    }
    if (input.length > 20) return '${input.substring(0, 20)}…';
    return input;
  }

  @override
  void dispose() {
    _streamSubscription?.cancel();
    _closeAllStreams();
    _preprocessingStreamController.close();
    _memoryState.dispose();
    super.dispose();
  }
}
