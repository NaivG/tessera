# 工作空间工具

Tessera 沙箱化的本地文件工具 —— LLM 访问用户文件系统的受控入口。

## 概述

**Workspace** 是用户授权的本地目录。用户在 **设置 → 工作空间** 中通过 `file_picker.getDirectoryPath` 添加一个或多个工作空间，并选一个激活；LLM 之后就可以通过 8 个 `workspace_*` 工具在内部读写文件。

设计上有三道护栏：

1. **路径沙箱** —— LLM 传入的每个相对路径都通过 [`path_traversal.dart`](../../lib/utils/path_traversal.dart) 针对工作空间根进行解析。`..`、绝对路径、以及会逃出根的符号链接都会被 `PathTraversalException` 拒绝，模型在物理上无法离开工作空间。
2. **Stale-read 强制** —— `workspace_write` / `workspace_edit` / `workspace_patch` 在文件 mtime 与 LLM 上次 `workspace_read` 记录不一致时会拒绝运行，模型必须重新读取后再写，避免「写到陈旧内容」这一经典翻车。
3. **用户审批门** —— 每次写操作都会在 `WorkspaceApprovalCoordinator` 处阻塞等待确认。对话框会展示工具名、工作空间名、目标路径以及完整参数映射，用户可以「同意一次」、「拒绝」，或在 `workspace_write` 时取消整次运行。

| 关注点 | 位置 |
|---|---|
| 工具定义 + handler | [`lib/core/workspace_tools.dart`](../../lib/core/workspace_tools.dart) |
| 文件系统服务（CRUD、mtime、搜索） | [`lib/services/workspace_service.dart`](../../lib/services/workspace_service.dart) |
| 审批流程（coordinator + 对话框） | [`lib/ui/widgets/workspace_approval_card.dart`](../../lib/ui/widgets/workspace_approval_card.dart)、[`workspace_approval_listener.dart`](../../lib/ui/widgets/workspace_approval_listener.dart)、[`workspace_confirmation_dialog.dart`](../../lib/ui/widgets/workspace_confirmation_dialog.dart) |
| 路径沙箱 | [`lib/utils/path_traversal.dart`](../../lib/utils/path_traversal.dart) |
| 数据模型 | [`lib/models/workspace.dart`](../../lib/models/workspace.dart) |
| 状态（Riverpod） | [`lib/providers/workspace_provider.dart`](../../lib/providers/workspace_provider.dart) |
| 工作空间页面 | [`lib/ui/pages/workspace_page.dart`](../../lib/ui/pages/workspace_page.dart) |

## 工具目录

| 工具 | Capability | 需审批 | 描述 |
|---|---|---|---|
| `workspace_list` | `workspace.list` | 否 | 列出某路径下的文件 / 目录 |
| `workspace_read` | `workspace.read` | 否 | 按行范围读取文本内容 |
| `workspace_search` | `workspace.search` | 否 | 递归搜索文件名 / 文件内容 |
| `workspace_write` | `workspace.write` | 是 | 写入文件（或替换一个行范围） |
| `workspace_edit` | `workspace.write` | 是 | 应用 `{find, replace, replace_all}` 编辑 |
| `workspace_patch` | `workspace.write` | 是 | 单元素版本的 `workspace_edit` 简写 |
| `workspace_mkdir` | `workspace.write` | 是 | 创建目录 |
| `workspace_delete` | `workspace.delete` | 是 | 删除文件或目录 |

以上 8 个工具由 `workspace_tools.dart` 中的 `registerWorkspaceTools(registry, confirmer: ...)` 注册到全局 `ToolRegistry`。`confirmer` 是一个闭包，捕获 `ChatNotifier` 的审批流程，返回 `true` 通过，`false` 拒绝。

## 按行范围读取（`workspace_read`）

`workspace_read` 接受 `start_line` 与 `end_line`（均为 1-indexed，包含）。默认值：

- `start_line` 缺省 → 1
- `end_line` 缺省且 `start_line` 也缺省 → 100
- `end_line` 缺省但提供了 `start_line` → 等于 `start_line`
- 提供 `end_line` → 截断到文件实际总行数

响应头始终会报告服务的行范围与文件总行数，让模型知道下一步该请求哪一段：

```text
Showing lines 1-100 of 432.
<content>
```

`workspace_write` 复用同一约定：若同时提供 `start_line` 和 `end_line`，就替换该行范围并保留文件其余内容，模型可以产出聚焦的 diff 而无需重写整个文件。

