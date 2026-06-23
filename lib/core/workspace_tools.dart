import 'dart:async';
import 'dart:convert';

import '../models/message.dart';
import '../models/tool.dart';
import '../models/workspace.dart';
import '../services/workspace_service.dart';
import '../utils/path_traversal.dart';
import 'tool_registry.dart';

// =============================================================================
// workspace_* 工具定义 — ToolRegistry 注册
//
// 工具按 capability 分类：
//   workspace.read      → workspace_list, workspace_read
//   workspace.search    → workspace_search
//   workspace.write     → workspace_write, workspace_edit, workspace_mkdir
//   workspace.delete    → workspace_delete
//
// 任何写操作（write/edit/mkdir/delete）都会先通过 WorkspaceApprovalCoordinator
// 请求用户确认。
// =============================================================================

// -----------------------------------------------------------------------------
// Tool definitions
// -----------------------------------------------------------------------------

const workspaceListTool = ToolDefinition(
  name: 'workspace_list',
  description:
      'List files and directories in a workspace. Paths are relative to the '
      'workspace root. Use "" or "/" for the root.',
  tags: {'file', 'workspace'},
  capabilities: {'workspace.list', 'workspace.read'},
  parameters: {
    'path': {
      'type': 'string',
      'description':
          'Relative directory path within the workspace. Empty or "/" for root.',
      'required': false,
    },
  },
);

const workspaceReadTool = ToolDefinition(
  name: 'workspace_read',
  description:
      'Read the text contents of a file in the active workspace. '
      'Paths are relative to the workspace root.',
  tags: {'file', 'workspace'},
  capabilities: {'workspace.read'},
  parameters: {
    'path': {
      'type': 'string',
      'description': 'Relative file path within the active workspace.',
      'required': true,
    },
  },
);

const workspaceSearchTool = ToolDefinition(
  name: 'workspace_search',
  description:
      'Recursively search for filenames or text contents in a workspace. '
      'Returns up to 200 matching entries.',
  tags: {'file', 'workspace'},
  capabilities: {'workspace.search'},
  parameters: {
    'query': {
      'type': 'string',
      'description': 'Search query (case-insensitive substring match).',
      'required': true,
    },
    'path': {
      'type': 'string',
      'description': 'Limit search to this subdirectory (relative to root).',
      'required': false,
    },
    'content_only': {
      'type': 'boolean',
      'description':
          'When true, only search file contents (skip filename matching).',
      'required': false,
    },
  },
);

const workspaceWriteTool = ToolDefinition(
  name: 'workspace_write',
  description:
      'Write text content to a file in the active workspace. '
      'Creates parent directories as needed. '
      'Triggers a user confirmation dialog before execution.',
  tags: {'file', 'workspace'},
  capabilities: {'workspace.write'},
  parameters: {
    'path': {
      'type': 'string',
      'description': 'Relative file path within the active workspace.',
      'required': true,
    },
    'content': {
      'type': 'string',
      'description': 'The text content to write.',
      'required': true,
    },
  },
);

const workspaceEditTool = ToolDefinition(
  name: 'workspace_edit',
  description:
      'Apply exact-text edits to a file in the active workspace. '
      'Each edit has {find, replace, replace_all}. '
      'Triggers a user confirmation dialog before execution.',
  tags: {'file', 'workspace'},
  capabilities: {'workspace.write'},
  parameters: {
    'path': {
      'type': 'string',
      'description': 'Relative file path within the active workspace.',
      'required': true,
    },
    'edits': {
      'type': 'array',
      'description': 'Array of {find, replace, replace_all} edit operations.',
      'required': true,
    },
  },
);

const workspaceMkdirTool = ToolDefinition(
  name: 'workspace_mkdir',
  description:
      'Create a directory in the active workspace. '
      'Triggers a user confirmation dialog before execution.',
  tags: {'file', 'workspace'},
  capabilities: {'workspace.write'},
  parameters: {
    'path': {
      'type': 'string',
      'description': 'Relative directory path within the active workspace.',
      'required': true,
    },
    'recursive': {
      'type': 'boolean',
      'description':
          'When true (default), create parent directories as needed.',
      'required': false,
    },
  },
);

