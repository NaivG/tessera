import 'package:flutter/material.dart';

import '../../core/core.dart';
import '../../state/chat_state.dart';
import 'chat_bubble.dart';
import 'message_input.dart';
import 'processing_block.dart';

/// 聊天内容视图 — 消息列表 + 输入栏
///
/// 从 ChatPage 中提取的核心 UI，不含 Scaffold/AppBar，
/// 以便在 MainPage 的响应式布局中复用。
class ChatContentView extends StatefulWidget {
  final ChatState chatState;
  final void Function(SendPayload payload) onSend;

  /// 修改消息回调（user 消息右键菜单）
  final void Function(Message msg)? onModify;

  /// 重新生成回调（assistant 消息右键菜单）
  final void Function()? onRegenerate;

  /// 分享回调
  final void Function(Message msg)? onShare;

  const ChatContentView({
    super.key,
    required this.chatState,
    required this.onSend,
    this.onModify,
    this.onRegenerate,
    this.onShare,
  });

  @override
  State<ChatContentView> createState() => _ChatContentViewState();
}

class _ChatContentViewState extends State<ChatContentView> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListenableBuilder(
      listenable: widget.chatState,
      builder: (context, _) {
        // 有新消息时滚动到底部
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
            );
          }
        });

        return Column(
          children: [
            // 消息列表
            Expanded(
              child: widget.chatState.displayMessages.isEmpty
                  ? _buildWelcomeView(theme)
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      itemCount: widget.chatState.displayMessages.length,
                      itemBuilder: (context, index) {
                        final msg = widget.chatState.displayMessages[index];
                        return ChatBubble(
                          key: ValueKey(msg.id),
                          message: msg,
                          contentStream: msg.status == MessageStatus.streaming
                              ? widget.chatState.getContentStream(msg.id)
                              : null,
                          thinkingStream: msg.status == MessageStatus.streaming
                              ? widget.chatState.getThinkingStream(msg.id)
                              : null,
                          onModify: msg.role == MessageRole.user
                              ? () => widget.onModify?.call(msg)
                              : null,
                          onRegenerate: msg.role == MessageRole.assistant
                              ? widget.onRegenerate
                              : null,
                          onShare: () => widget.onShare?.call(msg),
                        );
                      },
                    ),
            ),
            // 预处理指示器 — 附件分析中
            if (widget.chatState.isPreprocessing)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: ProcessingBlock(
                  icon: Icons.analytics,
                  inProgressTitle: widget.chatState.preprocessingTitle,
                  completedTitle: '',
                  isProcessing: true,
                  content: widget.chatState.preprocessingText,
                  contentStream: widget.chatState.preprocessingStream,
                  collapsible: false,
                  initiallyExpanded: true,
                ),
              ),
            // 输入栏
            MessageInput(
              enabled: !widget.chatState.isStreaming &&
                  !widget.chatState.isPreprocessing,
              onSend: widget.onSend,
            ),
          ],
        );
      },
    );
  }

  Widget _buildWelcomeView(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.smart_toy, size: 64, color: theme.colorScheme.primary),
          const SizedBox(height: 16),
          Text(
            'Tessera AI',
            style: theme.textTheme.headlineSmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '开始新对话，发送消息即可',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}
