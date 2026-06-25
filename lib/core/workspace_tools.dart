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
      'Paths are relative to the workspace root. '
      'By default, returns the first 100 lines; the response header '
      'shows the actual line range and total line count so you can '
      'request more with start_line / end_line. '
      'Also records the file mtime — workspace_write / workspace_edit / '
      'workspace_patch will refuse to run on a modified-since-read file '
      'until you re-read it.',
  tags: {'file', 'workspace'},
  capabilities: {'workspace.read'},
  parameters: {
    'path': {
      'type': 'string',
      'description': 'Relative file path within the active workspace.',
      'required': true,
    },
    'start_line': {
      'type': 'integer',
      'description':
          'First line to return (1-indexed, inclusive). Defaults to 1.',
      'required': false,
    },
    'end_line': {
      'type': 'integer',
      'description':
          'Last line to return (1-indexed, inclusive). Defaults to 100 '
          'when start_line is omitted, or equals start_line when only '
          'start_line is provided. Clamped to the file total line count.',
      'required': false,
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
      'Triggers a user confirmation dialog before execution. '
      'If start_line and end_line are both provided, replaces that line '
      'range and preserves the rest of the file. '
      'For an existing file, you must have called workspace_read on it '
      'earlier in this session; otherwise the write is rejected with a '
      'hint to re-read first.',
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
    'start_line': {
      'type': 'integer',
      'description':
          'First line of the range to replace (1-indexed, inclusive). '
          'If provided, end_line must also be provided.',
      'required': false,
    },
    'end_line': {
      'type': 'integer',
      'description':
          'Last line of the range to replace (1-indexed, inclusive). '
          'If provided, start_line must also be provided.',
      'required': false,
    },
  },
);

