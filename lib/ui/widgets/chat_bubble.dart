import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_context_menu/flutter_context_menu.dart';
import 'package:flutter_streaming_text_markdown/flutter_streaming_text_markdown.dart';

import '../../core/core.dart';
import '../../services/media_library.dart';
import 'processing_block.dart';

/// 聊天气泡组件
///
/// 使用 [StreamingTextMarkdown] 统一处理静态和流式 Markdown 渲染。
/// - 流式消息：通过 [contentStream] 传入 token 流，带打字动画
/// - 静态消息：使用 [StreamingTextMarkdown.instant] 立即渲染，无动画
/// - 思考过程：通过 [thinkingStream] 传入思考 token 流，可折叠显示
///
/// 支持上下文菜单（右键 / 长按）：
/// - 复制 / Markdown / 纯文本
/// - 修改（仅 user 消息）
/// - 重新生成（仅 assistant 消息）
/// - 分享
class ChatBubble extends StatelessWidget {
  final Message message;
  final Stream<String>? contentStream;
  final Stream<String>? thinkingStream;

  /// 修改消息回调（仅 user 消息）
  final void Function()? onModify;

  /// 重新生成回调（仅 assistant 消息）
  final void Function()? onRegenerate;

  /// 分享回调
  final void Function()? onShare;

