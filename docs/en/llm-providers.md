# LLM Provider Abstraction

Tessera's unified LLM provider interface, streaming protocol, and structured-output handling.

## Overview

Tessera talks to multiple LLM backends through a single abstract interface, [`LlmProvider`](../../lib/core/llm_provider.dart). Business logic (the chat pipeline, the capability adapter, the memory subsystem) never touches SDK specifics — `ProviderFactory.get(providerId)` returns the right instance and the rest of the app is provider-agnostic.

Four providers ship in the box:

| Provider | Adapter | SDK | Notes |
|---|---|---|---|
| OpenAI | [`openai_provider.dart`](../../lib/llm/openai_provider.dart) | `openai_dart` | Default base URL `https://api.openai.com/v1`; supports any OpenAI-compatible endpoint via custom `baseUrl` |
| Anthropic | [`anthropic_provider.dart`](../../lib/llm/anthropic_provider.dart) | `anthropic_sdk_dart` | Falls back to a hard-coded model list when the live `/models` endpoint is unavailable |
| Ollama | [`ollama_provider.dart`](../../lib/llm/ollama_provider.dart) | `ollama_dart` | Local; default `baseUrl` is `http://localhost:11434`; no API key required |
| Google AI | [`google_provider.dart`](../../lib/llm/google_provider.dart) | `googleai_dart` | Gemini models; also has a hard-coded fallback list |

Adding a new provider is intentionally a small surface: implement `LlmProvider`, register in [`ProviderFactory._create`](../../lib/llm/provider_factory.dart), and add a corresponding `LlmProviderConfig` format entry. There is no separate "adapter" interface; the providers *are* the adapters.

## The `LlmProvider` Interface

Defined in [`lib/core/llm_provider.dart`](../../lib/core/llm_provider.dart):

