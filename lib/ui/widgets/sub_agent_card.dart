import 'package:flutter/material.dart';

import 'package:tessera/l10n/app_localizations.dart';

/// 子 Agent 进度卡片 — 嵌入主会话消息流
class SubAgentCard extends StatefulWidget {
  final String sessionId;
  final String task;
  final String status; // 'running' | 'completed' | 'failed'
  final String? summary;
  final void Function(String sessionId)? onJumpToSession;

  const SubAgentCard({
    super.key,
    required this.sessionId,
    required this.task,
    required this.status,
    this.summary,
    this.onJumpToSession,
  });

  @override
  State<SubAgentCard> createState() => _SubAgentCardState();
}

class _SubAgentCardState extends State<SubAgentCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header (collapsible)
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    Icons.smart_toy,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.subAgentTitle(widget.task),
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _statusWidget(theme, l10n),
                  const SizedBox(width: 4),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
          // Expanded content
          if (_expanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.summary != null && widget.summary!.isNotEmpty)
                    Text(
                      widget.summary!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  if (widget.onJumpToSession != null) ...[
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: () => widget.onJumpToSession!(widget.sessionId),
                      icon: const Icon(Icons.open_in_new, size: 14),
                      label: Text(l10n.subAgentViewSession),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        textStyle: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _statusWidget(ThemeData theme, AppLocalizations l10n) {
    switch (widget.status) {
      case 'running':
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 4),
            Text(l10n.subAgentRunning, style: theme.textTheme.bodySmall),
          ],
        );
      case 'completed':
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, size: 14, color: Colors.green),
            const SizedBox(width: 4),
            Text(l10n.subAgentCompleted, style: theme.textTheme.bodySmall),
          ],
        );
      case 'failed':
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error, size: 14, color: Colors.red),
            const SizedBox(width: 4),
            Text(l10n.subAgentFailed, style: theme.textTheme.bodySmall),
          ],
        );
      default:
        return const SizedBox.shrink();
    }
  }
}
