// Tessera 插件系统 — 基于 LuaDardoPlus 的 Lua 插件运行时。
// 插件通过 Lua 脚本向 Tessera 注入 SKILL（系统提示描述）和 TOOL（LLM 可调用工具）。
//
// 快速开始：
//   final registry = PluginRegistry();
//   await registry.scanBundled();
//   await registry.enableAll();
//   registry.registerTo(toolRegistry);

export 'plugin_metadata.dart';
export 'lua_plugin_host.dart';
export 'plugin_registry.dart';
export 'plugin_manager.dart';
