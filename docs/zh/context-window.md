# 上下文窗口管理

每次 LLM 请求的客户端 token 预算强制。

## 为什么需要客户端预算？

Provider 侧的 token 计数并不一致：有的 API 返回 usage，有的没有；返回的那些又往往在请求**结束之后**才给 `prompt_tokens` —— 这时再想拦下一次超限请求已经太晚。Tessera 选择在**客户端**估算，以便：

- **发送前拒绝 / 压缩。** 当一段对话预计用量超过模型上下文窗口的 80% 时，manager 在下次调用前把最早的消息压成摘要。
- **把实时用量展示给用户。** 输入框旁显示「12K / 128K」指示器，会随消息增长实时变化，用户一眼就知道对话是不是太长了。
- **支持 per-model 覆盖。** 用户可以为某个模型单独覆盖默认窗口（比如一个 32K 自定义上下文的 Ollama 模型），不用改源码。

系统由三个小文件加上 Riverpod 黏合层组成：

| 关注点 | 位置 |
|---|---|
| 字符级 CJK 感知估算 | [`lib/utils/token_counter.dart`](../../lib/utils/token_counter.dart) |
| 内置模型上下文窗口表 | [`lib/utils/model_context_defaults.dart`](../../lib/utils/model_context_defaults.dart) |
| 预算 + 压缩编排 | [`lib/core/context_window_manager.dart`](../../lib/core/context_window_manager.dart) |
| `ModelInfo.contextWindow` 字段 | [`lib/models/model_info.dart`](../../lib/models/model_info.dart) |
| 持久化覆盖 map | [`lib/services/settings_service.dart`](../../lib/services/settings_service.dart)（key 为 `_keyContextWindowOverrides`） |
| 覆盖状态（Riverpod） | [`lib/providers/settings_provider.dart`](../../lib/providers/settings_provider.dart) |
| 实时指示器状态 | [`lib/providers/context_provider.dart`](../../lib/providers/context_provider.dart) |
| 输入框指示器 UI | [`lib/ui/widgets/message_input.dart`](../../lib/ui/widgets/message_input.dart) |
| Chat pipeline 集成 | [`lib/providers/chat_provider.dart`](../../lib/providers/chat_provider.dart) |

## `TokenCounter` —— 基于字符的估算

[`lib/utils/token_counter.dart`](../../lib/utils/token_counter.dart) 里的估算器刻意保持简单且无依赖。对任意文本：

1. 取**前 1000 个 rune** 计算 CJK 占比。
2. CJK 按 `1.5 chars / token`，拉丁按 `4 chars / token`。
3. 把比例扩展到全文长度，再 `ceil()` 求和。

CJK 范围覆盖：

- `U+4E00–U+9FFF` —— CJK 统一表意文字
- `U+F900–U+FAFF` —— CJK 兼容表意文字
- `U+3040–U+30FF` —— 平假名 + 片假名
- `U+AC00–U+D7AF` —— 韩文音节
- `U+FF01–U+FF60` —— 全角形式
- `U+3000–U+303F` —— CJK 符号与标点

对中英混排的对话，这比通用的 `4 chars / token` 估算要准得多；纯英文场景下与标准启发式等价。

### 四个估算方法

| 方法 | 输入 | 说明 |
|---|---|---|
| `estimateTokens(text)` | 任意字符串 | 如上 CJK 感知采样 |
| `estimateMessageTokens(msg)` | `Message` | `content` + `thinking` + 序列化后的 `toolCalls` JSON + 每张 `mediaAttachment` 1000 token |
| `estimateToolTokens(tools)` | `ToolDefinition` 列表 | 序列化每个工具的 OpenAI schema，再估算 JSON 长度 |
| `estimateSystemPromptTokens(prompt)` | string? | 委托给 `estimateTokens` |

1000-token-per-image 的启发式和 OpenAI、Anthropic 用于视觉 token 估算的粗略数字一致；宁多勿少。

## `ModelContextDefaults` —— 内置窗口表

[`lib/utils/model_context_defaults.dart`](../../lib/utils/model_context_defaults.dart)
是一个静态 `const Map<String, int> kModelContextDefaults`，覆盖 chat pipeline 实际会遇到的常见模型：

