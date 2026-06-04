import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:tessera/l10n/app_localizations.dart';
import '../../core/core.dart';
import '../../providers/chat_provider.dart';
import 'chat_bubble.dart';
import 'message_input.dart';
import 'processing_block.dart';

/// 聊天内容视图 — 消息列表 + 输入栏
class ChatContentView extends ConsumerStatefulWidget {
  final void Function(SendPayload payload) onSend;
  final void Function(Message msg)? onModify;
  final void Function()? onRegenerate;
  final void Function(Message msg)? onShare;

  const ChatContentView({
    super.key,
    required this.onSend,
    this.onModify,
    this.onRegenerate,
    this.onShare,
  });

  @override
  ConsumerState<ChatContentView> createState() => _ChatContentViewState();
}

class _ChatContentViewState extends ConsumerState<ChatContentView> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final data = ref.watch(chatProvider);
    final notifier = ref.read(chatProvider.notifier);

    // 有新消息时滚动到底部
    if (data.messages.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });
    }

    return Column(
      children: [
        Expanded(
          child: data.displayMessages.isEmpty
              ? _buildWelcomeView(theme)
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  itemCount: data.displayMessages.length,
                  itemBuilder: (context, index) {
                    final msg = data.displayMessages[index];
                    return ChatBubble(
                      key: ValueKey(msg.id),
                      message: msg,
                      contentStream: msg.status == MessageStatus.streaming
                          ? notifier.getContentStream(msg.id)
                          : null,
                      thinkingStream: msg.status == MessageStatus.streaming
                          ? notifier.getThinkingStream(msg.id)
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
        // 预处理指示器
        if (data.isPreprocessing)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: ProcessingBlock(
              icon: Icons.analytics,
              inProgressTitle: data.preprocessingTitle,
              completedTitle: '',
              isProcessing: true,
              content: data.preprocessingText,
              contentStream: notifier.preprocessingStream,
              collapsible: false,
              initiallyExpanded: true,
            ),
          ),
        // 输入栏
        MessageInput(
          enabled: !data.isStreaming && !data.isPreprocessing,
          onSend: widget.onSend,
        ),
      ],
    );
  }

  Widget _buildWelcomeView(ThemeData theme) {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.assistant, size: 64, color: theme.colorScheme.primary),
          const SizedBox(height: 16),
          Text(
            l10n.chatWelcomeTitle,
            style: theme.textTheme.headlineSmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.chatWelcomeSubtitle,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}
