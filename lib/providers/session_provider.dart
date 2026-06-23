import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/conversation_mode.dart';
import '../models/message.dart';
import '../models/session.dart';
import '../services/conversation_service.dart';

/// Session 状态数据
class SessionData {
  /// 当前对话的所有 Session
  final List<Session> sessions;

  /// 当前查看的 Session ID
  final String activeSessionId;

  /// 子 Agent 状态映射（sessionId → status）
  final Map<String, SessionStatus> subAgentStatuses;

  const SessionData({
    this.sessions = const [],
    this.activeSessionId = '',
    this.subAgentStatuses = const {},
  });

  SessionData copyWith({
    List<Session>? sessions,
    String? activeSessionId,
    Map<String, SessionStatus>? subAgentStatuses,
  }) {
    return SessionData(
      sessions: sessions ?? this.sessions,
      activeSessionId: activeSessionId ?? this.activeSessionId,
      subAgentStatuses: subAgentStatuses ?? this.subAgentStatuses,
    );
  }

  /// 获取当前激活的 Session 对象
  Session? get activeSession {
    if (activeSessionId.isEmpty) return null;
    for (final s in sessions) {
      if (s.id == activeSessionId) return s;
    }
    return null;
  }

  /// 获取子 Agent Session 列表
  List<Session> get subAgentSessions {
    return sessions.where((s) => s.type == SessionType.subAgent).toList();
  }
}

/// Session 状态管理
class SessionNotifier extends Notifier<SessionData> {
  final ConversationService _convService = ConversationService();

  @override
  SessionData build() {
    return const SessionData();
  }

  /// 加载对话的所有 Session
  Future<void> loadSessions(String conversationId) async {
    try {
      final sessions = await _convService.getSessions(conversationId);
      state = SessionData(
        sessions: sessions,
        activeSessionId: conversationId, // 默认激活主 Session
      );
    } catch (e) {
      debugPrint('[SessionNotifier] 加载 Session 失败: $e');
      state = const SessionData();
    }
  }

  /// 切换当前查看的 Session
  void switchSession(String sessionId) {
    state = state.copyWith(activeSessionId: sessionId);
  }

  /// 注册一个已存在的 Session 列表（从 Conversation 加载时直接设置）
  void setSessions(List<Session> sessions, {String? activeId}) {
    state = SessionData(
      sessions: sessions,
      activeSessionId: activeId ?? (sessions.isNotEmpty ? sessions.first.id : ''),
    );
  }

  /// 创建子 Agent Session
  Future<String> createSubAgentSession({
    required String conversationId,
    required String parentSessionId,
    required String title,
    required ConversationMode mode,
  }) async {
    final sessionId = Message.generateId();
    final now = DateTime.now();
    final session = Session(
      id: sessionId,
      conversationId: conversationId,
      parentSessionId: parentSessionId,
      type: SessionType.subAgent,
      title: title,
      mode: mode,
      status: SessionStatus.running,
      sortOrder: state.sessions.length,
      createdAt: now,
      updatedAt: now,
    );

    await _convService.createSession(session);
    state = state.copyWith(
      sessions: [...state.sessions, session],
      subAgentStatuses: {...state.subAgentStatuses, sessionId: SessionStatus.running},
    );
    debugPrint('[SessionNotifier] 创建子 Agent Session: $sessionId, title=$title');
    return sessionId;
  }

  /// 注册主 Session（创建对话时调用）
  Future<void> registerMainSession(Session session) async {
    await _convService.createSession(session);
    state = state.copyWith(
      sessions: [session, ...state.sessions.where((s) => s.id != session.id)],
      activeSessionId: session.id,
    );
  }

  /// 更新子 Agent 状态
  Future<void> updateSubAgentStatus(String sessionId, SessionStatus status) async {
    await _convService.updateSessionStatus(sessionId, status);
    final updatedSessions = state.sessions.map((s) {
      if (s.id == sessionId) return s.copyWith(status: status);
      return s;
    }).toList();
    state = state.copyWith(
      sessions: updatedSessions,
      subAgentStatuses: {...state.subAgentStatuses, sessionId: status},
    );
  }

  /// 获取指定 Session 的消息（从全量消息列表中过滤）
  List<Message> getMessagesForSession(String sessionId, List<Message> allMessages) {
    return allMessages.where((m) {
      // sessionId 为空的消息属于主 Session（即 conversationId）
      if (sessionId == m.sessionId) return true;
      // 主 Session 包含 sessionId 为空或等于主 Session ID 的消息
      return false;
    }).toList();
  }

  /// 重置
  void clear() {
    state = const SessionData();
  }
}

/// Session provider
final sessionProvider =
    NotifierProvider<SessionNotifier, SessionData>(SessionNotifier.new);
