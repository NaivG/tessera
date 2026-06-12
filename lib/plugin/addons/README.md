# addons/ — Lua 标准能力挂载

本目录存放**为 Lua 沙箱新增**的全局模块（http / json / base64 / html2md）。
所有 addon 在 `LuaPluginHost._initLuaState()` 启动序列中挂载。

> **关于 fork 修复**:LuaDardo 标准库（`os.*` / `string.*` / `math.*` ...）的 bug
> 在 fork 仓库内（`LuaDardo/`）直接修复,不再通过应用层 patchs/ 目录打补丁。
> 上游即为本仓库维护者,改动走 git 推送 → `flutter pub get` 即可生效。

## 命名约定

- 文件名：`lua_<模块名>.dart`
  - 例：`lua_http.dart`（挂载 `http` 表）
- 顶层函数：`install<Module>Addon(LuaState ls)`，对外只暴露这一个入口
- 私有回调（`_httpGet`、`_jsonEncode` 等）放在文件底部，不导出

## 当前 addons

| 文件 | 入口 | 暴露的全局 API |
| --- | --- | --- |
| `lua_http.dart` | `installHttpAddon` | `http.get/post/put/delete/request`（async） |
| `lua_json.dart` | `installJsonAddon` | `json.encode/decode`（sync） |
| `lua_base64.dart` | `installBase64Addon` | `base64.encode/decode`（sync） |
| `lua_html2md.dart` | `installHtml2mdAddon` | `html2md.convert`（sync，HTML→Markdown） |
| `lua_value_codec.dart` | （无注册入口） | Dart ↔ Lua 值互转工具，被 json/http 复用 |

## 新增 addon 步骤

1. 新建 `addons/lua_<模块名>.dart`：
   - 若模块下都是**同步**函数：直接 `ls.newLib({...})` + `ls.setGlobal('模块名')`。
   - 若模块含**异步**函数（依赖 `package:http` 等）：必须手工
     `ls.newTable()` + `ls.pushDartFunctionAsync(fn)` + `ls.setField(-2, 'name')`，
     因为 `newLib` 内部 `setFuncs` 不支持 `DartFunctionAsync`。
   - 公开 API 用纯小写名（`http`、`json`、`base64`），
     内部 Dart 回调加下划线前缀（`_httpGet`）。
2. 在 `addons/addon.dart` 中 `import` 该文件，并在 `installAddons()` 中按依赖顺序
   调用对应函数。
3. 调用方（`lua_plugin_host.dart`）**无需任何修改**——`installAddons()` 是统一入口。
4. （可选）若涉及 Dart↔Lua 值互转，复用 `lua_value_codec.dart` 而非重复实现。

## 启动序列

`LuaPluginHost._initLuaState()` 内的调用顺序：

```
newState
  → openLibs()              // LuaDardo 打开标准库
  → installAddons(state)    // 逐个挂载 addon (本目录)
  → _setupBridge()          // 注册 tessera 全局表（用户可见的桥接）
```

## 异步纪律

- `addons/` 中**声明为 `DartFunctionAsync`** 的函数（`Future<int> Function(LuaState)`），
  必须在 body 开头先把入参从栈位读出并 `ls.setTop(0)` 清栈，
  **await 期间不持有 Lua 栈引用**——async 期间 Lua VM 可能因宿主调度换出当前协程。
- 宿主已在 `loadString` 和 `callTool` 中切到 `pCallAsync`，
  异步函数在 main.lua 顶层和 tool handler 内都可用。

## 错误返回约定

addon 函数失败时遵循 Lua 惯用法：

```lua
local resp, err = http.get('https://x')
if not resp then
  tessera.log('fail: ' .. err)
  return
end
```

具体实现：失败时 `ls.pushNil(); ls.pushString('...'); return 2;`。
**不**在 addon 内抛 Lua 错误（避免中断 LLM tool handler 整体流程），
仅在类型不匹配等"调用方编程错误"时使用 `ls.checkString` 等让 Lua 错误自然抛起。

## 沙箱说明

当前所有 addon 挂载到**所有**插件的 Lua 沙箱（通过 `_initLuaState`）。
未做每插件级 addon 白名单——插件与本机 `documents/plugins/` 下用户安装的可信 zip 同级，
按需在 `PluginManager` 中引入权限声明再细化。
