# Tessera Architecture & Reference

This directory contains the technical deep-dives for Tessera's subsystems. 

---

## Architecture Highlights

### Reliable LLM Structured Output

Auxiliary LLM calls — memory extraction, topic generation, content summarization, and compression merging — all require structured output from the model. LLM responses are inherently inconsistent: some models wrap JSON in markdown code blocks, append explanatory text, or add extra whitespace.

Tessera handles this with a two-layer approach:

1. **Prompt discipline** — Every auxiliary prompt explicitly requests pure JSON output (e.g. `Return ONLY a JSON object — no markdown, no explanation, no other text: {"summary": "..."}`)
2. **Robust parsing** — `lib/utils/json_extractor.dart` provides `JsonExtractor`, a multi-strategy fallback parser:

| Strategy | What it handles |
|----------|----------------|
| Direct `jsonDecode` | Clean JSON responses |
| Markdown json code block | Responses wrapped in ` ```json ... ``` ` |
| Any markdown code block | Responses wrapped in ` ``` ... ``` ` |
| Delimiter scanning (`{`/`}` or `[`/`]`) | Junk text surrounding JSON payload |

Convenience methods — `tryExtract()`, `tryExtractMap()`, `tryExtractList()`, `tryExtractField()` — provide type-safe access without boilerplate. If none of the strategies succeed, the method returns `null` and the caller falls back to a best-effort `trim()`.

### Prompt Caching

`CacheManager` decomposes the system prompt into independent `PromptSection`s. Each section is tracked by its SHA256 hash. Unchanged sections reuse the previous request's cache markers, reducing redundant token transmission.

The three-block system prompt template:

| Block | Content | Cache tier |
|-------|---------|------------|
| **Agent Rules** | Static safety rules | High-priority server-side cache |
| **User Profile** | User info & long-term memory | Client-side cache |
| **User-Defined Prompt** | Custom instructions | Client-side cache |

Only the blocks that actually changed are re-sent to the LLM provider, significantly reducing token consumption and latency.

---

## Tech Stack

