import 'package:flutter/material.dart';

import 'package:share_plus/share_plus.dart';

import '../../models/conversation.dart';
import '../../models/message.dart';
import '../../state/chat_state.dart';
import '../../state/settings_state.dart';
import '../../services/conversation_service.dart';
import '../widgets/chat_content_view.dart';
import '../widgets/message_input.dart';
import '../widgets/sidebar.dart';

/// 主页面 — 响应式侧边栏 + 聊天区域
///
/// - 竖屏 / 窄屏 (width < 600): 侧边栏作为 Scaffold.drawer
/// - 横屏 / 宽屏 (width >= 600): 侧边栏常驻嵌入，与聊天区域并排
class MainPage extends StatefulWidget {
  final SettingsState settingsState;

  const MainPage({super.key, required this.settingsState});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> with TickerProviderStateMixin {
  final ConversationService _convService = ConversationService();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  /// 持久化的对话列表（用于侧边栏展示）
  List<Conversation> _conversations = [];
  Set<String> _conversationIds = {};
  bool _loading = true;

  ChatState? _chatState;
  String? _activeConversationId;

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
    _chatState = ChatState();
    _chatState!.configureCapabilities(widget.settingsState);
    _chatState!.addListener(_onChatStateChanged);
    _chatState!.init(); // 提前加载 SystemPromptBuilder + CacheManager
    _loadConversations();
    widget.settingsState.addListener(_onSettingsChanged);
  }

  @override
  void dispose() {
    widget.settingsState.removeListener(_onSettingsChanged);
    _chatState?.removeListener(_onChatStateChanged);
    _sidebarAnimController.dispose();
    _chatState?.dispose();
    super.dispose();
  }

  void _onSettingsChanged() {
    if (!mounted) return;
    setState(() {});
  }

  void _onChatStateChanged() {
    if (!mounted) return;
    final conv = _chatState?.conversation;
    if (conv != null) {
      if (!_conversationIds.contains(conv.id)) {
        // 新对话创建：加入侧边栏并刷新完整列表
        _conversationIds.add(conv.id);
        _conversations.insert(0, conv);
        _activeConversationId = conv.id;
        _loadConversations();
      } else {
        // 已有对话：同步标题变更（如主题生成更新了标题）
        final idx = _conversations.indexWhere((c) => c.id == conv.id);
        if (idx >= 0 && _conversations[idx].title != conv.title) {
          _conversations[idx] = _conversations[idx].copyWith(title: conv.title);
        }
      }
    }
    setState(() {});
  }

  /// 绑定或切换 [ChatState] 实例，自动管理 listener
  void _bindChatState(ChatState cs) {
    _chatState?.removeListener(_onChatStateChanged);
    _chatState?.dispose();
    cs.addListener(_onChatStateChanged);
    _chatState = cs;
  }

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

  // --- 对话操作 ---

  void _selectConversation(Conversation conv) async {
    if (_scaffoldKey.currentState?.isDrawerOpen == true) {
      Navigator.of(context).pop();
    }

    final cs = ChatState();
    cs.configureCapabilities(widget.settingsState);
    await cs.init();
    await cs.loadConversation(conv.id);
    _bindChatState(cs);
    setState(() {
      _activeConversationId = conv.id;
    });
  }

  /// 进入新对话状态
  void _newConversation() {
    if (_scaffoldKey.currentState?.isDrawerOpen == true) {
      Navigator.of(context).pop();
    }
    _chatState?.clear();
    _activeConversationId = null;
  }

  Future<void> _deleteConversation(String id) async {
    await _convService.deleteConversation(id);
    _conversationIds.remove(id);
    if (_activeConversationId == id) {
      _chatState?.clear();
      _activeConversationId = null;
    }
    _loadConversations();
  }

  Future<void> _renameConversation(String id, String newTitle) async {
    await _convService.renameConversation(id, newTitle);
    // 同步更新内存中的标题，使 AppBar 即时反映变更
    if (_chatState?.conversation?.id == id) {
      _chatState!.conversation!.title = newTitle;
    }
    _loadConversations();
  }

  void _openSettings() {
    Navigator.of(context).pushNamed('/settings');
  }

  // --- 发送消息 ---

