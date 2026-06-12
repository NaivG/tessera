import 'package:flutter/foundation.dart';
import 'package:luax/lua.dart';

import '../models/message.dart';
import '../models/tool.dart';
import 'addons/addon.dart';
import 'addons/lua_value_codec.dart';
import 'plugin_metadata.dart';

// =============================================================================
// PluginSkill — 插件注入的技能描述（插入到 System Prompt 中）
// =============================================================================

/// 一个插件注册的技能片段，最终会拼入 LLM 的 System Prompt。
class PluginSkill {
  final String pluginId;
  final String name;
  final String description;

  const PluginSkill({
    required this.pluginId,
    required this.name,
    required this.description,
  });
}

// =============================================================================
// 内部工具条目
// =============================================================================

/// 插件注册的单个工具元信息 + Lua 函数引用
class _PluginToolEntry {
  final String name;
  final String description;
  final Map<String, dynamic> parameters;
  final int luaRef;

  const _PluginToolEntry({
    required this.name,
    required this.description,
    required this.parameters,
    required this.luaRef,
  });
}

// =============================================================================
// LuaPluginHost — 每个插件一个独立的 Lua 沙箱
// =============================================================================

/// Lua 插件宿主。
///
/// 职责：
/// 1. 为单个插件创建隔离的 LuaState
/// 2. 注入 `tessera` 全局表提供 `register_tool` / `register_skill` / `log` 桥接
/// 3. 加载并执行插件 Lua 入口文件
/// 4. 暴露 `callTool()` 供 PluginRegistry 在 LLM 调用插件工具时分发
/// 5. 暴露 `toolDefinitions` 和 `skills` 供注册到 ToolRegistry 和 System Prompt
class LuaPluginHost {
  final String pluginId;

  PluginMetadata? metadata;

  late final LuaState _state;
  bool _initialized = false;

  /// 已注册的工具条目：toolName → _PluginToolEntry
  final Map<String, _PluginToolEntry> _tools = {};

  /// 已注册的技能列表
  final List<PluginSkill> _skills = [];

  // ---------------------------------------------------------------------------
  // 构造
  // ---------------------------------------------------------------------------

  LuaPluginHost._({required this.pluginId});

  /// 创建并初始化一个插件宿主。
  ///
  /// [pluginId] 用作沙箱标识，不影响 LuaState 隔离性。
  static LuaPluginHost create(String pluginId) {
    final host = LuaPluginHost._(pluginId: pluginId);
    host._initLuaState();
    return host;
  }

  void _initLuaState() {
    _state = LuaState.newState();
    _state.openLibs();
    // 一次性挂载 addons/ 下所有标准能力 (http / json / base64)
    installAddons(_state);
    _setupBridge();
    _initialized = true;
  }

  // ---------------------------------------------------------------------------
  // Lua ↔ Dart 桥接
  // ---------------------------------------------------------------------------

  void _setupBridge() {
    // tessera = {}
    _state.newTable();

    // tessera.register_tool(def: table)
    _state.pushDartFunction(_bridgeRegisterTool);
    _state.setField(-2, 'register_tool');

    // tessera.register_skill(def: table)
    _state.pushDartFunction(_bridgeRegisterSkill);
    _state.setField(-2, 'register_skill');

    // tessera.log(...)
    _state.pushDartFunction(_bridgeLog);
    _state.setField(-2, 'log');

    _state.setGlobal('tessera');
  }

  // ---------------------------------------------------------------------------
  // 加载 Lua 入口
  // ---------------------------------------------------------------------------

  /// 加载并执行一段 Lua 脚本（通常是插件入口文件内容）。
  Future<void> loadString(String script) async {
    if (!_initialized) return;

    final status = _state.loadString(script);
    if (status != ThreadStatus.luaOk) {
      final err = _state.toStr(-1) ?? 'load error';
      _state.pop(1);
      throw Exception('[$pluginId] Lua syntax error: $err');
    }

    // 用 pCallAsync 让 main.lua 顶层也可以调用异步 addon (如 http.get)
    final callStatus = await _state.pCallAsync(0, 0, 0);
    if (callStatus != ThreadStatus.luaOk) {
      final err = _state.toStr(-1) ?? 'runtime error';
      _state.pop(1);
      throw Exception('[$pluginId] Lua runtime error: $err');
    }
  }

  // ---------------------------------------------------------------------------
  // 工具相关
  // ---------------------------------------------------------------------------

  /// 插件注册的所有工具定义（用于注入 ToolRegistry）
  List<ToolDefinition> get toolDefinitions =>
      _tools.values.map(_toToolDefinition).toList();

  ToolDefinition _toToolDefinition(_PluginToolEntry entry) {
    return ToolDefinition(
      name: entry.name,
      description: entry.description,
      parameters: entry.parameters,
    );
  }

