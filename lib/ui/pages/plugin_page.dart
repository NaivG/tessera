import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tessera/l10n/app_localizations.dart';

import '../../plugin/plugin.dart';

/// 插件管理页面
///
/// 分为三个部分：
/// 1. 已安装插件 — 可启用/禁用和卸载
/// 2. 捆绑插件源 — 只显示安装按钮，无启用/禁用开关
/// 3. 从文件安装 — 选择 .plugin 文件安装
class PluginPage extends ConsumerStatefulWidget {
  const PluginPage({super.key});

  @override
  ConsumerState<PluginPage> createState() => _PluginPageState();
}

class _PluginPageState extends ConsumerState<PluginPage> {
  final PluginRegistry _registry = PluginRegistry();

  List<PluginEntry> _entries = [];
  Set<String> _activeIds = {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await _registry.scanAll();
      // 启用已有插件确保状态刷新
      for (final id in _registry.allPlugins.map((p) => p.id)) {
        await _registry.enable(id);
      }

      setState(() {
        _entries = _registry.allEntries;
        _activeIds = _registry.activePluginIds.toSet();
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  List<PluginEntry> get _installed =>
      _entries.where((e) => e.origin == PluginOrigin.installed).toList();

  List<PluginEntry> get _bundled =>
      _entries.where((e) => e.origin == PluginOrigin.bundled).toList();

  Future<void> _toggleEnable(PluginEntry entry) async {
    final l10n = AppLocalizations.of(context)!;
    final pluginId = entry.metadata.id;
    if (_registry.isEnabled(pluginId)) {
      await _registry.disable(pluginId);
    } else {
      final ok = await _registry.enable(pluginId);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.pluginEnableFailed(entry.metadata.name))),
        );
      }
    }
    setState(() {
      _activeIds = _registry.activePluginIds.toSet();
    });
  }

  Future<void> _installFromAssets(PluginEntry entry) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      final installed = await _registry.installFromAssets(entry.relativeId);
      // 自动启用
      await _registry.enable(installed.metadata.id);
      setState(() {
        _entries = _registry.allEntries;
        _activeIds = _registry.activePluginIds.toSet();
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.pluginInstallSuccess(installed.metadata.name)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.pluginInstallFailed(e.toString()))),
        );
      }
    }
  }

  Future<void> _pickAndInstallPlugin() async {
    final l10n = AppLocalizations.of(context)!;

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['plugin'],
    );
    if (result == null || result.files.single.path == null) return;

    final zipPath = result.files.single.path!;
    setState(() => _loading = true);

    try {
      // 阶段一：提取 zip 到临时目录并读取元数据
      final (meta, tempDir) = await _registry.previewZip(zipPath);

      if (!mounted) {
        await Directory(tempDir).delete(recursive: true);
        return;
      }

      // 阶段二：弹出确认对话框
      final theme = Theme.of(context);
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l10n.pluginInstallConfirmTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${meta.name} v${meta.version}',
                style: theme.textTheme.titleMedium,
              ),
              if (meta.author.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  l10n.pluginByAuthor(meta.author),
                  style: theme.textTheme.bodySmall,
                ),
              ],
              if (meta.description.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  meta.description,
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.commonCancel),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l10n.commonConfirm),
            ),
          ],
        ),
      );

      if (confirmed == true) {
        // 阶段三：安装到最终目录并自动启用
        await _registry.installFromTemp(tempDir, meta);

        setState(() {
          _entries = _registry.allEntries;
          _activeIds = _registry.activePluginIds.toSet();
          _loading = false;
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.pluginInstallSuccess(meta.name)),
            ),
          );
        }
      } else {
        // 取消 — 清理临时目录
        await Directory(tempDir).delete(recursive: true);
        setState(() => _loading = false);
      }
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.pluginInvalidZip(e.toString())),
          ),
        );
      }
    }
  }

  Future<void> _uninstall(PluginEntry entry) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.pluginUninstallDialogTitle),
        content: Text(l10n.pluginUninstallConfirm(entry.metadata.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              l10n.commonDelete,
              style: TextStyle(color: Theme.of(ctx).colorScheme.error),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _registry.uninstallPlugin(entry.relativeId);
        setState(() {
          _entries = _registry.allEntries;
          _activeIds = _registry.activePluginIds.toSet();
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.pluginUninstallSuccess(entry.metadata.name)),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l10n.pluginUninstallFailed(e.toString())),
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.pluginAppBarTitle)),
      body: _buildBody(theme, l10n),
    );
  }

  Widget _buildBody(ThemeData theme, AppLocalizations l10n) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text(l10n.pluginLoadError, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(_error!, style: theme.textTheme.bodySmall),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: _load,
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(l10n.pluginRetry),
            ),
          ],
        ),
      );
    }

    final installed = _installed;
    final bundled = _bundled;

    if (installed.isEmpty && bundled.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.extension_off, size: 64, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text(
              l10n.pluginEmpty,
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          // --- 已安装插件 ---
          if (installed.isNotEmpty) ...[
            _buildSectionHeader(
              theme: theme,
              title: l10n.pluginSectionInstalled,
              count: installed.length,
            ),
            ...installed.map((e) => _buildInstalledCard(theme, l10n, e)),
            const SizedBox(height: 12),
          ],

          // --- 捆绑插件源 ---
          if (bundled.isNotEmpty) ...[
            _buildSectionHeader(
              theme: theme,
              title: l10n.pluginSectionBundled,
              count: bundled.length,
            ),
            ...bundled.map((e) => _buildBundledCard(theme, l10n, e)),
            const SizedBox(height: 12),
          ],

          // --- 从文件安装 ---
          _buildSectionHeader(
            theme: theme,
            title: l10n.pluginSectionInstallFromFile,
          ),
          _buildInstallFromFileCard(theme, l10n),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Section header
  // ---------------------------------------------------------------------------

  Widget _buildSectionHeader({
    required ThemeData theme,
    required String title,
    int? count,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Row(
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (count != null) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: theme.colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSecondaryContainer,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 已安装插件卡片 — 有启用/禁用 Switch + 卸载按钮
  // ---------------------------------------------------------------------------

  Widget _buildInstalledCard(
    ThemeData theme,
    AppLocalizations l10n,
    PluginEntry entry,
  ) {
    final meta = entry.metadata;
    final isActive = _activeIds.contains(meta.id);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- 头部 + 开关 ---
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 插件图标
                CircleAvatar(
                  backgroundColor: isActive
                      ? theme.colorScheme.primaryContainer
                      : theme.colorScheme.surfaceContainerHighest,
                  child: Icon(
                    Icons.extension,
                    size: 20,
                    color: isActive
                        ? theme.colorScheme.onPrimaryContainer
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 12),
                // 标题和元数据
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        meta.name,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          _buildTag(
                            l10n.pluginInstalled,
                            Colors.green,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'v${meta.version}',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          if (meta.author.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                l10n.pluginByAuthor(meta.author),
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                // 启用/禁用开关
                Switch(
                  value: isActive,
                  onChanged: (_) => _toggleEnable(entry),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ],
            ),
            // --- 描述 ---
            if (meta.description.isNotEmpty) ...[
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  meta.description,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
            // --- 操作按钮 ---
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _buildActionButton(
                  theme: theme,
                  icon: Icons.delete_outline,
                  label: l10n.pluginUninstall,
                  color: theme.colorScheme.error,
                  onTap: () => _uninstall(entry),
                ),
                const SizedBox(width: 8),
                Text(
                  meta.id,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.outline,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 捆绑插件源卡片 — 无启用/禁用开关，只有安装按钮
  // ---------------------------------------------------------------------------

  Widget _buildBundledCard(
    ThemeData theme,
    AppLocalizations l10n,
    PluginEntry entry,
  ) {
    final meta = entry.metadata;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- 头部（无开关） ---
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  backgroundColor: theme.colorScheme.tertiaryContainer,
                  child: Icon(
                    Icons.extension,
                    size: 20,
                    color: theme.colorScheme.onTertiaryContainer,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        meta.name,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          _buildTag(
                            l10n.pluginBundled,
                            theme.colorScheme.tertiary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'v${meta.version}',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          if (meta.author.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                l10n.pluginByAuthor(meta.author),
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            // --- 描述 ---
            if (meta.description.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                meta.description,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            // --- 操作按钮 ---
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _buildActionButton(
                  theme: theme,
                  icon: Icons.download,
                  label: l10n.pluginInstall,
                  color: theme.colorScheme.primary,
                  onTap: () => _installFromAssets(entry),
                ),
                const SizedBox(width: 8),
                Text(
                  meta.id,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.outline,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 从文件安装卡片
  // ---------------------------------------------------------------------------

  Widget _buildInstallFromFileCard(
    ThemeData theme,
    AppLocalizations l10n,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _pickAndInstallPlugin,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: theme.colorScheme.secondaryContainer,
                child: Icon(
                  Icons.file_open,
                  size: 20,
                  color: theme.colorScheme.onSecondaryContainer,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.pluginInstallFromZip,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      l10n.pluginInstallFromFileAction,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 共享组件
  // ---------------------------------------------------------------------------

  Widget _buildTag(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required ThemeData theme,
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return TextButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(label, style: TextStyle(fontSize: 12)),
      style: TextButton.styleFrom(
        foregroundColor: color,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}
