import 'dart:async';

import '../llm/provider_factory.dart';
import '../models/llm_config.dart';
import '../models/message.dart';
import '../models/session.dart';
import '../models/stream_chunk.dart';
import '../services/conversation_service.dart';

/// 子 Agent 任务定义
class SubAgentTask {
  final String title;
  final String description;
  final String? context;

  const SubAgentTask({
    required this.title,
    required this.description,
    this.context,
  });
}

/// 子 Agent 执行结果
class SubAgentResult {
  final String sessionId;
  final String title;
  final String content;
  final bool success;
  final String? error;

  const SubAgentResult({
    required this.sessionId,
    required this.title,
    required this.content,
    this.success = true,
    this.error,
  });
}

/// 流式子 Agent 句柄 —
/// 调用方通过 [contentStream] / [thinkingStream] 监听增量输出，
/// 通过 [result] 等待最终结果。
class SubAgentStreamHandle {
  final String sessionId;
  final StreamController<String> contentController;
  final StreamController<String> thinkingController;

  /// 流订阅，调用方可通过 cancel 中断子 Agent
  StreamSubscription<StreamChunk>? _subscription;

  SubAgentStreamHandle({
    required this.sessionId,
    required this.contentController,
    required this.thinkingController,
  });

  /// 中断该子 Agent
  void cancel() {
    _subscription?.cancel();
    if (!contentController.isClosed) contentController.close();
    if (!thinkingController.isClosed) thinkingController.close();
  }
}

/// 子 Agent 生命周期管理器
class SubAgentManager {
  final ConversationService _convService = ConversationService();

  /// 并行启动多个流式子 Agent。
  /// 返回每个子 Agent 的流句柄列表，调用方自行聚合结果。
  Future<List<SubAgentStreamHandle>> runParallelStreaming({
    required List<SubAgentTask> tasks,
    required LlmConfig config,
    required String conversationId,
    required String parentSessionId,
    required String systemPrompt,
    required void Function(String sessionId, SessionStatus status) onStatusChange,
    required Future<String> Function(SubAgentTask task) createSessionCallback,
    String? pluginSkills,
    String? memoryContext,
  }) async {
    final handles = <SubAgentStreamHandle>[];

    // 先创建所有 Session，插入卡片
    final sessionIds = <String>[];
    for (final task in tasks) {
      final sessionId = await createSessionCallback(task);
      sessionIds.add(sessionId);
      onStatusChange(sessionId, SessionStatus.running);
    }

    // 并行启动流式子 Agent
    final futures = <Future<void>>[];
    for (var i = 0; i < tasks.length; i++) {
      final task = tasks.elementAt(i);
      final sessionId = sessionIds[i];
      final contentController = StreamController<String>.broadcast();
      final thinkingController = StreamController<String>.broadcast();
      final handle = SubAgentStreamHandle(
        sessionId: sessionId,
        contentController: contentController,
        thinkingController: thinkingController,
      );
      handles.add(handle);

      futures.add(_runStreaming(
        task: task,
        config: config,
        conversationId: conversationId,
        sessionId: sessionId,
        systemPrompt: systemPrompt,
        pluginSkills: pluginSkills,
        memoryContext: memoryContext,
        handle: handle,
        onStatusChange: (status) => onStatusChange(sessionId, status),
      ));
    }

    // 不阻塞调用方 — 后台运行，结果通过 handles 的流获取
    unawaited(Future.wait(futures));

    return handles;
  }