- **OpenAI** —— gpt-4o（128K）、gpt-4-turbo（128K）、gpt-3.5-turbo（16K）、o1/o3 系列（200K）、gpt-5.5-pro（1M）、……
- **Anthropic** —— claude-3/3.5/4 系列，全部 200K
- **Google** —— gemini-1.5-pro（2M）、gemini-1.5-flash / 2.x（1M）
- **DeepSeek** —— chat / reasoner / r1 / v3（128K）、v4（1M）
- **Minimax** —— m2 系列（204,800）、m3（1M）
- **Kimi** —— k2（128K）、k2.6（262,144）
- **Zhipu GLM** —— glm-5.x（200K–1M）
- **Qwen** —— qwen2.5/3（128K）
- **其他** —— llama3.x、mistral、mixtral、command-r

`getContextWindow(modelId)` 的查找顺序：

1. **精确匹配** —— 直接命中 map。
2. **前缀匹配** —— 按 key 长度降序遍历，返回第一个 model id 以其开头的条目。这样 `gpt-4o-mini-2024-07-18` 会落到 `gpt-4o-mini` 上。
3. **回退** —— 128K（故意给得宽松；高估预算好过低估、避免打断长对话）。

### Per-model 覆盖

`ModelInfo.contextWindow`（模型条目上的可选 `int?` 字段）让用户能为某个模型钉死上下文窗口。非空时它会覆盖默认表。持久化的覆盖 map（`SettingsService.getContextWindowOverrides()` / `setContextWindowOverrides()`）在它之上再加一层：一张「永远用这个」的手工 map，专治不在内置表里的模型（Ollama、自建 provider 等）。

查找优先级为：

```
1. 用户覆盖              （settings 里的 Map<String, int>）
2. ModelInfo.contextWindow  （per-model 字段，可选）
3. kModelContextDefaults   （内置表，带前缀匹配）
4. 128000 回退值
```

`ContextWindowManager.getContextWindowLimit(config, {userOverride, modelInfo})` 封装了这套级联。

## `ContextWindowManager` —— 预算 + 压缩

[`lib/core/context_window_manager.dart`](../../lib/core/context_window_manager.dart) 是编排者。它持有：

- `_compressionThreshold = 0.8` —— 80% 用量阈值
- `_recentRoundsToKeep = 2` —— 原样保留最近 N 轮（4 条消息）
- `_existingSummary` —— 上一轮压缩留下的滚动摘要

### `ContextBudget` 快照

`prepareContext(...)` 返回一个 `ContextBudget`：

```dart
class ContextBudget {
  final int    totalTokens;       // system + tools + messages + summary + reserved
  final int    contextLimit;      // 解析出的模型上下文窗口
  final double usageRatio;        // totalTokens / contextLimit
  final bool   needsCompression;  // usageRatio > 0.8
  final int    systemTokens;
  final int    toolTokens;
  final int    messageTokens;
  final int    reservedTokens;    // config.maxTokens，或 contextLimit 的 20%
}
```

预留逻辑：

- 若 `LlmConfig.maxTokens` 已设置，预留这么多 token 给输出。
- 否则预留 `contextLimit` 的 20%（多数 provider 至少需要这点余量给回复）。
- `totalTokens` 包含预留部分，所以「塞满」上下文的预算也还留有回复空间。

### `prepareCompression` + `applyCompression`

`needsCompression` 为 true 时，chat pipeline 调用 `prepareCompression(messages)`，拿到一个 `(prompt, toCompress, toKeep)` 三元组：

- `toKeep` = 最后 `_recentRoundsToKeep * 2` 条消息（默认 4 条）
- `toCompress` = 那之前的所有消息
- `prompt` = 压缩 prompt +（可选）已有摘要（增量压缩）+ 待压缩消息的转录

接着 pipeline 用这个 prompt 调用 LLM，把返回的 JSON `{"summary": "..."}` 喂给 `applyCompression(...)`，它会：

1. 把新摘要存进 `_existingSummary`（下一轮压缩就可以做增量合并）。
2. 构造 `enhancedSystemPrompt` = 原始系统提示词 + 一段 `[对话历史摘要]` 前缀。
3. 在 `toKeep` 列表最前面插入一条携带摘要的合成 `system` 角色消息。
4. 返回 `CompressionResult`，含 `messages`、`enhancedSystemPrompt`、`summary`、`compressedCount`。

