import '../core/llm_provider.dart';
import 'openai_provider.dart';
import 'anthropic_provider.dart';
import 'ollama_provider.dart';
import 'google_provider.dart';

/// 提供商工厂 — 根据 providerId 返回对应的 LlmProvider 实例
class ProviderFactory {
  static final Map<String, LlmProvider> _instances = {};

  /// 获取或创建 provider 实例（单例）
  static LlmProvider get(String providerId) {
    return _instances.putIfAbsent(providerId, () => _create(providerId));
  }

  static LlmProvider _create(String providerId) {
    return switch (providerId) {
      'openai' => OpenAiProvider(),
      'anthropic' => AnthropicProvider(),
      'ollama' => OllamaProvider(),
      'google' => GoogleProvider(),
      _ => throw ArgumentError('Unsupported provider: $providerId'),
    };
  }

  /// 获取所有可用的 provider 列表
  static List<LlmProvider> get allProviders => [
    OpenAiProvider(),
    AnthropicProvider(),
    OllamaProvider(),
    GoogleProvider(),
  ];

  /// 检查 providerId 是否受支持
  static bool isSupported(String providerId) {
    return ['openai', 'anthropic', 'ollama', 'google'].contains(providerId);
  }
}
