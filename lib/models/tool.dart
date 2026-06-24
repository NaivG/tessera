/// 工具定义 — 描述一个可供 LLM 调用的函数
class ToolDefinition {
  // ---------------------------------------------------------------------------
  // 类型规范化 — Lua 插件作者倾向用 `type = "table"`(Lua 里只有 table),
  // 但 JSON Schema 只认 string/number/integer/boolean/array/object/null。
  // 在出口(to*Schema)做归一化,遇到无法识别的 type 时直接抛错。
  // ---------------------------------------------------------------------------

  /// JSON Schema 标准 primitive 类型集合
  static const Set<String> _kJsonSchemaPrimitiveTypes = {
    'string', 'number', 'integer', 'boolean', 'array', 'object', 'null',
  };

  /// Lua/Python 风格的别名映射(归一化到 JSON Schema 标准类型)
  static const Map<String, String> _kLuaTypeAliases = {
    'table': 'array',   // Lua table 默认按有序数组处理
    'list': 'array',    // Python-style 别名
    'dict': 'object',   // Python-style 别名
    'int': 'integer',
    'bool': 'boolean',
    'float': 'number',
    'double': 'number',
    'str': 'string',
  };

  /// 把一个宽松的 type 字符串归一化成 JSON Schema 合规值。
  /// 已知别名静默映射;非标准 type 抛 [ArgumentError]。
  static String normalizeJsonSchemaType(String type) {
    final alias = _kLuaTypeAliases[type];
    if (alias != null) return alias;
    if (_kJsonSchemaPrimitiveTypes.contains(type)) return type;
    throw ArgumentError(
      'Invalid JSON Schema type "$type". '
      'Allowed: ${_kJsonSchemaPrimitiveTypes.join(", ")}. '
      'Lua-friendly aliases: ${_kLuaTypeAliases.keys.join(", ")}.',
    );
  }

  /// 对单个 property 的 Map 递归(浅)归一化:仅处理 `type` 字段,可能是
  /// `String`(常见)或 `List<String>`(联合类型,例如 `["string", "null"]`)。
  /// 不修改原 Map,返回新对象。
  static Map<String, dynamic> normalizeProperty(Map<String, dynamic> prop) {
    final out = Map<String, dynamic>.from(prop);
    final t = out['type'];
    if (t is String) {
      out['type'] = normalizeJsonSchemaType(t);
    } else if (t is List) {
      out['type'] = t
          .map((e) => e is String ? normalizeJsonSchemaType(e) : e)
          .toList();
    }
    return out;
  }

  /// 函数名
  final String name;

  /// 功能描述
  final String description;

  /// JSON Schema 参数定义
  final Map<String, dynamic> parameters;

  /// 自由分类标签（如 "web", "code", "file"）
  final Set<String> tags;

  /// 分层能力声明（如 "web.search", "code.execute"）
  final Set<String> capabilities;

  const ToolDefinition({
    required this.name,
    required this.description,
    this.parameters = const <String, dynamic>{},
    this.tags = const {},
    this.capabilities = const {},
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
          'properties': _normalizePropertiesMap(parameters),
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
        'properties': _normalizePropertiesMap(parameters),
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
        'properties': _normalizePropertiesMap(parameters),
        'required': _extractRequired(parameters),
      },
    };
  }

  /// 将内部 parameters 格式转换为标准 JSON Schema parameters 对象
  /// 输入：{propName: {type, description, required, ...}, ...}
  /// 输出：{type: 'object', properties: {...}, required: [...]}
  ///
  /// 每个 property 都会经过 [normalizeProperty],把 `table` 等 Lua 风格别名
  /// 翻译为 JSON Schema 标准类型,未识别的 type 抛 [ArgumentError]。
  Map<String, dynamic> toParametersSchema() {
    final properties = <String, dynamic>{};
    final required = <String>[];

    for (final entry in parameters.entries) {
      if (entry.value is Map) {
        final prop = Map<String, dynamic>.from(entry.value as Map);
        if (prop.remove('required') == true) {
          required.add(entry.key);
        }
        properties[entry.key] = normalizeProperty(prop);
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
          'properties': _normalizePropertiesMap(parameters),
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

  /// 对整个 properties Map 做归一化:只处理 value 是 Map 的 entry,
  /// 把它们的 `type` 字段映射到 JSON Schema 标准值。保留原 `required` 字段
  /// (这些 schema 方法依赖 `_extractRequired` 同时读取)。
  Map<String, dynamic> _normalizePropertiesMap(Map<String, dynamic> params) {
    final out = <String, dynamic>{};
    for (final entry in params.entries) {
      if (entry.value is Map) {
        out[entry.key] = normalizeProperty(Map<String, dynamic>.from(entry.value as Map));
      } else {
        out[entry.key] = entry.value;
      }
    }
    return out;
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
