# Context Window Manager

Client-side token budget enforcement for every LLM request.

## Why a client-side budget?

Provider-side token counting is inconsistent: some APIs return usage, some
don't; the ones that do often report `prompt_tokens` only after the request
completes — too late to stop an over-budget send. Tessera estimates
**client-side** so it can:

- **Reject / compress before send.** When a conversation's projected usage
  crosses 80% of the model's context window, the manager compresses the
  oldest messages into a summary before the next call.
- **Surface live usage to the user.** The input bar shows a "12K / 128K"
  indicator that updates as messages are added; the user knows when the
  conversation is getting long.
- **Support per-model overrides.** Users can override the default context
  window per model (e.g. an Ollama model with a 32K custom context) without
  editing the source.

The system is composed of three small files plus the Riverpod glue:

| Concern | Source |
|---|---|
| Character-level CJK-aware estimator | [`lib/utils/token_counter.dart`](../../lib/utils/token_counter.dart) |
| Built-in model context window table | [`lib/utils/model_context_defaults.dart`](../../lib/utils/model_context_defaults.dart) |
| Budget + compression orchestration | [`lib/core/context_window_manager.dart`](../../lib/core/context_window_manager.dart) |
| Per-message `contextWindow` field | [`lib/models/model_info.dart`](../../lib/models/model_info.dart) |
| Persisted override map | [`lib/services/settings_service.dart`](../../lib/services/settings_service.dart) (key `_keyContextWindowOverrides`) |
| Override state (Riverpod) | [`lib/providers/settings_provider.dart`](../../lib/providers/settings_provider.dart) |
| Live indicator state | [`lib/providers/context_provider.dart`](../../lib/providers/context_provider.dart) |
| Input-bar indicator UI | [`lib/ui/widgets/message_input.dart`](../../lib/ui/widgets/message_input.dart) |
| Chat pipeline integration | [`lib/providers/chat_provider.dart`](../../lib/providers/chat_provider.dart) |

## `TokenCounter` — character-based estimation

The estimator in [`lib/utils/token_counter.dart`](../../lib/utils/token_counter.dart) is
deliberately simple and dependency-free. For any text:

1. Sample the **first 1000 runes** to compute the CJK fraction.
2. Treat CJK as `1.5 chars / token` and Latin as `4 chars / token`.
3. Scale the ratio to the full text length and `ceil()` the sum.

The CJK ranges cover:

- `U+4E00–U+9FFF` — CJK Unified Ideographs
- `U+F900–U+FAFF` — CJK Compatibility Ideographs
- `U+3040–U+30FF` — Hiragana + Katakana
- `U+AC00–U+D7AF` — Hangul Syllables
- `U+FF01–U+FF60` — Fullwidth forms
- `U+3000–U+303F` — CJK Symbols and Punctuation

For mixed Chinese/English conversations this gives a much tighter estimate
than the off-the-shelf `4 chars / token` rule. For pure English, the result
is identical to the standard heuristic.

### The four estimators

| Method | Input | Notes |
|---|---|---|
| `estimateTokens(text)` | any string | CJK-aware sampling as above |
| `estimateMessageTokens(msg)` | a `Message` | `content` + `thinking` + serialized `toolCalls` JSON + 1000 tokens per `mediaAttachment` |
| `estimateToolTokens(tools)` | list of `ToolDefinition` | serializes the OpenAI schema for each tool and estimates the resulting JSON length |
| `estimateSystemPromptTokens(prompt)` | string? | delegates to `estimateTokens` |

The 1000-tokens-per-image heuristic is the same rough number OpenAI and
Anthropic use for vision-token accounting; it errs on the side of caution.

## `ModelContextDefaults` — built-in window table

[`lib/utils/model_context_defaults.dart`](../../lib/utils/model_context_defaults.dart)
is a static `const Map<String, int> kModelContextDefaults` covering the
common models the chat pipeline actually sees:

- **OpenAI** — gpt-4o (128K), gpt-4-turbo (128K), gpt-3.5-turbo (16K), o1/o3
  family (200K), gpt-5.5-pro (1M), …
- **Anthropic** — claude-3/3.5/4 family, all 200K
- **Google** — gemini-1.5-pro (2M), gemini-1.5-flash / 2.x (1M)
- **DeepSeek** — chat / reasoner / r1 / v3 (128K), v4 (1M)
- **Minimax** — m2 series (204,800), m3 (1M)
- **Kimi** — k2 (128K), k2.6 (262,144)
- **Zhipu GLM** — glm-5.x (200K–1M)
- **Qwen** — qwen2.5/3 (128K)
- **Other** — llama3.x, mistral, mixtral, command-r

Lookup is `getContextWindow(modelId)`:

1. **Exact match** — direct map hit.
2. **Prefix match** — iterate the keys (longest first) and return the first
   one the model id starts with. Lets `gpt-4o-mini-2024-07-18` resolve to
   the `gpt-4o-mini` entry.
3. **Fallback** — 128K (deliberately generous; better to over-estimate the
   budget than to under-estimate and break long-running conversations).

### Per-model override

`ModelInfo.contextWindow` (an optional `int?` field on the model entry) lets
the user pin a specific context window for a given model. If non-null, it
overrides the defaults table. The persisted override map
(`SettingsService.getContextWindowOverrides()` / `setContextWindowOverrides()`)
adds a third tier above that: a hand-curated "always use this" map for
models not in the built-in table (Ollama deployments, custom providers, etc.).

