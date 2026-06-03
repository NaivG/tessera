import 'memory_type.dart';

/// LLM 提取结果 DTO — 由 [MemoryExtractor] 调用 LLM 后解析的结构化 JSON
///
/// LLM 返回格式示例：
/// ```json
/// [
///   {"type": "user", "content": "用户是 Python 开发者", "importance": 0.8},
///   {"type": "knowledge", "content": "Dart 3.11 支持扩展类型", "importance": 0.6}
/// ]
/// ```
class MemoryExtraction {
  /// 提取类型
  final MemoryType type;

  /// 提取的核心内容
  final String content;

  /// 重要性评分（0.0 ~ 1.0）
  final double importance;

  const MemoryExtraction({
    required this.type,
    required this.content,
    this.importance = 0.5,
  });

  /// 从 LLM 返回的 JSON Map 解析
  factory MemoryExtraction.fromJson(Map<String, dynamic> json) {
    return MemoryExtraction(
      type: memoryTypeFromName(json['type'] as String? ?? 'knowledge'),
      content: json['content'] as String,
      importance: (json['importance'] as num?)?.toDouble() ?? 0.5,
    );
  }

  /// 解析 LLM 返回的 JSON 数组
  static List<MemoryExtraction> listFromJson(dynamic jsonData) {
    if (jsonData is List) {
      return jsonData
          .map((item) => MemoryExtraction.fromJson(item as Map<String, dynamic>))
          .toList();
    }
    return [];
  }

  @override
  String toString() =>
      'MemoryExtraction(type: ${type.name}, importance: $importance, '
      'content: "${content.length > 60 ? '${content.substring(0, 60)}...' : content}")';
}
