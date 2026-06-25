# Workspace Tools

Tessera's sandboxed local file tools — the LLM's controlled window into the
user's filesystem.

## Overview

A **Workspace** is a user-authorized local directory. The user adds one or more
workspaces in **Settings → Workspaces** (via `file_picker.getDirectoryPath`),
picks one as active, and the LLM can then read and edit files inside it
through eight `workspace_*` tools.

The design has three guardrails:

1. **Path sandbox** — every relative path the LLM passes is resolved against
   the workspace root with [`path_traversal.dart`](../../lib/utils/path_traversal.dart).
   `..` segments, absolute paths, and symlinks that escape the root are
   rejected with `PathTraversalException`. The LLM physically cannot reach
   outside the workspace.
2. **Stale-read enforcement** — `workspace_write` / `workspace_edit` /
   `workspace_patch` refuse to run on a file whose mtime changed since the
   LLM last called `workspace_read`. The model is forced to re-read the file
   before mutating it, eliminating the "write to stale content" footgun.
3. **User-approval gate** — every write tool blocks on a confirmation
   dialog (`WorkspaceApprovalCoordinator`). The dialog shows the tool name,
   the workspace name, the target path, and the full argument map. The
   user can approve once, deny, or (for `workspace_write`) cancel the entire
   run.

| Concern | Source |
|---|---|
| Tool definitions + handlers | [`lib/core/workspace_tools.dart`](../../lib/core/workspace_tools.dart) |
| Filesystem service (CRUD, mtime, search) | [`lib/services/workspace_service.dart`](../../lib/services/workspace_service.dart) |
| Approval flow (coordinator + dialog) | [`lib/ui/widgets/workspace_approval_card.dart`](../../lib/ui/widgets/workspace_approval_card.dart), [`workspace_approval_listener.dart`](../../lib/ui/widgets/workspace_approval_listener.dart), [`workspace_confirmation_dialog.dart`](../../lib/ui/widgets/workspace_confirmation_dialog.dart) |
| Path sandbox | [`lib/utils/path_traversal.dart`](../../lib/utils/path_traversal.dart) |
| Data model | [`lib/models/workspace.dart`](../../lib/models/workspace.dart) |
| State (Riverpod) | [`lib/providers/workspace_provider.dart`](../../lib/providers/workspace_provider.dart) |
| Workspace page | [`lib/ui/pages/workspace_page.dart`](../../lib/ui/pages/workspace_page.dart) |

## Tool catalog

| Tool | Capability | Approval | Description |
|---|---|---|---|
| `workspace_list` | `workspace.list` | no | List files / dirs under a path |
| `workspace_read` | `workspace.read` | no | Read text content with line-range support |
| `workspace_search` | `workspace.search` | no | Recursive name / content search |
| `workspace_write` | `workspace.write` | yes | Write a file (or replace a line range) |
| `workspace_edit` | `workspace.write` | yes | Apply `{find, replace, replace_all}` edits |
| `workspace_patch` | `workspace.write` | yes | Single-element shorthand for `workspace_edit` |
| `workspace_mkdir` | `workspace.write` | yes | Create a directory |
| `workspace_delete` | `workspace.delete` | yes | Delete a file or directory |

All eight are registered into the global `ToolRegistry` by
`registerWorkspaceTools(registry, confirmer: ...)` from
`workspace_tools.dart`. The `confirmer` is a closure that captures
`ChatNotifier`'s approval flow; it returns `true` to allow, `false` to
reject.

## Line-range reads (`workspace_read`)

`workspace_read` accepts `start_line` and `end_line` (both 1-indexed,
inclusive). Defaults:

- `start_line` omitted → 1
- `end_line` omitted with no `start_line` → 100
- `end_line` omitted with only `start_line` → equals `start_line`
- `end_line` provided → clamped to the file's actual total line count

The response header always reports the served range and the total line count,
so the model knows what to ask for next:

```text
Showing lines 1-100 of 432.
<content>
```

`workspace_write` reuses the same convention: if both `start_line` and
`end_line` are provided, the call replaces that range and preserves the rest
of the file. The model can produce a focused diff without rewriting the whole
file.

## Stale-read enforcement

