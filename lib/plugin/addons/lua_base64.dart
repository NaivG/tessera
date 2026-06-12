// =============================================================================
// base64 addon — 为 Lua 沙箱挂载 base64.encode / base64.decode
//
// 安装后,Lua 可调用:
//   base64.encode(str) -> string      | nil, err
//   base64.decode(str) -> string      | nil, err
//
// 字符串均按 UTF-8 字节处理,保证中文/emoji 等多字节字符 round-trip 正确。
// =============================================================================

import 'dart:convert';

import 'package:luax/lua.dart';

void installBase64Addon(LuaState ls) {
  ls.newLib(<String, DartFunction>{
    'encode': _b64Encode,
    'decode': _b64Decode,
  });
  ls.setGlobal('base64');
}

// ---------------------------------------------------------------------------
// base64.encode(str) -> string
// ---------------------------------------------------------------------------
int _b64Encode(LuaState ls) {
  if (ls.type(1) != LuaType.luaString) {
    ls.pushNil();
    ls.pushString('base64.encode: expected string argument');
    return 2;
  }
  final s = ls.toStr(1) ?? '';
  ls.pushString(base64Encode(utf8.encode(s)));
  return 1;
}

// ---------------------------------------------------------------------------
// base64.decode(str) -> string | nil, err
// ---------------------------------------------------------------------------
int _b64Decode(LuaState ls) {
  if (ls.type(1) != LuaType.luaString) {
    ls.pushNil();
    ls.pushString('base64.decode: expected string argument');
    return 2;
  }
  final s = ls.toStr(1) ?? '';
  try {
    final bytes = base64Decode(s);
    ls.pushString(utf8.decode(bytes));
    return 1;
  } catch (e) {
    ls.pushNil();
    ls.pushString('base64.decode failed: $e');
    return 2;
  }
}
