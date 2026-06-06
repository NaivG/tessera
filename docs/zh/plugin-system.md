# 插件系统

本页是 Tessera Lua 插件系统的深入讲解。

## 概述

Tessera 的插件系统是一个沙箱化的 **Lua 5.3** 运行时（由 vendored 的 [`lua_dardo_plus`](https://pub.dev/packages/lua_dardo_plus) 分支提供支持），让你可以在运行时通过两种方式扩展应用：

- **TOOL（工具）** —— 主对话模型可以通过 function-calling 调用的函数，结果以文本形式返回，并合并回对话中（包装为 `ToolResult`）。
- **SKILL（技能）** —— 一段简短的 Markdown 描述，会被追加到系统提示中，让模型知道**何时**该使用你注册的 TOOL。

每个插件都是一个文件夹，包含一个 `plugin.json` manifest 和一个 Lua 入口脚本。插件既可以随应用**捆版（bundled）**发布（位于 `assets/plugins/` 下），也可以让用户以 `.plugin` ZIP 包形式**自行安装**（解压到应用的 documents 目录）。在**插件**页面可以热启用 / 热禁用 —— 无需重启应用。

| 关注点 | 位置 |
|---|---|
| Manifest 数据模型 | [`lib/plugin/plugin_metadata.dart`](../../lib/plugin/plugin_metadata.dart) |
| Lua 沙箱 + 桥接 | [`lib/plugin/lua_plugin_host.dart`](../../lib/plugin/lua_plugin_host.dart) |
| 文件系统安装 / 卸载 | [`lib/plugin/plugin_manager.dart`](../../lib/plugin/plugin_manager.dart) |
| 生命周期 / 工具分发 | [`lib/plugin/plugin_registry.dart`](../../lib/plugin/plugin_registry.dart) |
| Lua 运行时补丁 | [`lib/plugin/patchs/`](../../lib/plugin/patchs/) |
| UI 页面 | [`lib/ui/pages/plugin_page.dart`](../../lib/ui/pages/plugin_page.dart) |

## 插件 Manifest（`plugin.json`）

每个插件目录都以一个 manifest 开头。Schema 由 [`PluginMetadata.fromJson`](../../lib/plugin/plugin_metadata.dart) 定义：

```json
{
  "id": "com.tessera.time",
  "name": "时间工具",
  "version": "1.0.0",
  "author": "Tessera",
  "description": "提供当前时间、strftime 格式化、时区转换等工具",
  "entryPoint": "main.lua",
  "homepage": ""
}
```

| 字段 | 必填 | 默认值 | 说明 |
|---|---|---|---|
| `id` | **是** | `""` | 反向域名风格，例如 `com.tessera.example` —— 必须唯一；同时作为磁盘上的目录名（经过 sanitize） |
| `name` | 否 | `""` | 插件页面中显示的名称 |
| `version` | 否 | `"0.0.0"` | semver 字符串 |
| `author` | 否 | `""` | 作者 / 维护者 |
| `description` | 否 | `""` | UI 中显示的简短说明 |
| `entryPoint` | 否 | `"main.lua"` | 相对于插件目录的 Lua 入口脚本路径 |
| `homepage` | 否 | `null` | 可选的项目首页 URL |

所有字符串字段都允许缺失，只有 `id` 是真正必填的。

## `tessera` 桥接 API

当你的 Lua 脚本运行时，[`LuaPluginHost._setupBridge()`](../../lib/plugin/lua_plugin_host.dart) 会向 Lua VM 注入一个名为 `tessera` 的全局表，对外暴露三个调用：

```lua
-- 1) 打印调试信息（输出到 Flutter 日志）
tessera.log("Time Plugin loaded")

-- 2) 注册一个 SKILL —— 文本会被追加到系统提示中
tessera.register_skill({
  name = "时间工具",
  description = "当用户询问当前时间、时间戳或时区转换时，使用 get_current_time / format_time / convert_timezone 工具。"
})

-- 3) 注册一个 TOOL —— 可被 LLM 调用的函数
tessera.register_tool({
  name = "get_current_time",
  description = "返回指定 IANA 时区的当前时间。",
  parameters = {
    timezone = { type = "string", description = "IANA 时区，如 Asia/Shanghai", required = false },
    format   = { type = "string", description = "iso / timestamp / human",        required = false },
  },
  handler = function(args)
    local tz  = args["timezone"] or "UTC"
    local fmt = args["format"]   or "iso"
    -- ...计算并返回字符串...
    return "2026-06-05T14:23:45+08:00"
  end,
})
```

`handler` 就是一个普通 Lua 函数：它以 Lua 表的形式接收 LLM 传来的参数映射，必须返回一个 `string`。宿主会把返回值包装为 [`lib/models/tool.dart`](../../lib/models/tool.dart) 中定义的 `ToolResult`，再送回主模型。

随后，`PluginRegistry.buildSkillBlocks()` 会把每个已注册技能的 `name` + `description` 拼成一个 Markdown 段落，注入到系统提示中 —— 模型从系统提示里看到技能摘要，按需调用对应的 TOOL。

## 生命周期

[`PluginRegistry`](../../lib/plugin/plugin_registry.dart) 是一个单例，统一管理插件状态。典型启动流程（在 `ChatNotifier.init()` 中调用）：

```dart
final registry = PluginRegistry();
await registry.scanAll();          // 扫描捆版 + 已安装
await registry.enableAll();        // 为每个启用的插件创建 LuaState
registry.registerTo(toolRegistry); // 把 TOOL 暴露给 LLM
```

内部步骤：

1. **`scanAll()`** 调用 `PluginManager.scanBundled()`（读取 [`assets/plugins/plugins_index.json`](../../assets/plugins/plugins_index.json) 这个白名单）和 `PluginManager.scanInstalled()`（枚举 `getApplicationDocumentsDirectory()/plugins/` 目录）。
2. **`enable(id)`** 为指定插件创建 `LuaPluginHost`，运行该插件的 Lua 启动序列（参见[运行时补丁](#运行时补丁)），加载入口脚本，并以 `pluginId` 为 key 缓存宿主。
3. **`registerTo(toolRegistry)`** 遍历每个宿主的 `toolDefinitions`，把 `callTool` 绑为分发器；`unregisterFrom` 负责清理。单插件的开关、卸载、ZIP 安装都走同一个 `PluginRegistry`。

## 发现与安装

Tessera 区分两种插件来源（`PluginOrigin`）：

- **Bundled（捆版）** —— 通过 [`assets/plugins/plugins_index.json`](../../assets/plugins/plugins_index.json) 中的 id 白名单显式列出。启动时注册表从 asset bundle 读取每个目录的 `plugin.json`，并把入口脚本 + 资源在首次运行时复制到一个临时目录。
- **Installed（已安装）** —— 从 `.plugin` ZIP 解压到 `getApplicationDocumentsDirectory()/plugins/<sanitized_id>/`。Sanitize 后的 id 会把 `.` 和 `-` 替换为 `_`。

### `.plugin` 分发格式

`.plugin` 文件就是一个普通 ZIP，根目录（或单层嵌套子目录）下包含 `plugin.json` 和入口 Lua 脚本，以及可选的 `icon.png` / `README.md` / `config.json` 等资源。`lib/plugin/plugin_manager.dart` 中的 ZIP 安装路径（`previewZip` → `installFromTemp`）会自动寻找位于 ZIP 根目录或单层子目录中的 `plugin.json`。

Tessera 提供了一个官方打包 CLI: [`plugins/pack_plugin.py`](../../plugins/pack_plugin.py)

用法: 

```bash
# 安装 lupa（用于 Lua 静态检查）
pip install lupa

# 校验插件目录（manifest + Lua 静态语法检查）
python plugins/pack_plugin.py validate plugins/my_plugin

# 打成 .plugin ZIP（默认输出到 ./<sanitized_id>-<version>.plugin）
python plugins/pack_plugin.py pack plugins/my_plugin -o dist/

# 未安装 lupa 时可跳过 Lua 静态检查
python plugins/pack_plugin.py pack plugins/my_plugin --skip-lua-check
```

### UI 安装流程

**插件**页面（[`lib/ui/pages/plugin_page.dart`](../../lib/ui/pages/plugin_page.dart)）通过 [`file_picker`](https://pub.dev/packages/file_picker) 接受 `.plugin` ZIP，弹出确认对话框展示名称 / 版本 / 作者 / 描述，确认后解压并启用。该页面同时列出所有 Bundled 插件，支持一键安装。

## 运行时补丁

Vendored 的 `lua_dardo_plus` 分支仍有一些边缘情况。Tessera 选择**运行时 monkey-patch**（[`lib/plugin/patchs/`](../../lib/plugin/patchs/)）的方案，**不**修改上游源码：在 `openLibs()` 之后、`tessera` 桥接安装之前应用补丁：

```
newState → openLibs() → patchAll(state) → _setupBridge()
```

这样可以保持上游依赖干净、升级安全 —— 一旦上游修了对应 bug，只需删掉一个 patch 文件即可。

| 文件 | 入口 | 修复目标 |
|---|---|---|
| `lua_os_date.dart` | `patchOsDate` | `os.date` 的 epoch 误用 + 缺失的 strftime 字面量处理 |

### 新增一个补丁

1. 新建 `lib/plugin/patchs/<lib>_<symptom>_patch.dart`，导出一个顶层函数 `patchXxx(LuaState ls)`。
2. 在 [`lib/plugin/patchs/patch.dart`](../../lib/plugin/patchs/patch.dart) 中 `import` 它，并在 `patchAll()` 里按依赖顺序调用。
3. 调用方（`lua_plugin_host.dart`）**无需任何修改** —— `patchAll()` 是唯一的集成点。

完整约定见 [`lib/plugin/patchs/README.md`](../../lib/plugin/patchs/README.md)（原文为中文）。

## 插件编写指南

### 方式 A —— Bundled（随应用发布）

1. 创建 `assets/plugins/<dir>/plugin.json` 与 `<dir>/main.lua`。
2. 把 id 加入 [`assets/plugins/plugins_index.json`](../../assets/plugins/plugins_index.json)（例如 `["example_hello", "my_plugin"]`）。
3. 在 [`pubspec.yaml`](../../pubspec.yaml) 的 `flutter: assets:` 块中注册这两个文件，然后执行 `flutter pub get`。
4. 重新构建应用；新插件就会出现在插件页面的"Bundled"区域。

### 方式 B —— 用户可安装的 `.plugin` 包

1. 准备一个目录，包含 `plugin.json`、`main.lua` 以及可选的 `icon.png` / `README.md`。
2. 执行 `python plugins/pack_plugin.py validate <folder>` 检查 manifest + Lua 语法，再 `python plugins/pack_plugin.py pack <folder> -o <out_dir>/` 打包。
3. 分发 `.plugin` 文件。用户在插件页面的"Install from file"卡片安装即可。ZIP 布局要求 `plugin.json` 位于 ZIP 根目录（或单层子目录 —— 两种布局 manager 都能处理）。

### 编写 `main.lua`

在顶层调用 `tessera.register_skill({...})` 与一个或多个 `tessera.register_tool({...})`。handler 接收一个 Lua 表作为参数，必须返回字符串。除了桥接 API 外，插件还可以使用经过 patch 的 Lua 标准库：`os`、`string`、`math`、`table`。

## 内置示例

### [`assets/plugins/example_hello/`](../../assets/plugins/example_hello/)

"Hello World" 示例插件 —— 56 行，1 个 SKILL + 1 个多语言 `greeting` TOOL。随应用 Bundled，并在 `plugins_index.json` 中注册。可作为最简模板：

```lua
tessera.register_skill({
  name = "问候技能",
  description = "我有一个 greeting 工具，可以用不同语言向用户打招呼。"
})

tessera.register_tool({
  name = "greeting",
  description = "用指定语言向用户打招呼",
  parameters = {
    name     = { type = "string", description = "要问候的用户名", required = true  },
    language = { type = "string", description = "语言代码（zh, en, ja, fr…）", required = false },
  },
  handler = function(args)
    local name = args["name"] or "World"
    local lang = args["language"] or "zh"
    -- ...查找 greetings[lang] 或回退到英文...
    return "Hello, " .. name .. "!"
  end,
})
```

## 参见

- [`lib/plugin/plugin.dart`](../../lib/plugin/plugin.dart) —— 公共 barrel，大多数调用方只需 import 一次
- [`lib/ui/pages/plugin_page.dart`](../../lib/ui/pages/plugin_page.dart) —— 安装 / 启用 / 卸载 UI
- [`plugins/pack_plugin.py`](../../plugins/pack_plugin.py) —— 官方打包工具
- [`lib/plugin/patchs/README.md`](../../lib/plugin/patchs/README.md) —— Lua 运行时补丁规范
- [`lib/models/tool.dart`](../../lib/models/tool.dart) —— `ToolDefinition` / `ToolCall` / `ToolResult` 类型定义
- [`lib/core/tool_registry.dart`](../../lib/core/tool_registry.dart) —— 插件宿主注册 TOOL 时写入的全局工具表
