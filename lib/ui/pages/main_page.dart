import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import 'package:tessera/l10n/app_localizations.dart';

import '../../models/conversation.dart';
import '../../models/message.dart';
import '../../providers/providers.dart';
import '../../services/conversation_service.dart';
import '../widgets/chat_content_view.dart';
import '../widgets/message_input.dart';
import '../widgets/sidebar.dart';

/// 主页面 — 响应式侧边栏 + 聊天区域
class MainPage extends ConsumerStatefulWidget {
  const MainPage({super.key});

  @override
  ConsumerState<MainPage> createState() => _MainPageState();
}

class _MainPageState extends ConsumerState<MainPage>
    with TickerProviderStateMixin {
  final ConversationService _convService = ConversationService();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  List<Conversation> _conversations = [];
  Set<String> _conversationIds = {};
  bool _loading = true;

  // 横屏模式侧边栏动画
  late final AnimationController _sidebarAnimController;
  late final Animation<double> _sidebarAnim;
  bool _sidebarVisible = true;

  @override
  void initState() {
    super.initState();
    _sidebarAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _sidebarAnim = CurvedAnimation(
      parent: _sidebarAnimController,
      curve: Curves.easeInOut,
    );
    _sidebarAnimController.value = 1.0;

    // 初始化 ChatNotifier
    final chat = ref.read(chatProvider.notifier);
    final settings = ref.read(settingsProvider);
    chat.configureCapabilities(settings);
    chat.init();

    _loadConversations();
  }

  @override
  void dispose() {
    _sidebarAnimController.dispose();
    super.dispose();
  }

  // ── 对话列表 ──

  Future<void> _loadConversations() async {
    setState(() => _loading = true);
    try {
      final list = await _convService.listConversations();
      setState(() {
        _conversations = list;
        _conversationIds = list.map((c) => c.id).toSet();
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  String? get _activeConversationId {
    final conv = ref.read(chatProvider).conversation;
    return conv?.id;
  }

  // ── 对话操作 ──

  void _selectConversation(Conversation conv) async {
    if (_scaffoldKey.currentState?.isDrawerOpen == true) {
      Navigator.of(context).pop();
    }
    final notifier = ref.read(chatProvider.notifier);
    notifier.configureCapabilities(ref.read(settingsProvider));
    await notifier.init();
    await notifier.loadConversation(conv.id);
  }

  void _newConversation() {
    if (_scaffoldKey.currentState?.isDrawerOpen == true) {
      Navigator.of(context).pop();
    }
    ref.read(chatProvider.notifier).clear();
  }

  Future<void> _deleteConversation(String id) async {
    await _convService.deleteConversation(id);
    _conversationIds.remove(id);
    if (_activeConversationId == id) {
      ref.read(chatProvider.notifier).clear();
    }
    _loadConversations();
  }

  Future<void> _renameConversation(String id, String newTitle) async {
    await _convService.renameConversation(id, newTitle);
    // 同步更新内存中的标题
    final conv = ref.read(chatProvider).conversation;
    if (conv?.id == id) {
      conv!.title = newTitle;
    }
    _loadConversations();
  }

  void _openSettings() {
    Navigator.of(context).pushNamed('/settings');
  }

  // ── 发送消息 ──

  void _handleSend(SendPayload payload) {
    final notifier = ref.read(settingsProvider.notifier);
    final config = notifier.buildMainLlmConfig();
    if (config == null) {
      _showNoConfigWarning();
      return;
    }

    final settings = ref.read(settingsProvider);
    ref.read(chatProvider.notifier).sendMessage(
      payload.text,
      attachments: payload.attachments,
      streamEnabled: settings.streamEnabled,
      config: config,
    );
  }

  void _showNoConfigWarning() {
    final l10n = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.chatConfigureProviderFirst),
        action: SnackBarAction(
          label: l10n.chatGoToSettings,
          onPressed: _openSettings,
        ),
      ),
    );
  }

  // ── 消息操作 ──

  void _handleModify(Message msg) async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController(text: msg.content);
    final newContent = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.chatModifyMessage),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 5,
          decoration: InputDecoration(hintText: l10n.chatNewContentHint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(l10n.chatSend),
          ),
        ],
      ),
    );

    if (newContent != null &&
        newContent.isNotEmpty &&
        newContent != msg.content) {
      ref.read(chatProvider.notifier).modifyAndResend(
        msg.id,
        newContent,
        streamEnabled: ref.read(settingsProvider).streamEnabled,
      );
    }
  }

  void _handleRegenerate() {
    ref.read(chatProvider.notifier).retry(
      streamEnabled: ref.read(settingsProvider).streamEnabled,
    );
  }

  void _handleShare(Message msg) {
    SharePlus.instance.share(
      ShareParams(text: msg.content, subject: 'Tessera AI Chat'),
    );
  }

  String get _title {
    final state = ref.watch(chatProvider);
    return state.conversation?.title ??
        AppLocalizations.of(context)!.chatNewConversation;
  }

  // ── 布局 ──

  static const double _sidebarWidth = 280;
  static const double _breakpoint = 600;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chatData = ref.watch(chatProvider);

    if (_loading) {
      return Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: theme.colorScheme.primary),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= _breakpoint;
        if (isWide) {
          return _buildWideLayout(theme, chatData);
        } else {
          return _buildNarrowLayout(theme);
        }
      },
    );
  }

  Widget _buildNarrowLayout(ThemeData theme) {
    final settings = ref.watch(settingsProvider);
    final chatNotifier = ref.read(chatProvider.notifier);

    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        title: Text(_title, style: theme.textTheme.titleMedium),
        actions: [
          if (ref.watch(chatProvider).isStreaming)
            IconButton(
              icon: const Icon(Icons.stop),
              onPressed: () => chatNotifier.stopStreaming(),
            ),
          if (!ref.watch(chatProvider).isStreaming &&
              ref.watch(chatProvider).messages.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => chatNotifier.retry(
                streamEnabled: ref.read(settingsProvider).streamEnabled,
              ),
            ),
        ],
      ),
      drawer: Drawer(
        width: _sidebarWidth,
        child: Sidebar(
          conversations: _conversations,
          isPermanent: false,
          onNewConversation: _newConversation,
          onSelectConversation: _selectConversation,
          onDeleteConversation: _deleteConversation,
          onRenameConversation: _renameConversation,
          onSettings: _openSettings,
          displayName: settings.userDisplayName,
          onProfile: () => Navigator.of(context).pushNamed('/profile'),
        ),
      ),
      body: _buildChatArea(theme),
    );
  }

  Widget _buildWideLayout(ThemeData theme, ChatData chatData) {
    final settings = ref.watch(settingsProvider);
    final chatNotifier = ref.read(chatProvider.notifier);

    return Scaffold(
      body: Row(
        children: [
          AnimatedBuilder(
            animation: _sidebarAnim,
            builder: (context, child) {
              return SizedBox(
                width: _sidebarWidth * _sidebarAnim.value,
                child: OverflowBox(maxWidth: _sidebarWidth, child: child),
              );
            },
            child: Sidebar(
              conversations: _conversations,
              isPermanent: true,
              onNewConversation: _newConversation,
              onSelectConversation: _selectConversation,
              onDeleteConversation: _deleteConversation,
              onRenameConversation: _renameConversation,
              onSettings: _openSettings,
              onToggleCollapse: _toggleSidebar,
              displayName: settings.userDisplayName,
              onProfile: () => Navigator.of(context).pushNamed('/profile'),
            ),
          ),
          Container(width: 1, color: theme.colorScheme.outlineVariant),
          Expanded(
            child: Scaffold(
              appBar: AppBar(
                leading: _sidebarVisible
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.menu),
                        onPressed: _toggleSidebar,
                      ),
                title: Text(_title, style: theme.textTheme.titleMedium),
                actions: [
                  if (chatData.isStreaming)
                    IconButton(
                      icon: const Icon(Icons.stop),
                      onPressed: () => chatNotifier.stopStreaming(),
                    ),
                  if (!chatData.isStreaming && chatData.messages.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.refresh),
                      onPressed: () => chatNotifier.retry(
                        streamEnabled: ref.read(settingsProvider).streamEnabled,
                      ),
                    ),
                ],
              ),
              body: _buildChatArea(theme),
            ),
          ),
        ],
      ),
    );
  }

  void _toggleSidebar() {
    setState(() {
      _sidebarVisible = !_sidebarVisible;
      if (_sidebarVisible) {
        _sidebarAnimController.forward();
      } else {
        _sidebarAnimController.reverse();
      }
    });
  }

  Widget _buildChatArea(ThemeData theme) {
    return ChatContentView(
      onSend: _handleSend,
      onModify: _handleModify,
      onRegenerate: _handleRegenerate,
      onShare: _handleShare,
    );
  }
}
