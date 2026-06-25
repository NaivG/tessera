import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/core.dart';
import '../llm/provider_factory.dart';
import '../memory/memory.dart';
import '../plugin/plugin.dart';
import '../services/conversation_service.dart';
import '../utils/json_extractor.dart';
import '../utils/plan_parser.dart';
import 'conversation_list_provider.dart';
import 'session_provider.dart';
import 'settings_provider.dart';
import 'stats_provider.dart';
import 'workspace_provider.dart';

// =============================================================================
// ChatData
// =============================================================================

class ChatData {
  /// 当前显示的对话(向后兼容)。等价于 `conversationsCache[当前正在浏览的对话ID]` 的快照。
  /// 与运行中的对话解耦 — 用户可在另一对话运行时只读浏览其他对话。
  final Conversation? conversation;

  /// 是否正在流式输出。等价于 `runningConversationId != null`。
  final bool isStreaming;

  final bool isPreprocessing;
  final String preprocessingTitle;
  final String preprocessingText;
  final String? error;
  final String memoryContextText;
  final ConversationMode pendingMode;
  final List<Session> sessions;
  final String activeSessionId;

  /// 当前正在流式执行的对话 ID。同一时刻最多一个对话处于运行状态。
  /// 在 `_sendStreaming` 启动时设置,在 `_finishStreaming` / `_setError` /
  /// `stopStreaming` 清理时清空。
  final String? runningConversationId;

  /// 已加载到内存中的对话缓存,key = conversation.id。
  /// 切换显示时不取消流,直接修改 `conversation` 指针即可;运行中的对话实例
  /// 始终保存在 cache 中,流订阅通过 `_streamSubscriptions[convId]` 索引。
  final Map<String, Conversation> conversationsCache;

  /// 子 Agent 进度文本映射（sessionId → 累积内容），供 SubAgentCard 流式展示。
  final Map<String, String> subAgentProgress;

  const ChatData({
    this.conversation,
    this.isStreaming = false,
    this.isPreprocessing = false,
    this.preprocessingTitle = '',
    this.preprocessingText = '',
    this.error,
    this.memoryContextText = '',
    this.pendingMode = ConversationMode.normal,
    this.sessions = const [],
    this.activeSessionId = '',
    this.runningConversationId,
    this.conversationsCache = const {},
    this.subAgentProgress = const {},
  });

  List<Message> get messages => conversation?.messages ?? [];
  List<Message> get displayMessages {
    final all = messages;
    if (all.isEmpty) return all;
    // Filter by active session
    final filtered = all.where((m) {
      if (activeSessionId.isEmpty || activeSessionId == conversation?.id) {
        // Main session: show messages where sessionId is null or matches conversation id
        return m.sessionId == null || m.sessionId == conversation?.id;
      }
      // Sub-agent session: show only messages for that session
      return m.sessionId == activeSessionId;
    }).toList();
    return filtered.where((m) => m.role != MessageRole.tool).toList();
  }

  bool get hasConversation => conversation != null;

  /// 当前显示的对话不是运行中的对话(用户在浏览只读视图)。
  bool get isReadOnlyView =>
      runningConversationId != null &&
      conversation?.id != runningConversationId;

  /// 当前显示的对话就是正在运行中的对话。
  bool get isDisplayedRunning =>
      conversation != null && conversation!.id == runningConversationId;

