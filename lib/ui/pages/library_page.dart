import 'dart:io';

import 'package:flutter/material.dart';

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
        title: const Text('资料库'),
        actions: [
          if (entries.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              tooltip: '清空资料库',
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
            '资料库为空',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '在对话中上传的图片、文件等会自动保存在这里',
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除文件'),
        content: Text('确定要删除「${entry.attachment.fileName}」吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              '删除',
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
    final theme = Theme.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清空资料库'),
        content: const Text('确定要删除资料库中的所有文件吗？此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('清空', style: TextStyle(color: theme.colorScheme.error)),
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
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
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
                      _buildInfoText(att),
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
                  child: Icon(
                    Icons.close,
                    size: 14,
                    color: colorScheme.error,
                  ),
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

    return Center(
      child: Icon(icon, size: 40, color: color),
    );
  }

  String _buildInfoText(MediaAttachment att) {
    final typeLabel = switch (att.type) {
      MediaType.image => '图片',
      MediaType.video => '视频',
      MediaType.audio => '音频',
      MediaType.file => '文件',
    };
    final sizeStr = att.fileSizeLabel ?? '';
    return '$typeLabel${sizeStr.isNotEmpty ? ' · $sizeStr' : ''}';
  }
}