const workspaceDeleteTool = ToolDefinition(
  name: 'workspace_delete',
  description:
      'Delete a file or directory in the active workspace. '
      'Triggers a user confirmation dialog before execution.',
  tags: {'file', 'workspace'},
  capabilities: {'workspace.delete'},
  parameters: {
    'path': {
      'type': 'string',
      'description': 'Relative path within the active workspace.',
      'required': true,
    },
    'recursive': {
      'type': 'boolean',
      'description': 'When true, allow recursive directory deletion.',
      'required': false,
    },
  },
);

// -----------------------------------------------------------------------------
// Handler signatures
// -----------------------------------------------------------------------------

typedef WorkspaceConfirmer =
    Future<bool> Function(WorkspaceApprovalRequest request);

/// 在 ToolRegistry 上注册所有 workspace_* 工具。
///
/// [confirmer] 是闭包，捕获 ChatNotifier 中的审批逻辑（通过
/// WorkspaceApprovalCoordinator.request() 返回 bool）。
void registerWorkspaceTools(
  ToolRegistry registry, {
  required WorkspaceConfirmer confirmer,
}) {
  registry.register(workspaceListTool, (call) => _handleList(call, confirmer));
  registry.register(workspaceReadTool, (call) => _handleRead(call, confirmer));
  registry.register(
    workspaceSearchTool,
    (call) => _handleSearch(call, confirmer),
  );
  registry.register(
    workspaceWriteTool,
    (call) => _handleWrite(call, confirmer),
  );
  registry.register(workspaceEditTool, (call) => _handleEdit(call, confirmer));
  registry.register(
    workspaceMkdirTool,
    (call) => _handleMkdir(call, confirmer),
  );
  registry.register(
    workspaceDeleteTool,
    (call) => _handleDelete(call, confirmer),
  );
}

// -----------------------------------------------------------------------------
// Helpers
// -----------------------------------------------------------------------------

/// 获取激活的工作空间 —— 若没有则返回错误结果。
({WorkspaceService service, Workspace? active, ToolResult? error})
_resolveActive() {
  final service = WorkspaceService.instance;
  if (!service.isInitialized) {
    return (
      service: service,
      active: null,
      error: ToolResult(
        toolCallId: '',
        isError: true,
        content: 'WorkspaceService is not initialized.',
      ),
    );
  }
  final active = service.active;
  if (active == null) {
    return (
      service: service,
      active: null,
      error: ToolResult(
        toolCallId: '',
        isError: true,
        content:
            'No active workspace. Ask the user to add a workspace in Settings → Workspaces.',
      ),
    );
  }
  return (service: service, active: active, error: null);
}

String _err(Object e) {
  if (e is PathTraversalException) {
    return e.toString();
  }
  if (e is WorkspaceFileException) {
    return e.toString();
  }
  if (e is WorkspaceNotFoundException) {
    return e.toString();
  }
  return e.toString();
}

// -----------------------------------------------------------------------------
// Handlers — read tools
// -----------------------------------------------------------------------------

Future<ToolResult> _handleList(
  ToolCall call,
  WorkspaceConfirmer confirmer,
) async {
  final ctx = _resolveActive();
  if (ctx.error != null) {
    return ToolResult(
      toolCallId: call.id,
      isError: true,
      content: ctx.error!.content,
    );
  }
  try {
    final path = (call.arguments['path'] as String?)?.trim() ?? '';
    final entries = await ctx.service.listDirectory(ctx.active!.id, path);
    if (entries.isEmpty) {
      return ToolResult(
        toolCallId: call.id,
        content: '(empty directory: ${path.isEmpty ? '/' : path})',
      );
    }
    final lines = entries
        .map((e) {
          final suffix = e.kind == WorkspaceEntryKind.directory ? '/' : '';
          return '- ${e.relativePath}$suffix  (${e.size} bytes)';
        })
        .join('\n');
    return ToolResult(
      toolCallId: call.id,
      content:
          'Workspace "${ctx.active!.name}" — ${entries.length} entries:\n$lines',
    );
  } catch (e) {
    return ToolResult(toolCallId: call.id, isError: true, content: _err(e));
  }
}

