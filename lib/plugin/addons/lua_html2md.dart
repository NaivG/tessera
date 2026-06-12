// =============================================================================
// html2md addon — 为 Lua 沙箱挂载 html2md.convert
//
// 安装后,Lua 可调用:
//   html2md.convert(html_str) -> markdown_str | nil, err
//
// 行为约定:
//   - 纯字符串变换,sync,可放心在 tool handler 中调用
//   - 失败时返回 (nil, err_string),与 json / base64 addon 保持一致
//   - 不在此层做大小限制:调用方(web_fetch 等)负责截断,addon 保持简单
// =============================================================================

import 'package:html2md/html2md.dart' as html2md;
import 'package:luax/lua.dart';

void installHtml2mdAddon(LuaState ls) {
  ls.newLib(<String, DartFunction>{
    'convert': _html2mdConvert,
  });
  ls.setGlobal('html2md');
}

// ---------------------------------------------------------------------------
// html2md.convert(html_str) -> markdown_str | nil, err
// ---------------------------------------------------------------------------
int _html2mdConvert(LuaState ls) {
  if (ls.type(1) != LuaType.luaString) {
    ls.pushNil();
    ls.pushString('html2md.convert: expected string argument');
    return 2;
  }
  final html = ls.toStr(1) ?? '';
  try {
    final md = html2md.convert(html);
    ls.pushString(md);
    return 1;
  } catch (e) {
    ls.pushNil();
    ls.pushString('html2md.convert failed: $e');
    return 2;
  }
}
