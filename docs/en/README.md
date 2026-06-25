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
| Plugin Runtime | [`luax`](https://github.com/NaivG/luax) (Lua 5.3, maintained by the project owner) + archive (`.plugin` zips) + path_provider |
| Workspaces | Workspace service (line-range reads, stale-read enforcement, write approval) + `path_traversal` sandbox |
| Discovery | Tag/capability indexing via `DiscoverManager` + `ToolCallValidator` (fail-with-schema) |
| Sub-agents | `SubAgentManager` for parallel streaming sub-tasks (Agent / Plan conversation modes) |
| Context Budget | `TokenCounter` (CJK-aware) + `ContextWindowManager` (80% threshold, LLM-compress oldest messages) |
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
│   │   ├── tool_registry.dart         # Tool registration + capability/tag index
│   │   ├── tool_call_validator.dart   # Runtime schema check, fail-with-schema
│   │   ├── discover_manager.dart      # Unified skill+tool search (compact catalog)
│   │   ├── discover_tool.dart         # The `discover` TOOL exposed to the LLM
│   │   ├── sub_agent_manager.dart     # Parallel streaming sub-agent execution
│   │   ├── sub_agent_tool.dart        # The `sub_agent` TOOL exposed to the LLM
│   │   ├── workspace_tools.dart       # workspace_list/read/search/write/edit/patch/mkdir/delete
│   │   ├── context_window_manager.dart # Token budget, 80% threshold, LLM-compress
│   │   ├── system_prompt_builder.dart # 3-block system prompt assembly
│   │   ├── prompt_template_store.dart # Prompt template storage
│   │   └── core.dart                  # Barrel export
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
│   │   ├── llm_provider_config.dart / provider_usage.dart
│   │   ├── session.dart               # Per-conversation sub-agent / sub-task session
│   │   ├── conversation_mode.dart     # Agent / Plan / Default conversation modes
│   │   ├── plan.dart                  # Plan-mode structured plan entries
│   │   └── workspace.dart             # Workspace + WorkspaceIndex + EditOperation
│   ├── services/                      # Business services
│   │   ├── conversation_service.dart  # SQLite conversation persistence
│   │   ├── memory_service.dart        # Memory persistence
│   │   ├── speech_service.dart        # STT/TTS
│   │   ├── media_library.dart         # Media file management
│   │   ├── settings_service.dart      # Settings persistence (+ context window overrides)
│   │   ├── usage_stats_service.dart   # Per-provider token usage
│   │   └── workspace_service.dart     # Workspace CRUD + read/edit enforcement
│   ├── providers/                     # State management (Riverpod)
│   │   ├── chat_provider.dart         # Chat flow state (streaming + tool dispatch)
│   │   ├── settings_provider.dart     # Settings state
│   │   ├── memory_provider.dart       # Memory state
│   │   ├── context_provider.dart      # Token-usage indicator state
│   │   ├── session_provider.dart      # Sub-agent session state
│   │   ├── workspace_provider.dart    # Active workspace + approval state
│   │   ├── stats_provider.dart        # Provider usage aggregation
│   │   ├── conversation_list_provider.dart / conversation_service_provider.dart
│   │   ├── memory_service_provider.dart / settings_service_provider.dart
│   │   ├── workspace_service_provider.dart
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
│   │   └── simhash.dart               # 128-bit SimHash engine (jieba tokenizer)
│   ├── plugin/                        # Lua plugin runtime
│   │   ├── plugin.dart                # Barrel export
│   │   ├── plugin_metadata.dart       # Manifest schema (plugin.json)
│   │   ├── lua_plugin_host.dart       # Per-plugin LuaState + tessera bridge
│   │   ├── plugin_manager.dart        # Bundled + installed discovery
│   │   ├── plugin_registry.dart       # Lifecycle, enable/disable, tool registration
│   │   └── addons/                    # Optional Lua modules (http / json / html2md / base64)
│   ├── ui/
│   │   ├── pages/                     # Pages
│   │   │   ├── main_page.dart / chat_page.dart
│   │   │   ├── settings_page.dart / user_profile_page.dart
│   │   │   ├── library_page.dart / memory_page.dart
│   │   │   ├── model_selection_page.dart / model_edit_page.dart
│   │   │   ├── plugin_page.dart / workspace_page.dart / stats_page.dart
│   │   │   └── error_page.dart
│   │   └── widgets/                   # Reusable components
│   │       ├── chat_bubble.dart / chat_content_view.dart
│   │       ├── message_input.dart / processing_block.dart
│   │       ├── sidebar.dart / conversation_menu.dart
│   │       ├── plan_block.dart / read_only_banner.dart
│   │       ├── sub_agent_card.dart
│   │       ├── workspace_approval_card.dart / workspace_approval_listener.dart
│   │       └── workspace_confirmation_dialog.dart
│   ├── l10n/                          # Localization
│   │   ├── app_en.arb / app_zh.arb
│   │   ├── app_localizations.dart
│   │   └── model_localization.dart
│   └── utils/
│       ├── logger.dart
│       ├── json_extractor.dart              # LLM JSON output extraction (multi-strategy)
│       ├── token_counter.dart               # CJK-aware token estimator
│       ├── model_context_defaults.dart      # Built-in model context window table
│       ├── path_traversal.dart              # Workspace path sandbox checks
│       └── plan_parser.dart                 # Plan-mode plan text parser
├── assets/
│   ├── system_prompt.txt              # Default 3-block system prompt template
│   ├── prompt_fable.txt               # Fable-mode system prompt
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

- [**Plugin System**](plugin-system.md) — sandboxed Lua runtime, `plugin.json` manifest, the `tessera` bridge API, lifecycle, `.plugin` distribution, the maintained `NaivG/luax` fork, authoring guide, and built-in examples.
- [**Memory System**](memory-system.md) — long-term memory pipeline: SimHash indexing, extraction, retrieval scoring, compression (DBSCAN + LLM merge), exponential-decay forgetting, and the `memory.db` persistence layer.
- [**LLM Provider Abstraction**](llm-providers.md) — the unified `LlmProvider` interface across OpenAI / Anthropic / Ollama / Google, the `Stream<StreamChunk>` streaming protocol, `LlmProviderConfig`, and the `JsonExtractor` 4-strategy parser for structured output.
- [**Capability Adapter**](capability-adapter.md) — multimodal routing: how a vision / audio / image-gen / TTS sub-model is exposed to a text-only main model as a function-call tool, and the slot-based `ModelSelectionConfig`.
- [**Workspace Tools**](workspace-tools.md) — sandboxed local-file tools (`workspace_list/read/search/write/edit/patch/mkdir/delete`) with line-range reads, stale-read enforcement, per-write user approval, and path-traversal guards.
- [**Discover System**](discover-system.md) — tag / capability indexing: `DiscoverManager` produces a compact skill catalog, the `discover` TOOL surfaces lightweight summaries, and `ToolCallValidator` returns the full schema when the LLM's call is malformed.
- [**Sub-Agents**](sub-agents.md) — `SubAgentManager` runs multiple sub-tasks in parallel streaming fashion; each gets its own session card, system-prompt variant, and `SubAgentStreamHandle` for live delta aggregation.
- [**Context Window Manager**](context-window.md) — client-side token budget enforcement: `TokenCounter` (CJK-aware), a built-in model context window table with user override, 80% usage threshold, and LLM-driven summarization of the oldest messages.

