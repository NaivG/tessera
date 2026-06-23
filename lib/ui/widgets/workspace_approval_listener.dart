import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/workspace.dart';
import '../../providers/providers.dart';
import 'workspace_confirmation_dialog.dart';

/// 工作空间审批监听器 —— 监听 [WorkspaceApprovalCoordinator] 流，
/// 在收到请求时弹出确认对话框。
///
/// 必须挂在 Navigator 上方（MaterialApp 层）。
class WorkspaceApprovalListener extends ConsumerStatefulWidget {
  final Widget child;
  const WorkspaceApprovalListener({super.key, required this.child});

  @override
  ConsumerState<WorkspaceApprovalListener> createState() =>
      _WorkspaceApprovalListenerState();
}

class _WorkspaceApprovalListenerState
    extends ConsumerState<WorkspaceApprovalListener> {
  StreamSubscription<WorkspaceApprovalRequest>? _sub;
  bool _dialogOpen = false;

  @override
  void initState() {
    super.initState();
    // 延迟到第一帧后再订阅，确保 navigator 就绪
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final coordinator = ref.read(workspaceApprovalCoordinatorProvider);
      _sub = coordinator.pending.listen(_onRequest);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _onRequest(WorkspaceApprovalRequest req) async {
    if (!mounted || _dialogOpen) {
      // 如果已有对话框打开或 widget 已卸载，视为拒绝
      if (!req.completer.isCompleted) {
        req.completer.complete(false);
      }
      return;
    }
    _dialogOpen = true;
    final navigator = Navigator.of(context, rootNavigator: true);
    final approved = await showWorkspaceConfirmationDialog(
      navigator.context,
      action: req.actionLabel,
      workspaceName: req.workspaceName,
      targetPath: req.targetPath,
    );
    _dialogOpen = false;
    if (!req.completer.isCompleted) {
      req.completer.complete(approved);
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
