import 'package:flutter/material.dart';

import 'package:tessera/l10n/app_localizations.dart';
import 'package:tessera/l10n/conversation_mode_localization.dart';

import '../../models/conversation.dart';
import '../../models/conversation_mode.dart';
import '../../models/session.dart';

/// 右上角对话菜单 — 模式切换（新对话）+ Session 切换（已有对话）
class ConversationMenu extends StatelessWidget {
  final Conversation? conversation;
  final ConversationMode pendingMode;
  final List<Session> sessions;
  final String activeSessionId;
  final Future<void> Function(String sessionId) onSwitchSession;
  final void Function(ConversationMode mode) onSwitchMode;

  const ConversationMenu({
    super.key,
    required this.conversation,
    required this.pendingMode,
    required this.sessions,
    required this.activeSessionId,
    required this.onSwitchSession,
    required this.onSwitchMode,
  });

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert),
      onSelected: (value) {
        if (value.startsWith('mode:')) {
          final modeName = value.substring(5);
          onSwitchMode(ConversationMode.fromName(modeName));
        } else if (value.startsWith('session:')) {
          final sessionId = value.substring(8);
          onSwitchSession(sessionId);
        }
      },
      itemBuilder: (context) {
        final l10n = AppLocalizations.of(context)!;
        final items = <PopupMenuEntry<String>>[];

        if (conversation == null) {
          // 新对话状态：模式选择
          items.add(
            PopupMenuItem<String>(
              enabled: false,
              child: Text(
                l10n.conversationSelectMode,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
          );
          for (final mode in ConversationMode.values) {
            final isSelected = mode == pendingMode;
            items.add(
              PopupMenuItem<String>(
                value: 'mode:${mode.name}',
                child: Row(
                  children: [
                    Icon(_modeIcon(mode), size: 18),
                    const SizedBox(width: 8),
                    Text(l10n.modeName(mode)),
                    if (isSelected) ...[
                      const Spacer(),
                      Icon(Icons.check, size: 16, color: Theme.of(context).colorScheme.primary),
                    ],
                  ],
                ),
              ),
            );
          }
        } else {
          // 已有对话：显示模式 + Session 切换
          items.add(
            PopupMenuItem<String>(
              enabled: false,
              child: Row(
                children: [
                  Icon(_modeIcon(conversation!.mode), size: 18),
                  const SizedBox(width: 8),
                  Text(l10n.conversationCurrentMode(l10n.modeName(conversation!.mode))),
                ],
              ),
            ),
          );

          // Session 列表（仅当有子 Agent Session 时显示）
          final subAgentSessions = sessions
              .where((s) => s.type == SessionType.subAgent)
              .toList();

          if (subAgentSessions.isNotEmpty) {
            items.add(const PopupMenuDivider());
            items.add(
              PopupMenuItem<String>(
                enabled: false,
                child: Text(
                  l10n.conversationSwitchSession,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
            );

            // 主 Session
            final isMainActive = activeSessionId == conversation!.id;
            items.add(
              PopupMenuItem<String>(
                value: 'session:${conversation!.id}',
                child: Row(
                  children: [
                    Icon(
                      isMainActive ? Icons.radio_button_checked : Icons.radio_button_off,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(l10n.conversationMainSession),
                  ],
                ),
              ),
            );

            // 子 Agent Sessions
            for (final session in subAgentSessions) {
              final isActive = session.id == activeSessionId;
              items.add(
                PopupMenuItem<String>(
                  value: 'session:${session.id}',
                  child: Row(
                    children: [
                      Icon(
                        isActive ? Icons.radio_button_checked : Icons.radio_button_off,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          session.title,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 4),
                      _statusIcon(session.status),
                    ],
                  ),
                ),
              );
            }
          }
        }

        return items;
      },
    );
  }

  IconData _modeIcon(ConversationMode mode) {
    switch (mode) {
      case ConversationMode.normal:
        return Icons.chat;
      case ConversationMode.plan:
        return Icons.checklist;
      case ConversationMode.agent:
        return Icons.smart_toy;
      case ConversationMode.agentCluster:
        return Icons.hub;
    }
  }

  Widget _statusIcon(SessionStatus status) {
    switch (status) {
      case SessionStatus.active:
        return const Icon(Icons.circle, size: 10, color: Colors.green);
      case SessionStatus.running:
        return const SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case SessionStatus.completed:
        return const Icon(Icons.check_circle, size: 14, color: Colors.green);
      case SessionStatus.failed:
        return const Icon(Icons.error, size: 14, color: Colors.red);
    }
  }
}