  /// 流式执行单个子 Agent（内部实现）
  Future<void> _runStreaming({
    required SubAgentTask task,
    required LlmConfig config,
    required String conversationId,
    required String sessionId,
    required String systemPrompt,
    required SubAgentStreamHandle handle,
    required void Function(SessionStatus status) onStatusChange,
    String? pluginSkills,
    String? memoryContext,
  }) async {
    final provider = ProviderFactory.get(config.providerId);

    final userContent = StringBuffer();
    userContent.writeln('Task: ${task.title}');
    userContent.writeln();
    userContent.writeln(task.description);
    if (task.context != null && task.context!.isNotEmpty) {
      userContent.writeln();
      userContent.writeln('Additional context:');
      userContent.writeln(task.context);
    }

    final userMsg = Message(
      id: Message.generateId(),
      role: MessageRole.user,
      content: userContent.toString(),
      sessionId: sessionId,
      timestamp: DateTime.now(),
    );

    final subSystemPrompt = buildSubAgentPrompt(
      systemPrompt: systemPrompt,
      pluginSkills: pluginSkills,
      memoryContext: memoryContext,
    );

    try {
      final stream = provider.chatStream(
        config: config,
        history: [userMsg],
        systemPrompt: subSystemPrompt,
      );

      String accumulatedContent = '';
      String accumulatedThinking = '';

      final completer = Completer<void>();
      handle._subscription = stream.listen(
        (chunk) {
          switch (chunk.type) {
            case StreamChunkType.contentDelta:
              final delta = chunk.contentDelta ?? '';
              accumulatedContent += delta;
              if (!handle.contentController.isClosed) {
                handle.contentController.add(delta);
              }
              break;
            case StreamChunkType.thinkingDelta:
              final delta = chunk.thinkingDelta ?? '';
              accumulatedThinking += delta;
              if (!handle.thinkingController.isClosed) {
                handle.thinkingController.add(delta);
              }
              break;
            case StreamChunkType.done:
              // 流结束 — 保存消息到数据库
              _finalizeAndSave(
                conversationId: conversationId,
                sessionId: sessionId,
                userMsg: userMsg,
                content: accumulatedContent,
                thinking: accumulatedThinking,
              );
              completer.complete();
              break;
            case StreamChunkType.error:
              completer.completeError(
                Exception(chunk.error ?? 'Unknown stream error'),
              );
              break;
            case StreamChunkType.toolCall:
              // 子 Agent 暂不支持 tool call，忽略
              break;
          }
        },
        onError: (e) {
          if (!completer.isCompleted) completer.completeError(e);
        },
        onDone: () {
          if (!completer.isCompleted) completer.complete();
        },
        cancelOnError: true,
      );

      await completer.future;
      onStatusChange(SessionStatus.completed);
    } catch (e) {
      onStatusChange(SessionStatus.failed);
      if (!handle.contentController.isClosed) {
        handle.contentController.addError(e);
      }
    } finally {
      if (!handle.contentController.isClosed) {
        handle.contentController.close();
      }
      if (!handle.thinkingController.isClosed) {
        handle.thinkingController.close();
      }
    }
  }

  /// 保存子 Agent 消息到数据库
  Future<void> _finalizeAndSave({
    required String conversationId,
    required String sessionId,
    required Message userMsg,
    required String content,
    String? thinking,
  }) async {
    final assistantMsg = Message(
      id: Message.generateId(),
      role: MessageRole.assistant,
      content: content,
      thinking: thinking,
      sessionId: sessionId,
      timestamp: DateTime.now(),
    );

    await _convService.saveMessage(userMsg, conversationId, sessionId);
    await _convService.saveMessage(assistantMsg, conversationId, sessionId);
  }

  /// 构建子 Agent 专用的增强系统提示词
  static String buildSubAgentPrompt({
    required String systemPrompt,
    String? pluginSkills,
    String? memoryContext,
  }) {
    final buf = StringBuffer();
    buf.writeln(systemPrompt);

    if (pluginSkills != null && pluginSkills.isNotEmpty) {
      buf.writeln();
      buf.writeln('You have access to the following plugin capabilities:');
      buf.writeln(pluginSkills);
    }

    if (memoryContext != null && memoryContext.isNotEmpty) {
      buf.writeln();
      buf.writeln('Relevant context from previous conversations:');
      buf.writeln(memoryContext);
    }

    buf.writeln();
    buf.writeln('You are a sub-agent working on a specific task. '
        'Focus on completing the assigned task thoroughly and return a comprehensive result.');

    return buf.toString();
  }

  // ── 向后兼容的非流式接口 ──

  /// 单个子 Agent 执行（供 Agent 模式的 tool call 使用）
  /// 保留用于 Agent 模式（需要在 tool call handler 中同步等待结果）
  Future<SubAgentResult> runSingle({
    required SubAgentTask task,
    required LlmConfig config,
    required String conversationId,
    required String sessionId,
    required String systemPrompt,
    required void Function(String delta) onProgress,
    String? pluginSkills,
    String? memoryContext,
  }) async {
    final contentController = StreamController<String>.broadcast();
    final thinkingController = StreamController<String>.broadcast();
    final handle = SubAgentStreamHandle(
      sessionId: sessionId,
      contentController: contentController,
      thinkingController: thinkingController,
    );

    String accumulatedContent = '';
    contentController.stream.listen((delta) {
      accumulatedContent += delta;
      onProgress(delta);
    });

    await _runStreaming(
      task: task,
      config: config,
      conversationId: conversationId,
      sessionId: sessionId,
      systemPrompt: systemPrompt,
      pluginSkills: pluginSkills,
      memoryContext: memoryContext,
      handle: handle,
      onStatusChange: (_) {}, // Agent 模式状态由 ChatNotifier 的 tool handler 管理
    );

    return SubAgentResult(
      sessionId: sessionId,
      title: task.title,
      content: accumulatedContent,
      success: true,
    );
  }
}
