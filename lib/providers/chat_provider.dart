import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/core.dart';
import '../llm/provider_factory.dart';
import '../memory/memory.dart';
import '../plugin/plugin.dart';
import '../services/conversation_service.dart';
import '../utils/json_extractor.dart';
import 'conversation_list_provider.dart';
import 'settings_provider.dart';
import 'stats_provider.dart';

// =============================================================================
// ChatData
// =============================================================================

class ChatData {
  final Conversation? conversation;
  final bool isStreaming;
  final bool isPreprocessing;
  final String preprocessingTitle;
  final String preprocessingText;
  final String? error;
  final String memoryContextText;

  const ChatData({
    this.conversation,
    this.isStreaming = false,
    this.isPreprocessing = false,
    this.preprocessingTitle = '',
    this.preprocessingText = '',
    this.error,
    this.memoryContextText = '',
  });

  List<Message> get messages => conversation?.messages ?? [];
  List<Message> get displayMessages {
    final all = messages;
    if (all.isEmpty) return all;
    return all.where((m) => m.role != MessageRole.tool).toList();
  }

  bool get hasConversation => conversation != null;


  ChatData copyWith({
    Conversation? conversation,
    bool? isStreaming,
    bool? isPreprocessing,
    String? preprocessingTitle,
    String? preprocessingText,
    String? error,
    String? memoryContextText,
    bool clearConversation = false,
    bool clearError = false,
  }) {
    return ChatData(
      conversation: clearConversation ? null : conversation ?? this.conversation,
      isStreaming: isStreaming ?? this.isStreaming,
      isPreprocessing: isPreprocessing ?? this.isPreprocessing,
      preprocessingTitle: preprocessingTitle ?? this.preprocessingTitle,
      preprocessingText: preprocessingText ?? this.preprocessingText,
      error: clearError ? null : error ?? this.error,
      memoryContextText: memoryContextText ?? this.memoryContextText,
    );
  }
}

// =============================================================================
// ChatNotifier
// =============================================================================

class ChatNotifier extends Notifier<ChatData> {
  final ConversationService _convService = ConversationService();
  final ToolRegistry _toolRegistry = ToolRegistry();
  final CacheManager _cacheManager = CacheManager();
  final MemoryExtractor _memoryExtractor = MemoryExtractor(
    extractRoundCount: 5,
  );
  late final ConversationalMemoryManager _convMemManager;

  SystemPromptBuilder? _promptBuilder;
  SettingsData? _settingsData;
  bool _initialized = false;
  bool _memoryInitialized = false;

  StreamSubscription<StreamChunk>? _streamSubscription;
  final Map<String, StreamController<String>> _activeStreams = {};
  final Map<String, StreamController<String>> _activeThinkingStreams = {};

  /// 已完成的流 ID 集合，防止 _finishStreaming 被 done chunk + onDone 双重触发
  final Set<String> _completedStreams = {};

  final StreamController<String> _preprocessingStreamController =
      StreamController<String>.broadcast();

  CapabilityAdapter? _adapter;

  MemoryNotifier get _memory => ref.read(memoryProvider.notifier);

  @override
  ChatData build() {
    ref.onDispose(_onDispose);

    // 监听设置变化，自动同步到 ChatNotifier，
    // 确保模型选择、提示词注入、用户档案等设置修改后即时生效
    ref.listen(settingsProvider, (prev, next) {
      configureCapabilities(next);
    });

    return const ChatData();
  }

  void _onDispose() {
    _streamSubscription?.cancel();
    _closeAllStreams();
    _completedStreams.clear();
    _preprocessingStreamController.close();
  }

  // ── 内部 helper ──

  void _setConversation(Conversation? conv) {
    state = state.copyWith(conversation: conv);
  }

  void _updateConversation(Conversation Function(Conversation) transform) {
    final c = state.conversation;
    if (c == null) return;
    state = state.copyWith(conversation: transform(c));
  }

  // ── 初始化 ──

  void configureCapabilities(SettingsData settings) {
    _settingsData = settings;
    final config = settings.modelSelectionConfig;
    _adapter = CapabilityAdapter(
      config: config,
      state: settings,
      providerFactory: (id) => ProviderFactory.get(id),
    );
    _toolRegistry.clear();
    _adapter!.registerTools(_toolRegistry);
    PluginRegistry().registerTo(_toolRegistry);
  }

