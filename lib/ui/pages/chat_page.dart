import 'package:flutter/material.dart';

import '../../core/core.dart';
import '../../state/chat_state.dart';
import '../../state/settings_state.dart';
import '../widgets/chat_content_view.dart';
import '../widgets/message_input.dart';

/// 聊天页面 — 独立路由模式（不含侧边栏）
///
/// 直接作为路由目标使用时，拥有完整的 Scaffold + AppBar。
/// 在 MainPage 中通过 [ChatContentView] 复用消息列表和输入栏。
class ChatPage extends StatefulWidget {
  final LlmConfig? config;
  final String? systemPrompt;
  final Conversation? existingConversation;
  final SettingsState settingsState;

  /// 创建新对话
  const ChatPage({
    super.key,
    this.config,
    this.systemPrompt,
    this.existingConversation,
    required this.settingsState,
  });

  /// 从已有对话加载
  ChatPage.fromConversation(Conversation conv, this.settingsState)
    : config = conv.config,
      systemPrompt = conv.systemPrompt,
      existingConversation = conv,
      super(key: const ValueKey('chat'));

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final ChatState _chatState = ChatState();

  @override
  void initState() {
    super.initState();
    _chatState.configureCapabilities(widget.settingsState);

    if (widget.existingConversation != null) {
      _chatState.loadConversation(widget.existingConversation!.id);
    }
  }

  @override
  void dispose() {
    _chatState.dispose();
    super.dispose();
  }

  void _handleSend(SendPayload payload) {
    _chatState.sendMessage(
      payload.text,
      attachments: payload.attachments,
      streamEnabled: widget.settingsState.streamEnabled,
      config: widget.config ?? widget.existingConversation?.config,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListenableBuilder(
      listenable: _chatState,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: Text(
              _chatState.conversation?.title ?? '新对话',
              style: theme.textTheme.titleMedium,
            ),
            actions: [
              if (_chatState.isStreaming)
                IconButton(
                  icon: const Icon(Icons.stop),
                  onPressed: () => _chatState.stopStreaming(),
                ),
              if (!_chatState.isStreaming && _chatState.messages.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: () => _chatState.retry(
                    streamEnabled: widget.settingsState.streamEnabled,
                  ),
                ),
            ],
          ),
          body: ChatContentView(
            chatState: _chatState,
            onSend: _handleSend,
          ),
        );
      },
    );
  }
}