  const ChatBubble({
    super.key,
    required this.message,
    this.contentStream,
    this.thinkingStream,
    this.onModify,
    this.onRegenerate,
    this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == MessageRole.user;
    final theme = Theme.of(context);
    final isStreaming = message.status == MessageStatus.streaming;
    final hasContent = message.content.isNotEmpty;

    final bubble = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisAlignment: isUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(width: 8),
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width,
              ),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isUser
                    ? theme.colorScheme.primaryContainer
                    : theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16).copyWith(
                  topLeft: const Radius.circular(16),
                  topRight: isUser
                      ? const Radius.circular(4)
                      : const Radius.circular(16),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 思考过程（仅 assistant 消息）
                  if (message.role == MessageRole.assistant &&
                      (message.thinking != null &&
                              message.thinking!.isNotEmpty ||
                          thinkingStream != null))
                    ProcessingBlock(
                      icon: Icons.psychology,
                      inProgressTitle: '思考中...',
                      completedTitle: '已思考',
                      isProcessing: isStreaming,
                      content: message.thinking,
                      contentStream: thinkingStream,
                    ),

                  // 媒体附件封面
                  if (message.mediaAttachments != null &&
                      message.mediaAttachments!.isNotEmpty)
                    _MediaCoverGrid(attachments: message.mediaAttachments!),

                  // 消息内容
                  if (isStreaming && contentStream != null)
                    StreamingTextMarkdown(
                      stream: contentStream!,
                      text: hasContent ? message.content : '',
                      isLoading: !hasContent,
                      markdownEnabled: true,
                      latexEnabled: true,
                      trailingFadeEnabled: true,
                      styleSheet: theme.textTheme.bodyMedium,
                    )
                  else if (hasContent)
                    StreamingTextMarkdown.instant(
                      text: message.content,
                      markdownEnabled: true,
                      latexEnabled: true,
                      styleSheet: theme.textTheme.bodyMedium,
                    )
                  else
                    const SizedBox.shrink(),

                  // 工具调用 — 复用 ProcessingBlock 保持 UI 一致性
                  if (message.toolCalls != null &&
                      message.toolCalls!.isNotEmpty)
                    ...message.toolCalls!.map((tc) {
                      final argsText = _formatToolArguments(tc.arguments);
                      final resultText = message.toolResults?[tc.id];
                      final content = resultText != null
                          ? '$argsText\n\n── 结果 ──\n$resultText'
                          : argsText;
                      return ProcessingBlock(
                        icon: Icons.terminal,
                        inProgressTitle: '调用工具...',
                        completedTitle: tc.name,
                        isProcessing: false,
                        content: content,
                        initiallyExpanded: resultText != null,
                      );
                    }),

                  // 错误信息
                  if (message.status == MessageStatus.error &&
                      message.errorMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        message.errorMessage!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ),

                  // 加载动画 — 仅在无流且无内容时显示（非流式等待中）
                  if (isStreaming && !hasContent && contentStream == null)
                    SizedBox(
                      width: 32,
                      height: 16,
                      child: _LoadingDots(color: theme.colorScheme.primary),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (isUser) _buildAvatar(theme, isUser),
        ],
      ),
    );

    // 仅在消息已完成且非错误时显示上下文菜单
    if (message.status == MessageStatus.completed &&
        message.content.isNotEmpty) {
      return ContextMenuRegion(
        contextMenu: _buildContextMenu(isUser),
        child: bubble,
      );
    }

    return bubble;
  }

  ContextMenu _buildContextMenu(bool isUser) {
    final entries = <ContextMenuEntry>[
      MenuItem.submenu(
        label: const Text('复制'),
        icon: const Icon(Icons.copy),
        items: [
          MenuItem(
            label: const Text('Markdown'),
            icon: const Icon(Icons.code),
            onSelected: (_) => _copyContent(),
          ),
          MenuItem(
            label: const Text('纯文本'),
            icon: const Icon(Icons.text_fields),
            onSelected: (_) => _copyPlainText(),
          ),
        ],
      ),
    ];

    if (isUser && onModify != null) {
      entries.add(
        MenuItem(
          label: const Text('修改'),
          icon: const Icon(Icons.edit),
          onSelected: (_) => onModify?.call(),
        ),
      );
    }

    if (!isUser && onRegenerate != null) {
      entries.add(
        MenuItem(
          label: const Text('重新生成'),
          icon: const Icon(Icons.refresh),
          onSelected: (_) => onRegenerate?.call(),
        ),
      );
    }

    if (onShare != null) {
      entries.add(
        MenuItem(
          label: const Text('分享'),
          icon: const Icon(Icons.share),
          onSelected: (_) => onShare?.call(),
        ),
      );
    }

    return ContextMenu(entries: entries);
  }

  void _copyContent() {
    Clipboard.setData(ClipboardData(text: message.content));
  }

  void _copyPlainText() {
    // 简单的 Markdown 剥离：移除常见 Markdown 语法
    String plain = message.content;
    // 移除代码块
    plain = plain.replaceAll(RegExp(r'```[\s\S]*?```'), '');
    // 移除行内代码
    plain = plain.replaceAll(RegExp(r'`([^`]+)`'), r'$1');
    // 移除加粗/斜体
    plain = plain.replaceAll(RegExp(r'\*\*([^*]+)\*\*'), r'$1');
    plain = plain.replaceAll(RegExp(r'\*([^*]+)\*'), r'$1');
    // 移除链接格式 [text](url) -> text
    plain = plain.replaceAll(RegExp(r'\[([^\]]*)\]\([^)]*\)'), r'$1');
    // 移除图片格式 ![alt](url)
    plain = plain.replaceAll(RegExp(r'!\[[^\]]*\]\([^)]*\)'), '');
    // 移除标题标记
    plain = plain.replaceAll(RegExp(r'^#{1,6}\s+', multiLine: true), '');
    Clipboard.setData(ClipboardData(text: plain.trim()));
  }

  Widget _buildAvatar(ThemeData theme, bool isUser) {
    return CircleAvatar(
      radius: 16,
      backgroundColor: isUser
          ? theme.colorScheme.primary
          : theme.colorScheme.secondary,
      child: Icon(
        isUser ? Icons.person : Icons.smart_toy,
        size: 18,
        color: theme.colorScheme.onPrimary,
      ),
    );
  }
}

/// 格式化工具调用参数为可读文本
String _formatToolArguments(Map<String, dynamic> args) {
  if (args.isEmpty) return '(无参数)';
  final buf = StringBuffer();
  for (final entry in args.entries) {
    buf.writeln('${entry.key}: ${entry.value}');
  }
  return buf.toString().trimRight();
}