```dart
abstract class LlmProvider {
  String get providerId;          // e.g. "openai", "anthropic", "ollama", "google"
  String get displayName;         // human-readable label

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

- `listAvailableModels` is used by the Settings page to populate the model dropdown. When the network call fails, adapters return either an empty list or a hard-coded fallback (Anthropic + Google do the latter so users can still pick a model offline).
- `validateConfig` is a smoke test (API key format, base URL reachability) before saving a provider config.
- `chat` is the non-streaming path used by the memory extractor / summarizer / compressor (see [Memory System](memory-system.md)).
- `chatStream` is the primary path; the chat provider multiplexes multiple streams and feeds `StreamChunk`s into the UI.

## Provider Configuration

Provider configs are stored as [`LlmProviderConfig`](../../lib/models/llm_provider_config.dart) in the user's settings (one config per provider instance, multiple models per config). The key fields:

| Field | Notes |
|---|---|
| `id` | UUID — the stable handle used by `ModelSlot.providerConfigId` |
| `format` | One of `openai` / `anthropic` / `ollama` / `google` — drives the SDK adapter and the default base URL |
| `name` | Optional user-friendly label; falls back to `formatDisplayName(format)` |
| `apiKey` | Required for cloud providers; Ollama doesn't need one (`formatNeedsApiKey('ollama') == false`) |
| `baseUrl` | Optional override; defaults via `defaultBaseUrlFor(format)` |
| `models` | List of `ModelInfo` (uid, id, displayName, capabilities, modelType) |

`LlmConfig` is the runtime shape that the adapters consume — it's built on demand from a `ModelSlot` + a `SettingsState` (see [Capability Adapter](capability-adapter.md) for the resolution flow).

## The Provider Factory

[`ProviderFactory`](../../lib/llm/provider_factory.dart) is a static singleton map keyed by `providerId`:

```dart
ProviderFactory.get('openai')    // → OpenAiProvider()
ProviderFactory.get('anthropic') // → AnthropicProvider()
ProviderFactory.get('ollama')    // → OllamaProvider()
ProviderFactory.get('google')    // → GoogleProvider()
ProviderFactory.isSupported('foo') // false → throws ArgumentError
```

`allProviders` returns one instance of each — used by the Settings page to drive the format-picker dropdown.

## Streaming Protocol

All providers normalize their SDK events into a single [`Stream<StreamChunk>`](../../lib/models/stream_chunk.dart). This is the contract the chat pipeline consumes.

### `StreamChunk` shape

```dart
class StreamChunk {
  final StreamChunkType type;       // discriminator
  final String? contentDelta;       // text delta (for contentDelta)
  final String? thinkingDelta;      // reasoning delta (for thinkingDelta)
  final ToolCall? toolCall;         // function call (for toolCall; may be incremental)
  final TokenUsage? usage;          // totals, delivered in done
  final String? error;              // error message (for error)
}
```

### `StreamChunkType` enum

| Variant | Carries | Notes |
|---|---|---|
| `contentDelta` | `contentDelta` | The actual reply text, piece by piece |
| `thinkingDelta` | `thinkingDelta` | Chain-of-thought / reasoning content; surfaced separately in the UI |
| `toolCall` | `toolCall` | Function call emitted by the model; the LLM may stream this incrementally |
| `done` | `usage` (optional) | Stream terminator; `usage` is the last-chance place to deliver `TokenUsage` |
| `error` | `error` | Fatal stream error; chat pipeline surfaces it in the UI |

Convenience constructors (`StreamChunk.content(...)`, `.thinking(...)`, `.tool(...)`, `.done(usage: ...)`, `.error(...)`) keep the call sites readable.

### `TokenUsage`

Carried in the final `done` chunk:

```dart
class TokenUsage {
  final int? promptTokens;
  final int? completionTokens;
  final int? totalTokens;
}
```

The chat pipeline attaches this to the assistant `Message` for downstream accounting (see [Stats & Usage Tracking](#) — out of scope here, but the same fields back the per-provider token counters).

### Multiplexing

`ChatNotifier` (in [`lib/providers/chat_provider.dart`](../../lib/providers/chat_provider.dart)) consumes multiple streams in parallel (e.g. the main model + a vision sub-model invoked via the capability adapter) and tracks a completion set so it knows when to render the final message.

## Structured Output

Several subsystems need the LLM to return *just* JSON — the memory extractor, the rolling conversation summarizer, the memory compressor, and the plugin skill registration prompt. LLMs are inconsistent: some wrap JSON in markdown code blocks, some add explanatory prose, some add stray whitespace.

Tessera solves this with [`JsonExtractor`](../../lib/utils/json_extractor.dart), a 4-strategy fallback parser that goes from most strict to most lenient:

| # | Strategy | What it handles |
|---|---|---|
| 1 | Direct `jsonDecode` | Clean JSON responses |
| 2 | Markdown json code block | ` ```json ... ``` ` |
| 3 | Any markdown code block | ` ``` ... ``` ` |
| 4 | Delimiter scan (`{`/`}` or `[`/`]`) | Junk text surrounding the JSON payload |

The convenience methods provide type-safe access:

- `tryExtract(content)` → `Map | List | null`
- `tryExtractMap(content)` → `Map<String, dynamic> | null`
- `tryExtractList(content)` → `List<dynamic> | null`
- `tryExtractField(content, fieldName)` → `String | null` (extracts one string field from a map result)

If every strategy fails, callers fall back to a best-effort `trim()` of the response.

### Prompt discipline

In addition to robust parsing, the auxiliary prompts explicitly request pure JSON output — for example the extractor prompt ends with:

> Return a JSON object ONLY.
> If there are no relevant information, return []

The two layers (strict prompts + lenient parser) keep the system reliable across all four providers without per-model prompt engineering.

## Adding a New Provider

Checklist:

1. **Create the adapter** at `lib/llm/<id>_provider.dart`, implementing `LlmProvider`. The 4 existing adapters are good templates — they all share the same shape: a `_buildClient(LlmConfig)` private method, a `_xxxModelToModelInfo` mapper, and the 4 public methods.
2. **Register the adapter** in [`ProviderFactory._create`](../../lib/llm/provider_factory.dart) and add the id to `isSupported`.
3. **Add a format entry** in [`LlmProviderConfig`](../../lib/models/llm_provider_config.dart): `formatDisplayName`, `defaultBaseUrlFor`, `formatNeedsApiKey` switches.
4. **Surface it in the UI** — the Settings page uses `ProviderFactory.allProviders` and the format switches above, so the new provider should appear in the provider-add dialog automatically once the config flags are in.
5. **Tool schema support** — if the new SDK has its own function-calling wire format, add a corresponding `toXxxSchema()` method to [`ToolDefinition`](../../lib/models/tool.dart). The existing OpenAI / Anthropic / Google / Ollama schemas are the templates.

## See Also

- [Capability Adapter](capability-adapter.md) — uses the `LlmProvider` interface to drive vision / audio / image / speech sub-models
- [Memory System](memory-system.md) — the heaviest consumer of `chat()` (non-streaming) and `JsonExtractor`
- [Plugin System](plugin-system.md) — plugin tool handlers share the same `ToolDefinition` / `ToolCall` / `ToolResult` envelope
- [`lib/models/stream_chunk.dart`](../../lib/models/stream_chunk.dart) — the streaming contract
- [`lib/models/tool.dart`](../../lib/models/tool.dart) — the tool-call envelope
- [`lib/utils/json_extractor.dart`](../../lib/utils/json_extractor.dart) — the structured-output parser
