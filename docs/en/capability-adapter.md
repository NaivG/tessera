# Capability Adapter

Tessera's multimodal routing layer — how a vision-capable sibling model is invoked from a text-only main model.

## Overview

The main chat model is not always multimodal. A user might pick a fast, cheap text-only LLM as the main model but still expect the assistant to read an image they paste, play back a TTS clip, or generate a picture on demand.

The **Capability Adapter** ([`lib/core/capability_adapter.dart`](../../lib/core/capability_adapter.dart)) is the bridge. It reads the user's [`ModelSelectionConfig`](../../lib/models/model_selection_config.dart) and, for each capability that the main model *doesn't* natively support, registers a **TOOL** into the global [`ToolRegistry`](../../lib/core/tool_registry.dart). When the LLM emits a matching `ToolCall`, the adapter routes it to the correct sibling model, runs the request, and merges the result back into the conversation as a `ToolResult`.

The main model never has to know it's talking to a different model — it just calls a tool, and the adapter takes care of the rest.

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────┐
│                   Main Chat Model                        │
│   (e.g. GPT-4o, Claude 4, Gemini 3 Pro)                  │
└──────────┬──────────┬──────────┬──────────┬──────────────┘
           │          │          │          │
     ┌─────▼──┐  ┌────▼───┐  ┌───▼────┐ ┌───▼──────┐
     │Vision  │  │Audible │  │Image   │ │Speech    │
     │Model   │  │Model   │  │Gen     │ │Gen Model │
     │(any)   │  │(any)   │  │(any)   │ │(any)     │
     └────────┘  └────────┘  └────────┘ └──────────┘
            ↑ CapabilityAdapter routes tool calls
            ↑ ToolRegistry dispatches by tool name
