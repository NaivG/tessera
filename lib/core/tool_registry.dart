import '../models/message.dart';
import '../models/tool.dart';

/// 工具执行器 — 定义工具的実際执行逻辑
typedef ToolHandler = Future<ToolResult> Function(ToolCall call);

/// 工具注册表 — 管理可用工具的注册、查找和执行
class ToolRegistry {
  final Map<String, ToolDefinition> _definitions = {};
  final Map<String, ToolHandler> _handlers = {};

  /// 注册一个工具
  void register(ToolDefinition definition, ToolHandler handler) {
    _definitions[definition.name] = definition;
    _handlers[definition.name] = handler;
  }

  /// 注销一个工具
  void unregister(String name) {
    _definitions.remove(name);
    _handlers.remove(name);
  }

  /// 获取所有已注册的工具定义（传给 LLM 的 tools 参数）
  List<ToolDefinition> get definitions => _definitions.values.toList();

  /// 检查工具是否已注册
  bool has(String name) => _handlers.containsKey(name);

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
  }
}
