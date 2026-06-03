/// Prompt 模板类别
enum PromptCategory {
  /// 对话主题生成
  topic,

  /// 对话摘要
  summary,

  /// 消息补全辅助
  completion,

  /// 自定义 / 扩展
  custom,
}

/// 统一的内部 Prompt 模板
///
/// 使用 `{{variable}}` 占位符标记变量位置，
/// 通过 [PromptTemplateStore.render] 注入实际参数后调用 LLM。
class PromptTemplate {
  /// 模板唯一标识，如 "topic_generation"、"summary_brief"
  final String name;

  /// 模板所属类别
  final PromptCategory category;

  /// 模板描述（便于查找和维护）
  final String description;

  /// 模板正文，使用 `{{variable}}` 标记占位符
  final String template;

  /// 所需的变量名列表（从 template 中的 `{{var}}` 自动提取）
  final List<String> requiredVariables;

  const PromptTemplate({
    required this.name,
    required this.category,
    required this.description,
    required this.template,
    required this.requiredVariables,
  });

  /// 从 JSON 反序列化
  factory PromptTemplate.fromJson(Map<String, dynamic> json) {
    return PromptTemplate(
      name: json['name'] as String,
      category: PromptCategory.values.firstWhere(
        (c) => c.name == json['category'],
        orElse: () => PromptCategory.custom,
      ),
      description: json['description'] as String? ?? '',
      template: json['template'] as String,
      requiredVariables: (json['required_variables'] as List<dynamic>?)
              ?.cast<String>() ??
          [],
    );
  }

  /// 序列化为 JSON
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'category': category.name,
      'description': description,
      'template': template,
      'required_variables': requiredVariables,
    };
  }
}