## Stale-read 强制

`WorkspaceService` 在 LLM 调用 `workspace_read` 的那一刻记录文件的 mtime，key 形式为 `"<workspaceId>:<relativePath>"`。之后模型发起 write / edit / patch 时，服务会比对记录的 mtime 与文件当前 mtime：

- **一致** → 放行（文件与模型上次看到的内容一致）。
- **不一致** → 拒绝并提示：
  `File "foo.txt" was modified since last read. Re-read it before writing.`
- **没有记录** → 拒绝并提示：
  `You must call workspace_read on "foo.txt" before writing.`

这是会话级别、内存中的；应用重启即重置。它**不是**版本控制系统，只是用来挡掉「写覆盖了用户/其他工具最新内容」这一常见 LLM 错误。

## 审批流程

`WorkspaceApprovalRequest`（在 [`lib/models/workspace.dart`](../../lib/models/workspace.dart) 中定义）是 coordinator 传给 UI 的工作单元。它携带：

- `toolName` —— 被调用的 `workspace_*` 工具
- `actionLabel` —— i18n key，对应人类可读的动词
- `workspaceName` —— 当前激活工作空间的显示名
- `targetPath` —— 模型操作的相对路径
- `arguments` —— 完整参数映射（便于对话框展示 search/replace 对、行范围等）
- `completer` —— tool handler 在其上 `await` 的 `Completer<bool>`

coordinator 位于 `ChatNotifier` 中。当 tool handler 调用 `confirmer(request)` 时，coordinator 会把 `WorkspaceApprovalRequest` 通过 stream 广播；UI 监听器（`workspace_approval_listener.dart`）接收后弹出 `WorkspaceConfirmationDialog`，并在用户选择时 `complete(completer)`。handler 接着继续或返回一条「被拒」的 `ToolResult`。

拒绝情形会返回结构化错误，方便模型调整：

```text
Tool "workspace_write" was denied by the user. Reason: user pressed Cancel.
```

## 路径沙箱

[`path_traversal.dart`](../../lib/utils/path_traversal.dart) 中的
`resolveSafePath({workspaceRootPath, relativePath})` 是唯一的卡点。它：

1. 解析根的真实路径（`resolveSymbolicLinksSync`）。
2. 修剪用户的 `relativePath`，如带前导绝对路径前缀则去掉，再与根拼接。
3. 解析拼接结果的真实路径（若文件还不存在则回退到父目录的真实路径，从而支持新建）。
4. 校验最终路径等于根，或以 `root + sep` 开头。

任何一步失败都会抛 `PathTraversalException`。所有 read / write / edit / delete handler 在接触文件系统前都会调用它。

## 平台支持

`workspace_tools.dart` 在 web 和 iOS 上短路返回 —— 这两个平台要么没有 `dart:io`，要么文件系统访问受限。任何 `workspace_*` 工具在这两个平台上的首次调用都会返回一条 `isError: true` 的 `ToolResult`：

```text
Workspace tools are not supported on this platform (Web).
```

设置 → 工作空间在 web/iOS 上也会隐藏「添加工作空间」按钮；底层的 `WorkspaceService.init` 在 web 上是 no-op。Android、macOS、Windows、Linux 全部完整支持（Android 端走对应的存储权限流程 —— 详见 `lib/services/workspace_service.dart`）。

## 生命周期

工作空间以 `WorkspaceIndex` 的形式持久化到 `<appDocs>/workspaces/index.json`：

```json
{
  "version": 1,
  "active_workspace_id": "uuid",
  "workspaces": [
    { "id": "uuid", "name": "My Project", "root_path": "C:\\…", "created_at": "…", "updated_at": "…" }
  ]
}
```

`WorkspaceService` 暴露标准的 `workspaces / active / byId / setActive` 接口。`WorkspaceProvider` 将其包装进 Riverpod 树。`WorkspacePage` 列出所有工作空间，支持通过 `file_picker` 新增、切换、重命名、删除（删除仅移除注册项，不会触碰底层目录）。

## 参见

- [发现系统](discover-system.md) —— `workspace_*` 工具按 capability（`workspace.read`、`workspace.write` 等）可被 `discover` 工具检索
- [插件系统](plugin-system.md) —— 工作空间工具与插件工具共享同一 `ToolDefinition` / `ToolCall` / `ToolResult` 信封
- [LLM 提供商抽象](llm-providers.md) —— `ToolDefinition.toXxxSchema()` 把参数映射转换为各家 LLM 原生的 function-call 格式
