import 'package:flutter/material.dart';
import 'package:animated_text_kit/animated_text_kit.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:tessera/l10n/app_localizations.dart';
import '../../core/core.dart';
import '../../providers/chat_provider.dart';
import 'chat_bubble.dart';
import 'message_input.dart';
import 'plan_block.dart';
import 'processing_block.dart';
import 'read_only_banner.dart';
import 'sub_agent_card.dart';

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
        // 只读模式条幅 — 用户切走到非运行对话时显示
        const ReadOnlyBanner(),
        Expanded(
          child: data.displayMessages.isEmpty
              ? _buildWelcomeView(theme)
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  itemCount: data.displayMessages.length,
                  itemBuilder: (context, index) {
                    final msg = data.displayMessages[index];

                    // Plan 消息
                    if (msg.metadata?['type'] == 'plan') {
                      final steps = (msg.metadata!['steps'] as List<dynamic>?)
                              ?.map((e) => Map<String, dynamic>.from(e as Map))
                              .toList() ??
                          [];
                      return PlanBlock(steps: steps);
                    }

                    // 子 Agent 卡片消息
                    if (msg.metadata?['type'] == 'sub_agent') {
                      return SubAgentCard(
                        sessionId: msg.metadata!['sessionId'] as String? ?? '',
                        task: msg.metadata!['task'] as String? ?? '',
                        status: msg.metadata!['status'] as String? ?? 'running',
                        summary: msg.metadata!['summary'] as String?,
                        onJumpToSession: (id) =>
                            ref.read(chatProvider.notifier).switchSession(id),
                      );
                    }

                    // 普通消息
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
        // 输入栏 — 仅当 displayed 对话就是 running 对话时可输入
        // (新草稿 + 无 running 也可输入;只读视图禁用)
        MessageInput(
          enabled: data.runningConversationId == null
              ? !data.isPreprocessing
              : data.isDisplayedRunning && !data.isPreprocessing,
          onSend: widget.onSend,
        ),
      ],
    );
  }

  Widget _buildWelcomeView(ThemeData theme) {
    final l10n = AppLocalizations.of(context)!;
    final descriptions = <String>[
      l10n.chatWelcomeDesc1,
      l10n.chatWelcomeDesc2,
      l10n.chatWelcomeDesc3,
      l10n.chatWelcomeDesc4,
    ];
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 第一行 —— 纯文字 Logo，左对齐
            Text(
              'Tessera',
              style: theme.textTheme.displayLarge?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.normal,
              ),
            ),
            const SizedBox(height: 16),
            // 第二行 —— 打字机轮播动态描述，左对齐
            SizedBox(
              width: MediaQuery.of(context).size.width * 0.8,
              child: AnimatedTextKit(
                animatedTexts: descriptions.map(
                  (desc) => TypewriterAnimatedText(
                    desc,
                    textStyle: theme.textTheme.displaySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    speed: const Duration(milliseconds: 100),
                  ),
                ).toList(),
                isRepeatingAnimation: true,
                pause: const Duration(milliseconds: 2500),
                displayFullTextOnTap: true,
              ),
            ),
            const SizedBox(height: 64),
          ],
        ),
      ),
    );
  }
}
