import 'package:flutter/material.dart';
import 'package:tessera/l10n/app_localizations.dart';

/// 工作空间审批卡片 — 嵌入主会话消息流
///
/// 展示一次工作空间操作的审批结果（pending / approved / denied）。
class WorkspaceApprovalCard extends StatelessWidget {
  final String action; // 'write' / 'edit' / 'mkdir' / 'delete'
  final String workspaceName;
  final String targetPath;
  final String status; // 'pending' | 'approved' | 'denied'

  const WorkspaceApprovalCard({
    super.key,
    required this.action,
    required this.workspaceName,
    required this.targetPath,
    required this.status,
  });

  String _actionLabel(AppLocalizations l10n) {
    switch (action) {
      case 'write':
        return l10n.workspaceApprovalActionWrite;
      case 'edit':
        return l10n.workspaceApprovalActionEdit;
      case 'mkdir':
        return l10n.workspaceApprovalActionMkdir;
      case 'delete':
        return l10n.workspaceApprovalActionDelete;
      default:
        return action;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final actionLabel = _actionLabel(l10n);

    Color borderColor;
    Widget statusIcon;
    String statusText;
    switch (status) {
      case 'approved':
        borderColor = Colors.green.withValues(alpha: 0.5);
        statusIcon = const Icon(
          Icons.check_circle,
          size: 14,
          color: Colors.green,
        );
        statusText = l10n.workspaceApprovalAllow;
        break;
      case 'denied':
        borderColor = theme.colorScheme.error.withValues(alpha: 0.5);
        statusIcon = Icon(
          Icons.block,
          size: 14,
          color: theme.colorScheme.error,
        );
        statusText = l10n.workspaceApprovalDeny;
        break;
      case 'pending':
      default:
        borderColor = theme.colorScheme.outlineVariant;
        statusIcon = const SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
        statusText = '...';
        break;
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Icon(
            Icons.folder_outlined,
            size: 16,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${l10n.workspaceApprovalTitle} · $actionLabel "$targetPath" @ $workspaceName',
              style: theme.textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
          ),
          const SizedBox(width: 8),
          statusIcon,
          const SizedBox(width: 4),
          Text(statusText, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}
