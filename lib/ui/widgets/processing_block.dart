import 'dart:async';

import 'package:flutter/material.dart';

/// 处理中/思考过程块 — 可复用的处理状态展示组件
///
/// 长条状圆角矩形样式，嵌入聊天气泡内部。
/// 点击头部可下拉展开文本详情。
/// 同时用于思考过程展示和工具调用展示，保持 UI 一致性。
///
/// 使用方式：
/// ```dart
/// // 流式思考
/// ProcessingBlock(
///   icon: Icons.psychology,
///   inProgressTitle: '思考中...',
///   completedTitle: '已思考',
///   isProcessing: true,
///   contentStream: thinkingStream,
/// )
///
/// // 完成的思考
/// ProcessingBlock(
///   icon: Icons.psychology,
///   inProgressTitle: '思考中...',
///   completedTitle: '已思考',
///   isProcessing: false,
///   content: '这是思考过程...',
/// )
///
/// // 工具调用
/// ProcessingBlock(
///   icon: Icons.terminal,
///   inProgressTitle: '调用工具...',
///   completedTitle: 'search_file',
///   isProcessing: false,
///   content: '{"query": "main.dart"}',
///   initiallyExpanded: false,
/// )
/// ```
class ProcessingBlock extends StatefulWidget {
  /// 头部图标（如 [Icons.psychology]、[Icons.terminal]）
  final IconData icon;

  /// 处理中显示的文字（如 "思考中..."、"调用工具..."）
  final String inProgressTitle;

  /// 处理完成后显示的文字（如 "已思考"、工具名称）
  final String completedTitle;

  /// 是否正在处理中
  final bool isProcessing;

  /// 静态文本内容（已完成时使用）
  final String? content;

  /// 流式文本内容（处理中时使用）
  final Stream<String>? contentStream;

  /// 是否可折叠（默认 true）
  final bool collapsible;

  /// 初始是否展开（默认：处理中时展开，完成时折叠）
  final bool? initiallyExpanded;

  const ProcessingBlock({
    super.key,
    required this.icon,
    required this.inProgressTitle,
    required this.completedTitle,
    this.isProcessing = false,
    this.content,
    this.contentStream,
    this.collapsible = true,
    this.initiallyExpanded,
  });

  @override
  State<ProcessingBlock> createState() => _ProcessingBlockState();
}

class _ProcessingBlockState extends State<ProcessingBlock>
    with SingleTickerProviderStateMixin {
  late bool _expanded;
  String _accumulatedContent = '';
  final ScrollController _scrollController = ScrollController();
  StreamSubscription<String>? _streamSubscription;

  @override
  void initState() {
    super.initState();
    _accumulatedContent = widget.content ?? '';
    _expanded = widget.initiallyExpanded ?? widget.isProcessing;
    _subscribeToStream();
  }

  @override
  void didUpdateWidget(covariant ProcessingBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.content != oldWidget.content) {
      _accumulatedContent = widget.content ?? '';
      _subscribeToStream();
    }
    if (widget.isProcessing && !oldWidget.isProcessing) {
      _expanded = true;
    }
  }

  void _subscribeToStream() {
    _streamSubscription?.cancel();
    if (widget.contentStream != null && widget.isProcessing) {
      _streamSubscription = widget.contentStream!.listen((delta) {
        if (!mounted) return;
        setState(() {
          _accumulatedContent += delta;
        });
        _scrollToBottom();
      });
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _streamSubscription?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  bool get _hasContent => _accumulatedContent.isNotEmpty;
  bool get _shouldShow =>
      _hasContent || (widget.isProcessing && widget.contentStream != null);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (!_shouldShow) {
      return const SizedBox.shrink();
    }

    final effectiveTitle = widget.isProcessing
        ? widget.inProgressTitle
        : widget.completedTitle;

    final headerColor = widget.isProcessing
        ? theme.colorScheme.tertiary
        : theme.colorScheme.onSurfaceVariant;

    // 长条状圆角矩形 — 嵌入气泡内部
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.55,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // 头部 — 整行可点击
              _buildHeader(theme, effectiveTitle, headerColor),

              // 展开后的内容区域
              if (_expanded && _hasContent) _buildContentArea(theme),

              // 展开但还没有内容 — 加载指示
              if (_expanded && !_hasContent && widget.isProcessing)
                _buildLoading(theme, headerColor),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme, String title, Color headerColor) {
    final VoidCallback? onTap = widget.collapsible
        ? () {
            setState(() => _expanded = !_expanded);
          }
        : null;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.max,
          children: [
            // 图标
            Icon(widget.icon, size: 15, color: headerColor),
            const SizedBox(width: 7),
            // 标题
            Expanded(
              child: Text(
                title,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: headerColor,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // 处理中小圆点 / 展开箭头
            if (widget.isProcessing && _hasContent)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: SizedBox(
                  width: 7,
                  height: 7,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: headerColor,
                  ),
                ),
              ),
            if (widget.collapsible)
              Icon(
                _expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                size: 18,
                color: headerColor,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildContentArea(ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 分隔线
        Divider(
          height: 1,
          thickness: 0.5,
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
        // 可滚动内容
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 260),
          child: SingleChildScrollView(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(10, 7, 10, 8),
            child: Text(
              _accumulatedContent,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.55,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLoading(ThemeData theme, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Divider(
          height: 1,
          thickness: 0.5,
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
          child: _LoadingDots(color: color),
        ),
      ],
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