The lookup precedence is therefore:

```
1. user override              (Map<String, int> from settings)
2. ModelInfo.contextWindow    (per-model field, optional)
3. kModelContextDefaults      (built-in table, with prefix matching)
4. 128000 fallback
```

`ContextWindowManager.getContextWindowLimit(config, {userOverride, modelInfo})`
encapsulates that cascade.

## `ContextWindowManager` — budget + compression

[`lib/core/context_window_manager.dart`](../../lib/core/context_window_manager.dart)
is the orchestrator. It owns:

- `_compressionThreshold = 0.8` — the 80% usage boundary
- `_recentRoundsToKeep = 2` — keep the last N rounds (4 messages) verbatim
- `_existingSummary` — the rolling summary from prior compressions

### `ContextBudget` snapshot

`prepareContext(...)` returns a `ContextBudget`:

```dart
class ContextBudget {
  final int    totalTokens;       // system + tools + messages + summary + reserved
  final int    contextLimit;      // resolved model context window
  final double usageRatio;        // totalTokens / contextLimit
  final bool   needsCompression;  // usageRatio > 0.8
  final int    systemTokens;
  final int    toolTokens;
  final int    messageTokens;
  final int    reservedTokens;    // config.maxTokens, or 20% of contextLimit
}
```

The reservation math:

- If `LlmConfig.maxTokens` is set, reserve that many tokens for output.
- Otherwise reserve 20% of `contextLimit` (most providers need at least
  some breathing room for the reply).
- `totalTokens` includes the reservation, so a budget that "fills" the
  context window still leaves room for the response.

### `prepareCompression` + `applyCompression`

When `needsCompression` is true, the chat pipeline calls
`prepareCompression(messages)` which returns a `(prompt, toCompress, toKeep)`
record:

- `toKeep` = the last `_recentRoundsToKeep * 2` messages (default: 4)
- `toCompress` = everything before that
- `prompt` = the compression prompt + (optionally) the existing summary
  (incremental compression) + the messages to compress formatted as a
  transcript

The pipeline then calls the LLM with this prompt and feeds the JSON
`{"summary": "..."}` back to `applyCompression(...)`, which:

1. Stores the new summary in `_existingSummary` (so the next compression
   can do incremental merge).
2. Builds an `enhancedSystemPrompt` = original system prompt + a
   `[对话历史摘要]` prefix containing the new summary.
3. Prepends a synthetic `system`-role message containing the summary to the
   `toKeep` list.
4. Returns a `CompressionResult` with `messages`, `enhancedSystemPrompt`,
   `summary`, and `compressedCount`.

### Fallback when LLM compression fails

`fallbackCompression(messages, ...)` is the last-resort path: just keep the
last `_recentRoundsToKeep * 2` messages and drop the rest. No summary, no
LLM call. The conversation effectively forgets the oldest context.

### Truncation edge cases (rare)

The plan covers two more edge cases that the manager handles but that
shouldn't trigger in practice:

- **System prompt alone > context limit** — would be truncated from the end
  and flagged with `systemPromptTruncated: true` (so the UI can show a
  warning icon on the indicator).
- **A single message > context limit** — the content is sliced with a
  `[...truncated...]` marker.

## Indicator UI

`MessageInput` ([`lib/ui/widgets/message_input.dart`](../../lib/ui/widgets/message_input.dart))
watches `contextTokenProvider` and renders an indicator next to the input:

- **Format** — `"12K / 128K"`, recomputed on every `update(...)`.
- **Color** — green (<50%), orange (50–80%), red (>80%).
- **Compression spinner** — when `ContextTokenState.isCompressing` is true,
  a small spinner replaces the percentage with "压缩中…".
- **Truncation warning** — a small icon next to the indicator if
  `systemPromptTruncated` is true.

The state is updated by `ChatNotifier` in the streaming path: after every
`provider.chatStream` call it pushes the new total to the provider, and the
indicator re-renders without a full message-list rebuild.

## Chat pipeline integration

In `ChatNotifier._sendStreaming(...)` and `_sendNonStreaming(...)`, the
flow is:

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
  final summary = await _summarizeViaLlm(prep.prompt);   // chat() against main model
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
// ...existing streaming + tool dispatch logic...
```

`_finishStreaming(...)` then optionally reconciles the estimate against the
real `TokenUsage` returned in the final `done` chunk, updating the indicator
to the provider-reported number when it disagrees with the client estimate
by a large margin (the indicator only shows the live client estimate during
streaming; the more accurate provider value takes over on completion).

`createConversation` / `enterDraft` / `clear` all reset
`ContextWindowManager._existingSummary = null` so the next conversation
starts fresh.

## See also

- [LLM Provider Abstraction](llm-providers.md) — `StreamChunk.usage` / `TokenUsage` is the cross-check used to recalibrate estimates
- [Memory System](memory-system.md) — `MemoryRetriever` is one of the system-prompt inputs whose tokens get budgeted here
- [Discover System](discover-system.md) — the compact skill catalog keeps the `toolTokens` term small
- [`lib/core/context_window_manager.dart`](../../lib/core/context_window_manager.dart) — `ContextWindowManager` source
- [`lib/utils/token_counter.dart`](../../lib/utils/token_counter.dart) — `TokenCounter` source
- [`lib/utils/model_context_defaults.dart`](../../lib/utils/model_context_defaults.dart) — built-in window table
