import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/workspace.dart';
import '../services/workspace_service.dart';
import 'workspace_service_provider.dart';

// =============================================================================
// WorkspaceData — 不可变状态
// =============================================================================

class WorkspaceData {
  final List<Workspace> workspaces;
  final String? activeWorkspaceId;
  final bool initialized;

  const WorkspaceData({
    this.workspaces = const [],
    this.activeWorkspaceId,
    this.initialized = false,
  });

  Workspace? get active {
    if (activeWorkspaceId == null) return null;
    for (final w in workspaces) {
      if (w.id == activeWorkspaceId) return w;
    }
    return null;
  }

  WorkspaceData copyWith({
    List<Workspace>? workspaces,
    String? activeWorkspaceId,
    bool? initialized,
    bool clearActive = false,
  }) {
    return WorkspaceData(
      workspaces: workspaces ?? this.workspaces,
      activeWorkspaceId: clearActive
          ? null
          : (activeWorkspaceId ?? this.activeWorkspaceId),
      initialized: initialized ?? this.initialized,
    );
  }
}

// =============================================================================
// WorkspaceNotifier
// =============================================================================

class WorkspaceNotifier extends Notifier<WorkspaceData> {
  WorkspaceService get _service => ref.read(workspaceServiceProvider);

  /// 初始状态直接从 service 同步读取 —— service 在 main.dart 中 runApp 之前
  /// 已经初始化完成。这里不能走 "load() + state=" 的模式，因为 initState
  /// / build 期间修改 provider 会被 Riverpod 拒绝（state = 的通知微任务会在
  /// widget 树构建中触发 _debugAssertNotificationAllowed）。
  @override
  WorkspaceData build() {
    return WorkspaceData(
      workspaces: _service.workspaces,
      activeWorkspaceId: _service.active?.id,
      initialized: true,
    );
  }

  /// 显式刷新 —— 当外部修改了 service 的状态（例如从磁盘重新加载）时调用。
  /// 推迟到下一微任务，避免在 widget 生命周期内直接修改 state。
  Future<void> load() async {
    scheduleMicrotask(() {
      state = WorkspaceData(
        workspaces: _service.workspaces,
        activeWorkspaceId: _service.active?.id,
        initialized: true,
      );
    });
  }

  Future<void> addWorkspace({
    required String name,
    required String path,
  }) async {
    final ws = await _service.addWorkspace(name: name, path: path);
    state = state.copyWith(
      workspaces: _service.workspaces,
      activeWorkspaceId: state.activeWorkspaceId ?? ws.id,
    );
  }

  Future<void> removeWorkspace(String id) async {
    await _service.removeWorkspace(id);
    state = state.copyWith(
      workspaces: _service.workspaces,
      activeWorkspaceId: state.activeWorkspaceId == id
          ? null
          : state.activeWorkspaceId,
      clearActive: state.activeWorkspaceId == id,
    );
  }

  Future<void> renameWorkspace(String id, String name) async {
    await _service.renameWorkspace(id, name);
    state = state.copyWith(workspaces: _service.workspaces);
  }

  Future<void> setActive(String? id) async {
    await _service.setActive(id);
    state = state.copyWith(
      workspaces: _service.workspaces,
      activeWorkspaceId: id,
      clearActive: id == null,
    );
  }

  /// 文件操作 — 直接委托给 service，UI 通过 provider rebuild 反映变化。
  Future<List<WorkspaceEntry>> listDirectory(
    String workspaceId,
    String relativePath,
  ) => _service.listDirectory(workspaceId, relativePath);

  Future<String> readFile(String workspaceId, String relativePath) =>
      _service.readFile(workspaceId, relativePath);

  Future<void> writeFile(
    String workspaceId,
    String relativePath,
    String content,
  ) => _service.writeFile(workspaceId, relativePath, content);

  Future<void> mkdir(
    String workspaceId,
    String relativePath, {
    bool recursive = true,
  }) => _service.mkdir(workspaceId, relativePath, recursive: recursive);

  Future<void> deleteFile(
    String workspaceId,
    String relativePath, {
    bool recursive = false,
  }) => _service.deleteFile(workspaceId, relativePath, recursive: recursive);

  Future<List<WorkspaceEntry>> search(
    String workspaceId,
    String query, {
    String? relativePath,
    bool contentOnly = false,
  }) => _service.search(
    workspaceId,
    query,
    relativePath: relativePath,
    contentOnly: contentOnly,
  );

  Future<({int length, int appliedEdits})> editFile(
    String workspaceId,
    String relativePath,
    List<EditOperation> edits,
  ) => _service.editFile(workspaceId, relativePath, edits);
}

final workspaceProvider = NotifierProvider<WorkspaceNotifier, WorkspaceData>(
  WorkspaceNotifier.new,
);

// =============================================================================
// WorkspaceApprovalCoordinator — 工作空间审批协调器
//
// Tool handler 调用 [request]，传入 [WorkspaceApprovalRequest]。
// UI 监听 [pending] 流，弹出对话框并最终 complete(completer, bool)。
// =============================================================================

class WorkspaceApprovalCoordinator {
  final StreamController<WorkspaceApprovalRequest> _pending =
      StreamController<WorkspaceApprovalRequest>.broadcast();

  Stream<WorkspaceApprovalRequest> get pending => _pending.stream;

  /// 提交请求并等待用户响应。Completer 由调用方持有（写入 WorkspaceApprovalRequest）。
  Future<bool> request(WorkspaceApprovalRequest req) {
    _pending.add(req);
    return req.completer.future;
  }

  void dispose() {
    _pending.close();
  }
}

final workspaceApprovalCoordinatorProvider =
    Provider<WorkspaceApprovalCoordinator>((ref) {
      final coordinator = WorkspaceApprovalCoordinator();
      ref.onDispose(coordinator.dispose);
      return coordinator;
    });
