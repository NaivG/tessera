# Plugin System

Tessera's Lua plugin system.

## Overview

Tessera's plugin system is a sandboxed **Lua 5.3** runtime — powered by the vendored [`lua_dardo_plus`](https://pub.dev/packages/lua_dardo_plus) (`lua_dardo` fork) — that lets you extend the app at runtime in two ways:

- **TOOL** — a function the main chat model can invoke via function-calling. Results are returned as text and merged back into the conversation as a `ToolResult`.
- **SKILL** — a short markdown description appended to the system prompt so the model knows *when* to use your TOOLs.

Each plugin is a folder containing a `plugin.json` manifest and a Lua entry script. Plugins can be **bundled** with the app (shipped under `assets/plugins/`) or **user-installed** as `.plugin` ZIPs (extracted into the app's documents directory). Hot-enable / hot-disable from the Plugins page — no app restart required.

| Layer | Source |
|---|---|
| Manifest schema | [`lib/plugin/plugin_metadata.dart`](../../lib/plugin/plugin_metadata.dart) |
| Lua sandbox + bridge | [`lib/plugin/lua_plugin_host.dart`](../../lib/plugin/lua_plugin_host.dart) |
| Filesystem install/uninstall | [`lib/plugin/plugin_manager.dart`](../../lib/plugin/plugin_manager.dart) |
| Lifecycle / tool dispatch | [`lib/plugin/plugin_registry.dart`](../../lib/plugin/plugin_registry.dart) |
| Lua runtime patches | [`lib/plugin/patchs/`](../../lib/plugin/patchs/) |
| UI surface | [`lib/ui/pages/plugin_page.dart`](../../lib/ui/pages/plugin_page.dart) |

## Plugin Manifest (`plugin.json`)

Every plugin folder starts with a manifest. The schema is defined by [`PluginMetadata.fromJson`](../../lib/plugin/plugin_metadata.dart):

```json
{
  "id": "com.tessera.time",
  "name": "Time Tools",
  "version": "1.0.0",
  "author": "Tessera",
  "description": "Provides current-time, strftime formatting, and timezone conversion tools",
  "entryPoint": "main.lua",
  "homepage": ""
}
```

| Field | Required | Default | Notes |
|---|---|---|---|
| `id` | **yes** | `""` | Reverse-DNS, e.g. `com.tessera.example` — must be unique; also used (sanitized) as the on-disk directory name |
| `name` | no | `""` | Display name shown in the Plugins page |
| `version` | no | `"0.0.0"` | Semver string |
| `author` | no | `""` | Author / maintainer |
| `description` | no | `""` | Short summary shown in the UI |
| `entryPoint` | no | `"main.lua"` | Lua script path, relative to the plugin folder |
| `homepage` | no | `null` | Optional URL |

All string fields are tolerant of missing keys; only `id` is strictly required.

## The `tessera` Bridge API

When your Lua script runs, a global table named `tessera` is injected into the Lua VM by [`LuaPluginHost._setupBridge()`](../../lib/plugin/lua_plugin_host.dart). It exposes three calls:

```lua
-- 1) Log a debug message (visible in the Flutter log)
tessera.log("Time Plugin loaded")

-- 2) Register a SKILL — text appended to the system prompt
tessera.register_skill({
  name = "Time Tools",
  description = "When the user asks about the current time, timestamps, or timezone conversions, use the get_current_time / format_time / convert_timezone tools."
})

-- 3) Register a TOOL — an LLM-callable function
tessera.register_tool({
  name = "get_current_time",
  description = "Return the current time in a given IANA timezone.",
  parameters = {
    timezone = { type = "string", description = "IANA tz, e.g. Asia/Shanghai", required = false },
    format   = { type = "string", description = "iso / timestamp / human",        required = false },
  },
  handler = function(args)
    local tz  = args["timezone"] or "UTC"
    local fmt = args["format"]   or "iso"
    -- ...compute and return a string...
    return "2026-06-05T14:23:45+08:00"
  end,
})
```

A `handler` is just a Lua function: it receives the LLM's argument map as a Lua table and must return a `string`. The host wraps the result in a `ToolResult` (defined in [`lib/models/tool.dart`](../../lib/models/tool.dart)) and feeds it back to the main model.

`PluginRegistry.buildSkillBlocks()` then concatenates every registered skill's `name` + `description` into a single markdown section that's injected into the system prompt — the model sees the skill summary in the system prompt and is expected to call the matching TOOL.

## Lifecycle

[`PluginRegistry`](../../lib/plugin/plugin_registry.dart) is a singleton that owns plugin state. The typical startup flow, called from `ChatNotifier.init()`:

```dart
final registry = PluginRegistry();
await registry.scanAll();          // Discover bundled + installed
await registry.enableAll();        // Spin up a LuaState per enabled plugin
registry.registerTo(toolRegistry); // Expose TOOLs to the LLM
```

Internally:

1. **`scanAll()`** calls `PluginManager.scanBundled()` (reads `assets/plugins/plugins_index.json` as an allowlist) and `PluginManager.scanInstalled()` (lists `getApplicationDocumentsDirectory()/plugins/`).
2. **`enable(id)`** creates a `LuaPluginHost`, runs the per-plugin Lua startup sequence (see [Runtime Patches](#runtime-patches)), loads the entry-point script, and caches the host keyed by `pluginId`.
3. **`registerTo(toolRegistry)`** iterates each host's `toolDefinitions` and wires `callTool` as the dispatcher; `unregisterFrom` cleans up. Per-plugin toggles, uninstall, and ZIP install all go through the same `PluginRegistry`.

## Discovery & Installation

Tessera distinguishes two plugin origins (`PluginOrigin`):

- **Bundled** — listed by name in [`assets/plugins/plugins_index.json`](../../assets/plugins/plugins_index.json) (an explicit allowlist). On startup the registry reads each folder's `plugin.json` from the asset bundle and copies the entry script + assets to a staging directory on first run.
- **Installed** — extracted from `.plugin` ZIPs into `getApplicationDocumentsDirectory()/plugins/<sanitized_id>/`. The sanitized id replaces `.` and `-` with `_`.

### `.plugin` distribution format

A `.plugin` file is a plain ZIP whose root (or a single nested folder) contains `plugin.json` plus the entry Lua and any optional resources (`icon.png`, `README.md`, `config.json`). The `lib/plugin/plugin_manager.dart` ZIP install path (`previewZip` → `installFromTemp`) locates `plugin.json` either at the ZIP root or in a first-level subdir.

Tessera has provide a official packager CLI [`plugins/pack_plugin.py`](../../plugins/pack_plugin.py).

Usage:

```bash
# Install lupa for Lua static check
pip install lupa

# Validate a plugin directory (manifest + Lua syntax check)
python plugins/pack_plugin.py validate plugins/my_plugin

# Build a .plugin ZIP (output defaults to ./<sanitized_id>-<version>.plugin)
python plugins/pack_plugin.py pack plugins/my_plugin -o dist/

# Skip the lupa-based Lua static check
python plugins/pack_plugin.py pack plugins/my_plugin --skip-lua-check
```

### Install flow (UI)

The **Plugins** page ([`lib/ui/pages/plugin_page.dart`](../../lib/ui/pages/plugin_page.dart)) accepts a `.plugin` ZIP via [`file_picker`](https://pub.dev/packages/file_picker), shows a confirmation dialog with name / version / author / description, then extracts and enables it. The page also lists bundled plugins with one-tap install.

## Runtime Patches

The vendored `lua_dardo_plus` fork still has rough edges. Rather than fork-and-modify, Tessera applies **runtime monkey-patches** from [`lib/plugin/patchs/`](../../lib/plugin/patchs/) *after* `openLibs()` and *before* the `tessera` bridge is installed:

```
newState → openLibs() → patchAll(state) → _setupBridge()
```

This keeps the upstream dependency clean and upgrade-safe — when the upstream is fixed, the corresponding patch can be deleted in one file.

| File | Entry | What it fixes |
|---|---|---|
| `lua_os_date.dart` | `patchOsDate` | `os.date` epoch misuse + missing strftime literal handling |

### Adding a new patch

1. Create `lib/plugin/patchs/<lib>_<symptom>_patch.dart` and export a `patchXxx(LuaState ls)` top-level function.
2. `import` it in [`lib/plugin/patchs/patch.dart`](../../lib/plugin/patchs/patch.dart) and call it from `patchAll()` in dependency order.
3. The caller (`lua_plugin_host.dart`) needs **no changes** — `patchAll()` is the single integration point.

See [`lib/plugin/patchs/README.md`](../../lib/plugin/patchs/README.md) for the full convention (Chinese-language original).

## Authoring a Plugin

### Option A — Bundled (ships with the app)

1. Create `assets/plugins/<dir>/plugin.json` and `<dir>/main.lua`.
2. Add the id to [`assets/plugins/plugins_index.json`](../../assets/plugins/plugins_index.json) (e.g. `["example_hello", "my_plugin"]`).
3. Add both files to the `flutter: assets:` block in [`pubspec.yaml`](../../pubspec.yaml) and run `flutter pub get`.
4. Rebuild; the new plugin will appear under "Bundled" in the Plugins page.

### Option B — User-installable `.plugin` package

1. Make a folder with `plugin.json`, `main.lua`, and any optional `icon.png` / `README.md`.
2. Run `python plugins/pack_plugin.py validate <folder>` to check the manifest + Lua syntax, then `python plugins/pack_plugin.py pack <folder> -o <out_dir>/`.
3. Distribute the `.plugin` file. Users install via the "Install from file" card on the Plugins page. The ZIP layout must keep `plugin.json` at the ZIP root (or one level deep — the manager handles both).

### Writing `main.lua`

Call `tessera.register_skill({...})` and one or more `tessera.register_tool({...})` at top level. The handler receives a Lua table of arguments and must return a string. Beyond the bridge, plugins can use the full patched `os`, `string`, `math`, and `table` Lua standard libraries.

## Built-in Examples

### [`assets/plugins/example_hello/`](../../assets/plugins/example_hello/)

The canonical "Hello World" plugin — 56 lines, one SKILL, one multilingual `greeting` TOOL. Bundled with the app and indexed in `plugins_index.json`. Use it as the minimum working template:

```lua
tessera.register_skill({
  name = "Greeting Skill",
  description = "I have a greeting tool that can greet the user in different languages."
})

tessera.register_tool({
  name = "greeting",
  description = "Greet the user in a specified language",
  parameters = {
    name     = { type = "string", description = "User name to greet",  required = true  },
    language = { type = "string", description = "Language code (zh, en, ja, fr…)", required = false },
  },
  handler = function(args)
    local name = args["name"] or "World"
    local lang = args["language"] or "zh"
    -- ...lookup greeting[lang] or fall back to English...
    return "Hello, " .. name .. "!"
  end,
})
```

## See Also

- [`lib/plugin/plugin.dart`](../../lib/plugin/plugin.dart) — public barrel, the only import most callers need
- [`lib/ui/pages/plugin_page.dart`](../../lib/ui/pages/plugin_page.dart) — install / enable / uninstall UI
- [`plugins/pack_plugin.py`](../../plugins/pack_plugin.py) — official packager
- [`lib/plugin/patchs/README.md`](../../lib/plugin/patchs/README.md) — Lua runtime patch convention
- [`lib/models/tool.dart`](../../lib/models/tool.dart) — `ToolDefinition` / `ToolCall` / `ToolResult` types
- [`lib/core/tool_registry.dart`](../../lib/core/tool_registry.dart) — global tool registry that the plugin host registers into
