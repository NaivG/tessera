import 'llm_provider_config.dart';

/// LLM 提供商配置（对话级别）
///
/// 保存对话所需的提供商配置快照，
/// [providerId] 实际代表格式（openai/anthropic/ollama/google），
/// 被 [ProviderFactory] 用于选择 SDK。
class LlmConfig {
  /// 提供商标识 / 格式：openai / anthropic / ollama / google
  final String providerId;

  /// 提供商显示名称（如 "DeepSeek" / "OpenAI"）
  final String providerName;

  /// 模型标识
  final String modelId;

  /// API 密钥（从设置中注入，不持久化到对话记录）
  final String? apiKey;

  /// 自定义端点（Ollama / 代理等场景）
  final String? baseUrl;

  /// 温度参数 0.0 ~ 2.0
  final double temperature;

  /// 最大输出 token 数
  final int? maxTokens;

  /// Top-P 采样
  final double? topP;

  /// 是否启用流式传输（默认 true）
  final bool stream;

  /// 是否启用深度思考（默认 false）
  final bool deepThinking;

  /// 提供商特有扩展参数
  final Map<String, dynamic> extra;

  const LlmConfig({
    required this.providerId,
    this.providerName = '',
    required this.modelId,
    this.apiKey,
    this.baseUrl,
    this.temperature = 0.7,
    this.maxTokens,
    this.topP,
    this.stream = true,
    this.deepThinking = false,
    this.extra = const {},
  });

  /// 聊天界面显示的标签：提供商名称 / 模型id
  String get chatLabel {
    final name = providerName.isNotEmpty
        ? providerName
        : LlmProviderConfig.formatDisplayName(providerId);
    return '$name/$modelId';
  }

  /// 复制并修改部分字段
  LlmConfig copyWith({
    String? providerId,
    String? providerName,
    String? modelId,
    String? apiKey,
    String? baseUrl,
    double? temperature,
    int? maxTokens,
    double? topP,
    bool? stream,
    bool? deepThinking,
    Map<String, dynamic>? extra,
    bool clearApiKey = false,
    bool clearProviderName = false,
  }) {
    return LlmConfig(
      providerId: providerId ?? this.providerId,
      providerName: clearProviderName
          ? ''
          : (providerName ?? this.providerName),
      modelId: modelId ?? this.modelId,
      apiKey: clearApiKey ? null : (apiKey ?? this.apiKey),
      baseUrl: baseUrl ?? this.baseUrl,
      temperature: temperature ?? this.temperature,
      maxTokens: maxTokens ?? this.maxTokens,
      topP: topP ?? this.topP,
      stream: stream ?? this.stream,
      deepThinking: deepThinking ?? this.deepThinking,
      extra: extra ?? Map<String, dynamic>.from(this.extra),
    );
  }

  factory LlmConfig.fromJson(Map<String, dynamic> json) {
    return LlmConfig(
      providerId: json['provider_id'] as String,
      providerName: json['provider_name'] as String? ?? '',
      modelId: json['model_id'] as String,
      apiKey: json['api_key'] as String?,
      baseUrl: json['base_url'] as String?,
      temperature: (json['temperature'] as num?)?.toDouble() ?? 0.7,
      maxTokens: json['max_tokens'] as int?,
      topP: (json['top_p'] as num?)?.toDouble(),
      stream: json['stream'] as bool? ?? true,
      deepThinking: json['deep_thinking'] as bool? ?? false,
      extra: (json['extra'] as Map<String, dynamic>?) ?? {},
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'provider_id': providerId,
      'provider_name': providerName,
      'model_id': modelId,
      'api_key': apiKey,
      'base_url': baseUrl,
      'temperature': temperature,
      'max_tokens': maxTokens,
      'top_p': topP,
      'stream': stream,
      'deep_thinking': deepThinking,
      'extra': extra,
    };
  }
}
