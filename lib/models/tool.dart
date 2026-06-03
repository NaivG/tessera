/// 工具定义 — 描述一个可供 LLM 调用的函数
class ToolDefinition {
  /// 函数名
  final String name;

  /// 功能描述
  final String description;

  /// JSON Schema 参数定义
  final Map<String, dynamic> parameters;

  const ToolDefinition({
    required this.name,
    required this.description,
    this.parameters = const <String, dynamic>{},
  });

  /// 转为 OpenAI / Anthropic 兼容的工具 schema
  Map<String, dynamic> toOpenAiSchema() {
    return {
      'type': 'function',
      'function': {
        'name': name,
        'description': description,
        'parameters': {
          'type': 'object',
          'properties': parameters,
          'required': _extractRequired(parameters),
        },
      },
    };
  }

  /// 转为 Anthropic 兼容的工具 schema
  Map<String, dynamic> toAnthropicSchema() {
    return {
      'name': name,
      'description': description,
      'input_schema': {
        'type': 'object',
        'properties': parameters,
        'required': _extractRequired(parameters),
      },
    };
  }

  /// 转为 Google AI 兼容的工具 schema
  Map<String, dynamic> toGoogleSchema() {
    return {
      'name': name,
      'description': description,
      'parameters': {
        'type': 'object',
        'properties': parameters,
        'required': _extractRequired(parameters),
      },
    };
  }

  /// 将内部 parameters 格式转换为标准 JSON Schema parameters 对象
  /// 输入：{propName: {type, description, required, ...}, ...}
  /// 输出：{type: 'object', properties: {...}, required: [...]}
  Map<String, dynamic> toParametersSchema() {
    final properties = <String, dynamic>{};
    final required = <String>[];

    for (final entry in parameters.entries) {
      if (entry.value is Map) {
        final prop = Map<String, dynamic>.from(entry.value as Map);
        if (prop.remove('required') == true) {
          required.add(entry.key);
        }
        properties[entry.key] = prop;
      }
    }

    return {
      'type': 'object',
      'properties': properties,
      if (required.isNotEmpty) 'required': required,
    };
  }

  /// 转为 Ollama 兼容的工具 schema
  Map<String, dynamic> toOllamaSchema() {
    return {
      'type': 'function',
      'function': {
        'name': name,
        'description': description,
        'parameters': {
          'type': 'object',
          'properties': parameters,
          'required': _extractRequired(parameters),
        },
      },
    };
  }

  List<String> _extractRequired(Map<String, dynamic> params) {
    final required = <String>[];
    for (final entry in params.entries) {
      if (entry.value is Map && (entry.value as Map)['required'] == true) {
        required.add(entry.key);
      }
    }
    return required;
  }
}

/// 工具执行结果
class ToolResult {
  /// 关联的工具调用 ID
  final String toolCallId;

  /// 结果内容（文本）
  final String content;

  /// 是否为错误结果
  final bool isError;

  const ToolResult({
    required this.toolCallId,
    required this.content,
    this.isError = false,
  });
}