Future<ToolResult> _handleRead(
  ToolCall call,
  WorkspaceConfirmer confirmer,
) async {
  final ctx = _resolveActive();
  if (ctx.error != null) {
    return ToolResult(
      toolCallId: call.id,
      isError: true,
      content: ctx.error!.content,
    );
  }
  try {
    final path = call.arguments['path'] as String? ?? '';
    if (path.isEmpty) {
      return ToolResult(
        toolCallId: call.id,
        isError: true,
        content: 'Missing required parameter "path".',
      );
    }
    final content = await ctx.service.readFile(ctx.active!.id, path);
    return ToolResult(
      toolCallId: call.id,
      content: content.isEmpty ? '(empty file)' : content,
    );
  } catch (e) {
    return ToolResult(toolCallId: call.id, isError: true, content: _err(e));
  }
}

Future<ToolResult> _handleSearch(
  ToolCall call,
  WorkspaceConfirmer confirmer,
) async {
  final ctx = _resolveActive();
  if (ctx.error != null) {
    return ToolResult(
      toolCallId: call.id,
      isError: true,
      content: ctx.error!.content,
    );
  }
  try {
    final query = call.arguments['query'] as String? ?? '';
    if (query.isEmpty) {
      return ToolResult(
        toolCallId: call.id,
        isError: true,
        content: 'Missing required parameter "query".',
      );
    }
    final path = call.arguments['path'] as String?;
    final contentOnly = call.arguments['content_only'] as bool? ?? false;
    final entries = await ctx.service.search(
      ctx.active!.id,
      query,
      relativePath: path,
      contentOnly: contentOnly,
    );
    if (entries.isEmpty) {
      return ToolResult(
        toolCallId: call.id,
        content: 'No matches for "$query".',
      );
    }
    final lines = entries
        .map((e) {
          final suffix = e.kind == WorkspaceEntryKind.directory ? '/' : '';
          return '- ${e.relativePath}$suffix';
        })
        .join('\n');
    return ToolResult(
      toolCallId: call.id,
      content: '${entries.length} matches for "$query":\n$lines',
    );
  } catch (e) {
    return ToolResult(toolCallId: call.id, isError: true, content: _err(e));
  }
}

// -----------------------------------------------------------------------------
// Handlers — write tools (require confirmation)
// -----------------------------------------------------------------------------

Future<ToolResult> _handleWrite(
  ToolCall call,
  WorkspaceConfirmer confirmer,
) async {
  final ctx = _resolveActive();
  if (ctx.error != null) {
    return ToolResult(
      toolCallId: call.id,
      isError: true,
      content: ctx.error!.content,
    );
  }
  final path = call.arguments['path'] as String? ?? '';
  final content = call.arguments['content'] as String? ?? '';
  if (path.isEmpty) {
    return ToolResult(
      toolCallId: call.id,
      isError: true,
      content: 'Missing required parameter "path".',
    );
  }

  // 询问用户
  final approved = await confirmer(
    WorkspaceApprovalRequest(
      toolName: call.name,
      actionLabel: 'write',
      workspaceName: ctx.active!.name,
      targetPath: path,
      arguments: call.arguments,
      completer: Completer<bool>(),
    ),
  );
  if (!approved) {
    return ToolResult(
      toolCallId: call.id,
      content: 'User denied the write to "$path".',
    );
  }

  try {
    await ctx.service.writeFile(ctx.active!.id, path, content);
    return ToolResult(
      toolCallId: call.id,
      content: 'Wrote ${content.length} characters to "$path".',
    );
  } catch (e) {
    return ToolResult(toolCallId: call.id, isError: true, content: _err(e));
  }
}

