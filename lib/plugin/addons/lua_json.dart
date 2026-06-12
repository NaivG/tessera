// =============================================================================
// json addon — 为 Lua 沙箱挂载 json.encode / json.decode
//
// 安装后,Lua 可调用:
//   json.encode(value)  → string         | nil, err
//   json.decode(str)    → value (lua)    | nil, err
//
// 行为约定:
//   - encode 时:Lua table 若键集是 {1..n} 视为 JSON 数组,否则视为 JSON 对象
//   - decode 时:JSON 数组 → 整型键 1..n 的 Lua table; JSON 对象 → 字符串键 table
//   - 任何失败(类型/解析/UTF-8)返回 (nil, err_string),符合 Lua 惯例
// =============================================================================

import 'dart:convert';

import 'package:luax/lua.dart';

import 'lua_value_codec.dart';

void installJsonAddon(LuaState ls) {
  ls.newLib(<String, DartFunction>{
    'encode': _jsonEncode,
    'decode': _jsonDecode,
  });
  ls.setGlobal('json');
}

// ---------------------------------------------------------------------------
// json.encode(value) -> string | nil, err
// ---------------------------------------------------------------------------
int _jsonEncode(LuaState ls) {
  try {
    final value = LuaValueCodec.readLua(ls, 1, detectArray: true);
    final s = jsonEncode(value);
    ls.pushString(s);
    return 1;
  } catch (e) {
    ls.pushNil();
    ls.pushString('json.encode failed: $e');
    return 2;
  }
}

// ---------------------------------------------------------------------------
// json.decode(str) -> value | nil, err
// ---------------------------------------------------------------------------
int _jsonDecode(LuaState ls) {
  // 不使用 checkString,避免抛 Lua 错误中断 handler;统一以 (nil, err) 返回
  if (ls.type(1) != LuaType.luaString) {
    ls.pushNil();
    ls.pushString('json.decode: expected string argument');
    return 2;
  }
  final s = ls.toStr(1) ?? '';
  try {
    final value = jsonDecode(s);
    LuaValueCodec.pushDart(ls, value);
    return 1;
  } catch (e) {
    ls.pushNil();
    ls.pushString('json.decode failed: $e');
    return 2;
  }
}
