// =============================================================================
// http addon — 为 Lua 沙箱挂载标准 HTTP 客户端
//
// 安装后,Lua 可调用:
//   local resp, err = http.get(url, opts?)
//   local resp, err = http.post(url, body?, opts?)
//   local resp, err = http.put(url, body?, opts?)
//   local resp, err = http.delete(url, opts?)
//   local resp, err = http.request({ method=..., url=..., body=...,
//                                    headers={...}, timeout=30, query={...} })
//
// opts 形状:
//   { headers = {['X-Foo']='bar'}, timeout = 30, query = {page=1} }
//   - headers: 字符串键映射,直接转发
//   - timeout: 秒,默认 30
//   - query:   字符串键映射,合并到 URL
//
// body 处理:
//   - nil        → 不发 body
//   - string     → 原样发送 (Content-Type 需在 headers 中显式指定)
//   - table      → JSON.encode 后发送,自动设 Content-Type: application/json
//
// 成功响应表:
//   { ok = true, status = 200, body = "...",
//     headers = { ['content-type'] = "..." }  -- 键统一小写 }
//
// 失败 (DNS 失败 / 超时 / TLS 错误 / Uri 解析失败) 返回 (nil, err_string);
// HTTP 4xx/5xx 视为成功,插件需自行检查 resp.status / resp.ok。
//
// 全部函数为 DartFunctionAsync,需在 pCallAsync 上下文中调用
// (LuaPluginHost 已切到 pCallAsync,顶层和 handler 都可用)。
// =============================================================================

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:lua_dardo_plus/lua.dart';

import 'lua_value_codec.dart';

/// 进程级单例 client,避免每次请求新建 socket pool。
final http.Client _client = http.Client();

const _defaultTimeoutSec = 30;

// ---------------------------------------------------------------------------
// 注册
// ---------------------------------------------------------------------------

/// 挂载 `http` 全局表(用 pushDartFunctionAsync 逐个挂,因为 newLib 不支持异步)
void installHttpAddon(LuaState ls) {
  ls.newTable();

  ls.pushDartFunctionAsync(_httpGet);
  ls.setField(-2, 'get');

  ls.pushDartFunctionAsync(_httpPost);
  ls.setField(-2, 'post');

  ls.pushDartFunctionAsync(_httpPut);
  ls.setField(-2, 'put');

  ls.pushDartFunctionAsync(_httpDelete);
  ls.setField(-2, 'delete');

  ls.pushDartFunctionAsync(_httpRequest);
  ls.setField(-2, 'request');

  ls.setGlobal('http');
}

// ---------------------------------------------------------------------------
// 各 verb 入口(参数位置不同,委托给 _doVerb)
// ---------------------------------------------------------------------------

Future<int> _httpGet(LuaState ls) async {
  return _doVerb(ls, 'GET', expectBody: false);
}

Future<int> _httpPost(LuaState ls) async {
  return _doVerb(ls, 'POST', expectBody: true);
}

Future<int> _httpPut(LuaState ls) async {
  return _doVerb(ls, 'PUT', expectBody: true);
}

Future<int> _httpDelete(LuaState ls) async {
  return _doVerb(ls, 'DELETE', expectBody: false);
}

// ---------------------------------------------------------------------------
// http.request({...}) 通用入口
// ---------------------------------------------------------------------------

Future<int> _httpRequest(LuaState ls) async {
  if (!ls.isTable(1)) {
    ls.setTop(0);
    ls.pushNil();
    ls.pushString('http.request: expected a table argument');
    return 2;
  }
  final cfg = LuaValueCodec.readLua(ls, 1) as Map<String, dynamic>;
  ls.setTop(0);

  final method = (cfg['method'] as String? ?? 'GET').toUpperCase();
  final url = cfg['url'] as String?;
  if (url == null || url.isEmpty) {
    ls.pushNil();
    ls.pushString('http.request: "url" is required');
    return 2;
  }

  return _executeRequest(
    ls,
    method: method,
    url: url,
    body: cfg['body'],
    headers: _asStringMap(cfg['headers']),
    timeoutSec: _asInt(cfg['timeout'], _defaultTimeoutSec),
    query: _asStringMap(cfg['query']),
  );
}

// ---------------------------------------------------------------------------
// 共享 verb 入口 (http.get/post/put/delete)
// ---------------------------------------------------------------------------

