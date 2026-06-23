import 'package:flutter/material.dart';
import 'package:tessera/l10n/app_localizations.dart';

/// 工作空间文件操作确认对话框。
///
/// 返回 `true` 表示允许，`false` 表示拒绝，`null` 表示用户取消（视为拒绝）。
class WorkspaceConfirmationDialog extends StatelessWidget {
  final String action; // 'write' / 'edit' / 'mkdir' / 'delete'
  final String workspaceName;
  final String targetPath;

  const WorkspaceConfirmationDialog({
    super.key,
    required this.action,
    required this.workspaceName,
    required this.targetPath,
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

  IconData _actionIcon() {
    switch (action) {
      case 'write':
        return Icons.edit_note;
      case 'edit':
        return Icons.find_replace;
      case 'mkdir':
        return Icons.create_new_folder_outlined;
      case 'delete':
        return Icons.delete_outline;
      default:
        return Icons.help_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final actionLabel = _actionLabel(l10n);

    return AlertDialog(
      title: Row(
        children: [
          Icon(_actionIcon(), color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(l10n.workspaceApprovalTitle)),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.workspaceApprovalMessage(
              actionLabel,
              targetPath,
              workspaceName,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.folder_outlined, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    targetPath,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.workspaceApprovalDeny),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.workspaceApprovalAllow),
        ),
      ],
    );
  }
}

/// 显示确认对话框并返回 bool 结果。null 表示用户取消。
Future<bool> showWorkspaceConfirmationDialog(
  BuildContext context, {
  required String action,
  required String workspaceName,
  required String targetPath,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => WorkspaceConfirmationDialog(
      action: action,
      workspaceName: workspaceName,
      targetPath: targetPath,
    ),
  );
  return result ?? false;
}
