# 发现系统

Tessera 基于 tag 与 capability 的插件 skill / tool 索引层。

## 为什么需要发现层？

LLM 上下文是有限的。把每个插件工具的完整 schema 都塞进系统提示词里，会很快把预算打爆。Tessera 选择只暴露一份**紧凑的 skill 目录**（名称、tag、capability、简短描述 —— 不带参数），再提供一个 `discover` 工具按需返回轻量摘要。完整 schema 只在 LLM 的调用有误时才暴露 —— `ToolCallValidator` 会把 schema 写进错误消息，让模型据此自纠。

两个协作模块：

| 关注点 | 位置 |
|---|---|
| 紧凑目录构造 | [`lib/core/discover_manager.dart`](../../lib/core/discover_manager.dart) |
| 暴露给 LLM 的 `discover` 工具 | [`lib/core/discover_tool.dart`](../../lib/core/discover_tool.dart) |
| 运行时 schema 校验 + 失败返回 schema | [`lib/core/tool_call_validator.dart`](../../lib/core/tool_call_validator.dart) |
| 目录使用的 capability / tag 索引 | [`lib/core/tool_registry.dart`](../../lib/core/tool_registry.dart) |
| 插件注册的 skill + capability | [`lib/plugin/lua_plugin_host.dart`](../../lib/plugin/lua_plugin_host.dart) |

## 紧凑的 skill 目录

`DiscoverManager.buildCompactCatalog(skills)` 产出追加到系统提示词的 Markdown 块。每一行一个 skill：

```text
## Available Skills
Use the `discover` tool to get details and find tools.

- [time, datetime] **Time Tools** (time.current, time.format): When the user
  asks about the current time, timestamps, or timezone conversions, use the
  get_current_time / format_time / convert_timezone tools.
- [web] **Web Search** (web.search): Look up information on the public web…
```

这段刻意保持简洁：name、tag、capability、以及 skill 自带的简短描述。`buildDiscoverGuidance()` 构造的 `discover` 工具使用说明紧跟其后，模型一看就知道怎么进一步检索。

## `discover` 工具

`discover_tool.dart` 向全局 `ToolRegistry` 注册一个名为 `discover` 的 `ToolDefinition`。参数：

| 参数 | 类型 | 必填 | 作用 |
|---|---|---|---|
| `query` | string | 否 | 在 name / description / capability / tag 上做模糊匹配 |
| `capability` | string | 否 | 精确匹配 capability 字符串（推荐） |
| `tag` | string | 否 | 精确匹配 tag |
| `kind` | string | 否 | `skill` / `tool` / `all` 之一（默认 `all`） |

handler 是 `DiscoverManager.discover(...)` 的薄包装，把 `DiscoverResult.toDisplayString()` 返回给模型：一份 `SkillSummary` 与 `ToolSummary` 列表（不含参数 schema —— 见下文）。

### 设计：schema 是被「拉」出来的，不是「推」出去的

`SkillSummary` 与 `ToolSummary` 都**故意省略**了参数 schema。契约是：

> LLM 负责选工具，Runtime 负责校验参数；schema 只在 LLM 真正需要时（即 Runtime 拒绝了一次错误调用）才暴露。

这是目录在长对话中依然可用的关键：一个有 20 个可选参数的工作空间工具不会撑爆系统提示词，但模型出错的那一刻就能拿到完整 schema。

## `ToolCallValidator` —— 失败时返回 schema

`ToolCallValidator.validate(call, definition)` 做三项检查：

1. **必填字段** —— `parameters[k].required == true` 的每个键都必须出现在 `call.arguments` 中。
2. **类型匹配** —— 对每个传入参数，将运行时类型与 `parameters[k].type` 对比。支持的类型：`string`、`number`、`integer`、`boolean`、`array`、`object`。未知类型跳过（前向兼容）。
3. **失败时返回 schema** —— 校验失败时，错误消息附带一个 pretty-printed `parameters` 块（fenced JSON）。模型可以读取 schema 后重新发起调用。

`validateAll(calls, registry)` 是批量版本。未知工具名会生成一条 `ToolResult` 错误，把模型指向 `discover`（"Tool \"foo\" is not registered. Use `discover` to find available tools."）。

### 错误消息示例

```text
Tool call validation failed for "workspace_write":
  - Missing required parameter: "content"

Full parameter schema for "workspace_write":
```json
{
  "path": { "type": "string", "description": "Relative file path…", "required": true },
  "content": { "type": "string", "description": "The text content to write.", "required": true },
  "start_line": { "type": "integer", "description": "…", "required": false },
  "end_line": { "type": "integer", "description": "…", "required": false }
}
```

Please correct your arguments and call the tool again.
```

## 端到端流程

```
Plugin main.lua
   ↓ register_skill / register_tool (带 tags + capabilities)
LuaPluginHost
   ↓ 暴露 PluginSkill + ToolDefinition
PluginRegistry.buildSkillBlocks()        DiscoverManager.buildCompactCatalog()
   ↓                                              ↓
系统提示词：紧凑 skill 目录              DiscoverManager.buildDiscoverGuidance()
                                              ↓
                                    系统提示词：如何使用 `discover`

LLM 读取目录，调用 discover({capability: "time.current"})
   ↓
discover handler 返回匹配的 SkillSummary / ToolSummary
   ↓
LLM 选中 `get_current_time`，发出 ToolCall({timezone: "Asia/Shanghai"})
   ↓
ToolRegistry.execute → ToolCallValidator.validate
   ↓ (pass)        ↓ (fail)
handler 运行        错误含完整 schema → 模型重试
   ↓
ToolResult 合并进对话
```

## 注册表侧索引

`ToolRegistry`（见 [`lib/core/tool_registry.dart`](../../lib/core/tool_registry.dart)）在每次 `register` / `unregister` 时维护两个二级索引：

- `capability → { tool name }` —— 从 `ToolDefinition.capabilities` 收集
- `tag → { tool name }` —— 从 `ToolDefinition.tags` 收集

`findByCapability(capability)` 与 `findByTag(tag)` 给 `DiscoverManager` 提供 O(1) 索引查找。`search(query)` 在模糊查询时回退到对 name / description / capability / tag 的不区分大小写子串扫描。

插件 skill 使用 `PluginSkill` 上同名的 `Set<String> tags` / `Set<String> capabilities` 字段；目录构造器直接从宿主的 `skills` 列表里读取，所以系统提示词和 discover 索引永远保持同步。

## 参见

- [插件系统](plugin-system.md) —— `register_skill` / `register_tool` API，以及如何声明 `tags` / `capabilities`
- [工作空间工具](workspace-tools.md) —— 注册表中最大的工具集，也是最常按 capability 被发现的
- [子 Agent](sub-agents.md) —— 子 Agent 也能看到紧凑目录
- [`lib/core/discover_manager.dart`](../../lib/core/discover_manager.dart) —— `DiscoverManager` 源码
- [`lib/core/discover_tool.dart`](../../lib/core/discover_tool.dart) —— `discover` 工具定义与 handler
- [`lib/core/tool_call_validator.dart`](../../lib/core/tool_call_validator.dart) —— `ToolCallValidator` 源码
