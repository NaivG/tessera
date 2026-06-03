import 'package:flutter/material.dart';

import '../../memory/memory.dart';

/// 记忆页面 — 展示记忆系统中的所有记忆条目
///
/// 以轻微透明卡片展示每条记忆的内容、类型和重要性。
class MemoryPage extends StatefulWidget {
  const MemoryPage({super.key});

  @override
  State<MemoryPage> createState() => _MemoryPageState();
}

class _MemoryPageState extends State<MemoryPage> {
  final MemoryState _memoryState = MemoryState();
  List<MemoryEntry> _entries = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _memoryState.init();
    await _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final all = await _memoryState.service.getAllEntries();
      // 按更新时间降序排列
      all.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      setState(() {
        _entries = all;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('记忆'),
      ),
      body: _loading
          ? Center(
              child: CircularProgressIndicator(color: colorScheme.primary),
            )
          : _entries.isEmpty
              ? _buildEmptyState(theme)
              : _buildMemoryList(theme, colorScheme),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.psychology_outlined,
            size: 64,
            color: theme.colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            '暂无记忆',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '对话中提取的记忆会显示在这里',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMemoryList(ThemeData theme, ColorScheme colorScheme) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _entries.length,
      itemBuilder: (context, index) {
        final entry = _entries[index];
        return _MemoryCard(entry: entry);
      },
    );
  }
}

/// 单条记忆卡片 — 轻微透明风格
class _MemoryCard extends StatelessWidget {
  final MemoryEntry entry;

  const _MemoryCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final typeLabel = _typeLabel(entry.type);
    final typeColor = _typeColor(entry.type, colorScheme);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Card(
        elevation: 0,
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 类型标签 + 重要性条
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: typeColor.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      typeLabel,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: typeColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _ImportanceBar(
                      value: entry.importance,
                      color: typeColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // 内容
              Text(
                entry.content,
                style: theme.textTheme.bodyMedium?.copyWith(
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 8),
              // 时间
              Text(
                _formatTime(entry.updatedAt),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.outline.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _typeLabel(MemoryType type) {
    return switch (type) {
      MemoryType.user => '用户',
      MemoryType.knowledge => '知识',
      MemoryType.event => '事件',
      MemoryType.conversational => '对话',
      MemoryType.longTerm => '长期',
    };
  }

  Color _typeColor(MemoryType type, ColorScheme cs) {
    return switch (type) {
      MemoryType.user => cs.primary,
      MemoryType.knowledge => cs.tertiary,
      MemoryType.event => cs.secondary,
      MemoryType.conversational => cs.error,
      MemoryType.longTerm => cs.primary,
    };
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
    if (diff.inHours < 24) return '${diff.inHours} 小时前';
    if (diff.inDays < 7) return '${diff.inDays} 天前';
    return '${dt.month}/${dt.day} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

/// 重要性指示条 — 渐变细条
class _ImportanceBar extends StatelessWidget {
  final double value;
  final Color color;

  const _ImportanceBar({required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 4,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(2),
        color: color.withValues(alpha: 0.12),
      ),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: value.clamp(0.0, 1.0),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(2),
            color: color.withValues(alpha: 0.55),
          ),
        ),
      ),
    );
  }
}