  Future<void> init() async {
    if (_initialized) return;
    await _cacheManager.init();
    _promptBuilder = await SystemPromptBuilder.load();

    if (!_memoryInitialized) {
      await _memory.init();
      _convMemManager = ConversationalMemoryManager(memoryNotifier: _memory);
      _memoryInitialized = true;
    }

    // 加载并启用所有捆版插件
    await PluginRegistry().enableAll();
    // configureCapabilities 同步先跑、registerTo 时 _activeHosts 仍为空，
    // 现在插件已就绪，把插件工具注入到本 ChatNotifier 的 _toolRegistry
    PluginRegistry().registerTo(_toolRegistry);

    _initialized = true;
    debugPrint('[ChatNotifier] 初始化完成，记忆系统就绪');
  }

  // ── 系统提示词 ──

  Future<void> _ensurePromptBuilder() async {
    if (_promptBuilder != null) return;
    _promptBuilder = await SystemPromptBuilder.load();
  }

  String _buildSystemPromptString() {
    if (_promptBuilder == null) return '';
    if (_settingsData?.lightweightSystemPrompt == true) {
      return _promptBuilder!.buildLightweightSystemPromptString(
        customPrompt: _settingsData?.userCustomPrompt,
      );
    }
    final base = _promptBuilder!.buildSystemPromptString(
      displayName: _settingsData?.userDisplayName,
      alias: _settingsData?.userAlias,
      role: _settingsData?.userRole,
      preferences: _settingsData?.userPreferences,
      facts: _settingsData?.userFacts,
      customPrompt: _settingsData?.userCustomPrompt,
    );
    // 追加插件技能块
    final pluginSkills = PluginRegistry().buildSkillBlocks();
    final withPluginBlock = pluginSkills.isNotEmpty ? '$base\n\n$pluginSkills' : base;

    if (state.memoryContextText.isNotEmpty) {
      final memBlock = '$withPluginBlock\n\n${state.memoryContextText}';
      return memBlock;
    }
    return withPluginBlock;
  }

  // ── 对话管理 ──

  void createConversation({
    required LlmConfig config,
    String? systemPrompt,
    String title = '新对话',
  }) {
    debugPrint('[ChatNotifier] 创建新对话：$title');
    _streamSubscription?.cancel();
    _completedStreams.clear();
    final conv = Conversation(
      id: Message.generateId(),
      title: title,
      config: config,
      systemPrompt: systemPrompt,
    );
    _cacheManager.resetSession();
    _convMemManager.reset();
    _memoryExtractor.clear();
    _memory.beginConversation(conv.id);
    state = state.copyWith(
      conversation: conv,
      isStreaming: false,
      error: null,
      memoryContextText: '',
    );
    // 同步到对话列表 provider，确保侧边栏即时更新
    ref.read(conversationListProvider.notifier).upsert(conv);
  }

  Future<void> loadConversation(String id) async {
    _streamSubscription?.cancel();
    _completedStreams.clear();
    final conv = await _convService.getConversation(id);
    if (conv != null) {
      await _ensurePromptBuilder();
      _convMemManager.reset();
      _memoryExtractor.clear();
      state = state.copyWith(
        conversation: conv,
        isStreaming: false,
        error: null,
        memoryContextText: '',
      );
    }
  }

  // ── 发送消息 ──

