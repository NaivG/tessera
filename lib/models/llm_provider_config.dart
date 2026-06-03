import 'model_info.dart';

/// 统一 LLM 提供商配置模型
///
/// 这是设置级别的数据模型，用于管理用户添加的 LLM 提供商。
/// 与 [LlmProvider]（SDK 适配层）不同，本模型只存储配置信息。
///
/// 一个提供商配置包含：
/// - 名称（用户自定义，留空则使用格式名称如 "OpenAI"）
/// - 格式（决定使用哪个 SDK：openai / anthropic / ollama / google）
/// - API Key、Base URL
/// - 多个模型 ID（同一 baseUrl 可添加多个模型）
/// - 当前选中的模型
class LlmProviderConfig {
  /// 唯一标识（自动生成）
  final String id;

  /// 提供商名称（用户自定义，留空使用格式名称）
  String name;

  /// 提供商格式：openai / anthropic / ollama / google
  final String format;

  /// API Key
  String apiKey;

  /// Base URL
  String baseUrl;

  /// 模型信息列表
  List<ModelInfo> models;

  LlmProviderConfig({
    required this.id,
    this.name = '',
    required this.format,
    this.apiKey = '',
    this.baseUrl = '',
    List<ModelInfo>? models,
  }) : models = models ?? [];

  /// 模型 ID 列表（便捷访问）
  List<String> get modelIds => models.map((m) => m.id).toList();

  /// 显示名称：优先使用用户设置的名称，否则使用格式对应的默认名称
  String get displayName {
    if (name.trim().isNotEmpty) return name.trim();
    return formatDisplayName(format);
  }

  /// 格式对应的默认显示名称
  static String formatDisplayName(String format) {
    return switch (format) {
      'openai' => 'OpenAI',
      'anthropic' => 'Anthropic',
      'ollama' => 'Ollama',
      'google' => 'Google AI',
      _ => format,
    };
  }

  /// 格式对应的默认 Base URL
  static String defaultBaseUrlFor(String format) {
    return switch (format) {
      'openai' => 'https://api.openai.com/v1',
      'anthropic' => 'https://api.anthropic.com',
      'google' => 'https://generativelanguage.googleapis.com',
      'ollama' => 'http://localhost:11434',
      _ => '',
    };
  }

  /// 格式是否需要 API Key（Ollama 不需要）
  static bool formatNeedsApiKey(String format) {
    return switch (format) {
      'ollama' => false,
      _ => true,
    };
  }

  /// 复制并修改部分字段
  LlmProviderConfig copyWith({
    String? id,
    String? name,
    String? format,
    String? apiKey,
    String? baseUrl,
    List<ModelInfo>? models,
    bool clearApiKey = false,
    bool clearName = false,
    bool clearBaseUrl = false,
  }) {
    return LlmProviderConfig(
      id: id ?? this.id,
      name: clearName ? '' : (name ?? this.name),
      format: format ?? this.format,
      apiKey: clearApiKey ? '' : (apiKey ?? this.apiKey),
      baseUrl: clearBaseUrl ? '' : (baseUrl ?? this.baseUrl),
      models: models ?? List<ModelInfo>.from(this.models),
    );
  }

  /// 从 JSON 反序列化
  factory LlmProviderConfig.fromJson(Map<String, dynamic> json) {
    return LlmProviderConfig(
      id: json['id'] as String,
      name: json['name'] as String? ?? '',
      format: json['format'] as String,
      apiKey: json['api_key'] as String? ?? '',
      baseUrl: json['base_url'] as String? ?? '',
      models:
          (json['models'] as List<dynamic>?)
              ?.map((e) => ModelInfo.fromJson(e))
              .toList() ??
          [],
    );
  }

  /// 序列化为 JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'format': format,
      'api_key': apiKey,
      'base_url': baseUrl,
      'models': models.map((m) => m.toJson()).toList(),
    };
  }
}