| Category | Technology |
|----------|-----------|
| Framework | Flutter 3.11+ / Dart |
| State Management | Riverpod (ref.watch / ref.read) |
| Persistence | sqflite (conversations) + shared_preferences (settings) |
| LLM SDKs | openai_dart / anthropic_sdk_dart / googleai_dart / ollama_dart |
| Voice | speech_to_text / flutter_tts |
| UI | Material 3 / flutter_streaming_text_markdown / flutter_context_menu |
| Media | image_picker / file_picker / video_player / gal |
| Platform | window_manager (desktop) / flutter_local_notifications |
| Memory Search | SimHash (128-bit) + jieba (Chinese segmentation) |
| Plugin Runtime | [`lua_dardo_plus`](https://pub.dev/packages/lua_dardo_plus) from `NaivG/LuaDardo` fork (Lua 5.3) + archive (`.plugin` zips) + path_provider |
| Localization | Flutter l10n (intl) |

---

## Project Structure

```
tessera/
├── lib/
│   ├── main.dart                      # Entry point, window init, global error handler
│   ├── app.dart                       # MaterialApp, routing, theme, localization
│   ├── core/                          # Core abstractions
│   │   ├── llm_provider.dart          # Unified LLM provider interface
│   │   ├── capability_adapter.dart    # Capability translation routing
│   │   ├── tool_registry.dart         # Tool registration & execution
│   │   ├── system_prompt_builder.dart # 3-block system prompt assembly
│   │   └── prompt_template_store.dart # Prompt template storage
│   ├── llm/                           # LLM SDK wrappers
│   │   ├── openai_provider.dart
│   │   ├── anthropic_provider.dart
│   │   ├── google_provider.dart
│   │   ├── ollama_provider.dart
│   │   └── provider_factory.dart
│   ├── models/                        # Data models
│   │   ├── message.dart / conversation.dart / tool.dart
│   │   ├── llm_config.dart / model_info.dart
│   │   ├── model_selection_config.dart / stream_chunk.dart
│   │   ├── media_attachment.dart / prompt_template.dart
│   │   ├── memory_entry.dart / memory_type.dart / memory_relation.dart / memory_extraction.dart
│   │   └── llm_provider_config.dart
│   ├── services/                      # Business services
│   │   ├── conversation_service.dart  # SQLite conversation persistence
│   │   ├── memory_service.dart        # Memory persistence
│   │   ├── speech_service.dart        # STT/TTS
│   │   ├── media_library.dart         # Media file management
│   │   └── settings_service.dart      # Settings persistence
│   ├── providers/                     # State management (Riverpod)
│   │   ├── chat_provider.dart         # Chat flow state
│   │   ├── settings_provider.dart     # Settings state
│   │   ├── memory_provider.dart       # Memory state
│   │   ├── conversation_service_provider.dart # Conversation service
│   │   ├── memory_service_provider.dart       # Memory service
│   │   ├── settings_service_provider.dart      # Settings service
│   │   └── providers.dart             # Barrel export
│   ├── cache/                         # Prompt caching system
│   │   ├── cache_manager.dart
│   │   ├── cache_store.dart
│   │   └── prompt_section.dart
│   ├── memory/                        # Long-term memory system
│   │   ├── memory_extractor.dart      # LLM-based fact extraction
│   │   ├── memory_retriever.dart      # SimHash semantic search
│   │   ├── memory_compressor.dart     # Clustering & merging
│   │   ├── memory_forgetter.dart      # Time-decay forgetting
│   │   ├── memory_middleware.dart     # Conversational summary management
│   │   └── simhash.dart              # 128-bit SimHash engine (jieba tokenizer)
│   ├── plugin/                        # Lua plugin runtime
│   │   ├── plugin.dart                # Barrel export
│   │   ├── plugin_metadata.dart       # Manifest schema (plugin.json)
│   │   ├── lua_plugin_host.dart       # Per-plugin LuaState + tessera bridge
│   │   ├── plugin_manager.dart        # Bundled + installed discovery
│   │   └── plugin_registry.dart       # Lifecycle, enable/disable, tool registration
│   ├── ui/
│   │   ├── pages/                     # Pages
│   │   │   ├── main_page.dart / chat_page.dart
│   │   │   ├── settings_page.dart / user_profile_page.dart
│   │   │   ├── library_page.dart / memory_page.dart
│   │   │   ├── model_selection_page.dart / model_edit_page.dart
│   │   │   └── error_page.dart
│   │   └── widgets/                   # Reusable components
│   │       ├── chat_bubble.dart / chat_content_view.dart
│   │       ├── message_input.dart / processing_block.dart
│   │       └── sidebar.dart
│   ├── l10n/                          # Localization
│   │   ├── app_en.arb / app_zh.arb
│   │   ├── app_localizations.dart
│   │   └── model_localization.dart
│   └── utils/
│       ├── logger.dart
│       └── json_extractor.dart              # LLM JSON output extraction (multi-strategy)
├── assets/
│   ├── system_prompt.txt              # 3-block system prompt template
│   ├── dict*.txt / idf_dict.txt       # jieba dictionaries
│   └── plugins/                       # Bundled plugins (shipped with the app)
│       ├── plugins_index.json         # Allowlist of bundled plugin ids
│       └── example_hello/             # Greeting SKILL + TOOL example
├── plugins/                           # Dev workspace for plugin sources
│   └── pack_plugin.py                 # CLI to validate/pack .plugin zips
├── android/ ios/ macos/ windows/ linux/ web/
└── test/
```

---

## Contents

- [**Plugin System**](plugin-system.md) — sandboxed Lua runtime, `plugin.json` manifest, the `tessera` bridge API, lifecycle, `.plugin` distribution, the maintained `NaivG/LuaDardo` fork, authoring guide, and built-in examples.
- [**Memory System**](memory-system.md) — long-term memory pipeline: SimHash indexing, extraction, retrieval scoring, compression (DBSCAN + LLM merge), exponential-decay forgetting, and the `memory.db` persistence layer.
- [**LLM Provider Abstraction**](llm-providers.md) — the unified `LlmProvider` interface across OpenAI / Anthropic / Ollama / Google, the `Stream<StreamChunk>` streaming protocol, `LlmProviderConfig`, and the `JsonExtractor` 4-strategy parser for structured output.
- [**Capability Adapter**](capability-adapter.md) — multimodal routing: how a vision / audio / image-gen / TTS sub-model is exposed to a text-only main model as a function-call tool, and the slot-based `ModelSelectionConfig`.