  Future<void> sendMessage(
    String content, {
    List<MediaAttachment>? attachments,
    bool streamEnabled = true,
    LlmConfig? config,
  }) async {
    if (state.isStreaming) return;

    if (state.conversation == null) {
      if (config == null) {
        state = state.copyWith(error: '无法创建对话：缺少 LLM 配置');
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
      await _convService.saveConversation(state.conversation!);
      unawaited(_generateAndUpdateTopic(content, config));
    }

    // 记忆检索
    if (_memoryInitialized) {
      final memories = await _memory.search(
        content,
        excludeConversationId: state.conversation?.id,
      );
      final memText = _memory.formatMemoryContext(memories);
      if (memText.isNotEmpty) {
        debugPrint('[ChatNotifier] 检索到 ${memories.length} 条相关记忆');
      }

      _updateConversation((conv) {
        if (memText.isNotEmpty && _promptBuilder != null) {
          return conv.copyWith(
            systemPrompt: _buildSystemPromptString(),
          );
        }
        return conv;
      });
      state = state.copyWith(memoryContextText: memText);
    }

    final effectiveAttachments =
        attachments != null && attachments.isNotEmpty ? attachments : null;

    if (effectiveAttachments != null) {
      state = state.copyWith(
        isPreprocessing: true,
        preprocessingTitle: '正在分析附件...',
        preprocessingText:
            '正在分析 ${effectiveAttachments.length} 个附件...',
      );
      _preprocessingStreamController.add('开始分析附件...\n');
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
        state = state.copyWith(
          isPreprocessing: false,
          preprocessingTitle: '',
          preprocessingText: '',
        );
      }
    }

    final userMsg = Message(
      id: Message.generateId(),
      role: MessageRole.user,
      content: adaptedContent,
      mediaAttachments: attachments,
      status: MessageStatus.completed,
      timestamp: DateTime.now(),
    );

    _updateConversation(
      (conv) => conv.copyWith(
        messages: [...conv.messages, userMsg],
      ),
    );

    final assistantId = Message.generateId();
    final streamingMsg = Message.streamingAssistant(id: assistantId);
    _updateConversation(
      (conv) => conv.copyWith(
        messages: [...conv.messages, streamingMsg],
      ),
    );
    state = state.copyWith(isStreaming: true);

    if (streamEnabled) {
      await _sendStreaming(assistantId);
    } else {
      await _sendNonStreaming(assistantId);
    }
  }

  // ── 流式发送 ──

  List<ToolDefinition> get _currentTools {
    final adapterTools = _adapter?.buildTools() ?? const <ToolDefinition>[];
    final pluginTools = PluginRegistry().allEnabledToolDefinitions;
    return [...adapterTools, ...pluginTools];
  }

  Future<void> _sendStreaming(String assistantId) async {
    final contentController = StreamController<String>.broadcast();
    _activeStreams[assistantId] = contentController;
    final thinkingController = StreamController<String>.broadcast();
    _activeThinkingStreams[assistantId] = thinkingController;

    try {
      final conv = state.conversation;
      if (conv == null) return;
      final provider = ProviderFactory.get(conv.config.providerId);
      final tools = _currentTools;
      final stream = provider.chatStream(
        config: conv.config,
        history: conv.messages.sublist(
          0,
          conv.messages.length - 1,
        ),
        systemPrompt: conv.systemPrompt,
        tools: tools.isNotEmpty ? tools : null,
      );

      String accumulatedContent = '';
      String accumulatedThinking = '';
      final accumulatedToolCalls = <ToolCall>[];
      TokenUsage? finalUsage;

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
                thinking:
                    accumulatedThinking.isNotEmpty ? accumulatedThinking : null,
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
                  thinking:
                      accumulatedThinking.isNotEmpty ? accumulatedThinking : null,
                  toolCalls: accumulatedToolCalls,
                );
              }
              break;

            case StreamChunkType.done:
              finalUsage = chunk.usage;
              // 不再用 unawaited —— _finishStreaming 的异步性由内部的
              // _completedStreams 守卫 + saveConversation 锁共同保证
              unawaited(
                _finishStreaming(
                  assistantId,
                  accumulatedContent,
                  accumulatedToolCalls,
                  accumulatedThinking.isNotEmpty ? accumulatedThinking : null,
                  finalUsage,
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
              finalUsage,
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
      final conv = state.conversation;
      if (conv == null) return;
      final provider = ProviderFactory.get(conv.config.providerId);
      final tools = _currentTools;
      final response = await provider.chat(
        config: conv.config,
        history: conv.messages.sublist(
          0,
          conv.messages.length - 1,
        ),
        systemPrompt: conv.systemPrompt,
        tools: tools.isNotEmpty ? tools : null,
      );

      final toolCalls = response.toolCalls ?? [];

      // 记录请求次数与 token 用量 — 必须在 tool call 提前返回之前执行
      debugPrint(
        '[ChatNotifier] _sendNonStreaming recordUsage: '
        'provider=${conv.config.providerId}, '
        'usage=${response.usage}, '
        'promptTokens=${response.usage?.promptTokens}, '
        'completionTokens=${response.usage?.completionTokens}',
      );
      unawaited(
        ref.read(statsProvider.notifier).recordUsage(
          providerId: conv.config.providerId,
          providerName: conv.config.providerName.isNotEmpty
              ? conv.config.providerName
              : conv.config.providerId,
          promptTokens: response.usage?.promptTokens ?? 0,
          completionTokens: response.usage?.completionTokens ?? 0,
        ),
      );

      _updateConversation((c) => c.copyWith(
        messages: c.messages.map((m) {
          if (m.id == assistantId) {
            return response.copyWith(status: MessageStatus.completed);
          }
          return m;
        }).toList(),
      ));

      if (toolCalls.isNotEmpty) {
        await _handleToolCallsAndContinue(
          assistantId,
          toolCalls,
          streamEnabled: false,
        );
        return;
      }

      state = state.copyWith(isStreaming: false);
      _convService.saveConversation(state.conversation!);
      unawaited(_commitCache());
      await _triggerMemoryPipeline(assistantId);
    } catch (e) {
      _setError('发送失败: $e', assistantId);
    }
  }

