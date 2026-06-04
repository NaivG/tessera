import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/core.dart';
import '../../providers/chat_provider.dart';
import '../../providers/settings_provider.dart';
import '../widgets/chat_content_view.dart';
import '../widgets/message_input.dart';

/// 聊天页面 — 独立路由模式（不含侧边栏）
class ChatPage extends ConsumerStatefulWidget {
  final LlmConfig? config;
  final String? systemPrompt;

  const ChatPage({
    super.key,
    this.config,
    this.systemPrompt,
  });

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage> {
  @override
  void initState() {
    super.initState();
    final chat = ref.read(chatProvider.notifier);
    chat.configureCapabilities(ref.read(settingsProvider));
    chat.init();
  }

  void _handleSend(SendPayload payload) {
    final config = widget.config ??
        ref.read(settingsProvider.notifier).buildMainLlmConfig();
    if (config == null) return;

    ref.read(chatProvider.notifier).sendMessage(
      payload.text,
      attachments: payload.attachments,
      streamEnabled: ref.read(settingsProvider).streamEnabled,
      config: config,
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(chatProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(state.conversation?.title ?? 'Chat'),
      ),
      body: ChatContentView(
        onSend: _handleSend,
      ),
    );
  }
}
