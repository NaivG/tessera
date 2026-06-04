import 'package:flutter/material.dart';
import 'package:flutter_context_menu/flutter_context_menu.dart';

import '../../models/conversation.dart';
import 'package:tessera/l10n/app_localizations.dart';

/// 侧边栏组件
///
/// 同时作为 Scaffold.drawer 内容和横屏常驻面板使用。
/// 根据 [isPermanent] 决定是否显示收回按钮和不同的边距。
class Sidebar extends StatefulWidget {
  final List<Conversation> conversations;
  final bool isPermanent;
  final VoidCallback onNewConversation;
  final void Function(Conversation conversation) onSelectConversation;
  final void Function(String id) onDeleteConversation;
  final void Function(String id, String newTitle) onRenameConversation;
  final VoidCallback onSettings;
  final VoidCallback? onToggleCollapse;
  final String displayName;
  final VoidCallback? onProfile;

  const Sidebar({
    super.key,
    required this.conversations,
    this.isPermanent = false,
    required this.onNewConversation,
    required this.onSelectConversation,
    required this.onDeleteConversation,
    required this.onRenameConversation,
    required this.onSettings,
    this.onToggleCollapse,
    this.displayName = '',
    this.onProfile,
  });

  @override
  State<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<Sidebar> {
  ContextMenu _buildConversationContextMenu(Conversation conv) {
    final l10n = AppLocalizations.of(context)!;
    return ContextMenu(
      entries: [
        MenuItem(
          label: Text(l10n.sidebarRename),
          icon: const Icon(Icons.edit),
          onSelected: (_) => _showRenameDialog(conv),
        ),
        MenuItem(
          label: Text(l10n.commonDelete),
          icon: const Icon(Icons.delete, color: Colors.red),
          onSelected: (_) => _confirmDelete(conv),
        ),
      ],
    );
  }

  Future<void> _showRenameDialog(Conversation conv) async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController(text: conv.title);
    final newTitle = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.sidebarRenameDialogTitle),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: l10n.sidebarRenameHint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(l10n.commonConfirm),
          ),
        ],
      ),
    );
    if (newTitle != null && newTitle.isNotEmpty && newTitle != conv.title) {
      widget.onRenameConversation(conv.id, newTitle);
    }
  }

  Future<void> _confirmDelete(Conversation conv) async {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.sidebarDeleteDialogTitle),
        content: Text(l10n.sidebarDeleteConfirm(conv.title)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              l10n.commonDelete,
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      widget.onDeleteConversation(conv.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return DrawerHeaderStyle(
      theme: theme,
      child: Column(
        children: [
          // --- Header ---
          Container(
            padding: EdgeInsets.only(
              top: MediaQuery.of(context).padding.top + 8,
              left: 16,
              right: 8,
              bottom: 8,
            ),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: colorScheme.outlineVariant),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.sidebarTitle,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.primary,
                    ),
                  ),
                ),
                if (widget.onToggleCollapse != null)
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    tooltip: l10n.sidebarCollapseTooltip,
                    onPressed: widget.onToggleCollapse,
                  ),
                if (widget.onToggleCollapse == null && !widget.isPermanent)
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: l10n.sidebarCloseTooltip,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
              ],
            ),
          ),

          // --- Body (对话列表) ---
          Expanded(
            child: Column(
              children: [
                Expanded(child: _buildConversationsTab(theme, colorScheme)),
                _buildLibraryTab(theme, colorScheme),
              ],
            ),
          ),

          // --- Footer ---
          Container(
            padding: EdgeInsets.only(
              left: 16,
              right: 8,
              bottom: MediaQuery.of(context).padding.bottom + 8,
              top: 8,
            ),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: colorScheme.outlineVariant),
              ),
            ),
            child: Row(
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: widget.onProfile,
                  child: CircleAvatar(
                    radius: 16,
                    backgroundColor: colorScheme.primary,
                    child: Icon(
                      Icons.person,
                      size: 18,
                      color: colorScheme.onPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: widget.onProfile,
                    child: Text(
                      widget.displayName.isNotEmpty
                          ? widget.displayName
                          : l10n.sidebarDefaultUserName,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.settings),
                  tooltip: l10n.settingsTitle,
                  onPressed: widget.onSettings,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── 对话 Tab ──

  Widget _buildConversationsTab(ThemeData theme, ColorScheme colorScheme) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      children: [
        // 新建对话（框式按钮）
        Padding(
          padding: const EdgeInsets.all(12),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: widget.onNewConversation,
              icon: const Icon(Icons.add_comment, size: 18),
              label: Text(l10n.chatNewLabel),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                side: BorderSide(
                  color: colorScheme.outline.withValues(alpha: 0.5),
                ),
                alignment: Alignment.centerLeft,
              ),
            ),
          ),
        ),

        // 分隔
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Text(
                l10n.sidebarConversationsLabel,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colorScheme.outline,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: Divider(color: colorScheme.outlineVariant)),
            ],
          ),
        ),

        const SizedBox(height: 4),

        // 对话主题列表
        Expanded(
          child: widget.conversations.isEmpty
              ? Center(
                  child: Text(
                    l10n.chatNoConversations,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.outline,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: widget.conversations.length,
                  itemBuilder: (context, index) {
                    final conv = widget.conversations[index];
                    return ContextMenuRegion(
                      contextMenu: _buildConversationContextMenu(conv),
                      child: ListTile(
                        leading: CircleAvatar(
                          radius: 16,
                          backgroundColor: colorScheme.primaryContainer,
                          child: Icon(
                            Icons.chat,
                            size: 16,
                            color: colorScheme.onPrimaryContainer,
                          ),
                        ),
                        title: Text(
                          conv.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium,
                        ),
                        subtitle: Text(
                          '${conv.config.providerId} · ${conv.config.modelId}',
                          style: theme.textTheme.labelSmall,
                        ),
                        dense: true,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        onTap: () => widget.onSelectConversation(conv),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ── 底部快捷按钮 (资料库 / 记忆) ──

  Widget _buildLibraryTab(ThemeData theme, ColorScheme colorScheme) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: _buildShortcutButton(
              icon: Icons.photo_library_outlined,
              label: l10n.shortcutLibrary,
              route: '/library',
              theme: theme,
              colorScheme: colorScheme,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildShortcutButton(
              icon: Icons.psychology_outlined,
              label: l10n.shortcutMemory,
              route: '/memory',
              theme: theme,
              colorScheme: colorScheme,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShortcutButton({
    required IconData icon,
    required String label,
    required String route,
    required ThemeData theme,
    required ColorScheme colorScheme,
  }) {
    return OutlinedButton.icon(
      onPressed: () => Navigator.of(context).pushNamed(route),
      icon: Icon(icon, size: 16),
      label: Text(label, style: theme.textTheme.labelSmall),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        side: BorderSide(color: colorScheme.outline.withValues(alpha: 0.4)),
        alignment: Alignment.center,
      ),
    );
  }
}

/// 一个简单的包装器，模仿 DrawerHeader 的样式但不使用 DrawerHeader 的默认边距
class DrawerHeaderStyle extends StatelessWidget {
  final Widget child;
  final ThemeData theme;

  const DrawerHeaderStyle({
    super.key,
    required this.child,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: theme.colorScheme.surface),
      child: child,
    );
  }
}
