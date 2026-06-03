import 'dart:io';

import 'package:flutter/material.dart';

import 'package:tessera/l10n/app_localizations.dart';

import '../../models/media_attachment.dart';
import '../../services/media_library.dart';

/// 资料库页面 — 展示所有已上传的媒体文件，支持预览和删除
class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  final _library = MediaLibrary.instance;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final entries = _library.entries.toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.libraryAppBarTitle),
        actions: [
          if (entries.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              tooltip: AppLocalizations.of(context)!.libraryClearTooltip,
              onPressed: _confirmClear,
            ),
        ],
      ),
      body: entries.isEmpty
          ? _buildEmptyState(theme)
          : _buildGridView(entries, theme, colorScheme),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.photo_library_outlined,
            size: 64,
            color: theme.colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            AppLocalizations.of(context)!.libraryEmpty,
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            AppLocalizations.of(context)!.libraryEmptySubtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGridView(
    List<LibraryEntry> entries,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    return RefreshIndicator(
      onRefresh: () async {
        setState(() {});
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final crossAxisCount = constraints.maxWidth > 600 ? 4 : 3;
          return GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 0.85,
            ),
            itemCount: entries.length,
            itemBuilder: (context, index) {
              final entry = entries[index];
              return _LibraryGridItem(
                entry: entry,
                filePath: _library.filePathFor(entry.id),
                onDelete: () => _deleteEntry(entry),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _deleteEntry(LibraryEntry entry) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.libraryDeleteDialogTitle),
        content: Text(l10n.libraryDeleteConfirm(entry.attachment.fileName)),
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
    if (confirmed == true) {
      await _library.remove(entry.id);
      setState(() {});
    }
  }

  Future<void> _confirmClear() async {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.libraryClearDialogTitle),
        content: Text(l10n.libraryClearConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              l10n.commonClear,
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _library.clear();
      setState(() {});
    }
  }
}

/// 资料库网格项 — 缩略图 + 文件名 + 删除按钮
class _LibraryGridItem extends StatelessWidget {
  final LibraryEntry entry;
  final String? filePath;
  final VoidCallback onDelete;

  const _LibraryGridItem({
    required this.entry,
    required this.filePath,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final att = entry.attachment;

    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 缩略图区域
              Expanded(
                child: Container(
                  color: colorScheme.surfaceContainerHighest,
                  child: _buildThumbnail(att, filePath, colorScheme),
                ),
              ),
              // 文件名 + 信息
              Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      att.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _buildInfoText(att, context),
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontSize: 10,
                        color: colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          // 删除按钮
          Positioned(
            top: 4,
            right: 4,
            child: Material(
              color: colorScheme.surface.withValues(alpha: 0.9),
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onDelete,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(Icons.close, size: 14, color: colorScheme.error),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThumbnail(
    MediaAttachment att,
    String? filePath,
    ColorScheme colorScheme,
  ) {
    if (att.isImage && filePath != null) {
      return Image.file(
        File(filePath),
        fit: BoxFit.cover,
        errorBuilder: (_, error, stack) => _buildFileIcon(att, colorScheme),
      );
    }
    return _buildFileIcon(att, colorScheme);
  }

  Widget _buildFileIcon(MediaAttachment att, ColorScheme colorScheme) {
    IconData icon;
    Color? color;

    if (att.isVideo) {
      icon = Icons.play_circle_outline;
      color = colorScheme.tertiary;
    } else if (att.isAudio) {
      icon = Icons.audio_file;
      color = colorScheme.secondary;
    } else {
      icon = Icons.insert_drive_file;
      color = colorScheme.outline;
    }

    return Center(child: Icon(icon, size: 40, color: color));
  }

  String _buildInfoText(MediaAttachment att, BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final typeLabel = switch (att.type) {
      MediaType.image => l10n.mediaTypeImage,
      MediaType.video => l10n.mediaTypeVideo,
      MediaType.audio => l10n.mediaTypeAudio,
      MediaType.file => l10n.mediaTypeFile,
    };
    final sizeStr = att.fileSizeLabel ?? '';
    return '$typeLabel${sizeStr.isNotEmpty ? ' · $sizeStr' : ''}';
  }
}