```

## Multimodal Tool Registration

`CapabilityAdapter.buildTools()` inspects the `ModelSelectionConfig` and emits one or more of:

| Tool | Trigger condition | Sibling model slot |
|---|---|---|
| `vision` | A vision-capable model is configured and the main model does **not** natively carry the `vision` tag | `ModelSelectionConfig.resolveInput(ModelTag.vision, state)` |
| `audible` | An audio-capable model is configured and the main model does not carry `audible` | `resolveInput(ModelTag.audible, state)` |
| `image_generate` | A text-to-image output model is configured | `resolveOutput(ModelType.image, state)` |
| `speech_generate` | A text-to-speech output model is configured | `resolveOutput(ModelType.speech, state)` |

If the main model natively supports the modality (i.e. the resolved slot equals `config.mainModel`), the corresponding tool is **not** registered — the main model handles it directly. This is the "graceful degradation" property: a user with a fully multimodal main model sees zero extra tool overhead.

`registerTools(toolRegistry)` then wires each emitted `ToolDefinition` to a handler that delegates to `executeTool(toolCall)`.

## Tool Dispatch & Execution

When the main model emits a `ToolCall`, the chat pipeline resolves it via `ToolRegistry.execute(call)` → `CapabilityAdapter.executeTool(call)`:

| Tool | Handler | Behavior |
|---|---|---|
| `vision` | `_executeVision` | Loads the referenced image / video (object key, filename, URL, or data URI), calls the vision model with the LLM's question, returns the description as text |
| `audible` | `_executeAudible` | Loads the referenced audio, calls the audio model with the LLM's question, returns the transcription / description as text |
| `image_generate` | `_executeImageGenerate` | Calls the text-to-image model with the LLM's prompt, returns a `libraryId` reference (or a description, depending on pipeline) |
| `speech_generate` | `_executeSpeechGenerate` | Calls the TTS model, returns a `libraryId` reference back into the conversation as audio |

The returned `ToolResult` is merged into the conversation as a synthetic tool-role message; the main model sees the result and continues the turn. This is the same envelope that [plugin tool calls](plugin-system.md) use.

## Model Selection Matrix

The user's configuration is a [`ModelSelectionConfig`](../../lib/models/model_selection_config.dart) with five logical slots:

| Slot | Type | Purpose | Resolution |
|---|---|---|---|
| `mainModel` | `ModelSlot` | The primary chat LLM | Always used for conversation |
| `inputModalities` | `Map<ModelTag, ModelSlot?>` | Per-input-modality sibling | `resolveInput(tag, state)` |
| `outputModalities` | `Map<ModelType, ModelSlot?>` | Per-output-type sibling | `resolveOutput(type, state)` |
| `otherModels` | `Map<String, ModelSlot?>` | Embeddings, rerankers, … | `resolveOther(key, state)` |

### `ModelTag` (input modalities)

| Tag | Meaning |
|---|---|
| `text` | Text input / output |
| `vision` | Image input (visual understanding) |
| `audible` | Audio input / output |
| `video` | Video input / output |

When a model carries `text` + `vision` + `audible` + `video` it is treated as an **omni** (fully multimodal) model. The `tags` field on [`ModelInfo`](../../lib/models/model_info.dart) holds this set.

### `ModelType` (output types)

| Type | Meaning | Short name |
|---|---|---|
| `text` | Text generation (LLM) | `LLM` |
| `image` | Text-to-Image | `TTI` |
| `video` | Text-to-Video | `TTV` |
| `speech` | Text-to-Speech | `TTS` |
| `embedding` | Embedding vectors | `EMB` |
| `ranking` | Rerank / scoring | `RNK` |

### Why UUIDs, not array indices

A `ModelSlot` references its provider + model by UUID:

```dart
class ModelSlot {
  final String providerConfigId;  // LlmProviderConfig.id
  final String modelUid;          // ModelInfo.uid
}
```

This replaces the older integer-index scheme (`pi` / `mi` arrays) which broke when the user deleted or reordered providers. UUIDs survive reordering, deletion of unrelated providers, and even swapping the model list on the disk. `ModelSlot.fromJson` still reads the old format (`pi` / `mi` → coerced to empty strings) so old serialized configs are tolerated on load.

The `state` argument to `resolveInput / resolveOutput` is the `SettingsState` (or any object with `providerConfigs` + per-provider `models` / `format` / `apiKey` / `baseUrl` fields). The slot resolves on demand into a fully-formed [`LlmConfig`](../../lib/models/llm_config.dart) — API keys and base URLs are pulled live from the user's settings rather than copied into the serialized slot, so saved configs don't leak secrets.

## Tool Execution Flow (end to end)

```
User: "What does this image show?"
   ↓
Chat pipeline builds system prompt + tool list
   ↓
Main model emits ToolCall(name="vision", args={type:"image", object:"img_42", question:"What does this image show?"})
   ↓
ToolRegistry.execute(call) → CapabilityAdapter._executeVision(call)
   ↓
CapabilityAdapter resolves vision slot → LlmConfig
   ↓
ProviderFactory.get(format).chat(config, history, …) on the vision model
   ↓
Vision model's description returned as ToolResult
   ↓
Tool result message merged into conversation
   ↓
Main model sees the description, writes the user-facing answer
```

## Configuration UI

The configuration surfaces are:

- [`lib/ui/pages/model_selection_page.dart`](../../lib/ui/pages/model_selection_page.dart) — pick the main model and the sibling models per slot
- [`lib/ui/pages/model_edit_page.dart`](../../lib/ui/pages/model_edit_page.dart) — add / edit a model entry within a provider config (UID, display name, capability tags, model type)

Both pages are part of the Settings flow and persist their choices via `ModelSelectionConfig.toJson()`.

## See Also

- [LLM Provider Abstraction](llm-providers.md) — `LlmProvider` is what the adapter calls to drive each sibling model
- [Plugin System](plugin-system.md) — plugin tools share the same `ToolDefinition` / `ToolCall` / `ToolResult` envelope and the same `ToolRegistry`
- [Memory System](memory-system.md) — retrieved memory is one of several inputs to the system prompt the adapter's tool calls sit alongside
- [`lib/core/tool_registry.dart`](../../lib/core/tool_registry.dart) — the global dispatch table
- [`lib/models/model_selection_config.dart`](../../lib/models/model_selection_config.dart) — the slot-based config model
