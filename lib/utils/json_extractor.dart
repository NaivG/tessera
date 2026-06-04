import 'dart:convert';

/// 从 LLM 响应中稳健提取 JSON 的工具。
///
/// LLM 的输出格式不可靠——有些模型会在 JSON 外包裹 markdown 代码块、
/// 解释性文字、或者前后空白。本工具采用多重容错策略，从最严格到最宽松
/// 依次尝试：
///
/// 1. 直接解析整个响应内容
/// 2. 从 markdown json 代码块中提取
/// 3. 从任意 markdown 代码块中提取
/// 4. 查找首尾定界符（`{`/`}` 或 `[`/`]`）提取
///
/// 用法：
/// ```dart
/// final result = JsonExtractor.tryExtract(response.content);
/// if (result is Map<String, dynamic>) { ... }
/// else if (result is List) { ... }
/// ```
class JsonExtractor {
  JsonExtractor._();

  /// 尝试从 [content] 中提取 JSON 对象或数组。
  ///
  /// 成功时返回 `Map<String, dynamic>` 或 `List<dynamic>`；
  /// 失败时返回 `null`。
  static dynamic tryExtract(String content) {
    if (content.isEmpty) return null;
    final trimmed = content.trim();

    // 策略 1: 直接解析
    final direct = _tryParse(trimmed);
    if (direct != null) return direct;

    // 策略 2: 从 markdown json 代码块提取
    final fromJsonBlock = _extractFromMarkdownBlock(trimmed, lang: 'json');
    if (fromJsonBlock != null) return fromJsonBlock;

    // 策略 3: 从任意 markdown 代码块提取
    final fromAnyBlock = _extractFromMarkdownBlock(trimmed);
    if (fromAnyBlock != null) return fromAnyBlock;

    // 策略 4: 从首尾定界符提取
    return _extractFromDelimiters(trimmed);
  }

  /// 提取 JSON 对象（带类型安全）。
  /// 如果提取结果是 List 则返回 null。
  static Map<String, dynamic>? tryExtractMap(String content) {
    final result = tryExtract(content);
    if (result is Map<String, dynamic>) return result;
    return null;
  }

  /// 提取 JSON 数组（带类型安全）。
  /// 如果提取结果是 Map 则返回 null。
  static List<dynamic>? tryExtractList(String content) {
    final result = tryExtract(content);
    if (result is List<dynamic>) return result;
    return null;
  }

  /// 尝试从字符串 JSON 字段中提取值。
  ///
  /// 例如从 `{"topic": "Hello"}` 中提取 `topic` 字段。
  static String? tryExtractField(String content, String fieldName) {
    final map = tryExtractMap(content);
    if (map == null) return null;
    final value = map[fieldName];
    if (value is String && value.isNotEmpty) return value;
    return null;
  }

  // -- 内部 --

  static dynamic _tryParse(String content) {
    try {
      return jsonDecode(content);
    } catch (_) {
      return null;
    }
  }

  /// 从 markdown 代码块中提取 JSON。
  /// [lang] 为 null 时匹配任意代码块。
  static dynamic _extractFromMarkdownBlock(String content, {String? lang}) {
    final langPattern = lang != null ? '(?:$lang)?' : '';
    final pattern = RegExp(
      '```$langPattern\\s*\\n(.*?)\\n\\s*```',
      dotAll: true,
    );

    for (final match in pattern.allMatches(content)) {
      final block = match.group(1)?.trim();
      if (block != null && block.isNotEmpty) {
        final parsed = _tryParse(block);
        if (parsed != null) return parsed;
      }
    }
    return null;
  }

  /// 从首尾定界符提取 JSON。
  static dynamic _extractFromDelimiters(String content) {
    // 先尝试 {} 对象
    final objStart = content.indexOf('{');
    final objEnd = content.lastIndexOf('}');
    if (objStart >= 0 && objEnd > objStart) {
      final candidate = content.substring(objStart, objEnd + 1);
      final parsed = _tryParse(candidate);
      if (parsed != null) return parsed;
    }

    // 再尝试 [] 数组
    final arrStart = content.indexOf('[');
    final arrEnd = content.lastIndexOf(']');
    if (arrStart >= 0 && arrEnd > arrStart) {
      final candidate = content.substring(arrStart, arrEnd + 1);
      final parsed = _tryParse(candidate);
      if (parsed != null) return parsed;
    }

    return null;
  }
}
