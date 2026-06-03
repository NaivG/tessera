import '../models/prompt_template.dart';

/// 内置 Prompt 模板注册表
///
/// 单例，统一管理所有内部 prompt 模板。
/// 提供按名称/类别查找、变量渲染、自定义模板注册等功能。
/// 建议 Prompt 模板以英文形式编写。
///
/// 使用模式：
/// ```dart
/// final store = PromptTemplateStore.instance;
/// final rendered = store.render(
///   'topic_generation',
///   {'user_input': '你好，今天天气怎么样？'},
/// );
/// ```
class PromptTemplateStore {
  PromptTemplateStore._();

  static final PromptTemplateStore _instance = PromptTemplateStore._();

  /// 全局单例
  static PromptTemplateStore get instance => _instance;

  final Map<String, PromptTemplate> _templates = {};

  bool _initialized = false;

  /// 延迟初始化：首次访问时注册所有内置模板
  void _ensureInitialized() {
    if (_initialized) return;
    _initialized = true;
    _registerBuiltins();
  }

  // ---- 查找 ----

  /// 按名称获取模板（null 表示未找到）
  PromptTemplate? get(String name) {
    _ensureInitialized();
    return _templates[name];
  }

  /// 获取指定类别的所有模板
  List<PromptTemplate> getByCategory(PromptCategory category) {
    _ensureInitialized();
    return _templates.values.where((t) => t.category == category).toList();
  }

  /// 获取所有已注册模板
  List<PromptTemplate> get all {
    _ensureInitialized();
    return _templates.values.toList();
  }

  /// 检查模板是否存在
  bool has(String name) {
    _ensureInitialized();
    return _templates.containsKey(name);
  }

  // ---- 渲染 ----

  /// 按名称渲染模板 — 将 `{{var}}` 替换为 [variables] 中对应的值
  ///
  /// 若模板不存在则抛出 [ArgumentError]；
  /// 若缺少必需变量则抛出 [ArgumentError]。
  String render(String name, Map<String, String> variables) {
    _ensureInitialized();

    final template = _templates[name];
    if (template == null) {
      throw ArgumentError('模板 "$name" 未注册');
    }

    // 检查必需变量
    final missing = template.requiredVariables
        .where((v) => !variables.containsKey(v))
        .toList();
    if (missing.isNotEmpty) {
      throw ArgumentError('模板 "$name" 缺少变量: ${missing.join(", ")}');
    }

    // 替换占位符
    String result = template.template;
    for (final entry in variables.entries) {
      result = result.replaceAll('{{${entry.key}}}', entry.value);
    }

    return result;
  }

  /// 渲染模板但忽略缺失变量（将未被替换的占位符置空）
  String renderOrEmpty(String name, Map<String, String> variables) {
    _ensureInitialized();

    final template = _templates[name];
    if (template == null) {
      return '';
    }

    String result = template.template;
    for (final variable in template.requiredVariables) {
      result = result.replaceAll('{{$variable}}', variables[variable] ?? '');
    }

    return result;
  }

  // ---- 注册 ----

  /// 注册或覆盖一个模板
  void register(PromptTemplate template) {
    _templates[template.name] = template;
  }

  /// 批量注册模板
  void registerAll(Iterable<PromptTemplate> templates) {
    for (final t in templates) {
      _templates[t.name] = t;
    }
  }

  /// 移除一个模板
  void unregister(String name) {
    _templates.remove(name);
  }

  // ---- 内置模板 ----

  void _registerBuiltins() {
    _templates['topic_generation'] = const PromptTemplate(
      name: 'topic_generation',
      category: PromptCategory.topic,
      description: '根据用户输入生成对话主题（≤15个字符）',
      template: '''User input:

{{user_input}}

Summarize the user's input into a conversation topic of 15 characters or fewer. Use the language of the input as the output language. DO NOT include punctuation or any other content.''',
      requiredVariables: ['user_input'],
    );
  }
}