### 压缩失败时的 Fallback

`fallbackCompression(messages, ...)` 是最后一道兜底：只保留最后 `_recentRoundsToKeep * 2` 条消息，剩下的直接丢；不调 LLM、不生成摘要。对话相当于「忘掉」了最早的上下文。

### 罕见的截断边界

plan 还覆盖了两个 manager 会处理但实际不应触发的边界：

- **系统提示词本身超过 context limit** —— 从末尾截断，并打 `systemPromptTruncated: true` 标记（这样 UI 可以在指示器旁显示警告图标）。
- **单条消息超过 context limit** —— 把内容切片并加 `[...truncated...]` 标记。

## 指示器 UI

`MessageInput`（[`lib/ui/widgets/message_input.dart`](../../lib/ui/widgets/message_input.dart)）监听 `contextTokenProvider` 并在输入框旁渲染一个指示器：

- **格式** —— `"12K / 128K"`，每次 `update(...)` 重算。
- **颜色** —— 绿（<50%）、橙（50–80%）、红（>80%）。
- **压缩中 spinner** —— `ContextTokenState.isCompressing` 为 true 时，一个小 spinner 把百分比替换为「压缩中…」。
- **截断警告** —— 若 `systemPromptTruncated` 为 true，指示器旁显示一个小图标。

状态由 `ChatNotifier` 在流式路径中更新：每次 `provider.chatStream` 调用之后把新的 total 推到 provider，指示器重渲染但不需要整个消息列表 rebuild。

## Chat pipeline 集成

在 `ChatNotifier._sendStreaming(...)` 与 `_sendNonStreaming(...)` 中，流程是：

```dart
final contextLimit = _getContextLimit(conv.config);
final budget = _contextManager.prepareContext(
  conversation: conv,
  systemPrompt: systemPrompt,
  tools: tools,
  userOverride: ref.read(settingsProvider).getContextWindowOverride(conv.config.modelId),
  modelInfo: resolveModelInfo(conv.config),
);

if (budget.needsCompression) {
  ref.read(contextTokenProvider.notifier).setCompressing(true);
  final prep = _contextManager.prepareCompression(conv.messages);
  final summary = await _summarizeViaLlm(prep.prompt);   // 用主模型调 chat()
  final compressed = _contextManager.applyCompression(
    summary: summary,
    toKeep: prep.toKeep,
    originalSystemPrompt: systemPrompt,
  );
  history = compressed.messages;
  effectiveSystemPrompt = compressed.enhancedSystemPrompt ?? systemPrompt;
  ref.read(contextTokenProvider.notifier).setCompressing(false);
}

ref.read(contextTokenProvider.notifier).update(budget.totalTokens, contextLimit);
final stream = provider.chatStream(
  config: conv.config,
  history: history,
  systemPrompt: effectiveSystemPrompt,
  tools: tools,
);
// ...既有流式 + 工具分发逻辑...
```

`_finishStreaming(...)` 可选地会把估算值与 `done` chunk 里返回的真实 `TokenUsage` 对齐 —— 当两者差异显著时，用 provider 报告的数字覆盖估算（流式中始终显示客户端估算，结束时切换到更准的 provider 值）。

`createConversation` / `enterDraft` / `clear` 都会重置
`ContextWindowManager._existingSummary = null`，让下一段对话从干净状态开始。

## 参见

- [LLM 提供商抽象](llm-providers.md) —— `StreamChunk.usage` / `TokenUsage` 是用来校准估算的交叉验证
- [记忆系统](memory-system.md) —— `MemoryRetriever` 检索结果是被预算计入的若干系统提示词输入之一
- [发现系统](discover-system.md) —— 紧凑的 skill 目录让 `toolTokens` 项保持小
- [`lib/core/context_window_manager.dart`](../../lib/core/context_window_manager.dart) —— `ContextWindowManager` 源码
- [`lib/utils/token_counter.dart`](../../lib/utils/token_counter.dart) —— `TokenCounter` 源码
- [`lib/utils/model_context_defaults.dart`](../../lib/utils/model_context_defaults.dart) —— 内置窗口表
