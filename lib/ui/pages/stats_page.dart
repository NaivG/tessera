import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tessera/l10n/app_localizations.dart';

import '../../models/provider_usage.dart';
import '../../providers/providers.dart';

/// 数据统计页面 — 展示各 provider 的 token 消耗与缓存命中率
class StatsPage extends ConsumerWidget {
  const StatsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(statsProvider);
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.statsAppBarTitle),
        actions: [
          if (stats.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: l10n.statsReset,
              onPressed: () => _confirmReset(context, ref, l10n),
            ),
        ],
      ),
      body: stats.isEmpty
          ? _buildEmptyState(l10n, theme, colorScheme)
          : _buildStatsList(context, ref, stats, l10n, theme, colorScheme),
    );
  }

  Widget _buildEmptyState(
    AppLocalizations l10n,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.bar_chart_outlined,
            size: 64,
            color: colorScheme.outlineVariant,
          ),
          const SizedBox(height: 16),
          Text(
            l10n.statsEmpty,
            style: theme.textTheme.titleMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.statsEmptySubtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.outline,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildStatsList(
    BuildContext context,
    WidgetRef ref,
    Map<String, ProviderUsage> stats,
    AppLocalizations l10n,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    final usages = stats.values.toList()
      ..sort((a, b) => b.totalTokens.compareTo(a.totalTokens));

    // 总计
    final totalPrompt =
        usages.fold<int>(0, (s, u) => s + u.totalPromptTokens);
    final totalCompletion =
        usages.fold<int>(0, (s, u) => s + u.totalCompletionTokens);
    final totalRequests =
        usages.fold<int>(0, (s, u) => s + u.totalRequests);
    final totalCacheHits =
        usages.fold<int>(0, (s, u) => s + u.cacheHitCount);
    final totalCacheMisses =
        usages.fold<int>(0, (s, u) => s + u.cacheMissCount);
    final totalCacheOps = totalCacheHits + totalCacheMisses;
    final overallHitRate = totalCacheOps > 0
        ? totalCacheHits / totalCacheOps
        : 0.0;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── 总计卡片 ──
        _OverallCard(
          totalTokens: totalPrompt + totalCompletion,
          totalPrompt: totalPrompt,
          totalCompletion: totalCompletion,
          totalRequests: totalRequests,
          cacheHitRate: overallHitRate,
          l10n: l10n,
          theme: theme,
          colorScheme: colorScheme,
        ),
        const SizedBox(height: 20),

        // ── 每个 provider ──
        Text(
          l10n.settingsSectionLlmProviders,
          style: theme.textTheme.titleSmall?.copyWith(
            color: colorScheme.outline,
          ),
        ),
        const SizedBox(height: 8),
        ...usages.map(
          (usage) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _ProviderCard(
              usage: usage,
              l10n: l10n,
              theme: theme,
              colorScheme: colorScheme,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _confirmReset(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.statsResetConfirmTitle),
        content: Text(l10n.statsResetConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              l10n.statsReset,
              style: TextStyle(color: Theme.of(ctx).colorScheme.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(statsProvider.notifier).resetStats();
    }
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// 总计卡片
// ═════════════════════════════════════════════════════════════════════════════

class _OverallCard extends StatelessWidget {
  final int totalTokens;
  final int totalPrompt;
  final int totalCompletion;
  final int totalRequests;
  final double cacheHitRate;
  final AppLocalizations l10n;
  final ThemeData theme;
  final ColorScheme colorScheme;

  const _OverallCard({
    required this.totalTokens,
    required this.totalPrompt,
    required this.totalCompletion,
    required this.totalRequests,
    required this.cacheHitRate,
    required this.l10n,
    required this.theme,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: colorScheme.primaryContainer.withValues(alpha: 0.3),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.analytics_outlined,
                    size: 20, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  l10n.statsOverall,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _StatRow(
              label: l10n.statsTotalTokens,
              value: _formatNumber(totalTokens),
              colorScheme: colorScheme,
            ),
            const SizedBox(height: 6),
            _StatRow(
              label: l10n.statsPromptTokens,
              value: _formatNumber(totalPrompt),
              colorScheme: colorScheme,
            ),
            const SizedBox(height: 6),
            _StatRow(
              label: l10n.statsCompletionTokens,
              value: _formatNumber(totalCompletion),
              colorScheme: colorScheme,
            ),
            const SizedBox(height: 6),
            _StatRow(
              label: l10n.statsRequests,
              value: _formatNumber(totalRequests),
              colorScheme: colorScheme,
            ),
            const SizedBox(height: 6),
            _StatRow(
              label: l10n.statsCacheHitRate,
              value: _formatPercent(cacheHitRate),
              colorScheme: colorScheme,
            ),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// 单个 Provider 卡片
// ═════════════════════════════════════════════════════════════════════════════

class _ProviderCard extends StatelessWidget {
  final ProviderUsage usage;
  final AppLocalizations l10n;
  final ThemeData theme;
  final ColorScheme colorScheme;

  const _ProviderCard({
    required this.usage,
    required this.l10n,
    required this.theme,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 标题行 ──
            Row(
              children: [
                Icon(
                  Icons.cloud_outlined,
                  size: 20,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    usage.providerName.isNotEmpty
                        ? usage.providerName
                        : usage.providerId,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  usage.providerId,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.outline,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // ── 数据行 ──
            Row(
              children: [
                Expanded(
                  child: _MiniStat(
                    label: l10n.statsTotalTokens,
                    value: _formatNumber(usage.totalTokens),
                    colorScheme: colorScheme,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _MiniStat(
                    label: l10n.statsRequests,
                    value: _formatNumber(usage.totalRequests),
                    colorScheme: colorScheme,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _MiniStat(
                    label: l10n.statsCacheHitRate,
                    value: _formatPercent(usage.cacheHitRate),
                    colorScheme: colorScheme,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // ── 进度条提示/补全 ──
            if (usage.totalTokens > 0)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: usage.totalPromptTokens /
                          usage.totalTokens,
                      backgroundColor: colorScheme.surfaceContainerHighest,
                      color: colorScheme.primary,
                      minHeight: 6,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      _DotLabel(
                        color: colorScheme.primary,
                        label: '${l10n.statsPromptTokens}: ${_formatNumber(usage.totalPromptTokens)}',
                        style: theme.textTheme.labelSmall,
                      ),
                      const SizedBox(width: 12),
                      _DotLabel(
                        color: colorScheme.outline,
                        label: '${l10n.statsCompletionTokens}: ${_formatNumber(usage.totalCompletionTokens)}',
                        style: theme.textTheme.labelSmall,
                      ),
                    ],
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// 小组件
// ═════════════════════════════════════════════════════════════════════════════

class _StatRow extends StatelessWidget {
  final String label;
  final String value;
  final ColorScheme colorScheme;

  const _StatRow({
    required this.label,
    required this.value,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 13)),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final ColorScheme colorScheme;

  const _MiniStat({
    required this.label,
    required this.value,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: colorScheme.outline,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class _DotLabel extends StatelessWidget {
  final Color color;
  final String label;
  final TextStyle? style;

  const _DotLabel({
    required this.color,
    required this.label,
    this.style,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: style),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// 格式化工具
// ═════════════════════════════════════════════════════════════════════════════

String _formatNumber(int n) {
  if (n >= 1_000_000) {
    return '${(n / 1_000_000).toStringAsFixed(1)}M';
  }
  if (n >= 1_000) {
    return '${(n / 1_000).toStringAsFixed(1)}K';
  }
  return n.toString();
}

String _formatPercent(double rate) {
  return '${(rate * 100).toStringAsFixed(1)}%';
}
