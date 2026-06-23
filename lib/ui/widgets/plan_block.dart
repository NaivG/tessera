import 'package:flutter/material.dart';

import 'package:tessera/l10n/app_localizations.dart';

import '../../models/plan.dart';

/// 计划展示组件 — 基于 ProcessingBlock 设计
class PlanBlock extends StatefulWidget {
  final List<Map<String, dynamic>> steps;
  final bool isCollapsed;

  const PlanBlock({
    super.key,
    required this.steps,
    this.isCollapsed = false,
  });

  @override
  State<PlanBlock> createState() => _PlanBlockState();
}

class _PlanBlockState extends State<PlanBlock> {
  late bool _collapsed;

  @override
  void initState() {
    super.initState();
    _collapsed = widget.isCollapsed;
  }

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
          // Header
          InkWell(
            onTap: () => setState(() => _collapsed = !_collapsed),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    Icons.checklist,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    l10n.planExecuteTitle,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    _collapsed ? Icons.expand_more : Icons.expand_less,
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
          // Steps
          if (!_collapsed)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: widget.steps.map((stepJson) {
                  final step = PlanStep.fromJson(stepJson);
                  return _buildStepItem(step, theme);
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStepItem(PlanStep step, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _stepStatusIcon(step.status),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  step.title,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w500,
                    decoration: step.status == PlanStepStatus.completed
                        ? TextDecoration.lineThrough
                        : null,
                  ),
                ),
                if (step.description.isNotEmpty)
                  Text(
                    step.description,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepStatusIcon(PlanStepStatus status) {
    switch (status) {
      case PlanStepStatus.pending:
        return const Icon(Icons.hourglass_empty, size: 14, color: Colors.grey);
      case PlanStepStatus.inProgress:
        return const SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case PlanStepStatus.completed:
        return const Icon(Icons.check_circle, size: 14, color: Colors.green);
      case PlanStepStatus.failed:
        return const Icon(Icons.error, size: 14, color: Colors.red);
    }
  }
}