  // ── 更新消息 ──

  void _updateAssistant(
    String assistantId, {
    String? content,
    String? thinking,
    List<ToolCall>? toolCalls,
  }) {
    _updateConversation((conv) => conv.copyWith(
      messages: conv.messages.map((m) {
        if (m.id == assistantId) {
          return m.copyWith(
            content: content ?? m.content,
            thinking: thinking ?? m.thinking,
            toolCalls: toolCalls ?? m.toolCalls,
            clearToolCalls:
                toolCalls == null && m.toolCalls == null,
          );
        }
        return m;
      }).toList(),
    ));
  }

  // ── Tool 调用 ──

  Future<bool> _handleToolCallsAndContinue(
    String assistantId,
    List<ToolCall> toolCalls, {
    bool streamEnabled = true,
  }) async {
    if (toolCalls.isEmpty) return false;
    debugPrint('[ChatNotifier] _handleToolCallsAndContinue: count=${toolCalls.length}');

    final results = await _toolRegistry.executeAll(toolCalls);
    final toolResults = <String, String>{};
    for (final result in results) {
      toolResults[result.toolCallId] = result.content;
    }

    _updateConversation((conv) => conv.copyWith(
      messages: conv.messages.map((m) {
        if (m.id == assistantId) return m.copyWith(toolResults: toolResults);
        return m;
      }).toList(),
    ));

    _updateConversation((conv) {
      final newMessages = [...conv.messages];
      for (final result in results) {
        newMessages.add(
          Message(
            id: Message.generateId(),
            role: MessageRole.tool,
            content: result.content,
            toolCallId: result.toolCallId,
            status: MessageStatus.completed,
            timestamp: DateTime.now(),
          ),
        );
      }
      return conv.copyWith(messages: newMessages);
    });

    final newAssistantId = Message.generateId();
    _updateConversation(
      (conv) => conv.copyWith(
        messages: [...conv.messages, Message.streamingAssistant(id: newAssistantId)],
      ),
    );
    state = state.copyWith(isStreaming: true);

    if (streamEnabled) {
      await _sendStreaming(newAssistantId);
    } else {
      await _sendNonStreaming(newAssistantId);
    }
    return true;
  }

  // ── 流完成 ──

  Future<void> _finishStreaming(
    String assistantId,
    String content,
    List<ToolCall> toolCalls, [
    String? thinking,
    TokenUsage? usage,
  ]) async {
    // 防止 done chunk + onDone 双重触发
    if (!_completedStreams.add(assistantId)) return;

    final conv = state.conversation;
    if (conv == null) return;

    int targetIdx = -1;
    for (int i = conv.messages.length - 1; i >= 0; i--) {
      if (conv.messages[i].id == assistantId) {
        targetIdx = i;
        break;
      }
    }
    if (targetIdx < 0) return;
    if (conv.messages[targetIdx].status == MessageStatus.completed) return;

    _updateConversation((c) => c.copyWith(
      messages: c.messages.map((m) {
        if (m.id == assistantId) {
          return m.copyWith(
            content: content,
            thinking: thinking,
            toolCalls: toolCalls.isNotEmpty ? toolCalls : null,
            status: MessageStatus.completed,
          );
        }
        return m;
      }).toList(),
    ));

    _activeStreams.remove(assistantId)?.close();
    _activeThinkingStreams.remove(assistantId)?.close();

    // 记录请求次数与 token 用量 — 必须在 tool call 提前返回之前执行
    debugPrint(
      '[ChatNotifier] _finishStreaming recordUsage: '
      'provider=${conv.config.providerId}, '
      'promptTokens=${usage?.promptTokens}, '
      'completionTokens=${usage?.completionTokens}',
    );
    unawaited(
      ref.read(statsProvider.notifier).recordUsage(
        providerId: conv.config.providerId,
        providerName: conv.config.providerName.isNotEmpty
            ? conv.config.providerName
            : conv.config.providerId,
        promptTokens: usage?.promptTokens ?? 0,
        completionTokens: usage?.completionTokens ?? 0,
      ),
    );

    if (toolCalls.isNotEmpty) {
      await _handleToolCallsAndContinue(
        assistantId,
        toolCalls,
        streamEnabled: true,
      );
      return;
    }

    state = state.copyWith(isStreaming: false);
    _streamSubscription = null;
    _convService.saveConversation(state.conversation!);
    unawaited(_commitCache());
    await _triggerMemoryPipeline(assistantId);
  }