/// [expectBody] 控制第 2 个参数是 body 还是 opts。
///   false:http.get / http.delete  → arg2 = opts
///   true: http.post / http.put    → arg2 = body, arg3 = opts
Future<int> _doVerb(LuaState ls, String method,
    {required bool expectBody}) async {
  // url 是必传,checkString 在类型不匹配时抛 Lua 错误 (干净失败)
  final url = ls.checkString(1)!;

  dynamic body;
  Map<String, dynamic>? headers;
  int timeoutSec = _defaultTimeoutSec;
  Map<String, dynamic>? query;
  int optsArgIdx;

  if (expectBody) {
    if (!ls.isNoneOrNil(2)) {
      body = LuaValueCodec.readLua(ls, 2, detectArray: true);
    }
    optsArgIdx = 3;
  } else {
    optsArgIdx = 2;
  }

  if (ls.isTable(optsArgIdx)) {
    final opts = LuaValueCodec.readLua(ls, optsArgIdx) as Map<String, dynamic>;
    headers = _asStringMap(opts['headers']);
    timeoutSec = _asInt(opts['timeout'], _defaultTimeoutSec);
    query = _asStringMap(opts['query']);
  }

  // 入参读完立即清栈,async 期间不持有 Lua 栈引用
  ls.setTop(0);

  return _executeRequest(
    ls,
    method: method,
    url: url,
    body: body,
    headers: headers,
    timeoutSec: timeoutSec,
    query: query,
  );
}

// ---------------------------------------------------------------------------
// 实际执行
// ---------------------------------------------------------------------------

Future<int> _executeRequest(
  LuaState ls, {
  required String method,
  required String url,
  dynamic body,
  Map<String, dynamic>? headers,
  required int timeoutSec,
  Map<String, dynamic>? query,
}) async {
  try {
    // ---- 处理 body ----
    String? sendBody;
    final hasContentTypeHeader = headers != null &&
        headers.keys.any((k) => k.toLowerCase() == 'content-type');

    if (body != null) {
      if (body is String) {
        sendBody = body;
      } else {
        // table (Map / List) → JSON
        sendBody = jsonEncode(body);
        if (!hasContentTypeHeader) {
          headers ??= <String, dynamic>{};
          headers['Content-Type'] = 'application/json';
        }
      }
    }

    // ---- 处理 URI + query ----
    final base = Uri.parse(url);
    final queryMap = (base.hasQuery ? base.queryParametersAll : {});
    if (query != null) {
      query.forEach((k, v) {
        if (k.isNotEmpty) queryMap[k] = v;
      });
    }
    final uri = base.replace(queryParameters: queryMap.isEmpty ? null : {
      for (final e in queryMap.entries) e.key: e.value.toString()
    });

    // ---- 发请求 ----
    final req = http.Request(method, uri);
    if (headers != null) {
      headers.forEach((k, v) {
        if (k.isNotEmpty) req.headers[k] = v.toString();
      });
    }
    if (sendBody != null) req.body = sendBody;

    final streamed = await _client
        .send(req)
        .timeout(Duration(seconds: timeoutSec));
    final resp = await http.Response.fromStream(streamed);

    _pushResponseTable(ls, resp);
    return 1;
  } catch (e) {
    ls.pushNil();
    ls.pushString('http.${method.toLowerCase()} failed: $e');
    return 2;
  }
}

// ---------------------------------------------------------------------------
// 辅助
// ---------------------------------------------------------------------------

void _pushResponseTable(LuaState ls, http.Response resp) {
  ls.createTable(0, 4);

  // ok = true iff 2xx
  ls.pushBoolean(resp.statusCode >= 200 && resp.statusCode < 300);
  ls.setField(-2, 'ok');

  ls.pushInteger(resp.statusCode);
  ls.setField(-2, 'status');

  ls.pushString(resp.body);
  ls.setField(-2, 'body');

  // headers — 键统一小写,便于 Lua 端一致性访问
  ls.newTable();
  resp.headers.forEach((k, v) {
    ls.pushString(v);
    ls.setField(-2, k.toLowerCase());
  });
  ls.setField(-2, 'headers');
}

Map<String, dynamic>? _asStringMap(dynamic v) {
  if (v is Map) {
    return v.map((k, val) => MapEntry(k.toString(), val));
  }
  return null;
}

int _asInt(dynamic v, int fallback) {
  if (v is int) return v;
  if (v is double) return v.toInt();
  if (v is num) return v.toInt();
  return fallback;
}
