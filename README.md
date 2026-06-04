<!-- ![Tessera](docs/logo.png) -->
<div align="center">

<div>
    <img src="./docs/favicon.png" alt="logo" style="width: 20%; height: auto;">
</div>

# Tessera

<p>
  <strong>All-in-one LLM client. Make a multimodal AI yourself.</strong>
</p>

<p>
  <em>Your own multimodal AI assistant — powered by the models you choose, running on every device you own.</em>
</p>

![Stars](https://shields.io/github/stars/NaivG/tessera.svg)
![Forks](https://img.shields.io/github/forks/NaivG/tessera.svg)
![Issues](https://img.shields.io/github/issues/NaivG/tessera.svg)
[![Flutter](https://img.shields.io/badge/Flutter-3.41.1-02569B.svg?logo=flutter)](https://flutter.dev/)
[![Dart](https://img.shields.io/badge/Dart-3.11.0-0175C2.svg?logo=dart)](https://dart.dev/)
[![GitHub release (latest by date)](https://img.shields.io/github/v/release/NaivG/tessera)](https://github.com/NaivG/tessera/releases)
[![License](https://img.shields.io/badge/License-AGPL3.0-blue.svg)](LICENSE)

<p>
  <a href="#features">Features</a> •
  <a href="#screenshots">Screenshots</a> •
  <a href="#quick-start">Quick Start</a> •
  <a href="#architecture">Architecture</a> •
  <a href="#tech-stack">Tech Stack</a> •
  <a href="#project-structure">Project Structure</a> •
  <a href="#license">License</a>
</p>

<p style="font-size: 1.1em;">
  <a>English</a> |
  <a href="README_ZH.md">中文文档</a>
</p>

</div>

---

**Tessera** (τέσσερα, Greek for "four" — the four corners of one unified piece) is a cross-platform AI chat client built with Flutter. It brings together multiple large language model providers under one roof, seamlessly routing multimodal tasks — vision, audio, image generation, speech synthesis — to the right models without you ever leaving the conversation.

With a experimental built-in long-term memory system that extracts, retrieves, compresses, and forgets like a human mind, Tessera goes beyond simple chatbot interfaces to deliver a truly personal assistant.

---

## Features

### 🤖 Multi-Provider LLM Access
Switch between AI providers effortlessly from a single interface:

| Provider | Example Models |
|----------|--------|
| **OpenAI** | GPT-5.5, GPT-4o |
| **Anthropic** | Claude 4.7 Opus, Claude 4.6 Sonnet, Claude 4.5 Haiku |
| **Google AI** | Gemini 3 Pro, Gemini 3 Flash |
| **Ollama** | Llama, Mistral, Qwen, DeepSeek — any open-source model running locally |

Each provider maintains its own **API Key**, **Base URL**, and **model configuration**. Add as many **compatible** provider instances as you need.

### 🔄 Streaming Conversations
Real-time token-by-token AI responses with full Markdown rendering and syntax-highlighted code blocks. Cancel, continue, or switch topics mid-conversation without losing context.

### 🧠 Capability Adapter System
When your main chat model can't handle a modality, Tessera's Capability Adapter automatically routes it to a specialized model:

| Capability | Description |
|-----------|-------------|
| **Vision** | Send images/videos to a vision model, return text descriptions |
| **Audible** | Forward audio to an audio-processing model |
| **Image Generate** | Call a text-to-image model to generate pictures |
| **Speech Generate** | Call a text-to-speech model to generate speech |

The AI decides when to invoke these sub-capabilities — the process is transparent to you, and results flow back into the main conversation seamlessly.

### 💾 Intelligent Prompt Caching
Three-block system prompt template with SHA256 hash-based delta caching:

1. **Agent Rules** — Static safety rules, high-priority server-side cache
2. **User Profile** — User info & long-term memory, client-side cache
3. **User-Defined Prompt** — Custom instructions, client-side cache

Only the blocks that actually changed are re-sent to the LLM provider, significantly reducing token consumption and latency.

### 🧠 Long-Term Memory
Tessera features a sophisticated, biologically inspired memory system that evolves with your conversations:

- **MemoryExtractor** — Periodically calls an LLM to extract structured facts (user preferences, knowledge, events) from conversation turns
- **MemoryRetriever** — Uses SimHash (128-bit) with bucket-based indexing and Hamming distance scoring for fast semantic memory search
- **MemoryCompressor** — Clusters similar memories via simplified DBSCAN and merges them using LLM summarization; auto-purges low-importance, aged-out events
- **MemoryForgetter** — Applies exponential time-decay and access-decay to calculate forgetting scores; memory fades naturally if unused
- **ConversationalMemoryManager** — Generates rolling summaries of the current conversation (every N turns) to keep context intact without unbounded token growth

> Memory is not just stored — it's lived. Retrieved. Compressed. Forgotten. Just like you.

All auxilary LLM calls in the memory pipeline (extraction, merge, summary, topic generation) use **strict JSON prompts** with a multi-strategy **`JsonExtractor`** fallback parser. The prompt asks for pure JSON; the parser tolerates markdown code blocks, extra text, and arbitrary whitespace — so the system stays robust regardless of model quirks.

### 🎤 Voice Interaction
- **Speech-to-Text**: Speak naturally, see it transcribed in real time
- **Text-to-Speech**: Listen to AI responses read aloud (including Chinese)

### 📚 Conversation Management
- **SQLite** local persistent storage — conversations never get lost
- Create, rename, delete conversations
- **Media Library**: Manage images, videos, and audio files; reference them in conversations

### 🎨 User Experience
- **Material 3** design language
- Light / Dark / System theme
- Desktop window: resize, drag, minimum 400×600, default 480×720
- Media attachment preview (images, video, audio)
- Streaming text with Markdown rendering & code highlighting
- Global error handling with dedicated error page

### 🌐 Localization
- English & Chinese (fully localized)
- Easy to extend with Flutter's l10n system

---

## Quick Start

### Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) 3.11+
- Platform-specific build tools (Xcode, Android Studio, Visual Studio, etc.)

### Install & Run

```bash
# Clone the repository
git clone https://github.com/NaivG/tessera.git
cd tessera

# Install dependencies
flutter pub get

# Run (auto-detects current platform)
flutter run
```

Desktop builds auto-configure the window: minimum 400×600, default 480×720, centered on screen.

### Configure API Key

1. Launch the app and navigate to **Settings**
2. Add an LLM provider (OpenAI / Anthropic / Google / Ollama)
3. Enter your API Key and optional Base URL
4. Configure model from provider
5. Select your main chat model and specialized models for each capability
6. Return to the main page and start a conversation

---

## Architecture

### Provider Abstraction

All LLM providers implement the unified `LlmProvider` interface:

```dart
abstract class LlmProvider {
  Future<List<ModelInfo>> listAvailableModels({String? apiKey, String? baseUrl});
  Future<bool> validateConfig(LlmConfig config);
  Future<Message> chat({required LlmConfig config, required List<Message> history, ...});
  Stream<StreamChunk> chatStream({required LlmConfig config, required List<Message> history, ...});
}
```

Business logic never touches SDK specifics — `ProviderFactory.get(providerId)` returns the right instance.

### Capability Translation

The main text model handles conversation; specialized models handle multimodal tasks. `CapabilityAdapter` reads the model matrix from `ModelSelectionConfig` and registers tools into `ToolRegistry`. The AI invokes these tools as needed, and results return as text to the main model.

```
┌─────────────────────────────────────────────────────────┐
│                   Main Chat Model                        │
│   (e.g. GPT-4o, Claude 4, Gemini 2.5 Pro)               │
└──────────┬──────────┬──────────┬──────────┬──────────────┘
           │          │          │          │
     ┌─────▼──┐ ┌────▼───┐ ┌───▼────┐ ┌───▼──────┐
     │Vision  │ │Audible │ │Image   │ │Speech    │
     │Model   │ │Model   │ │Gen     │ │Gen Model │
     └────────┘ └────────┘ └────────┘ └──────────┘
```

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

### Model Selection Matrix

`ModelSelectionConfig` defines a flexible slot-based matrix:

- **Main Model** — The primary chat LLM
- **Input Modalities** — vision, audible (per-modal model assignment)
- **Output Modalities** — image generation, speech generation
- **Other** — embeddings, reranking, etc.

Each slot is a `ModelSlot` pointing to a specific provider config + model via stable UUID references — resilient to reordering or deletion.

### Memory System Pipeline

```
Conversation Turns
       ↓ (accumulate N rounds)
MemoryExtractor
       ↓ (LLM extracts facts)
Structured Memories (user / knowledge / event)
       ↓
MemoryRetriever ← SimHash indexing ← SQLite
       ↓ (query-time retrieval)
MemoryContext injected into system prompt
       ↑
MemoryCompressor (clustering + LLM merge)
MemoryForgetter   (time-decay scoring)
```

---

## Tech Stack

| Category | Technology |
|----------|-----------|
| Framework | Flutter 3.11+ / Dart |
| State Management | ChangeNotifier + ListenableBuilder |
| Persistence | sqflite (conversations) + shared_preferences (settings) |
| LLM SDKs | openai_dart / anthropic_sdk_dart / googleai_dart / ollama_dart |
| Voice | speech_to_text / flutter_tts |
| UI | Material 3 / flutter_streaming_text_markdown / flutter_context_menu |
| Media | image_picker / file_picker / video_player / gal |
| Platform | window_manager (desktop) / flutter_local_notifications |
| Memory Search | SimHash (128-bit) + jieba (Chinese segmentation) |
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
│   ├── state/                         # State management (ChangeNotifier)
│   │   ├── chat_state.dart            # Chat flow state
│   │   ├── settings_state.dart        # Settings state
│   │   └── memory_state.dart          # Memory state
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
│   └── dict*.txt / idf_dict.txt       # jieba dictionaries
├── android/ ios/ macos/ windows/ linux/ web/
└── test/
```

---

## Screenshots

> *(Coming soon — screenshots of chat, settings, model selection, memory viewer, and media library)*

---

## License

Copyright (C) 2026 NaivG and contributors.

This project is licensed under the **GNU Affero General Public License v3.0** — see the [LICENSE](LICENSE) file for details.

```
This program is free software: you can redistribute it and/or modify
it under the terms of the GNU Affero General Public License as
published by the Free Software Foundation, either version 3 of the
License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU Affero General Public License for more details.

You should have received a copy of the GNU Affero General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
```
