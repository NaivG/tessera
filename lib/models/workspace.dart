import 'dart:async';

import 'package:uuid/uuid.dart';

// =============================================================================
// Workspace — 用户授权的本地目录
//
// Tessera 在 Settings → Workspaces 中维护若干 Workspace，
// LLM 通过 workspace_* 工具读取 / 写入其中的文件。
// =============================================================================

/// 工作空间 — 用户授权的本地目录。
class Workspace {
  /// UUID v4
  final String id;

  /// 用户给定的友好名
  final String name;

  /// 绝对路径（来自 file_picker.getDirectoryPath）
  final String rootPath;

  final DateTime createdAt;
  final DateTime updatedAt;

  const Workspace({
    required this.id,
    required this.name,
    required this.rootPath,
    required this.createdAt,
    required this.updatedAt,
  });

  Workspace copyWith({String? name, String? rootPath, DateTime? updatedAt}) {
    return Workspace(
      id: id,
      name: name ?? this.name,
      rootPath: rootPath ?? this.rootPath,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'root_path': rootPath,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
  };

  factory Workspace.fromJson(Map<String, dynamic> json) {
    return Workspace(
      id: json['id'] as String,
      name: json['name'] as String,
      rootPath: json['root_path'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  factory Workspace.create({required String name, required String rootPath}) {
    final now = DateTime.now();
    return Workspace(
      id: const Uuid().v4(),
      name: name,
      rootPath: rootPath,
      createdAt: now,
      updatedAt: now,
    );
  }
}

/// 持久化索引 — 顶层 JSON 结构。
class WorkspaceIndex {
  final List<Workspace> workspaces;
  final String? activeWorkspaceId;

  const WorkspaceIndex({this.workspaces = const [], this.activeWorkspaceId});

  Workspace? get active {
    if (activeWorkspaceId == null) return null;
    for (final w in workspaces) {
      if (w.id == activeWorkspaceId) return w;
    }
    return null;
  }

  Workspace? byId(String id) {
    for (final w in workspaces) {
      if (w.id == id) return w;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
    'version': 1,
    'active_workspace_id': activeWorkspaceId,
    'workspaces': workspaces.map((w) => w.toJson()).toList(),
  };

  factory WorkspaceIndex.fromJson(Map<String, dynamic> json) {
    final rawList = json['workspaces'] as List<dynamic>? ?? const [];
    return WorkspaceIndex(
      activeWorkspaceId: json['active_workspace_id'] as String?,
      workspaces: rawList
          .map((e) => Workspace.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  static const empty = WorkspaceIndex();
}

// =============================================================================
// WorkspaceEntry — listDirectory 返回的瞬态条目
// =============================================================================

enum WorkspaceEntryKind { file, directory }

/// 目录条目 — 每次列出时由 service 构造，不持久化。
class WorkspaceEntry {
  final String name;
  final String relativePath;
  final WorkspaceEntryKind kind;
  final int size;
  final DateTime modified;

  const WorkspaceEntry({
    required this.name,
    required this.relativePath,
    required this.kind,
    required this.size,
    required this.modified,
  });
}

// =============================================================================
// EditOperation — workspace_edit 工具使用的编辑指令
// =============================================================================

class EditOperation {
  final String find;
  final String replace;
  final bool replaceAll;

  const EditOperation({
    required this.find,
    required this.replace,
    this.replaceAll = false,
  });

  Map<String, dynamic> toJson() => {
    'find': find,
    'replace': replace,
    'replace_all': replaceAll,
  };

  factory EditOperation.fromJson(Map<String, dynamic> json) {
    return EditOperation(
      find: json['find'] as String? ?? '',
      replace: json['replace'] as String? ?? '',
      replaceAll: json['replace_all'] as bool? ?? false,
    );
  }
}

// =============================================================================
// WorkspaceApprovalRequest — UI 审批请求
//
// Completer 由 tool handler 持有；对话框 / 卡片在用户选择时 complete(bool)。
// =============================================================================

class WorkspaceApprovalRequest {
  final String toolName; // 'workspace_write' / 'workspace_edit' / ...
  final String actionLabel; // i18n key passed to l10n on UI side
  final String workspaceName;
  final String targetPath; // 相对路径
  final Map<String, dynamic> arguments;
  final Completer<bool> completer;

  WorkspaceApprovalRequest({
    required this.toolName,
    required this.actionLabel,
    required this.workspaceName,
    required this.targetPath,
    required this.arguments,
    required this.completer,
  });
}

// =============================================================================
// ReadResult — workspace_read 服务层返回的 (切片内容, 总行数) 配对
//
// 不持久化,不参与 JSON 序列化。handler 用 totalLines 构造
// "Showing lines X-Y of Z" 响应头。
// =============================================================================

class ReadResult {
  final String content;
  final int totalLines;
  const ReadResult({required this.content, required this.totalLines});
}
