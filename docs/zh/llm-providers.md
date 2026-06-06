# LLM 提供商抽象

本页是 Tessera 统一 LLM 提供商接口、流式协议与结构化输出处理的深入讲解。

## 概述

Tessera 通过一个统一的抽象接口 [`LlmProvider`](../../lib/core/llm_provider.dart) 与多种 LLM 后端对话。上层业务逻辑（对话流水线、能力转译、记忆子系统）从不需要直接接触 SDK 细节 —— `ProviderFactory.get(providerId)` 返回对应实例，其余代码对提供商无感知。

开箱即支持 4 家提供商：

| 提供商 | 适配器 | SDK | 备注 |
|---|---|---|---|
| OpenAI | [`openai_provider.dart`](../../lib/llm/openai_provider.dart) | `openai_dart` | 默认 base URL `https://api.openai.com/v1`；通过自定义 `baseUrl` 可对接任何 OpenAI 兼容端点 |
| Anthropic | [`anthropic_provider.dart`](../../lib/llm/anthropic_provider.dart) | `anthropic_sdk_dart` | 实时 `/models` 接口不可用时回退到硬编码模型列表 |
| Ollama | [`ollama_provider.dart`](../../lib/llm/ollama_provider.dart) | `ollama_dart` | 本地部署；默认 `baseUrl` 为 `http://localhost:11434`；无需 API key |
| Google AI | [`google_provider.dart`](../../lib/llm/google_provider.dart) | `googleai_dart` | Gemini 模型；同样有硬编码回退列表 |

新增提供商的接入面很小：实现 `LlmProvider`、在 [`ProviderFactory._create`](../../lib/llm/provider_factory.dart) 中注册一条 switch 分支，再加一条 `LlmProviderConfig` 格式配置项即可。不存在独立的"adapter"接口 —— **提供商实现本身就是 adapter**。

## `LlmProvider` 接口

定义见 [`lib/core/llm_provider.dart`](../../lib/core/llm_provider.dart)：

```dart
abstract class LlmProvider {
  String get providerId;          // 例如 "openai"、"anthropic"、"ollama"、"google"
  String get displayName;         // 人读标签

  Future<List<ModelInfo>> listAvailableModels({String? apiKey, String? baseUrl});
  Future<ModelInfo?>    getModelInfo(String modelId, {String? apiKey, String? baseUrl});

  Future<bool> validateConfig(LlmConfig config);

  Future<Message> chat({
    required LlmConfig config,
    required List<Message> history,
    String? systemPrompt,
    List<ToolDefinition>? tools,
  });

  Stream<StreamChunk> chatStream({
    required LlmConfig config,
    required List<Message> history,
    String? systemPrompt,
    List<ToolDefinition>? tools,
  });
}
```

- `listAvailableModels` 给设置页用来填充模型下拉框。请求失败时 adapter 返回空列表或硬编码回退列表（Anthropic + Google 走后者，离线时用户依然能选模型）。
- `validateConfig` 是保存前的烟测（API key 格式、base URL 可达性）。
- `chat` 是非流式路径，供记忆抽取器 / 摘要器 / 合并器使用（见 [记忆系统](memory-system.md)）。
- `chatStream` 是主路径；对话提供方会多路复用多个流，把 `StreamChunk` 喂给 UI。

## 提供商配置

提供商配置以 [`LlmProviderConfig`](../../lib/models/llm_provider_config.dart) 形式持久化在用户设置里（每个 provider 一个 config，每个 config 包含多个 model）。关键字段：

| 字段 | 说明 |
|---|---|
| `id` | UUID —— `ModelSlot.providerConfigId` 引用的稳定句柄 |
| `format` | `openai` / `anthropic` / `ollama` / `google` 之一 —— 决定 SDK adapter 与默认 base URL |
| `name` | 可选用户友好标签；为空时回退到 `formatDisplayName(format)` |
| `apiKey` | 云端提供商必填；Ollama 不需要（`formatNeedsApiKey('ollama') == false`） |
| `baseUrl` | 可选覆盖；默认走 `defaultBaseUrlFor(format)` |
| `models` | `ModelInfo` 列表（uid、id、displayName、capabilities、modelType） |

`LlmConfig` 是 adapter 真正消费的运行时形态，由 `ModelSlot` + `SettingsState` 按需构建（详见 [能力转译](capability-adapter.md) 中的解析流程）。

## Provider 工厂

[`ProviderFactory`](../../lib/llm/provider_factory.dart) 是一个按 `providerId` 索引的静态单例表：

```dart
ProviderFactory.get('openai')    // → OpenAiProvider()
ProviderFactory.get('anthropic') // → AnthropicProvider()
ProviderFactory.get('ollama')    // → OllamaProvider()
ProviderFactory.get('google')    // → GoogleProvider()
ProviderFactory.isSupported('foo') // false → throws ArgumentError
```

`allProviders` 返回每家一个实例 —— 设置页用它驱动"新增 provider"对话框中的格式下拉框。

## 流式协议

所有提供商都把各自的 SDK 事件归一化为统一的 [`Stream<StreamChunk>`](../../lib/models/stream_chunk.dart) —— 这是对话流水线消费的契约。

### `StreamChunk` 结构