  void _handleSend(SendPayload payload) {
    final config = widget.settingsState.buildMainLlmConfig();
    if (config == null) {
      _showNoConfigWarning();
      return;
    }

    _chatState?.sendMessage(
      payload.text,
      attachments: payload.attachments,
      streamEnabled: widget.settingsState.streamEnabled,
      config: config,
    );
    // 注：新对话创建后的侧边栏更新由 _onChatStateChanged listener 统一处理，
    // 避免因 sendMessage 内部异步操作导致竞态漏检。
  }

  void _showNoConfigWarning() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('请先在设置中配置 LLM 提供商并选择模型'),
        action: SnackBarAction(
          label: '去设置',
          onPressed: _openSettings,
        ),
      ),
    );
  }

  // --- 上下文菜单 ---

  void _handleModify(Message msg) async {
    final controller = TextEditingController(text: msg.content);
    final newContent = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('修改消息'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 5,
          decoration: const InputDecoration(hintText: '输入新内容'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('发送'),
          ),
        ],
      ),
    );
    
    if (newContent != null && newContent.isNotEmpty && newContent != msg.content) {
      _chatState?.modifyAndResend(
        msg.id,
        newContent,
        streamEnabled: widget.settingsState.streamEnabled,
      );
    }
  }

  void _handleRegenerate() {
    _chatState?.retry(streamEnabled: widget.settingsState.streamEnabled);
  }

  void _handleShare(Message msg) {
    SharePlus.instance.share(ShareParams(text: msg.content, subject: 'Tessera AI Chat'));
  }

  /// 当前对话标题
  String get _title {
    final conv = _chatState?.conversation;
    return conv?.title ?? '新对话';
  }

  // --- 工具方法 ---

  static const double _sidebarWidth = 280;
  static const double _breakpoint = 600;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
          return _buildWideLayout(theme);
        } else {
          return _buildNarrowLayout(theme);
        }
      },
    );
  }

  // ============ 窄屏（竖屏 / 手机）============

  Widget _buildNarrowLayout(ThemeData theme) {
    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        title: Text(_title, style: theme.textTheme.titleMedium),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '新建对话',
            onPressed: () => _scaffoldKey.currentState?.openDrawer(),
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
          displayName: widget.settingsState.userDisplayName,
          onProfile: () => Navigator.of(context).pushNamed('/profile'),
        ),
      ),
      body: _buildChatArea(theme),
    );
  }

  // ============ 宽屏（横屏 / 平板/桌面）============

  Widget _buildWideLayout(ThemeData theme) {
    return Scaffold(
      body: Row(
        children: [
          // 侧边栏（带动画）
          AnimatedBuilder(
            animation: _sidebarAnim,
            builder: (context, child) {
              return SizedBox(
                width: _sidebarWidth * _sidebarAnim.value,
                child: OverflowBox(
                  maxWidth: _sidebarWidth,
                  child: child,
                ),
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
              displayName: widget.settingsState.userDisplayName,
              onProfile: () => Navigator.of(context).pushNamed('/profile'),
            ),
          ),
          // 分隔线
          Container(
            width: 1,
            color: theme.colorScheme.outlineVariant,
          ),
          // 聊天区域
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
                  if (!_sidebarVisible)
                    IconButton(
                      icon: const Icon(Icons.add),
                      tooltip: '新建对话',
                      onPressed: () {
                        if (!_sidebarVisible) _toggleSidebar();
                      },
                    ),
                  if (_chatState != null && _chatState!.isStreaming)
                    IconButton(
                      icon: const Icon(Icons.stop),
                      onPressed: () => _chatState!.stopStreaming(),
                    ),
                  if (_chatState != null &&
                      !_chatState!.isStreaming &&
                      _chatState!.messages.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.refresh),
                      onPressed: () => _chatState!.retry(
                        streamEnabled: widget.settingsState.streamEnabled,
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

  // ============ 聊天区域 ============

  Widget _buildChatArea(ThemeData theme) {
    return ChatContentView(
      chatState: _chatState ?? ChatState(),
      onSend: _handleSend,
      onModify: _handleModify,
      onRegenerate: _handleRegenerate,
      onShare: _handleShare,
    );
  }
}
