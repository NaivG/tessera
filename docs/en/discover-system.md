# Discover System

Tessera's tag and capability indexing layer for plugin skills and tools.

## Why a discover layer?

LLM context is finite. Pushing the full schema of every plugin tool into the
system prompt would quickly blow the budget for any non-trivial setup. Tessera
instead exposes a **compact skill catalog** (names, tags, capabilities, short
descriptions — no parameters) and a `discover` TOOL that returns lightweight
summaries on demand. The full schema is revealed only when the LLM's call is
malformed — `ToolCallValidator` returns the schema in the error so the model
can correct itself.

The two cooperating modules are:

| Concern | Source |
|---|---|
| Compact catalog builder | [`lib/core/discover_manager.dart`](../../lib/core/discover_manager.dart) |
| The `discover` TOOL exposed to the LLM | [`lib/core/discover_tool.dart`](../../lib/core/discover_tool.dart) |
| Runtime schema check + fail-with-schema | [`lib/core/tool_call_validator.dart`](../../lib/core/tool_call_validator.dart) |
| Capability / tag index used by the catalog | [`lib/core/tool_registry.dart`](../../lib/core/tool_registry.dart) |
| Skills + capabilities registered by plugins | [`lib/plugin/lua_plugin_host.dart`](../../lib/plugin/lua_plugin_host.dart) |

## Compact skill catalog

`DiscoverManager.buildCompactCatalog(skills)` produces the markdown block that's
appended to the system prompt. Each entry is a single line:

```text
## Available Skills
Use the `discover` tool to get details and find tools.

- [time, datetime] **Time Tools** (time.current, time.format): When the user
  asks about the current time, timestamps, or timezone conversions, use the
  get_current_time / format_time / convert_timezone tools.
- [web] **Web Search** (web.search): Look up information on the public web…
```

The block is intentionally small: name, tags, capabilities, and the skill's
own short description. The `discover` tool description (built by
`buildDiscoverGuidance()`) is appended right after it, so the model knows
exactly how to find more.

## The `discover` tool

`discover_tool.dart` registers a single `ToolDefinition` named `discover` into
the global `ToolRegistry`. Its `parameters`:

| Param | Type | Required | Effect |
|---|---|---|---|
| `query` | string | no | Fuzzy match against name, description, capabilities, tags |
| `capability` | string | no | Exact match against a capability string (preferred) |
| `tag` | string | no | Exact match against a tag |
| `kind` | string | no | One of `skill` / `tool` / `all` (default `all`) |

The handler is a thin wrapper around `DiscoverManager.discover(...)`. It
returns a `DiscoverResult.toDisplayString()` to the model: a list of
`SkillSummary` and `ToolSummary` blocks (no parameter schemas — see below).

### Design: schemas are pulled, not pushed

Both `SkillSummary` and `ToolSummary` deliberately **omit** the parameter
schema. The contract is:

> The LLM is responsible for picking a tool. The runtime is responsible for
> parameter validation. Schemas are exposed only when the LLM actually needs
> them — i.e. when the runtime rejects a malformed call.

This is what keeps the catalog usable in long conversations: a workspace tool
with 20 optional parameters doesn't bloat the system prompt, but the model
still gets the full schema the moment it makes a mistake.

## `ToolCallValidator` — fail-with-schema

`ToolCallValidator.validate(call, definition)` performs three checks:

1. **Required fields** — every `parameters[k].required == true` key must be
   present in `call.arguments`.
2. **Type matching** — for each supplied argument, the runtime type is
   compared to `parameters[k].type`. Supported types: `string`, `number`,
   `integer`, `boolean`, `array`, `object`. Unknown types are skipped
   (forward-compatible).
3. **Schema returned on failure** — when validation fails, the error message
   includes a pretty-printed `parameters` block as a fenced JSON code block.
   The model can then read the schema and re-issue the call.

`validateAll(calls, registry)` is the batch version. Unknown tool names
generate a `ToolResult` error pointing the LLM at the `discover` tool
("Tool \"foo\" is not registered. Use `discover` to find available tools.").

### Example failure message

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

## End-to-end flow

```
Plugin main.lua
   ↓ register_skill / register_tool (with tags + capabilities)
LuaPluginHost
   ↓ exposes PluginSkill + ToolDefinition
PluginRegistry.buildSkillBlocks()        DiscoverManager.buildCompactCatalog()
   ↓                                              ↓
System prompt: compact skill catalog    DiscoverManager.buildDiscoverGuidance()
                                              ↓
                                     System prompt: how to use `discover`

LLM reads the catalog, calls discover({capability: "time.current"})
   ↓
discover handler returns matching SkillSummary / ToolSummary
   ↓
LLM picks `get_current_time`, emits ToolCall({timezone: "Asia/Shanghai"})
   ↓
ToolRegistry.execute → ToolCallValidator.validate
   ↓ (pass)        ↓ (fail)
handler runs       error includes full schema → model retries
   ↓
ToolResult merged into conversation
```

## Indexing on the registry side

`ToolRegistry` (see [`lib/core/tool_registry.dart`](../../lib/core/tool_registry.dart))
keeps two secondary indices updated on every `register` / `unregister`:

- `capability → { tool name }` — populated from `ToolDefinition.capabilities`
- `tag → { tool name }` — populated from `ToolDefinition.tags`

`findByCapability(capability)` and `findByTag(tag)` give `DiscoverManager`
O(1) lookup for the indexed lookups. `search(query)` falls back to a
case-insensitive substring scan over name / description / capabilities / tags
for fuzzy queries.

Plugin skills use the same `Set<String> tags` / `Set<String> capabilities`
fields on `PluginSkill`; the catalog builder reads those directly from the
host's `skills` list, so the system prompt and the discover index never drift.

## See also

- [Plugin System](plugin-system.md) — the `register_skill` / `register_tool` API and how `tags` / `capabilities` are declared
- [Workspace Tools](workspace-tools.md) — the largest tool set in the registry, and the one most often discovered by capability
- [Sub-Agents](sub-agents.md) — sub-agents can also see the compact catalog
- [`lib/core/discover_manager.dart`](../../lib/core/discover_manager.dart) — `DiscoverManager` source
- [`lib/core/discover_tool.dart`](../../lib/core/discover_tool.dart) — the `discover` tool definition + handler
- [`lib/core/tool_call_validator.dart`](../../lib/core/tool_call_validator.dart) — `ToolCallValidator` source