```dart
class StreamChunk {
  final StreamChunkType type;       // 判别字段
  final String? contentDelta;       // 文本增量（contentDelta）
  final String? thinkingDelta;      // 思维链增量（thinkingDelta）
  final ToolCall? toolCall;         // 函数调用（toolCall；可能增量）
  final TokenUsage? usage;          // 总额，done 阶段送达
  final String? error;              // 错误信息（error）
}
```

### `StreamChunkType` 枚举

| 变体 | 携带 | 说明 |
|---|---|---|
| `contentDelta` | `contentDelta` | 实际的回复文本片段 |
| `thinkingDelta` | `thinkingDelta` | 思维链 / 推理过程；UI 中独立展示 |
| `toolCall` | `toolCall` | 模型发出的函数调用；可能以增量形式到达 |
| `done` | `usage`（可选） | 流终止；`usage` 是送达 `TokenUsage` 的最后时机 |
| `error` | `error` | 致命流错误；对话流水线把它展示在 UI 中 |

便捷构造器（`StreamChunk.content(...)`、`.thinking(...)`、`.tool(...)`、`.done(usage: ...)`、`.error(...)`）让调用方代码更易读。

### `TokenUsage`

随最后一个 `done` 块一起送达：

```dart
class TokenUsage {
  final int? promptTokens;
  final int? completionTokens;
  final int? totalTokens;
}
```

对话流水线把它附在 assistant `Message` 上，用于下游用量统计（stats 页面里的 per-provider token 计数就是这套字段）。

### 多路复用

`ChatNotifier`（[`lib/providers/chat_provider.dart`](../../lib/providers/chat_provider.dart)）会并行消费多个流（例如主模型 + 通过能力转译调起的视觉子模型），并维护一个完成集合，以便判断何时可以渲染最终消息。

## 结构化输出

多个子系统需要 LLM **只**返回 JSON —— 记忆抽取器、滚动对话摘要器、记忆合并器、插件技能注册 prompt。LLM 输出天生不稳定：有的会把 JSON 包进 markdown 代码块、有的会追加解释性文字、有的会带零散空白。

Tessera 用 [`JsonExtractor`](../../lib/utils/json_extractor.dart) 解决 —— 一个由严到松的 4 步回退解析器：

| # | 策略 | 处理场景 |
|---|---|---|
| 1 | 直接 `jsonDecode` | 干净的 JSON 响应 |
| 2 | Markdown json 代码块 | ` ```json ... ``` ` |
| 3 | 任意 markdown 代码块 | ` ``` ... ``` ` |
| 4 | 首尾定界符扫描（`{`/`}` 或 `[`/`]`） | JSON 前后有杂文本 |

便捷方法提供类型安全访问：

- `tryExtract(content)` → `Map | List | null`
- `tryExtractMap(content)` → `Map<String, dynamic> | null`
- `tryExtractList(content)` → `List<dynamic> | null`
- `tryExtractField(content, fieldName)` → `String | null`（从 map 结果中取单个字符串字段）

若所有策略都失败，调用方会回退到对响应做 best-effort `trim()`。

### Prompt 纪律

除了鲁棒解析外，辅助 prompt 还会显式要求纯 JSON 输出 —— 例如抽取 prompt 的结尾是：

> 返回 ONLY 一个 JSON 数组 — 不要 markdown 代码块、不要解释、不要其他任何文字。
> 如果没有值得记忆的内容，返回空数组 []。

"严格 prompt + 宽松 parser" 两层组合，让系统在 4 家提供商之间都能保持稳定，无需针对某个模型做 prompt 调优。

## 新增提供商

清单：

1. **新建 adapter**：`lib/llm/<id>_provider.dart`，实现 `LlmProvider`。现有 4 个 adapter 都是好模板 —— 共享同样的形状：一个 `_buildClient(LlmConfig)` 私有方法、一个 `_xxxModelToModelInfo` 映射函数、4 个 public 方法。
2. **注册 adapter**：在 [`ProviderFactory._create`](../../lib/llm/provider_factory.dart) 中加 switch 分支，并把 id 加入 `isSupported`。
3. **加入格式配置项**：在 [`LlmProviderConfig`](../../lib/models/llm_provider_config.dart) 的 `formatDisplayName` / `defaultBaseUrlFor` / `formatNeedsApiKey` switch 中各加一条。
4. **UI 暴露**：设置页使用 `ProviderFactory.allProviders` 和上面的格式 switch，所以一旦配置项就位，新提供商就会自动出现在"新增 provider"对话框中。
5. **工具 schema 支持**：如果新 SDK 有自己的 function-calling wire format，给 [`ToolDefinition`](../../lib/models/tool.dart) 加一个对应的 `toXxxSchema()` 方法。OpenAI / Anthropic / Google / Ollama 的 4 套实现是范本。

## 参见

- [能力转译](capability-adapter.md) —— 用 `LlmProvider` 接口驱动视觉 / 音频 / 图像 / 语音子模型
- [记忆系统](memory-system.md) —— `chat()`（非流式）与 `JsonExtractor` 的最重消费者
- [插件系统](plugin-system.md) —— 插件工具调用共享同一个 `ToolDefinition` / `ToolCall` / `ToolResult` 信封
- [`lib/models/stream_chunk.dart`](../../lib/models/stream_chunk.dart) —— 流式契约
- [`lib/models/tool.dart`](../../lib/models/tool.dart) —— 工具调用信封
- [`lib/utils/json_extractor.dart`](../../lib/utils/json_extractor.dart) —— 结构化输出解析器