`WorkspaceService` records the mtime of the file at the moment the LLM calls
`workspace_read`, keyed by `"<workspaceId>:<relativePath>"`. When the LLM
subsequently issues a write / edit / patch, the service compares the recorded
mtime to the file's current mtime:

- **Match** → proceed (the file is exactly what the LLM last saw).
- **Mismatch** → reject with a hint:
  `File "foo.txt" was modified since last read. Re-read it before writing.`
- **No record** → reject with a hint:
  `You must call workspace_read on "foo.txt" before writing.`

This is session-scoped and in-memory; it resets on app restart. It is **not**
a version-control system — just a guard against the common LLM mistake of
writing over content the user (or another tool) has changed in the meantime.

## Approval flow

`WorkspaceApprovalRequest` (defined in [`lib/models/workspace.dart`](../../lib/models/workspace.dart))
is the unit of work the coordinator passes to the UI. It carries:

- `toolName` — which `workspace_*` tool was called
- `actionLabel` — i18n key for the human-readable verb
- `workspaceName` — the active workspace's display name
- `targetPath` — the relative path the LLM is touching
- `arguments` — the full argument map (so the dialog can show e.g. the
  search/replace pairs, the line range, etc.)
- `completer` — the `Completer<bool>` the tool handler awaits on

The coordinator sits in `ChatNotifier`. When a tool handler calls
`confirmer(request)`, the coordinator broadcasts a
`WorkspaceApprovalRequest` over a stream; the UI listener (`workspace_approval_listener.dart`)
picks it up, shows the `WorkspaceConfirmationDialog`, and `complete()`s the
completer with the user's choice. The handler then proceeds or returns a
denied `ToolResult`.

The denied case returns a structured error so the model can adjust:

```text
Tool "workspace_write" was denied by the user. Reason: user pressed Cancel.
```

## Path sandbox

`resolveSafePath({workspaceRootPath, relativePath})` in
[`path_traversal.dart`](../../lib/utils/path_traversal.dart) is the choke point.
It:

1. Resolves the root's real path (`resolveSymbolicLinksSync`).
2. Trims the user's `relativePath`, strips a leading absolute-path prefix if
   present, and joins it to the root.
3. Resolves the joined path's real path (falling back to the parent's real
   path if the file doesn't exist yet, so new files work).
4. Verifies the final path is `==` the root or `startsWith(root + sep)`.

If any step fails, the function throws `PathTraversalException`. Every
read/write/edit/delete handler calls it before touching the filesystem.

## Platform support

`workspace_tools.dart` short-circuits on web and iOS — both have either no
`dart:io` or restricted filesystem access. The first call to any
`workspace_*` tool on those platforms returns a `ToolResult` with
`isError: true`:

```text
Workspace tools are not supported on this platform (Web).
```

Settings → Workspaces also hides the "add workspace" UI on web and iOS; the
underlying `WorkspaceService.init` is a no-op on web. Android, macOS, Windows,
and Linux are all fully supported (with the appropriate storage permission
flow on Android — see `lib/services/workspace_service.dart`).

## Lifecycle

Workspaces are persisted in `<appDocs>/workspaces/index.json` as a
`WorkspaceIndex`:

```json
{
  "version": 1,
  "active_workspace_id": "uuid",
  "workspaces": [
    { "id": "uuid", "name": "My Project", "root_path": "C:\\…", "created_at": "…", "updated_at": "…" }
  ]
}
```

`WorkspaceService` exposes the standard `workspaces / active / byId / setActive`
surface. `WorkspaceProvider` wraps it for the Riverpod tree. The
`WorkspacePage` lists all workspaces, lets the user add a new one via
`file_picker`, switch the active workspace, rename, or delete (delete
does not touch the underlying directory — it only removes the registration).

## See also

- [Discover System](discover-system.md) — the `workspace_*` tools are discoverable by capability (`workspace.read`, `workspace.write`, etc.) and exposed via the `discover` tool
- [Plugin System](plugin-system.md) — workspace tools share the same `ToolDefinition` / `ToolCall` / `ToolResult` envelope as plugin tools
- [LLM Provider Abstraction](llm-providers.md) — `ToolDefinition.toXxxSchema()` converts the parameter map to the LLM's native function-call format
