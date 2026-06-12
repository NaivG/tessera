// =============================================================================
// addons/ 统一入口
//
// 集中 import 本目录下的所有 addon,按依赖顺序在 [installAddons] 中调用。
// 调用方 (LuaPluginHost) 只需 `import 'addons/addon.dart';` 并在
// openLibs() 之后调用 installAddons(state),新增 addon 无需修改 host。
//
// 用途:为 Lua 沙箱新增全局模块 (http.* / json.* / base64.* / html2md.*)。
// LuaDardo 标准库 (string/os/math/...) 已有 bug 在 fork 内修,不再用 patchs/。
// =============================================================================

import 'package:flutter/foundation.dart';
import 'package:lua_dardo_plus/lua.dart';

import 'lua_base64.dart';
import 'lua_html2md.dart';
import 'lua_http.dart';
import 'lua_json.dart';

/// 对单个 [LuaState] 一次性挂载所有 addons。
///
/// 调用时机:`openLibs()` 之后、`_setupBridge()` 之前。
/// 挂载顺序:同步基础库 (json / base64 / html2md) 先于 http,这样如果 http 的
/// Dart 端有需要复用 json 工具的地方时,已经准备就绪;Lua 端调用顺序无关。
void installAddons(LuaState ls) {
  debugPrint('[LuaPluginHost] Installing Lua addons...');
  installJsonAddon(ls); // json.encode / json.decode
  installBase64Addon(ls); // base64.encode / base64.decode
  installHtml2mdAddon(ls); // html2md.convert
  installHttpAddon(ls); // http.get / post / put / delete / request
}