  ChatData copyWith({
    Conversation? conversation,
    bool? isStreaming,
    bool? isPreprocessing,
    String? preprocessingTitle,
    String? preprocessingText,
    String? error,
    String? memoryContextText,
    ConversationMode? pendingMode,
    List<Session>? sessions,
    String? activeSessionId,
    String? runningConversationId,
    Map<String, Conversation>? conversationsCache,
    Map<String, String>? subAgentProgress,
    bool clearConversation = false,
    bool clearError = false,
    bool clearRunningConversation = false,
  }) {
    return ChatData(
      conversation: clearConversation ? null : conversation ?? this.conversation,
      isStreaming: isStreaming ?? this.isStreaming,
      isPreprocessing: isPreprocessing ?? this.isPreprocessing,
      preprocessingTitle: preprocessingTitle ?? this.preprocessingTitle,
      preprocessingText: preprocessingText ?? this.preprocessingText,
      error: clearError ? null : error ?? this.error,
      memoryContextText: memoryContextText ?? this.memoryContextText,
      pendingMode: pendingMode ?? this.pendingMode,
      sessions: sessions ?? this.sessions,
      activeSessionId: activeSessionId ?? this.activeSessionId,
      runningConversationId: clearRunningConversation
          ? null
          : runningConversationId ?? this.runningConversationId,
      conversationsCache: conversationsCache ?? this.conversationsCache,
      subAgentProgress: subAgentProgress ?? this.subAgentProgress,
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
  final SubAgentManager _subAgentManager = SubAgentManager();

  SystemPromptBuilder? _promptBuilder;
  SettingsData? _settingsData;
  bool _initialized = false;
  bool _memoryInitialized = false;

  /// 按 conversationId 索引的流订阅。同一时刻只有一个会话运行(由
  /// `runningConversationId` 保证),但用 Map 表达便于未来扩展。
  final Map<String, StreamSubscription<StreamChunk>> _streamSubscriptions = {};
  final Map<String, StreamController<String>> _activeStreams = {};
  final Map<String, StreamController<String>> _activeThinkingStreams = {};

  /// 已完成的流 ID 集合，防止 _finishStreaming 被 done chunk + onDone 双重触发
  final Set<String> _completedStreams = {};

  /// 子 Agent 流句柄，按 sessionId 索引，供 stopStreaming 统一取消。
  final Map<String, SubAgentStreamHandle> _subAgentHandles = {};

  /// 统一发现管理器
  final DiscoverManager _discoverManager = DiscoverManager();

  /// 运行时工具调用参数校验器
  final ToolCallValidator _toolCallValidator = ToolCallValidator();

  /// LLM 通过 discover 工具发现后、下一轮 API 调用时注入完整 schema 的工具名集合。
  final Set<String> _discoveredInSession = {};

  /// 临时记录 `sendMessage` 流程中正在操作的 convId,供 `_sendNormal` /
  /// `_sendPlanMode` 等模式分发方法使用。`sendMessage` 进入时设置,
  /// 退出前清空。
  String? _activeSendConvId;

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
    for (final sub in _streamSubscriptions.values) {
      sub.cancel();
    }
    _streamSubscriptions.clear();
    for (final handle in _subAgentHandles.values) {
      handle.cancel();
    }
    _subAgentHandles.clear();
    _closeAllStreams();
    _completedStreams.clear();
    _preprocessingStreamController.close();
  }

  // ── 内部 helper ──

  /// 将 `conv` 写入 `conversationsCache`;若 `conv.id == 当前显示的 conversation.id`,
  /// 同步更新 `state.conversation` 指针,保持 UI 即时响应。
  void _putConversation(Conversation conv) {
    final cache = Map<String, Conversation>.from(state.conversationsCache);
    cache[conv.id] = conv;
    // 若 convId 与当前显示对话一致,需要让 `state.conversation` 指针也跟着更新,
    // 否则 UI 不会重渲染。一次性把两个字段都设置好。
    if (state.conversation?.id == conv.id) {
      state = state.copyWith(conversation: conv, conversationsCache: cache);
    } else {
      state = state.copyWith(conversationsCache: cache);
    }
  }

  /// 按 convId 读取并写回 cache;若 convId == 当前显示 ID,同步更新 `state.conversation`。
  void _updateConversationById(
    String convId,
    Conversation Function(Conversation) transform,
  ) {
    final c = state.conversationsCache[convId];
    if (c == null) return;
    _putConversation(transform(c));
  }

  /// 从 cache 移除指定对话(用于删除对话)。同时清空 `runningConversationId`
  /// 如果它指向被删除的对话(防御性)。
  void _removeConversationFromCache(String convId) {
    if (!state.conversationsCache.containsKey(convId)) return;
    final cache = Map<String, Conversation>.from(state.conversationsCache);
    cache.remove(convId);
    final isDisplayed = state.conversation?.id == convId;
    state = state.copyWith(
      conversationsCache: cache,
      clearConversation: isDisplayed,
      clearRunningConversation:
          state.runningConversationId == convId || isDisplayed,
    );
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
    _discoveredInSession.clear();
    // 首先注册 discover meta-tool（始终可用）
    _toolRegistry.register(discoverTool, _handleDiscover);
    _adapter!.registerTools(_toolRegistry);
    PluginRegistry().registerTo(_toolRegistry);
    // 工作空间工具 — 由 WorkspaceApprovalCoordinator 异步审批
    registerWorkspaceTools(_toolRegistry, confirmer: _confirmWorkspaceAction);
  }

  Future<void> init() async {
    if (_initialized) return;
    await _cacheManager.init();
    _promptBuilder = await SystemPromptBuilder.load();
    await _promptBuilder!.loadFableCore();

    if (!_memoryInitialized) {
      await _memory.init();
      _convMemManager = ConversationalMemoryManager(memoryNotifier: _memory);
      _memoryInitialized = true;
    }

    // 加载并启用所有捆版插件
    await PluginRegistry().enableAll();
    // configureCapabilities 同步先跑、registerTo 时 _activeHosts 仍为空，
    // 现在插件已就绪，把插件工具注入到本 ChatNotifier 的 _toolRegistry。
    // 注意：discover meta-tool 已在 configureCapabilities 中注册，这里补注册确保不丢失。
    if (!_toolRegistry.has('discover')) {
      _toolRegistry.register(discoverTool, _handleDiscover);
    }
    PluginRegistry().registerTo(_toolRegistry);
    // 工作空间工具 — 防止 configureCapabilities 清空后未重新注册
    if (!_toolRegistry.has('workspace_list')) {
      registerWorkspaceTools(_toolRegistry, confirmer: _confirmWorkspaceAction);
    }

    _initialized = true;
    debugPrint('[ChatNotifier] 初始化完成，记忆系统就绪');
  }

  // ── 系统提示词 ──

  Future<void> _ensurePromptBuilder() async {
    if (_promptBuilder != null) return;
    _promptBuilder = await SystemPromptBuilder.load();
  }

  String _buildSystemPromptString({ConversationMode? mode}) {
    if (_promptBuilder == null) return '';
    final settings = _settingsData;
    String base;
    if (settings?.fableMode == true) {
      base = _promptBuilder!.buildFableSystemPromptString(
        displayName: settings?.userDisplayName,
        alias: settings?.userAlias,
        role: settings?.userRole,
        preferences: settings?.userPreferences,
        facts: settings?.userFacts,
        customPrompt: settings?.userCustomPrompt,
      );
    } else if (settings?.lightweightSystemPrompt == true) {
      base = _promptBuilder!.buildLightweightSystemPromptString(
        customPrompt: settings?.userCustomPrompt,
      );
    } else {
      base = _promptBuilder!.buildSystemPromptString(
        displayName: settings?.userDisplayName,
        alias: settings?.userAlias,
        role: settings?.userRole,
        preferences: settings?.userPreferences,
        facts: settings?.userFacts,
        customPrompt: settings?.userCustomPrompt,
      );
    }

    // 追加紧凑技能目录 + discover 使用说明
    final skills = PluginRegistry().allSkills;
    final catalog = _discoverManager.buildCompactCatalog(skills);
    if (catalog.isNotEmpty) {
      base = '$base\n\n$catalog';
    }
    base = '$base\n\n${_discoverManager.buildDiscoverGuidance()}';

    String result = base;
    if (state.memoryContextText.isNotEmpty) {
      result = '$result\n\n${state.memoryContextText}';
    }

    // 追加模式特定提示
    if (mode != null && mode != ConversationMode.normal) {
      final modePrompt = _buildModeSpecificPrompt(mode);
      if (modePrompt.isNotEmpty) {
        result = '$result\n\n$modePrompt';
      }
    }

    return result;
  }

  /// 构建模式特定的 system prompt
  String _buildModeSpecificPrompt(ConversationMode mode) {
    switch (mode) {
      case ConversationMode.normal:
        return '';
      case ConversationMode.plan:
        return '''
When the user gives you a task, first generate a structured execution plan in JSON format:
{"steps": [{"title": "step name", "description": "what to do"}]}
Then execute each step sequentially, updating the user on progress.
Wrap the plan JSON in a ```json code block.''';
      case ConversationMode.agent:
        return '''
You have access to the spawn_sub_agent tool. When a task can be decomposed into subtasks,
call spawn_sub_agent with a clear task description for each subtask.
Sub-agents will execute independently and return results to you.''';
      case ConversationMode.agentCluster:
        return '''
When the user gives you a task, first generate a plan that decomposes the task into parallel subtasks in JSON format:
{"tasks": [{"title": "task name", "description": "what to do"}]}
These tasks will be executed in parallel by independent sub-agents.
Wrap the plan JSON in a ```json code block.''';
    }
  }

  // ── 对话管理 ──

  void createConversation({
    required LlmConfig config,
    ConversationMode mode = ConversationMode.normal,
    String? systemPrompt,
    String title = '新对话',
  }) {
    debugPrint('[ChatNotifier] 创建新对话：$title, mode=${mode.name}');
    // 不取消运行中的对话 — `sendMessage` 的守卫会保证调用此方法时无运行。

    // 新对话：重置发现状态
    _discoveredInSession.clear();

    final conv = Conversation(
      id: Message.generateId(),
      title: title,
      config: config,
      systemPrompt: systemPrompt,
      mode: mode,
    );
    conv.activeSessionId = conv.id; // 主 Session ID = Conversation ID
    _cacheManager.resetSession();
    _convMemManager.reset();
    _memoryExtractor.clear();
    _memory.beginConversation(conv.id);

    // 创建主 Session
    final mainSession = Session(
      id: conv.id,
      conversationId: conv.id,
      type: SessionType.main,
      title: title,
      mode: mode,
      status: SessionStatus.active,
      sortOrder: 0,
      createdAt: conv.createdAt,
      updatedAt: conv.updatedAt,
    );

    // 写入 cache + 显示指针 + 标记为运行中
    _putConversation(conv);
    state = state.copyWith(
      conversation: conv, // 新对话自动成为显示中的对话
      isStreaming: false,
      error: null,
      memoryContextText: '',
      sessions: [mainSession],
      activeSessionId: conv.id,
      runningConversationId: conv.id,
    );
    // 注册主 Session 到数据库
    ref.read(sessionProvider.notifier).registerMainSession(mainSession);
    // 同步到对话列表 provider，确保侧边栏即时更新
    ref.read(conversationListProvider.notifier).upsert(conv);
  }

  /// 新对话状态下切换模式（仅当 conversation == null 时有效）
  void setPendingMode(ConversationMode mode) {
    if (state.conversation != null) return; // 已有对话，不允许切换
    state = state.copyWith(pendingMode: mode);
  }

  /// 切换到指定 Session，自动加载该 Session 的消息到内存。
  Future<void> switchSession(String sessionId) async {
    final convId = state.conversation?.id;
    if (convId == null) return;

    // 更新 Session 提供者中的活跃 Session
    ref.read(sessionProvider.notifier).switchSession(sessionId);
    state = state.copyWith(activeSessionId: sessionId);

    // 如果切换到子 Agent Session，检查内存中是否已有该 Session 的消息；
    // 若无，从数据库加载并注入到当前对话的 messages 列表中。
    final conv = state.conversationsCache[convId];
    if (conv == null) return;
    final hasMessages = conv.messages.any((m) => m.sessionId == sessionId);
    if (hasMessages) return;

    try {
      final loaded = await _convService.getMessagesBySession(sessionId);
      if (loaded.isNotEmpty) {
        _updateConversationById(convId, (c) {
          // 合并已加载消息，去重
          final existingIds = c.messages.map((m) => m.id).toSet();
          final newMsgs = loaded.where((m) => !existingIds.contains(m.id)).toList();
          if (newMsgs.isEmpty) return c;
          final merged = [...c.messages, ...newMsgs]
            ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
          return c.copyWith(messages: merged);
        });
      }
    } catch (e) {
      debugPrint('[ChatNotifier] 加载 Session $sessionId 消息失败: $e');
    }
  }

  /// 切换当前显示的对话 — 不取消任何运行中的流。
  ///
  /// 这是关键的拆分点:旧 `loadConversation` 会取消流订阅,导致用户在流式过程中
  /// 点侧边栏时直接打断输出。本方法只修改显示指针,让运行中的对话在 cache 中
  /// 继续完成。
  Future<void> setDisplayedConversation(String id) async {
    // 先从 cache 查找;若 cache 中没有再从 DB 加载
    Conversation? conv = state.conversationsCache[id] ??
        await _convService.getConversation(id);
    if (conv == null) return;

    // 同步到 SessionNotifier
    ref.read(sessionProvider.notifier).setSessions(conv.sessions, activeId: conv.id);

    // 更新显示指针 — 不动 runningConversationId / isStreaming / isPreprocessing
    state = state.copyWith(
      conversation: conv,
      error: null,
      memoryContextText: '',
      sessions: conv.sessions,
      activeSessionId: conv.id,
    );
  }

  /// 仅加载到 cache 但不切换显示。用于预热或批量加载场景。
  Future<Conversation?> warmLoadConversation(String id) async {
    if (state.conversationsCache.containsKey(id)) {
      return state.conversationsCache[id];
    }
    final conv = await _convService.getConversation(id);
    if (conv != null) {
      _putConversation(conv);
    }
    return conv;
  }

  /// 从 cache 和 DB 中移除指定对话。仅在非运行状态下允许删除(由 UI 层守卫)。
  void removeConversation(String id) {
    _removeConversationFromCache(id);
  }

  /// 进入草稿状态(新对话)— 不取消运行中的对话。
  ///
  /// 与 `clear()` 的区别:`clear()` 会取消所有流(用于 app shutdown),
  /// `enterDraft()` 仅重置显示指针,运行中的对话实例仍在 cache 中继续完成。
  void enterDraft() {
    // 如果当前显示的就是运行中的对话,不能盲目清空 — 让它继续
    // (此时 UI 上仍能看到它的流式输出,只是"草稿"语义不适用)
    if (state.isDisplayedRunning) {
      // 显示指针保持不变,只清空 sessions/activeSessionId 等草稿相关字段
      state = state.copyWith(
        sessions: const [],
        activeSessionId: '',
        error: null,
        isPreprocessing: false,
        preprocessingTitle: '',
        preprocessingText: '',
      );
      return;
    }
    state = state.copyWith(
      clearConversation: true,
      sessions: const [],
      activeSessionId: '',
      error: null,
      isPreprocessing: false,
      preprocessingTitle: '',
      preprocessingText: '',
    );
    ref.read(sessionProvider.notifier).clear();
  }

  /// 完全重置(包括运行中的)— 仅 dispose / app shutdown 使用。
  /// UI 层应使用 `enterDraft()` 进入新对话草稿状态。
  void clear() {
    for (final sub in _streamSubscriptions.values) {
      sub.cancel();
    }
    _streamSubscriptions.clear();
    _closeAllStreams();
    _completedStreams.clear();
    _convMemManager.reset();
    _memoryExtractor.clear();
    _memory.clearCache();
    _preprocessingStreamController.add('');
    ref.read(sessionProvider.notifier).clear();
    state = ChatData(conversationsCache: state.conversationsCache);
  }

  /// 旧 `loadConversation` 接口的兼容包装,转发到 `setDisplayedConversation`。
  /// 保留以避免大规模调用方改动;新代码应直接使用 `setDisplayedConversation`。
  Future<void> loadConversation(String id) =>
      setDisplayedConversation(id);

  // ── 发送消息 ──

  Future<void> sendMessage(
    String content, {
    List<MediaAttachment>? attachments,
    bool streamEnabled = true,
    LlmConfig? config,
  }) async {
    // 守卫:已有运行中的对话,不允许启动新的发送
    if (state.runningConversationId != null) return;

    if (state.conversation == null) {
      if (config == null) {
        state = state.copyWith(error: '无法创建对话：缺少 LLM 配置');
        return;
      }
      await _ensurePromptBuilder();
      final title = _fallbackTopic(content);
      final mode = state.pendingMode; // 模式在此刻定死
      final systemPrompt = _buildSystemPromptString(mode: mode);
      createConversation(
        config: config,
        mode: mode,
        title: title,
        systemPrompt: systemPrompt.isNotEmpty ? systemPrompt : null,
      );
      final convId = state.conversation!.id;
      await _convService.saveConversation(state.conversation!);
      unawaited(_generateAndUpdateTopic(convId, content, config));
      // 已经在 createConversation 中设置了 runningConversationId,这里记录一下 convId
      // 供下面使用
      _activeSendConvId = convId;
    } else {
      _activeSendConvId = state.conversation!.id;
    }

    final sendConvId = _activeSendConvId!;
    final sendConv = state.conversationsCache[sendConvId] ?? state.conversation;

    // 记忆检索
    if (_memoryInitialized) {
      final memories = await _memory.search(
        content,
        excludeConversationId: sendConv?.id,
      );
      final memText = _memory.formatMemoryContext(memories);
      if (memText.isNotEmpty) {
        debugPrint('[ChatNotifier] 检索到 ${memories.length} 条相关记忆');
      }

      if (memText.isNotEmpty && _promptBuilder != null && sendConv != null) {
        _updateConversationById(sendConvId, (conv) => conv.copyWith(
              systemPrompt: _buildSystemPromptString(mode: conv.mode),
            ));
      }
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
      sessionId: state.activeSessionId.isEmpty ? null : state.activeSessionId,
    );

    _updateConversationById(
      sendConvId,
      (conv) => conv.copyWith(messages: [...conv.messages, userMsg]),
    );

    // 根据模式分发 — 所有方法现在通过 sendConvId 定位 cache 中的对话
    final mode = sendConv!.mode;
    switch (mode) {
      case ConversationMode.normal:
        await _sendNormal(sendConvId, userMsg, streamEnabled);
        break;
      case ConversationMode.plan:
        await _sendPlanMode(sendConvId, content, streamEnabled);
        break;
      case ConversationMode.agent:
        await _sendAgentMode(sendConvId, userMsg, streamEnabled);
        break;
      case ConversationMode.agentCluster:
        await _sendAgentClusterMode(sendConvId, content, streamEnabled);
        break;
    }
    _activeSendConvId = null;
  }

  /// Normal 模式 — 直接复用现有流式/非流式逻辑
  Future<void> _sendNormal(
    String convId,
    Message userMsg,
    bool streamEnabled,
  ) async {
    final assistantId = Message.generateId();
    final streamingMsg = Message.streamingAssistant(id: assistantId);
    _updateConversationById(
      convId,
      (conv) => conv.copyWith(messages: [...conv.messages, streamingMsg]),
    );
    state = state.copyWith(isStreaming: true);

    if (streamEnabled) {
      await _sendStreaming(convId, assistantId);
    } else {
      await _sendNonStreaming(convId, assistantId);
    }
  }

  /// Plan 模式 — 两阶段：计划生成 + 逐步执行
  Future<void> _sendPlanMode(
    String convId,
    String userContent,
    bool streamEnabled,
  ) async {
    final conv = state.conversationsCache[convId];
    if (conv == null) return;

    // 阶段一：让 LLM 生成计划（使用流式接收）
    final planAssistantId = Message.generateId();
    final streamingMsg = Message.streamingAssistant(id: planAssistantId);
    _updateConversationById(
      convId,
      (c) => c.copyWith(messages: [...c.messages, streamingMsg]),
    );
    state = state.copyWith(isStreaming: true);

    if (streamEnabled) {
      await _sendStreaming(convId, planAssistantId);
    } else {
      await _sendNonStreaming(convId, planAssistantId);
    }

    // 等待流式完成后解析计划 — 此时用户可能已切走到其他对话,
    // 所以从 cache 读取最新消息,而不是 state.conversation。
    final finalConv = state.conversationsCache[convId];
    if (finalConv == null) return;
    final lastMsg = finalConv.messages.last;
    if (lastMsg.role != MessageRole.assistant) return;

    final plan = PlanParser.parse(lastMsg.content);
    if (plan != null && plan.steps.isNotEmpty) {
      final planMsgId = lastMsg.id;
      debugPrint('[ChatNotifier] Plan 模式: 解析到 ${plan.steps.length} 个步骤');

      // 为计划消息添加 metadata 标记，所有步骤初始状态 pending
      _updatePlanStepsMetadata(convId, planMsgId, plan.steps);

      // ── 阶段二：逐步执行 ──
      // 累积每个步骤的执行结果，为后续步骤提供上下文
      final stepResults = <String, String>{};

      for (var i = 0; i < plan.steps.length; i++) {
        final step = plan.steps[i];
        debugPrint('[ChatNotifier] Plan 阶段二: 执行步骤 ${i + 1}/${plan.steps.length}: ${step.title}');

        // 更新的步骤列表：将当前步骤标记为 inProgress
        final updatedSteps = List<PlanStep>.from(plan.steps);
        updatedSteps[i] = step.copyWith(status: PlanStepStatus.inProgress);
        _updatePlanStepsMetadata(convId, planMsgId, updatedSteps);

        // 构建该步骤的执行上下文
        final stepContext = StringBuffer();
        stepContext.writeln('You are executing step ${i + 1} of a plan. '
            'The original task was: "$userContent"');
        stepContext.writeln();
        stepContext.writeln('Current step: ${step.title}');
        if (step.description.isNotEmpty) {
          stepContext.writeln('Description: ${step.description}');
        }

        // 注入之前步骤的结果作为上下文
        if (stepResults.isNotEmpty) {
          stepContext.writeln();
          stepContext.writeln('Results from previous steps:');
          for (var j = 0; j < i; j++) {
            final prevStep = plan.steps[j];
            stepContext.writeln('- Step "${prevStep.title}": ${stepResults[prevStep.title] ?? "(no result)"}');
          }
        }

        stepContext.writeln();
        stepContext.writeln('Please execute this step now. Focus only on this specific task.');

        // 创建用户消息模拟该步骤的指令（但实际用 system prompt 注入上下文更好）
        // 这里我们直接发送一条包含步骤上下文的新消息到 LLM
        final stepAssistantId = Message.generateId();
        final stepStreamingMsg = Message.streamingAssistant(id: stepAssistantId);
        _updateConversationById(
          convId,
          (c) => c.copyWith(messages: [...c.messages, stepStreamingMsg]),
        );

        // 流式执行该步骤 — 使用对话的系统提示词 + 步骤上下文
        await _sendStreamingWithContext(
          convId: convId,
          assistantId: stepAssistantId,
          contextPrompt: stepContext.toString(),
        );

        // 从 cache 中获取该步骤的输出
        final stepConv = state.conversationsCache[convId];
        final stepMsg = stepConv?.messages.lastWhere(
          (m) => m.id == stepAssistantId,
          orElse: () => stepConv.messages.last,
        );
        final stepOutput = stepMsg?.content ?? '';
        stepResults[step.title] = stepOutput;

        // 标记该步骤为 completed
        updatedSteps[i] = step.copyWith(status: PlanStepStatus.completed);
        _updatePlanStepsMetadata(convId, planMsgId, updatedSteps);
      }

      // 全部完成，发送总结
      final summaryId = Message.generateId();
      final summaryMsg = Message(
        id: summaryId,
        role: MessageRole.assistant,
        content: 'All ${plan.steps.length} steps completed. Check the plan above for individual step results.',
        sessionId: convId,
        metadata: {'type': 'plan_complete'},
        timestamp: DateTime.now(),
      );
      _updateConversationById(
        convId,
        (c) => c.copyWith(messages: [...c.messages, summaryMsg]),
      );
    }

    state = state.copyWith(isStreaming: false);
    final savedConv = state.conversationsCache[convId];
    if (savedConv != null) {
      _convService.saveConversation(savedConv);
    }
  }

  /// 更新计划消息中步骤的 metadata
  void _updatePlanStepsMetadata(
    String convId,
    String planMsgId,
    List<PlanStep> steps,
  ) {
    _updateConversationById(convId, (c) {
      return c.copyWith(
        messages: c.messages.map((m) {
          if (m.id == planMsgId) {
            return m.copyWith(
              metadata: {
                'type': 'plan',
                'steps': steps.map((s) => s.toJson()).toList(),
              },
            );
          }
          return m;
        }).toList(),
      );
    });
  }

  /// 带自定义上下文的流式发送 —
  /// 在对话 system prompt 后注入步骤上下文，不修改对话的 system prompt。
  Future<void> _sendStreamingWithContext({
    required String convId,
    required String assistantId,
    required String contextPrompt,
  }) async {
    final contentController = StreamController<String>.broadcast();
    _activeStreams[assistantId] = contentController;
    final thinkingController = StreamController<String>.broadcast();
    _activeThinkingStreams[assistantId] = thinkingController;

    try {
      final conv = state.conversationsCache[convId];
      if (conv == null) return;
      final provider = ProviderFactory.get(conv.config.providerId);
      final tools = _currentTools;

      // 构建增强的 system prompt：基础提示词 + 步骤上下文
      final enhancedPrompt = '${conv.systemPrompt ?? ''}\n\n$contextPrompt';

      final stream = provider.chatStream(
        config: conv.config,
        history: conv.messages.where((m) => m.id != assistantId && m.status != MessageStatus.streaming).toList(),
        systemPrompt: enhancedPrompt,
        tools: tools.isNotEmpty ? tools : null,
      );

      String accumulatedContent = '';
      String accumulatedThinking = '';

      _streamSubscriptions[convId] = stream.listen(
        (chunk) {
          switch (chunk.type) {
            case StreamChunkType.contentDelta:
              final delta = chunk.contentDelta ?? '';
              accumulatedContent += delta;
              contentController.add(delta);
              _updateAssistant(convId, assistantId, content: accumulatedContent);
              break;
            case StreamChunkType.thinkingDelta:
              final delta = chunk.thinkingDelta ?? '';
              accumulatedThinking += delta;
              thinkingController.add(delta);
              _updateAssistant(convId, assistantId, content: accumulatedContent, thinking: accumulatedThinking);
              break;
            case StreamChunkType.done:
              _finishStreaming(convId, assistantId, accumulatedContent, const <ToolCall>[], accumulatedThinking, chunk.usage);
              break;
            case StreamChunkType.error:
              _setError(convId, chunk.error ?? 'Stream error', assistantId);
              break;
            default:
              break;
          }
        },
        onError: (e) {
          _setError(convId, e.toString(), assistantId);
        },
        onDone: () {
          _finishStreaming(convId, assistantId, accumulatedContent, const <ToolCall>[], accumulatedThinking, null);
        },
      );
      // 等待流完成
      await _streamSubscriptions[convId]?.asFuture<void>();
    } catch (e) {
      debugPrint('[ChatNotifier] _sendStreamingWithContext error: $e');
    } finally {
      _streamSubscriptions.remove(convId);
      _activeStreams.remove(assistantId);
      _activeThinkingStreams.remove(assistantId);
    }
  }

  /// Agent 模式 — AI 通过 tool call 调用 spawn_sub_agent
  Future<void> _sendAgentMode(
    String convId,
    Message userMsg,
    bool streamEnabled,
  ) async {
    final conv = state.conversationsCache[convId];
    if (conv == null) return;

    // 注册 spawn_sub_agent 工具（仅 Agent 模式）
    // 闭包捕获 convId,确保用户切走到其他对话后,子 Agent 仍作用于原 convId。
    _toolRegistry.register(spawnSubAgentTool, (call) async {
      final args = parseSubAgentArgs(call);
      final currentConv = state.conversationsCache[convId];
      if (currentConv == null) {
        return ToolResult(toolCallId: call.id, content: 'No active conversation', isError: true);
      }

      final sessionId = await ref.read(sessionProvider.notifier).createSubAgentSession(
        conversationId: convId,
        parentSessionId: convId, // 主 Session
        title: args.task.length > 30 ? '${args.task.substring(0, 30)}...' : args.task,
        mode: ConversationMode.agent,
      );

      // 插入子 Agent 卡片消息到主 Session
      final cardMsg = Message(
        id: Message.generateId(),
        role: MessageRole.assistant,
        content: '',
        sessionId: convId,
        metadata: {
          'type': 'sub_agent',
          'sessionId': sessionId,
          'task': args.task,
          'status': 'running',
        },
        timestamp: DateTime.now(),
      );
      _updateConversationById(
        convId,
        (c) => c.copyWith(messages: [...c.messages, cardMsg]),
      );

      try {
        final result = await _subAgentManager.runSingle(
          task: SubAgentTask(title: args.task, description: args.task, context: args.context),
          config: currentConv.config,
          conversationId: convId,
          sessionId: sessionId,
          systemPrompt: _buildSystemPromptString(),
          onProgress: (delta) {
            final updatedProgress = Map<String, String>.from(state.subAgentProgress);
            final existing = updatedProgress[sessionId] ?? '';
            updatedProgress[sessionId] = existing + delta;
            state = state.copyWith(subAgentProgress: updatedProgress);
            debugPrint('[ChatNotifier] Sub-agent progress: $delta');
          },
        );

        await ref.read(sessionProvider.notifier).updateSubAgentStatus(sessionId, SessionStatus.completed);

        // 更新卡片消息状态
        _updateConversationById(convId, (c) {
          return c.copyWith(
            messages: c.messages.map((m) {
              if (m.id == cardMsg.id) {
                return m.copyWith(
                  metadata: {
                    'type': 'sub_agent',
                    'sessionId': sessionId,
                    'task': args.task,
                    'status': 'completed',
                    'summary': result.content.length > 100
                        ? '${result.content.substring(0, 100)}...'
                        : result.content,
                  },
                );
              }
              return m;
            }).toList(),
          );
        });

        return ToolResult(
          toolCallId: call.id,
          content: 'Sub-agent completed:\n${result.content}',
        );
      } catch (e) {
        await ref.read(sessionProvider.notifier).updateSubAgentStatus(sessionId, SessionStatus.failed);
        return ToolResult(
          toolCallId: call.id,
          content: 'Sub-agent failed: $e',
          isError: true,
        );
      }
    });

    // 正常发送（Agent 模式下 LLM 可以使用 spawn_sub_agent 工具）
    final assistantId = Message.generateId();
    final streamingMsg = Message.streamingAssistant(id: assistantId);
    _updateConversationById(
      convId,
      (c) => c.copyWith(messages: [...c.messages, streamingMsg]),
    );
    state = state.copyWith(isStreaming: true);

    if (streamEnabled) {
      await _sendStreaming(convId, assistantId);
    } else {
      await _sendNonStreaming(convId, assistantId);
    }
  }

  /// Agent Cluster 模式 — 计划拆分 + 并行子 Agent + 结果聚合
  Future<void> _sendAgentClusterMode(
    String convId,
    String userContent,
    bool streamEnabled,
  ) async {
    final conv = state.conversationsCache[convId];
    if (conv == null) return;

    // 阶段一：生成并行任务计划（和 Plan 模式类似）
    final planAssistantId = Message.generateId();
    final streamingMsg = Message.streamingAssistant(id: planAssistantId);
    _updateConversationById(
      convId,
      (c) => c.copyWith(messages: [...c.messages, streamingMsg]),
    );
    state = state.copyWith(isStreaming: true);

    if (streamEnabled) {
      await _sendStreaming(convId, planAssistantId);
    } else {
      await _sendNonStreaming(convId, planAssistantId);
    }

    // 等待完成后解析任务列表 — 从 cache 读最新
    final finalConv = state.conversationsCache[convId];
    if (finalConv == null) return;
    final lastMsg = finalConv.messages.last;
    if (lastMsg.role != MessageRole.assistant) return;

    final tasks = PlanParser.parseTasks(lastMsg.content);
    if (tasks.isEmpty) {
      debugPrint('[ChatNotifier] AgentCluster: 未能解析到并行任务，回退到普通对话');
      return;
    }

    // 为计划消息添加 metadata
    _updateConversationById(convId, (c) {
      return c.copyWith(
        messages: c.messages.map((m) {
          if (m.id == lastMsg.id) {
            return m.copyWith(
              metadata: {'type': 'plan', 'steps': tasks.map((s) => s.toJson()).toList()},
            );
          }
          return m;
        }).toList(),
      );
    });

    debugPrint('[ChatNotifier] AgentCluster: 解析到 ${tasks.length} 个并行任务');

    // 阶段二：创建 Session + 插入卡片 + 流式并行执行
    state = state.copyWith(isStreaming: true);

    final subAgentTasks = tasks
        .map((t) => SubAgentTask(title: t.title, description: t.description))
        .toList();

    // 1) 创建 Session 并插入子 Agent 卡片消息
    final sessionIdByTask = <SubAgentTask, String>{};
    for (final task in subAgentTasks) {
      final sessionId = await ref.read(sessionProvider.notifier).createSubAgentSession(
        conversationId: convId,
        parentSessionId: convId,
        title: task.title,
        mode: ConversationMode.agentCluster,
      );
      sessionIdByTask[task] = sessionId;

      // 插入卡片消息到主 Session
      final cardMsg = Message(
        id: Message.generateId(),
        role: MessageRole.assistant,
        content: '',
        sessionId: convId,
        metadata: {
          'type': 'sub_agent',
          'sessionId': sessionId,
          'task': task.title,
          'status': 'running',
        },
        timestamp: DateTime.now(),
      );
      _updateConversationById(convId, (c) => c.copyWith(
        messages: [...c.messages, cardMsg],
      ));
    }

    // 2) 并行启动流式子 Agent
    final handles = await _subAgentManager.runParallelStreaming(
      tasks: subAgentTasks,
      config: conv.config,
      conversationId: convId,
      parentSessionId: convId,
      systemPrompt: _buildSystemPromptString(),
      createSessionCallback: (task) async {
        // Session 已创建，直接返回已分配的 ID
        return sessionIdByTask[task]!;
      },
      onStatusChange: (sessionId, status) {
        ref.read(sessionProvider.notifier).updateSubAgentStatus(sessionId, status);
        // 更新卡片消息中该子 Agent 的状态
        _updateConversationById(convId, (c) {
          return c.copyWith(
            messages: c.messages.map((m) {
              if (m.metadata?['sessionId'] == sessionId && m.metadata?['type'] == 'sub_agent') {
                return m.copyWith(
                  metadata: {
                    ...m.metadata!,
                    'status': status == SessionStatus.completed ? 'completed'
                        : status == SessionStatus.failed ? 'failed' : 'running',
                  },
                );
              }
              return m;
            }).toList(),
          );
        });
      },
    );

    // 3) 存储句柄 + 连线内容流到 subAgentProgress + 卡片 summary
    final accumulatedContents = <String, String>{};
    for (final handle in handles) {
      _subAgentHandles[handle.sessionId] = handle;
      accumulatedContents[handle.sessionId] = '';
      handle.contentController.stream.listen(
        (delta) {
          // 实时累积到 subAgentProgress
          final updatedProgress = Map<String, String>.from(state.subAgentProgress);
          updatedProgress[handle.sessionId] = (updatedProgress[handle.sessionId] ?? '') + delta;
          state = state.copyWith(subAgentProgress: updatedProgress);

          // 更新卡片 summary
          final currentAccumulated = (accumulatedContents[handle.sessionId] ?? '') + delta;
          accumulatedContents[handle.sessionId] = currentAccumulated;
          _updateConversationById(convId, (c) {
            return c.copyWith(
              messages: c.messages.map((m) {
                if (m.metadata?['sessionId'] == handle.sessionId &&
                    m.metadata?['type'] == 'sub_agent') {
                  return m.copyWith(
                    metadata: {
                      ...m.metadata!,
                      'summary': currentAccumulated.length > 200
                          ? '${currentAccumulated.substring(0, 200)}...'
                          : currentAccumulated,
                    },
                  );
                }
                return m;
              }).toList(),
            );
          });
        },
        onDone: () {
          _subAgentHandles.remove(handle.sessionId);
        },
      );
    }

    // 4) 等待全部完成
    final allStreams = handles.map((h) => h.contentController.stream.toList());
    await Future.wait(allStreams);

    // 阶段三：LLM 综合总结
    final summaryContent = await _generateClusterSummary(
      conv: conv,
      subAgentTasks: subAgentTasks,
      sessionIdByTask: sessionIdByTask,
      accumulatedContents: accumulatedContents,
      originalUserContent: userContent,
    );

    final summaryMsg = Message(
      id: Message.generateId(),
      role: MessageRole.assistant,
      content: summaryContent,
      sessionId: convId,
      timestamp: DateTime.now(),
    );
    _updateConversationById(
      convId,
      (c) => c.copyWith(messages: [...c.messages, summaryMsg]),
    );

    state = state.copyWith(isStreaming: false);
    final savedConv = state.conversationsCache[convId];
    if (savedConv != null) {
      _convService.saveConversation(savedConv);
    }
  }

  /// 生成 Agent Cluster 综合总结 —
  /// 将所有子 Agent 结果发送给 LLM，生成综合性的最终总结。
  Future<String> _generateClusterSummary({
    required Conversation conv,
    required List<SubAgentTask> subAgentTasks,
    required Map<SubAgentTask, String> sessionIdByTask,
    required Map<String, String> accumulatedContents,
    required String originalUserContent,
  }) async {
    try {
      // 构建汇总上下文
      final context = StringBuffer();
      context.writeln('The original task was: "$originalUserContent"');
      context.writeln();
      context.writeln('The following sub-agents have completed their work. '
          'Here are their results:');
      context.writeln();

      for (final task in subAgentTasks) {
        final sid = sessionIdByTask[task];
        final content = accumulatedContents[sid] ?? '(no output)';
        context.writeln('--- Sub-agent: ${task.title} ---');
        context.writeln(content);
        context.writeln();
      }

      context.writeln('Please write a comprehensive summary that synthesizes '
          'all sub-agent results into a cohesive final answer for the user. '
          'Do not just repeat each result — integrate them, identify connections, '
          'and present a unified response.');

      final provider = ProviderFactory.get(conv.config.providerId);

      final response = await provider.chat(
        config: conv.config,
        history: [], // 空 history，只用 system prompt 传递上下文
        systemPrompt: context.toString(),
      );

      debugPrint('[ChatNotifier] AgentCluster 总结生成成功: ${response.content.length} chars');
      return response.content;
    } catch (e) {
      // 如果 LLM 调用失败，回退到拼接模式
      debugPrint('[ChatNotifier] AgentCluster 总结 LLM 调用失败: $e，回退到拼接');
      final fallback = StringBuffer();
      fallback.writeln('All sub-agents have completed. Here are the results:');
      fallback.writeln();
      for (final task in subAgentTasks) {
        final sid = sessionIdByTask[task];
        final content = accumulatedContents[sid] ?? '';
        fallback.writeln('## ${task.title}');
        fallback.writeln(content.isNotEmpty ? content : '(no output)');
        fallback.writeln();
      }
      return fallback.toString();
    }
  }

  // ── 流式发送 ──

  List<ToolDefinition> get _currentTools {
    // 始终包含 discover meta-tool
    final tools = <ToolDefinition>[discoverTool];

    // 注入 LLM 已通过 discover 发现、但尚未注入 schema 的工具
    for (final name in _discoveredInSession) {
      final def = _toolRegistry.get(name);
      if (def != null) {
        tools.add(def);
      }
    }

    final adapterTools = _adapter?.buildTools() ?? const <ToolDefinition>[];
    final pluginTools = PluginRegistry().allEnabledToolDefinitions;
    tools.addAll(adapterTools);
    tools.addAll(pluginTools);

    // 始终注入 workspace_* 工具 — 核心能力，与 discover/adapter 并列。
    // 写操作仍由 WorkspaceApprovalCoordinator 弹窗向用户确认，这里只是
    // 让 LLM 在 tools schema 中能看到这些工具。
    for (final def in const [
      workspaceListTool,
      workspaceReadTool,
      workspaceSearchTool,
      workspaceWriteTool,
      workspaceEditTool,
      workspacePatchTool,
      workspaceMkdirTool,
      workspaceDeleteTool,
    ]) {
      if (_toolRegistry.has(def.name)) {
        tools.add(def);
      }
    }

    // 去重（按 name）
    final seen = <String>{};
    return tools.where((t) => seen.add(t.name)).toList();
  }

  Future<void> _sendStreaming(String convId, String assistantId) async {
    final contentController = StreamController<String>.broadcast();
    _activeStreams[assistantId] = contentController;
    final thinkingController = StreamController<String>.broadcast();
    _activeThinkingStreams[assistantId] = thinkingController;

    try {
      final conv = state.conversationsCache[convId];
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

      _streamSubscriptions[convId] = stream.listen(
        (chunk) {
          switch (chunk.type) {
            case StreamChunkType.contentDelta:
              final delta = chunk.contentDelta ?? '';
              accumulatedContent += delta;
              contentController.add(delta);
              _updateAssistant(
                convId,
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
                convId,
                assistantId,
                content: accumulatedContent,
                thinking: accumulatedThinking,
              );
              break;

            case StreamChunkType.toolCall:
              if (chunk.toolCall != null) {
                accumulatedToolCalls.add(chunk.toolCall!);
                _updateAssistant(
                  convId,
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
              unawaited(
                _finishStreaming(
                  convId,
                  assistantId,
                  accumulatedContent,
                  accumulatedToolCalls,
                  accumulatedThinking.isNotEmpty ? accumulatedThinking : null,
                  finalUsage,
                ),
              );
              break;

            case StreamChunkType.error:
              _setError(convId, chunk.error ?? '未知错误', assistantId);
              break;
          }
        },
        onError: (e) {
          _setError(convId, '连接错误: $e', assistantId);
        },
        onDone: () {
          unawaited(
            _finishStreaming(
              convId,
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
      _setError(convId, '发送失败: $e', assistantId);
    }
  }

  Future<void> _sendNonStreaming(String convId, String assistantId) async {
    try {
      final conv = state.conversationsCache[convId];
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

      _updateConversationById(convId, (c) => c.copyWith(
        messages: c.messages.map((m) {
          if (m.id == assistantId) {
            return response.copyWith(status: MessageStatus.completed);
          }
          return m;
        }).toList(),
      ));

      if (toolCalls.isNotEmpty) {
        await _handleToolCallsAndContinue(
          convId,
          assistantId,
          toolCalls,
          streamEnabled: false,
        );
        return;
      }

      state = state.copyWith(isStreaming: false);
      final savedConv = state.conversationsCache[convId];
      if (savedConv != null) {
        _convService.saveConversation(savedConv);
      }
      unawaited(_commitCache());
      await _triggerMemoryPipeline(convId, assistantId);
    } catch (e) {
      _setError(convId, '发送失败: $e', assistantId);
    }
  }

  // ── 更新消息 ──

  void _updateAssistant(
    String convId,
    String assistantId, {
    String? content,
    String? thinking,
    List<ToolCall>? toolCalls,
  }) {
    _updateConversationById(convId, (conv) => conv.copyWith(
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

  /// 工作空间工具审批 — 通过 WorkspaceApprovalCoordinator 弹出对话框
  Future<bool> _confirmWorkspaceAction(
      WorkspaceApprovalRequest request) async {
    final coordinator = ref.read(workspaceApprovalCoordinatorProvider);
    // 启动一个超时计时器，5 秒内若无响应视为拒绝
    final timeout = Future<bool>.delayed(
      const Duration(seconds: 5),
      () {
        if (!request.completer.isCompleted) {
          request.completer.complete(false);
        }
        return false;
      },
    );
    final result = await Future.any([
      coordinator.request(request),
      timeout,
    ]);
    return result;
  }

  /// `discover` meta-tool handler：统一发现 skills 和 tools
  Future<ToolResult> _handleDiscover(ToolCall call) async {
    try {
      final query = call.arguments['query'] as String?;
      final capability = call.arguments['capability'] as String?;
      final tag = call.arguments['tag'] as String?;
      final kind = call.arguments['kind'] as String? ?? 'all';

      final result = _discoverManager.discover(
        skills: PluginRegistry().allSkills,
        toolRegistry: _toolRegistry,
        query: query,
        capability: capability,
        tag: tag,
        kind: kind,
      );

      // 将发现的工具名加入 _discoveredInSession，
      // 下一轮 API 调用时 _currentTools 会包含这些工具的完整 schema
      _discoveredInSession.addAll(result.discoveredToolNames);

      return ToolResult(
        toolCallId: call.id,
        content: result.toDisplayString(),
      );
    } catch (e) {
      return ToolResult(
        toolCallId: call.id,
        content: 'discover tool error: $e',
        isError: true,
      );
    }
  }

  Future<bool> _handleToolCallsAndContinue(
    String convId,
    String assistantId,
    List<ToolCall> toolCalls, {
    bool streamEnabled = true,
  }) async {
    if (toolCalls.isEmpty) return false;
    debugPrint('[ChatNotifier] _handleToolCallsAndContinue: count=${toolCalls.length}');

    // Phase 1: 运行时参数校验（validateAll 同时处理未注册工具 + schema 不匹配）
    final batchResult = _toolCallValidator.validateAll(toolCalls, _toolRegistry);

    // Phase 2: 执行通过校验的调用
    final execResults = <ToolResult>[];
    if (batchResult.validCalls.isNotEmpty) {
      execResults.addAll(await _toolRegistry.executeAll(batchResult.validCalls));
    }

    // Phase 3: 合并错误结果 + 执行结果
    final allResults = [
      ...batchResult.errors,
      ...execResults,
    ];

    final toolResults = <String, String>{};
    for (final result in allResults) {
      toolResults[result.toolCallId] = result.content;
    }

    _updateConversationById(convId, (conv) => conv.copyWith(
      messages: conv.messages.map((m) {
        if (m.id == assistantId) return m.copyWith(toolResults: toolResults);
        return m;
      }).toList(),
    ));

    _updateConversationById(convId, (conv) {
      final newMessages = [...conv.messages];
      for (final result in allResults) {
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
    _updateConversationById(
      convId,
      (conv) => conv.copyWith(
        messages: [...conv.messages, Message.streamingAssistant(id: newAssistantId)],
      ),
    );
    state = state.copyWith(isStreaming: true);

    if (streamEnabled) {
      await _sendStreaming(convId, newAssistantId);
    } else {
      await _sendNonStreaming(convId, newAssistantId);
    }
    return true;
  }

  // ── 流完成 ──

  Future<void> _finishStreaming(
    String convId,
    String assistantId,
    String content,
    List<ToolCall> toolCalls, [
    String? thinking,
    TokenUsage? usage,
  ]) async {
    // 防止 done chunk + onDone 双重触发
    if (!_completedStreams.add(assistantId)) return;

    final conv = state.conversationsCache[convId];
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

    _updateConversationById(convId, (c) => c.copyWith(
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
        convId,
        assistantId,
        toolCalls,
        streamEnabled: true,
      );
      return;
    }

    state = state.copyWith(isStreaming: false);
    _streamSubscriptions.remove(convId);
    // 如果当前显示的就是完成流的对话,清空 runningConversationId;
    // 若用户已切走到其他对话,保留 runningConversationId 直到新的 sendMessage 启动。
    if (state.conversation?.id == convId) {
      state = state.copyWith(clearRunningConversation: true);
    } else {
      // 完成的对话仍是 cache 中的运行实例,但运行态已结束
      state = state.copyWith(runningConversationId: null);
    }
    final savedConv = state.conversationsCache[convId];
    if (savedConv != null) {
      _convService.saveConversation(savedConv);
    }
    unawaited(_commitCache());
    await _triggerMemoryPipeline(convId, assistantId);
  }

  // ── 记忆流水线 ──

  Future<void> _triggerMemoryPipeline(String convId, String assistantId) async {
    if (!_memoryInitialized) return;
    final conv = state.conversationsCache[convId];
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

  // ── 错误处理 ──

  void _setError(String convId, String message, String assistantId) {
    _updateConversationById(convId, (conv) => conv.copyWith(
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
    state = state.copyWith(
      isStreaming: false,
      error: message,
      clearRunningConversation: true,
    );
    _streamSubscriptions.remove(convId);
    _activeStreams.remove(assistantId)?.close();
    _activeThinkingStreams.remove(assistantId)?.close();
  }

  // ── 重试 / 修改 ──

  Future<void> retry({bool streamEnabled = true}) async {
    if (state.conversation == null) return;
    // 仅当 displayed 对话就是运行完成的对话时才允许重试
    // (从只读视图触发的 retry 没有语义,因为它会启动新的 sendMessage)
    if (state.runningConversationId != null) return;
    final convId = state.conversation!.id;
    final conv = state.conversationsCache[convId];
    if (conv == null) return;
    final messages = conv.messages;
    if (messages.length < 2) return;

    final lastUserIdx = messages.lastIndexWhere(
      (m) => m.role == MessageRole.user,
    );

    // 移除最后一条 assistant 消息
    _updateConversationById(convId, (c) => c.copyWith(
      messages: c.messages.sublist(0, c.messages.length - 1),
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
    if (state.conversation == null) return;
    // 仅当 displayed 对话没有运行中的流时才允许修改并重发
    if (state.runningConversationId != null) return;
    final convId = state.conversation!.id;
    final conv = state.conversationsCache[convId];
    if (conv == null) return;

    int index = -1;
    _updateConversationById(convId, (c) {
      index = c.messages.indexWhere((m) => m.id == messageId);
      if (index < 0 || c.messages[index].role != MessageRole.user) {
        return c;
      }
      return c.copyWith(
        messages: [
          ...c.messages.take(index),
          c.messages[index].copyWith(content: newContent),
          ...c.messages.skip(index + 1),
        ],
      );
    });

    if (index < 0) return;
    final msg = conv.messages[index];
    if (msg.role != MessageRole.user) return;

    // 截断后续消息
    _updateConversationById(
      convId,
      (c) => c.copyWith(messages: c.messages.sublist(0, index + 1)),
    );

    await sendMessage(newContent, streamEnabled: streamEnabled);
  }

  // ── 停止 ──

  void stopStreaming() {
    final convId = state.runningConversationId;
    if (convId != null) {
      _streamSubscriptions.remove(convId)?.cancel();
    }
    _closeAllStreams();

    // 取消所有活跃的子 Agent 流句柄
    for (final handle in _subAgentHandles.values) {
      handle.cancel();
    }
    _subAgentHandles.clear();

    // 清理所有 running 状态的子 Agent Session，标记为 failed
    final sessions = ref.read(sessionProvider).sessions;
    final sessionNotifier = ref.read(sessionProvider.notifier);
    for (final session in sessions) {
      if (session.status == SessionStatus.running) {
        sessionNotifier.updateSubAgentStatus(session.id, SessionStatus.failed);
        debugPrint('[ChatNotifier] stopStreaming: 将子 Agent "${session.title}" 标记为 failed');
      }
    }

    state = state.copyWith(
      isStreaming: false,
      isPreprocessing: false,
      preprocessingTitle: '',
      preprocessingText: '',
      clearRunningConversation: true,
      subAgentProgress: {}, // 清空子 Agent 进度缓存
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
    final isFable = _settingsData?.fableMode == true;
    final isLightweight = _settingsData?.lightweightSystemPrompt == true;

    if (_promptBuilder != null) {
      final PromptSectionCollection spSections;
      if (isFable) {
        spSections = _promptBuilder!.buildFableSystemPrompt(
          displayName: _settingsData?.userDisplayName,
          alias: _settingsData?.userAlias,
          role: _settingsData?.userRole,
          preferences: _settingsData?.userPreferences,
          facts: _settingsData?.userFacts,
          customPrompt: _settingsData?.userCustomPrompt,
        );
      } else if (isLightweight) {
        spSections = _promptBuilder!.buildLightweightSystemPrompt(
          customPrompt: _settingsData?.userCustomPrompt,
        );
      } else {
        spSections = _promptBuilder!.buildSystemPrompt(
          displayName: _settingsData?.userDisplayName,
          alias: _settingsData?.userAlias,
          role: _settingsData?.userRole,
          preferences: _settingsData?.userPreferences,
          facts: _settingsData?.userFacts,
          customPrompt: _settingsData?.userCustomPrompt,
        );
      }
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
    String convId,
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
      _updateConversationById(convId, (conv) {
        conv.title = sanitized;
        _convService.renameConversation(conv.id, sanitized);
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