/// 媒体封面网格 — 在聊天气泡中渲染多模态附件封面
class _MediaCoverGrid extends StatelessWidget {
  final List<MediaAttachment> attachments;

  const _MediaCoverGrid({required this.attachments});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lib = MediaLibrary.instance;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: attachments.map((att) {
          final filePath = lib.filePathFor(att.libraryId);
          return _buildCover(context, att, filePath, theme);
        }).toList(),
      ),
    );
  }

  Widget _buildCover(
    BuildContext context,
    MediaAttachment att,
    String? filePath,
    ThemeData theme,
  ) {
    switch (att.type) {
      case MediaType.image:
        return _ImageCover(attachment: att, filePath: filePath);
      case MediaType.video:
        return _VideoCover(attachment: att);
      case MediaType.audio:
        return _AudioCover(attachment: att);
      case MediaType.file:
        return _FileCover(attachment: att);
    }
  }
}

/// 图片封面 — 缩略图 + 点击可全屏预览
class _ImageCover extends StatelessWidget {
  final MediaAttachment attachment;
  final String? filePath;

  const _ImageCover({required this.attachment, this.filePath});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: () => _showFullScreen(context),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 160,
          height: 120,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (filePath != null)
                Image.file(
                  File(filePath!),
                  fit: BoxFit.cover,
                  errorBuilder: (_, err, stack) => Icon(
                    Icons.image,
                    size: 40,
                    color: theme.colorScheme.outline,
                  ),
                )
              else
                Icon(Icons.image, size: 40, color: theme.colorScheme.outline),
              // 文件名标签
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 3,
                  ),
                  color: Colors.black54,
                  child: Text(
                    attachment.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showFullScreen(BuildContext context) {
    if (filePath == null) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            iconTheme: const IconThemeData(color: Colors.white),
          ),
          body: Center(
            child: InteractiveViewer(child: Image.file(File(filePath!))),
          ),
        ),
      ),
    );
  }
}

/// 视频封面 — 播放图标 + 文件名
class _VideoCover extends StatelessWidget {
  final MediaAttachment attachment;

  const _VideoCover({required this.attachment});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: 160,
      height: 120,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.play_circle_fill,
            size: 40,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 6),
          Text(
            attachment.fileName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall,
          ),
          if (attachment.fileSizeLabel != null)
            Text(
              attachment.fileSizeLabel!,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
        ],
      ),
    );
  }
}

/// 音频封面 — 波形图标 + 文件名
class _AudioCover extends StatelessWidget {
  final MediaAttachment attachment;

  const _AudioCover({required this.attachment});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: 200,
      height: 56,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const SizedBox(width: 12),
          Icon(Icons.audio_file, size: 28, color: theme.colorScheme.secondary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  attachment.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
                if (attachment.fileSizeLabel != null)
                  Text(
                    attachment.fileSizeLabel!,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
    );
  }
}

/// 文件封面 — 文件图标 + 文件名 + 大小
class _FileCover extends StatelessWidget {
  final MediaAttachment attachment;

  const _FileCover({required this.attachment});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: 200,
      height: 56,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const SizedBox(width: 12),
          Icon(
            Icons.insert_drive_file,
            size: 28,
            color: theme.colorScheme.outline,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  attachment.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
                if (attachment.fileSizeLabel != null)
                  Text(
                    attachment.fileSizeLabel!,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
    );
  }
}

/// 加载动画点
class _LoadingDots extends StatefulWidget {
  final Color color;

  const _LoadingDots({required this.color});

  @override
  State<_LoadingDots> createState() => _LoadingDotsState();
}

class _LoadingDotsState extends State<_LoadingDots>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (index) {
        return AnimatedBuilder(
          animation: _controller,
          builder: (_, child) {
            final delay = index * 0.2;
            final t = (_controller.value - delay).clamp(0.0, 1.0);
            final opacity = (t < 0.5 ? t * 2 : 2 - t * 2).clamp(0.0, 1.0);
            return Opacity(opacity: opacity, child: child);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: widget.color,
                shape: BoxShape.circle,
              ),
            ),
          ),
        );
      }),
    );
  }
}
