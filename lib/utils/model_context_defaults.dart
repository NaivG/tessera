/// 常见模型的上下文窗口默认值
///
/// 提供模型 ID → 上下文窗口 Token 数的映射。
/// 支持精确匹配和前缀匹配（如 "gpt-4o-mini" 前缀匹配 "gpt-4o" 的默认值）。
library;

/// 已知模型的上下文窗口（Token 数）
const Map<String, int> kModelContextDefaults = {
  // ── OpenAI ──
  'gpt-4o': 128000,
  'gpt-4o-mini': 128000,
  'gpt-4-turbo': 128000,
  'gpt-4': 8192,
  'gpt-4-32k': 32768,
  'gpt-3.5-turbo': 16384,
  'gpt-3.5-turbo-16k': 16384,
  'o1': 200000,
  'o1-mini': 128000,
  'o3-mini': 200000,
  'o3': 200000,
  'o4-mini': 200000,
  'gpt-5': 128000,
  'gpt-5.4': 1000000,
  'gpt-5.5': 1000000,
  'gpt-5.5-pro': 1000000,

  // ── Anthropic Claude ──
  'claude-3-opus': 200000,
  'claude-3.5-sonnet': 200000,
  'claude-3.5-haiku': 200000,
  'claude-3-haiku': 200000,
  'claude-3-sonnet': 200000,
  'claude-4': 200000,
  'claude-4-sonnet': 200000,
  'claude-4-opus': 200000,

  // ── Google Gemini ──
  'gemini-1.5-pro': 2000000,
  'gemini-1.5-flash': 1000000,
  'gemini-2.0-flash': 1000000,
  'gemini-2.5-pro': 1000000,
  'gemini-2.5-flash': 1000000,

  // ── DeepSeek ──
  'deepseek-chat': 128000,
  'deepseek-reasoner': 128000,
  'deepseek-r1': 128000,
  'deepseek-v3': 128000,
  'deepseek-v4-flash': 1000000,
  'deepseek-v4-pro': 1000000,

  // ── Minimax ──
  'minimax-m2': 204800,
  'minimax-m2.1': 204800,
  'minimax-m2.5': 204800,
  'minimax-m2.7': 204800,
  'minimax-m3': 1000000,

  // ── Kimi ──
  'kimi-k2': 128000,
  'kimi-k2.5': 128000,
  'kimi-k2.6': 262144,

  // ── Zhipu ──
  'glm-5': 200000,
  'glm-5.1': 200000,
  'glm-5.2': 1000000,

  // ── Qwen ──
  // Qwen家族太多了，这里只列出最常用的
  'qwen2.5': 128000,
  'qwen3': 128000,

  // ── Other ──
  'llama3': 8192,
  'llama3.1': 128000,
  'llama3.2': 128000,
  'llama3.3': 128000,
  'codellama': 16384,
  'mixtral': 32768,
  'mistral': 8192,
  'mistral-large': 128000,
  'mistral-small': 32000,
  'command-r': 128000,
  'command-r-plus': 128000,
};

/// 未在默认值表中匹配到模型时的回落值
const int _kFallbackContextWindow = 128000;

/// 查找模型的上下文窗口。
///
/// 查找顺序：
/// 1. 精确匹配模型 ID
/// 2. 前缀匹配（如 "gpt-4o-mini-2024-07-18" 匹配 "gpt-4o-mini" 键）
/// 3. 回落值 [_kFallbackContextWindow]
int getContextWindow(String modelId) {
  // 精确匹配
  if (kModelContextDefaults.containsKey(modelId)) {
    return kModelContextDefaults[modelId]!;
  }

  // 前缀匹配：按键长降序排序，确保更长的前缀优先匹配
  final sortedKeys = kModelContextDefaults.keys.toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  for (final key in sortedKeys) {
    if (modelId.toLowerCase().startsWith(key.toLowerCase())) {
      return kModelContextDefaults[key]!;
    }
  }

  return _kFallbackContextWindow;
}