  // ── 记忆流水线 ──

  Future<void> _triggerMemoryPipeline(String assistantId) async {
    if (!_memoryInitialized) return;
    final conv = state.conversation;
    if (conv == null) return;

    Message? userMsg;
    Message? assistantMsg;
    for (int i = conv.messages.length - 1; i >= 0; i--) {
      final msg = conv.messages[i];
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
      // conv.id accessible directly
      final convConfig = conv.config;
      final provider = ProviderFactory.get(convConfig.providerId);
      final srcMsgId = assistantMsg.id;
      unawaited(
        _memoryExtractor
            .extract(provider: provider, config: convConfig)
            .then((extractions) {
          if (extractions.isNotEmpty) {
            _memoryExtractor.bufferExtractions(extractions);
            if (_memoryExtractor.shouldFlush) {
              unawaited(
                _memoryExtractor.flushToMemory(
                  memoryNotifier: _memory,
                  conversationId: conv.id,
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
      final convConfig = conv.config;
      final provider = ProviderFactory.get(convConfig.providerId);
      final recentMessages = conv.messages.sublist(
        (conv.messages.length - _convMemManager.turnsSinceLastSummary * 2)
            .clamp(0, conv.messages.length),
      );

      if (_convMemManager.hasSummary) {
        unawaited(
          _convMemManager.updateSummary(
            provider: provider,
            config: convConfig,
            messages: recentMessages,
            conversationId: conv.id,
          ),
        );
      } else {
        unawaited(
          _convMemManager.generateInitialSummary(
            provider: provider,
            config: convConfig,
            messages: recentMessages,
            conversationId: conv.id,
          ),
        );
      }
    }
  }

  // ── 错误处理 ──

  void _setError(String message, String assistantId) {
    _updateConversation((conv) => conv.copyWith(
      messages: conv.messages.map((m) {
        if (m.id == assistantId) {
          return m.copyWith(
            status: MessageStatus.error,
            errorMessage: message,
          );
        }
        return m;
      }).toList(),
    ));
    state = state.copyWith(isStreaming: false, error: message);

    _streamSubscription = null;
    _activeStreams.remove(assistantId)?.close();
    _activeThinkingStreams.remove(assistantId)?.close();
  }

  // ── 重试 / 修改 ──

  Future<void> retry({bool streamEnabled = true}) async {
    if (state.conversation == null || state.isStreaming) return;
    final messages = state.conversation!.messages;
    if (messages.length < 2) return;

    final lastUserIdx = messages.lastIndexWhere(
      (m) => m.role == MessageRole.user,
    );

    // 移除最后一条 assistant 消息
    _updateConversation((conv) => conv.copyWith(
      messages: conv.messages.sublist(0, conv.messages.length - 1),
    ));

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
    if (state.conversation == null || state.isStreaming) return;

    int index = -1;
    _updateConversation((conv) {
      index = conv.messages.indexWhere((m) => m.id == messageId);
      if (index < 0 || conv.messages[index].role != MessageRole.user) {
        return conv;
      }
      return conv.copyWith(
        messages: [
          ...conv.messages.take(index),
          conv.messages[index].copyWith(content: newContent),
          ...conv.messages.skip(index + 1),
        ],
      );
    });

    if (index < 0) return;
    final msg = state.conversation!.messages[index];
    if (msg.role != MessageRole.user) return;

    // 截断后续消息
    _updateConversation(
      (conv) => conv.copyWith(messages: conv.messages.sublist(0, index + 1)),
    );

    await sendMessage(newContent, streamEnabled: streamEnabled);
  }

  // ── 停止 ──

  void stopStreaming() {
    _streamSubscription?.cancel();
    _streamSubscription = null;
    _closeAllStreams();
    state = state.copyWith(
      isStreaming: false,
      isPreprocessing: false,
      preprocessingTitle: '',
      preprocessingText: '',
    );
  }

  // ── 流 Stream API ──

  Stream<String>? getContentStream(String messageId) {
    return _activeStreams[messageId]?.stream;
  }

  Stream<String>? getThinkingStream(String messageId) {
    return _activeThinkingStreams[messageId]?.stream;
  }

  Stream<String> get preprocessingStream =>
      _preprocessingStreamController.stream;

  // ── 缓存管理 ──

  Future<void> initCache() async {
    await _cacheManager.init();
  }

  PromptSectionCollection _buildCacheCollection() {
    final sections = <PromptSection>[];
    final isLightweight = _settingsData?.lightweightSystemPrompt == true;

    if (_promptBuilder != null) {
      final spSections = isLightweight
          ? _promptBuilder!.buildLightweightSystemPrompt(
              customPrompt: _settingsData?.userCustomPrompt,
            )
          : _promptBuilder!.buildSystemPrompt(
              displayName: _settingsData?.userDisplayName,
              alias: _settingsData?.userAlias,
              role: _settingsData?.userRole,
              preferences: _settingsData?.userPreferences,
              facts: _settingsData?.userFacts,
              customPrompt: _settingsData?.userCustomPrompt,
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
    } else if (state.conversation?.systemPrompt != null &&
        state.conversation!.systemPrompt!.isNotEmpty) {
      sections.add(
        _cacheManager.buildPromptSection(
          state.conversation!.systemPrompt!,
          ttlSeconds: 300,
        ),
      );
    }

    if (!isLightweight && state.memoryContextText.isNotEmpty) {
      sections.add(
        PromptSection.create(
          id: 'system.block4.memory_context',
          type: PromptSectionType.memory,
          content: state.memoryContextText,
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
        _cacheManager.buildToolSection(
          toolDefsMap.toString(),
          ttlSeconds: 300,
        ),
      );
    }

    return PromptSectionCollection(sections);
  }

  Future<void> _commitCache() async {
    final collection = _buildCacheCollection();

    // 统计缓存命中/未命中
    final cached = _cacheManager.cached;
    int hitCount = 0;
    int missCount = 0;
    for (final section in collection.sections) {
      final existing = cached.sections.where(
        (s) => s.id == section.id,
      );
      if (existing.isNotEmpty &&
          !existing.first.isExpired &&
          existing.first.content == section.content) {
        hitCount++;
      } else {
        missCount++;
      }
    }
    if (hitCount + missCount > 0) {
      final cfg = state.conversation?.config;
      if (cfg != null) {
        final providerId = cfg.providerId;
        final providerName = cfg.providerName.isNotEmpty
            ? cfg.providerName
            : cfg.providerId;
        if (hitCount > 0) {
          unawaited(
            ref.read(statsProvider.notifier).recordCacheHit(
              providerId: providerId,
              providerName: providerName,
            ),
          );
        }
        if (missCount > 0) {
          unawaited(
            ref.read(statsProvider.notifier).recordCacheMiss(
              providerId: providerId,
              providerName: providerName,
            ),
          );
        }
      }
    }

    _cacheManager.commitCollection(collection);
    await _cacheManager.persistCacheable(collection);
  }

  // ── 清空 ──

  void clear() {
    _streamSubscription?.cancel();
    _closeAllStreams();
    _completedStreams.clear();
    _convMemManager.reset();
    _memoryExtractor.clear();
    _memory.clearCache();
    _preprocessingStreamController.add('');
    state = const ChatData();
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

  // ── 话题生成 ──

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
      final topic =
          JsonExtractor.tryExtractField(response.content, 'topic') ??
              response.content.trim();
      if (topic.isEmpty) return;
      final sanitized = topic.length > 25 ? topic.substring(0, 25) : topic;
      _updateConversation((conv) {
        conv.title = sanitized;
        _convService.renameConversation(conv.id, sanitized);
        // 同步标题到侧边栏列表
        ref.read(conversationListProvider.notifier).updateTitle(
          conv.id,
          sanitized,
        );
        return conv;
      });
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
}

// =============================================================================
// Provider
// =============================================================================

final chatProvider = NotifierProvider<ChatNotifier, ChatData>(
  ChatNotifier.new,
);