Future<ToolResult> _handleEdit(
  ToolCall call,
  WorkspaceConfirmer confirmer,
) async {
  final ctx = _resolveActive();
  if (ctx.error != null) {
    return ToolResult(
      toolCallId: call.id,
      isError: true,
      content: ctx.error!.content,
    );
  }
  final path = call.arguments['path'] as String? ?? '';
  final rawEdits = call.arguments['edits'];
  if (path.isEmpty) {
    return ToolResult(
      toolCallId: call.id,
      isError: true,
      content: 'Missing required parameter "path".',
    );
  }
  if (rawEdits is! List) {
    return ToolResult(
      toolCallId: call.id,
      isError: true,
      content: 'Parameter "edits" must be an array.',
    );
  }
  final edits = <EditOperation>[];
  try {
    for (final raw in rawEdits) {
      if (raw is Map) {
        edits.add(EditOperation.fromJson(Map<String, dynamic>.from(raw)));
      } else {
        edits.add(
          EditOperation.fromJson(
            jsonDecode(jsonEncode(raw)) as Map<String, dynamic>,
          ),
        );
      }
    }
  } catch (e) {
    return ToolResult(
      toolCallId: call.id,
      isError: true,
      content: 'Failed to parse edits: $e',
    );
  }

  // 询问用户
  final approved = await confirmer(
    WorkspaceApprovalRequest(
      toolName: call.name,
      actionLabel: 'edit',
      workspaceName: ctx.active!.name,
      targetPath: path,
      arguments: call.arguments,
      completer: Completer<bool>(),
    ),
  );
  if (!approved) {
    return ToolResult(
      toolCallId: call.id,
      content: 'User denied the edit of "$path".',
    );
  }

  try {
    final result = await ctx.service.editFile(ctx.active!.id, path, edits);
    return ToolResult(
      toolCallId: call.id,
      content:
          'Applied ${result.appliedEdits} edit(s) to "$path" (${result.length} chars now).',
    );
  } catch (e) {
    return ToolResult(toolCallId: call.id, isError: true, content: _err(e));
  }
}

Future<ToolResult> _handleMkdir(
  ToolCall call,
  WorkspaceConfirmer confirmer,
) async {
  final ctx = _resolveActive();
  if (ctx.error != null) {
    return ToolResult(
      toolCallId: call.id,
      isError: true,
      content: ctx.error!.content,
    );
  }
  final path = call.arguments['path'] as String? ?? '';
  final recursive = call.arguments['recursive'] as bool? ?? true;
  if (path.isEmpty) {
    return ToolResult(
      toolCallId: call.id,
      isError: true,
      content: 'Missing required parameter "path".',
    );
  }

  final approved = await confirmer(
    WorkspaceApprovalRequest(
      toolName: call.name,
      actionLabel: 'mkdir',
      workspaceName: ctx.active!.name,
      targetPath: path,
      arguments: call.arguments,
      completer: Completer<bool>(),
    ),
  );
  if (!approved) {
    return ToolResult(
      toolCallId: call.id,
      content: 'User denied the creation of "$path".',
    );
  }

  try {
    await ctx.service.mkdir(ctx.active!.id, path, recursive: recursive);
    return ToolResult(
      toolCallId: call.id,
      content: 'Created directory "$path".',
    );
  } catch (e) {
    return ToolResult(toolCallId: call.id, isError: true, content: _err(e));
  }
}

Future<ToolResult> _handleDelete(
  ToolCall call,
  WorkspaceConfirmer confirmer,
) async {
  final ctx = _resolveActive();
  if (ctx.error != null) {
    return ToolResult(
      toolCallId: call.id,
      isError: true,
      content: ctx.error!.content,
    );
  }
  final path = call.arguments['path'] as String? ?? '';
  final recursive = call.arguments['recursive'] as bool? ?? false;
  if (path.isEmpty) {
    return ToolResult(
      toolCallId: call.id,
      isError: true,
      content: 'Missing required parameter "path".',
    );
  }

  final approved = await confirmer(
    WorkspaceApprovalRequest(
      toolName: call.name,
      actionLabel: 'delete',
      workspaceName: ctx.active!.name,
      targetPath: path,
      arguments: call.arguments,
      completer: Completer<bool>(),
    ),
  );
  if (!approved) {
    return ToolResult(
      toolCallId: call.id,
      content: 'User denied the deletion of "$path".',
    );
  }

  try {
    await ctx.service.deleteFile(ctx.active!.id, path, recursive: recursive);
    return ToolResult(toolCallId: call.id, content: 'Deleted "$path".');
  } catch (e) {
    return ToolResult(toolCallId: call.id, isError: true, content: _err(e));
  }
}
