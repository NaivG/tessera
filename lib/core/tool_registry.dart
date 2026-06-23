import '../models/message.dart';
import '../models/tool.dart';

/// 工具执行器 — 定义工具的实际执行逻辑
typedef ToolHandler = Future<ToolResult> Function(ToolCall call);

/// 工具注册表 — 管理可用工具的注册、查找和执行
///
/// 支持 capability 与 tag 双索引，便于按具体能力或分类检索工具。
class ToolRegistry {
  final Map<String, ToolDefinition> _definitions = {};
  final Map<String, ToolHandler> _handlers = {};

  // ── 索引 ──
  /// capability → tool names
  final Map<String, Set<String>> _capabilityIndex = {};
  /// tag → tool names
  final Map<String, Set<String>> _tagIndex = {};

  /// 注册一个工具
  void register(ToolDefinition definition, ToolHandler handler) {
    _definitions[definition.name] = definition;
    _handlers[definition.name] = handler;

    for (final cap in definition.capabilities) {
      _capabilityIndex.putIfAbsent(cap, () => {}).add(definition.name);
    }
    for (final tag in definition.tags) {
      _tagIndex.putIfAbsent(tag, () => {}).add(definition.name);
    }
  }

  /// 注销一个工具
  void unregister(String name) {
    final def = _definitions.remove(name);
    _handlers.remove(name);

    if (def != null) {
      for (final cap in def.capabilities) {
        _capabilityIndex[cap]?.remove(name);
        if (_capabilityIndex[cap]?.isEmpty ?? false) {
          _capabilityIndex.remove(cap);
        }
      }
      for (final tag in def.tags) {
        _tagIndex[tag]?.remove(name);
        if (_tagIndex[tag]?.isEmpty ?? false) {
          _tagIndex.remove(tag);
        }
      }
    }
  }

  /// 获取所有已注册的工具定义（传给 LLM 的 tools 参数）
  List<ToolDefinition> get definitions => _definitions.values.toList();

  /// 检查工具是否已注册
  bool has(String name) => _handlers.containsKey(name);

  /// 获取单个工具定义
  ToolDefinition? get(String name) => _definitions[name];

  /// 按 capability 精确匹配
  List<ToolDefinition> findByCapability(String capability) {
    final names = _capabilityIndex[capability] ?? {};
    return names.map((n) => _definitions[n]!).toList();
  }

  /// 按 tag 匹配
  List<ToolDefinition> findByTag(String tag) {
    final names = _tagIndex[tag] ?? {};
    return names.map((n) => _definitions[n]!).toList();
  }

  /// 模糊搜索 name/description/capability/tag
  List<ToolDefinition> search(String query) {
    final q = query.toLowerCase();
    return _definitions.values.where((t) =>
        t.name.toLowerCase().contains(q) ||
        t.description.toLowerCase().contains(q) ||
        t.capabilities.any((c) => c.toLowerCase().contains(q)) ||
        t.tags.any((tag) => tag.toLowerCase().contains(q)),
    ).toList();
  }

  /// 执行一个工具调用
  Future<ToolResult> execute(ToolCall call) async {
    final handler = _handlers[call.name];
    if (handler == null) {
      return ToolResult(
        toolCallId: call.id,
        content: 'Tool "${call.name}" is not registered.',
        isError: true,
      );
    }

    try {
      return await handler(call);
    } catch (e) {
      return ToolResult(
        toolCallId: call.id,
        content: 'Tool "${call.name}" execution failed: $e',
        isError: true,
      );
    }
  }

  /// 批量执行工具调用
  Future<List<ToolResult>> executeAll(List<ToolCall> calls) async {
    final futures = calls.map((call) => execute(call));
    return Future.wait(futures);
  }

  /// 清空所有注册
  void clear() {
    _definitions.clear();
    _handlers.clear();
    _capabilityIndex.clear();
    _tagIndex.clear();
  }
}