const workspaceEditTool = ToolDefinition(
  name: 'workspace_edit',
  description:
      'Apply exact-text edits to a file in the active workspace. '
      'Each edit has {find, replace, replace_all}. '
      'Triggers a user confirmation dialog before execution. '
      'You must have called workspace_read on the file earlier in this '
      'session; otherwise the edit is rejected with a hint to re-read first.',
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

const workspacePatchTool = ToolDefinition(
  name: 'workspace_patch',
  description:
      'Apply a single find/replace edit to an existing file. '
      'A shorthand for a one-element workspace_edit — use this for '
      'quick targeted replacements instead of wrapping a single op '
      'in an array. Triggers a user confirmation dialog before '
      'execution. You must have called workspace_read on the file '
      'earlier in this session; otherwise the patch is rejected with '
      'a hint to re-read first.',
  tags: {'file', 'workspace'},
  capabilities: {'workspace.write'},
  parameters: {
    'path': {
      'type': 'string',
      'description': 'Relative file path within the active workspace.',
      'required': true,
    },
    'find': {
      'type': 'string',
      'description':
          'The exact text to find. Must match exactly and uniquely '
          'unless replace_all is true.',
      'required': true,
    },
    'replace': {
      'type': 'string',
      'description': 'The replacement text.',
      'required': true,
    },
    'replace_all': {
      'type': 'boolean',
      'description':
          'When true, replace all occurrences of find. Defaults to false.',
      'required': false,
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
    workspacePatchTool,
    (call) => _handlePatch(call, confirmer),
  );
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

/// 完整性检查 —— 写入已存在的文件前调用。
///
/// 若文件存在但 (a) 本会话从未 read 过 或 (b) 自上次 read 以来 mtime 已变,
/// 返回 [ToolResult] 错误让 LLM 重读;否则返回 null,handler 继续。
///
/// 新建文件(fileExists == false)直接放行 —— 全新内容没有"陈旧"概念。
Future<ToolResult?> _checkReadFreshness(
  WorkspaceService service,
  String workspaceId,
  String path,
  String toolCallId,
) async {
  if (!await service.fileExists(workspaceId, path)) {
    return null; // 全新文件,跳过
  }
  final f = await service.readFreshness(workspaceId, path);
  if (f.neverRead) {
    return ToolResult(
      toolCallId: toolCallId,
      isError: true,
      content:
          'File "$path" has not been read in this session. '
          'Call workspace_read on "$path" first, then retry the write.',
    );
  }
  if (f.modified) {
    return ToolResult(
      toolCallId: toolCallId,
      isError: true,
      content:
          'File "$path" has been modified since it was last read by '
          'this session. Call workspace_read on "$path" first to '
          'refresh its tracked state, then retry the write.',
    );
  }
  return null;
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
    // 解析行范围 —— 默认读 1-100
    final startLine = call.arguments['start_line'] as int?;
    final endLineRaw = call.arguments['end_line'] as int?;
    final s = startLine ?? 1;
    final e = endLineRaw ?? (startLine ?? 100);
    if (s < 1) {
      return ToolResult(
        toolCallId: call.id,
        isError: true,
        content: 'start_line must be >= 1 (got $s).',
      );
    }
    if (e < s) {
      return ToolResult(
        toolCallId: call.id,
        isError: true,
        content: 'end_line ($e) must be >= start_line ($s).',
      );
    }

    final result = await ctx.service.readFile(
      ctx.active!.id,
      path,
      startLine: s,
      endLine: e,
    );

    if (result.totalLines == 0) {
      return ToolResult(
        toolCallId: call.id,
        content: '(empty file: $path, 0 lines)',
      );
    }

    // 计算实际返回的行范围(可能被文件实际长度 clamp)
    final returnedLineCount = result.content.isEmpty
        ? 0
        : result.content.split('\n').length;
    final actualEnd = (s + returnedLineCount - 1).clamp(1, result.totalLines);
    final header = 'Showing lines $s-$actualEnd of ${result.totalLines} '
        'in "$path":';
    return ToolResult(
      toolCallId: call.id,
      content: '$header\n${result.content}',
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

  // 解析行范围 —— 必须同时给或同时不给
  final startLine = call.arguments['start_line'] as int?;
  final endLine = call.arguments['end_line'] as int?;
  if ((startLine == null) != (endLine == null)) {
    return ToolResult(
      toolCallId: call.id,
      isError: true,
      content:
          'start_line and end_line must be provided together, or both omitted.',
    );
  }
  if (startLine != null && startLine < 1) {
    return ToolResult(
      toolCallId: call.id,
      isError: true,
      content: 'start_line must be >= 1 (got $startLine).',
    );
  }
  if (startLine != null && endLine! < startLine) {
    return ToolResult(
      toolCallId: call.id,
      isError: true,
      content: 'end_line ($endLine) must be >= start_line ($startLine).',
    );
  }

  // 完整性检查 —— 写入已存在的文件前要求本会话已 read
  final stale = await _checkReadFreshness(ctx.service, ctx.active!.id, path, call.id);
  if (stale != null) return stale;

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
    await ctx.service.writeFile(
      ctx.active!.id,
      path,
      content,
      startLine: startLine,
      endLine: endLine,
    );
    final msg = startLine == null
        ? 'Wrote ${content.length} characters to "$path".'
        : 'Replaced lines $startLine-$endLine of "$path" '
            '(${content.length} characters written).';
    return ToolResult(toolCallId: call.id, content: msg);
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

  // 完整性检查 —— 写入已存在的文件前要求本会话已 read
  final stale = await _checkReadFreshness(ctx.service, ctx.active!.id, path, call.id);
  if (stale != null) return stale;

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

Future<ToolResult> _handlePatch(
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
  final find = call.arguments['find'] as String? ?? '';
  final replace = call.arguments['replace'] as String? ?? '';
  final replaceAll = call.arguments['replace_all'] as bool? ?? false;
  if (path.isEmpty) {
    return ToolResult(
      toolCallId: call.id,
      isError: true,
      content: 'Missing required parameter "path".',
    );
  }
  if (find.isEmpty) {
    return ToolResult(
      toolCallId: call.id,
      isError: true,
      content: 'Missing required parameter "find".',
    );
  }

  // workspace_patch 必须打到已存在的文件
  if (!await ctx.service.fileExists(ctx.active!.id, path)) {
    return ToolResult(
      toolCallId: call.id,
      isError: true,
      content:
          'File not found: $path. workspace_patch requires an existing file; '
          'use workspace_write to create a new file.',
    );
  }

  // 完整性检查
  final stale =
      await _checkReadFreshness(ctx.service, ctx.active!.id, path, call.id);
  if (stale != null) return stale;

  // 询问用户
  final approved = await confirmer(
    WorkspaceApprovalRequest(
      toolName: call.name,
      actionLabel: 'patch',
      workspaceName: ctx.active!.name,
      targetPath: path,
      arguments: call.arguments,
      completer: Completer<bool>(),
    ),
  );
  if (!approved) {
    return ToolResult(
      toolCallId: call.id,
      content: 'User denied the patch of "$path".',
    );
  }

  try {
    final result = await ctx.service.applyPatch(
      ctx.active!.id,
      path,
      find: find,
      replace: replace,
      replaceAll: replaceAll,
    );
    return ToolResult(
      toolCallId: call.id,
      content: 'Applied patch to "$path" (${result.length} chars now).',
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