  /// LLM 调用插件工具时的分发入口。
  ///
  /// 从 Lua registry 中取出对应的 function，传入参数 table，返回字符串结果。
  Future<ToolResult> callTool(ToolCall call) async {
    final entry = _tools[call.name];
    if (entry == null) {
      return ToolResult(
        toolCallId: call.id,
        content: 'Plugin tool "${call.name}" is not registered.',
        isError: true,
      );
    }

    try {
      // 1. 从 registry 取出 Lua function
      _state.rawGetI(luaRegistryIndex, entry.luaRef);

      // 2. 将 Dart Map 转为 Lua table 压栈
      LuaValueCodec.pushDart(_state, call.arguments);

      // 3. 用 pCallAsync 调用 (1 参, 1 返回值),让 handler 内可调用异步 addon (如 http.get)
      final callStatus = await _state.pCallAsync(1, 1, 0);
      if (callStatus != ThreadStatus.luaOk) {
        final err = _state.toStr(-1) ?? 'runtime error';
        _state.pop(1);
        return ToolResult(
          toolCallId: call.id,
          content: 'Plugin tool "${call.name}" runtime error: $err',
          isError: true,
        );
      }

      // 4. 读取返回值
      final result = _state.toStr(-1) ?? '';
      _state.pop(1);
      return ToolResult(toolCallId: call.id, content: result);
    } catch (e) {
      debugPrint('[Plugin:$pluginId] tool "${call.name}" error: $e');
      return ToolResult(
        toolCallId: call.id,
        content: 'Plugin tool "${call.name}" execution error: $e',
        isError: true,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // 技能相关
  // ---------------------------------------------------------------------------

  /// 插件注册的所有技能（用于注入 System Prompt）
  List<PluginSkill> get skills => List.unmodifiable(_skills);

  /// 将技能渲染为一段系统提示文本
  String renderSkillsBlock() {
    if (_skills.isEmpty) return '';
    final buf = StringBuffer();
    buf.writeln('### Plugin Skills from "${metadata?.name ?? pluginId}"');
    for (final skill in _skills) {
      buf.writeln('- **${skill.name}**: ${skill.description}');
    }
    return buf.toString();
  }

  // ---------------------------------------------------------------------------
  // 桥接函数（DartFunction 签名的回调）
  // ---------------------------------------------------------------------------

  /// `tessera.register_tool(def)` — 注册一个 LLM 可调用工具。
  int _bridgeRegisterTool(LuaState ls) {
    ls.checkType(1, LuaType.luaTable);

    // 读取 name
    ls.getField(1, 'name');
    final name = ls.toStr(-1);
    ls.pop(1);

    if (name == null || name.isEmpty) {
      return ls.error2('register_tool: "name" is required');
    }

    // 读取 description
    ls.getField(1, 'description');
    final description = ls.toStr(-1) ?? '';
    ls.pop(1);

    // 读取 parameters table（可选）
    ls.getField(1, 'parameters');
    Map<String, dynamic> parameters;
    if (ls.isTable(-1)) {
      parameters = LuaValueCodec.readLua(ls, -1) as Map<String, dynamic>;
    } else {
      parameters = {};
    }
    ls.pop(1);

    // 读取 handler function
    ls.getField(1, 'handler');
    if (!ls.isFunction(-1)) {
      ls.pop(1);
      return ls.error2('register_tool: "handler" must be a function');
    }

    // 在 registry 中存储 handler 函数引用
    final ref = ls.ref(luaRegistryIndex);

    _tools[name] = _PluginToolEntry(
      name: name,
      description: description,
      parameters: parameters,
      luaRef: ref,
    );

    debugPrint('[Plugin:$pluginId] registered tool "$name"');
    return 0;
  }

  /// `tessera.register_skill(def)` — 注册一个技能描述。
  int _bridgeRegisterSkill(LuaState ls) {
    ls.checkType(1, LuaType.luaTable);

    ls.getField(1, 'name');
    final name = ls.toStr(-1);
    ls.pop(1);

    ls.getField(1, 'description');
    final description = ls.toStr(-1);
    ls.pop(1);

    if (name == null || name.isEmpty) return 0;

    _skills.add(PluginSkill(
      pluginId: pluginId,
      name: name,
      description: description ?? '',
    ));

    debugPrint('[Plugin:$pluginId] registered skill "$name"');
    return 0;
  }

  /// `tessera.log(...)` — 插件日志输出。
  int _bridgeLog(LuaState ls) {
    final n = ls.getTop();
    final parts = <String>[];
    for (int i = 1; i <= n; i++) {
      final s = ls.toStr(i);
      if (s != null) {
        parts.add(s);
      } else {
        parts.add(ls.typeName(ls.type(i)));
      }
    }
    debugPrint('[Plugin:$pluginId] ${parts.join('\t')}');
    return 0;
  }

  // ---------------------------------------------------------------------------
  // 资源释放
  // ---------------------------------------------------------------------------

  /// 释放 Lua 状态和所有引用。
  void dispose() {
    debugPrint('[Plugin:$pluginId] disposing...');
    _tools.clear();
    _skills.clear();
    _initialized = false;
    // 注意：LuaDardoPlus 的 LuaState 没有显式的 close 方法，
    // 将 state 置 null 等待 GC 回收
  }
}
