import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:tessera/l10n/app_localizations.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../models/workspace.dart';
import '../../providers/providers.dart';
import '../../services/workspace_service.dart';

/// 工作空间管理页面
///
/// - 顶部：当前激活工作空间的文件浏览（含搜索）
/// - 下方：所有已注册工作空间卡片（可设为激活 / 重命名 / 删除）
class WorkspacePage extends ConsumerStatefulWidget {
  const WorkspacePage({super.key});

  @override
  ConsumerState<WorkspacePage> createState() => _WorkspacePageState();
}

class _WorkspacePageState extends ConsumerState<WorkspacePage> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _currentRelativePath = '';
  List<WorkspaceEntry> _entries = [];
  bool _loadingList = false;
  String? _listError;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _refreshList(String workspaceId) async {
    setState(() {
      _loadingList = true;
      _listError = null;
    });
    try {
      final list = await ref
          .read(workspaceProvider.notifier)
          .listDirectory(workspaceId, _currentRelativePath);
      if (!mounted) return;
      setState(() {
        _entries = list;
        _loadingList = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _entries = [];
        _loadingList = false;
        _listError = e.toString();
      });
    }
  }

  Future<void> _addWorkspace() async {
    final l10n = AppLocalizations.of(context)!;
    // Web / iOS —— 工作空间功能始终禁用,直接给出明确提示,避免后续 picker 走空。
    final service = ref.read(workspaceServiceProvider);
    if (!service.isPlatformSupported) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.workspaceUnsupportedPlatform),
          duration: const Duration(seconds: 4),
        ),
      );
      return;
    }
    final picked = await FilePicker.platform.getDirectoryPath(
      dialogTitle: l10n.workspacePickFolder,
    );
    debugPrint('[ws] picked path = $picked');
    if (picked == null || !mounted) return;
    final defaultName = p.basename(picked);
    final nameCtrl = TextEditingController(text: defaultName);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.workspaceAddTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.workspacePathLabel(picked),
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: nameCtrl,
              decoration: InputDecoration(
                labelText: l10n.workspaceNameHint,
                border: const OutlineInputBorder(),
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, nameCtrl.text.trim()),
            child: Text(l10n.commonSave),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    try {
      // service.addWorkspace 内部处理 Android MANAGE_EXTERNAL_STORAGE 请求
      // —— 第三方 ROM 可能撤回权限,所以这里每次都重新校验,不依赖 session 缓存。
      await ref
          .read(workspaceProvider.notifier)
          .addWorkspace(name: name, path: picked);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('"$name" added.')));
      }
    } on WorkspaceFileException catch (e) {
      if (!mounted) return;
      final isPermission = e.message.contains('MANAGE_EXTERNAL_STORAGE');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          duration: const Duration(seconds: 6),
          action: isPermission
              ? SnackBarAction(
                  label: l10n.workspaceOpenSettings,
                  onPressed: openAppSettings,
                )
              : null,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Add failed: $e')));
      }
    }
  }

  Future<void> _renameWorkspace(Workspace ws) async {
    final l10n = AppLocalizations.of(context)!;
    final ctrl = TextEditingController(text: ws.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.workspaceRename),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(
            labelText: l10n.workspaceNameHint,
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: Text(l10n.commonSave),
          ),
        ],
      ),
    );
    if (newName == null || newName.isEmpty || newName == ws.name) return;
    await ref.read(workspaceProvider.notifier).renameWorkspace(ws.id, newName);
  }

  Future<void> _removeWorkspace(Workspace ws) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.workspaceRemove),
        content: Text(
          'Remove workspace "${ws.name}"? Files on disk will NOT be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              l10n.commonDelete,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(workspaceProvider.notifier).removeWorkspace(ws.id);
    if (_currentRelativePath.isNotEmpty) {
      setState(() => _currentRelativePath = '');
    }
  }

  Future<void> _setActive(Workspace ws) async {
    await ref.read(workspaceProvider.notifier).setActive(ws.id);
    setState(() => _currentRelativePath = '');
    await _refreshList(ws.id);
  }

  Future<void> _onSearch(String workspaceId, String query) async {
    if (query.trim().isEmpty) {
      await _refreshList(workspaceId);
      return;
    }
    setState(() {
      _loadingList = true;
      _listError = null;
    });
    try {
      final results = await ref
          .read(workspaceProvider.notifier)
          .search(workspaceId, query.trim());
      if (!mounted) return;
      setState(() {
        _entries = results;
        _loadingList = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingList = false;
        _listError = e.toString();
      });
    }
  }

  Future<void> _navigateTo(Workspace ws, WorkspaceEntry entry) async {
    if (entry.kind == WorkspaceEntryKind.directory) {
      setState(() => _currentRelativePath = entry.relativePath);
      await _refreshList(ws.id);
    } else {
      // 文件 —— 弹出只读内容预览
      try {
        final result = await ref
            .read(workspaceProvider.notifier)
            .readFile(ws.id, entry.relativePath);
        final content = result.content;
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(entry.name, overflow: TextOverflow.ellipsis),
            content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                child: SelectableText(
                  content.isEmpty ? '(empty)' : content,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(l10nOf(ctx).commonCancel),
              ),
            ],
          ),
        );
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Read failed: $e')));
        }
      }
    }
  }

  AppLocalizations l10nOf(BuildContext ctx) => AppLocalizations.of(ctx)!;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final wsState = ref.watch(workspaceProvider);
    final active = wsState.active;

    // 当激活工作空间变化时刷新列表
    ref.listen<WorkspaceData>(workspaceProvider, (prev, next) {
      if (prev?.activeWorkspaceId != next.activeWorkspaceId) {
        if (_currentRelativePath.isNotEmpty) {
          _currentRelativePath = '';
        }
        _searchCtrl.clear();
        final newActive = next.active;
        if (newActive != null) {
          _refreshList(newActive.id);
        }
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.workspaceAppBarTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.create_new_folder_outlined),
            tooltip: l10n.workspaceAddTitle,
            onPressed: _addWorkspace,
          ),
        ],
      ),
      body: Column(
        children: [
          // 激活工作空间的文件浏览
          if (active != null) _buildActiveSection(theme, l10n, active),
          const Divider(height: 1),
          Expanded(child: _buildWorkspaceList(theme, l10n, wsState)),
        ],
      ),
    );
  }

  Widget _buildActiveSection(
    ThemeData theme,
    AppLocalizations l10n,
    Workspace active,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.folder_open,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  active.name,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  l10n.workspaceActive,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
          Text(
            active.rootPath,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
              fontFamily: 'monospace',
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: l10n.workspaceSearchHint,
                    prefixIcon: const Icon(Icons.search, size: 18),
                    suffixIcon: _searchCtrl.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear, size: 16),
                            onPressed: () {
                              _searchCtrl.clear();
                              _refreshList(active.id);
                              setState(() {});
                            },
                          ),
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (v) {
                    setState(() {});
                    _onSearch(active.id, v);
                  },
                ),
              ),
              if (_currentRelativePath.isNotEmpty) ...[
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: () {
                    setState(() => _currentRelativePath = '');
                    _refreshList(active.id);
                  },
                  icon: const Icon(Icons.home_outlined, size: 16),
                  label: Text('/'),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          _buildEntryList(theme, l10n, active),
        ],
      ),
    );
  }

  Widget _buildEntryList(
    ThemeData theme,
    AppLocalizations l10n,
    Workspace active,
  ) {
    if (_loadingList) {
      return const SizedBox(
        height: 80,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_listError != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          _listError!,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.error,
          ),
        ),
      );
    }
    if (_entries.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          _searchCtrl.text.isEmpty ? '(empty)' : 'No matches.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
      );
    }
    return SizedBox(
      height: 240,
      child: ListView.builder(
        itemCount: _entries.length,
        itemBuilder: (ctx, i) {
          final entry = _entries[i];
          final isDir = entry.kind == WorkspaceEntryKind.directory;
          return ListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            leading: Icon(
              isDir ? Icons.folder_outlined : Icons.insert_drive_file_outlined,
              size: 18,
              color: isDir
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
            title: Text(
              entry.relativePath,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
            onTap: () => _navigateTo(active, entry),
          );
        },
      ),
    );
  }

  Widget _buildWorkspaceList(
    ThemeData theme,
    AppLocalizations l10n,
    WorkspaceData wsState,
  ) {
    if (wsState.workspaces.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.folder_off_outlined,
              size: 64,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              l10n.workspaceEmpty,
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.workspaceEmptySubtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: _addWorkspace,
              icon: const Icon(Icons.add),
              label: Text(l10n.workspaceAddTitle),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      itemCount: wsState.workspaces.length,
      itemBuilder: (ctx, i) {
        final ws = wsState.workspaces[i];
        final isActive = ws.id == wsState.activeWorkspaceId;
        return ListTile(
          leading: Icon(
            isActive ? Icons.check_circle : Icons.folder_outlined,
            color: isActive
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurfaceVariant,
          ),
          title: Text(ws.name),
          subtitle: Text(
            ws.rootPath,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
              fontFamily: 'monospace',
            ),
          ),
          trailing: PopupMenuButton<String>(
            onSelected: (v) {
              switch (v) {
                case 'active':
                  _setActive(ws);
                  break;
                case 'rename':
                  _renameWorkspace(ws);
                  break;
                case 'remove':
                  _removeWorkspace(ws);
                  break;
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'active',
                enabled: !isActive,
                child: Text(l10n.workspaceSetActive),
              ),
              PopupMenuItem(value: 'rename', child: Text(l10n.workspaceRename)),
              PopupMenuItem(
                value: 'remove',
                child: Text(
                  l10n.workspaceRemove,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
