<div align="center">

# Tessera

<p>
  <strong>一站式 LLM 客户端。打造你自己的多模态 AI。</strong>
</p>

<p>
  <em>你的专属多模态 AI 助手——由你选择的模型驱动，在你拥有的每台设备上运行。</em>
</p>

![Stars](https://shields.io/github/stars/NaivG/tessera.svg)
![Forks](https://img.shields.io/github/forks/NaivG/tessera.svg)
![Issues](https://img.shields.io/github/issues/NaivG/tessera.svg)
[![Flutter](https://img.shields.io/badge/Flutter-3.41.1-02569B.svg?logo=flutter)](https://flutter.dev/)
[![Dart](https://img.shields.io/badge/Dart-3.11.0-0175C2.svg?logo=dart)](https://dart.dev/)
[![GitHub release (latest by date)](https://img.shields.io/github/v/release/NaivG/tessera)](https://github.com/NaivG/tessera/releases)
[![License](https://img.shields.io/badge/License-AGPL3.0-blue.svg)](LICENSE)

<p>
  <a href="#功能特性">功能特性</a> •
  <a href="#截图">截图</a> •
  <a href="#快速开始">快速开始</a> •
  <a href="#架构设计">架构设计</a> •
  <a href="#技术栈">技术栈</a> •
  <a href="#项目结构">项目结构</a> •
  <a href="#许可证">许可证</a>
</p>

<p style="font-size: 1.1em;">
  <a href="README.md">English</a> |
  <a>中文文档</a>
</p>

</div>

---

**Tessera**（τέσσερα，希腊语意为"四"——四角合一的一块拼片）是一个用 Flutter 构建的跨平台 AI 聊天客户端。它将多个大语言模型提供商汇聚在一个界面下，将多模态任务——视觉识别、音频处理、图像生成、语音合成——无缝路由到对应模型，你无需离开对话窗口。

Tessera 内置了类似人脑的长期记忆系统：提取、检索、压缩、遗忘。它超越了简单的聊天机器人界面，打造真正个性化的 AI 助手。

---

## 功能特性

### 🤖 多提供商 LLM 接入

在统一界面上无缝切换各 AI 提供商：

| 提供商 | 支持的模型 |
|--------|-----------|
| **OpenAI** | GPT-5.5, GPT-4o |
| **Anthropic** | Claude 4.7 Opus, Claude 4.6 Sonnet, Claude 4.5 Haiku |
| **Google AI** | Gemini 3 Pro, Gemini 3 Flash |
| **Ollama** | Llama, Mistral, Qwen, DeepSeek — 任意本地运行的模型 |

每个提供商拥有独立的 **API Key**、**Base URL** 和**模型配置**，你可以添加任意多个**兼容**的提供商实例。

### 🔄 流式对话

逐 token 实时显示 AI 回复，完整支持 Markdown 渲染和代码语法高亮。对话过程中随时取消、继续或切换话题，不丢失上下文。

### 🧠 能力转译系统

当主对话模型无法处理某种模态时，Tessera 的 Capability Adapter 自动路由到专用模型：

| 能力 | 说明 |
|------|------|
| **视觉识别** | 将图片/视频发送给视觉模型分析，返回文字描述 |
| **音频处理** | 将音频转发给音频处理模型分析 |
| **图像生成** | 调用文生图模型生成图片 |
| **语音合成** | 调用文生语音模型生成语音回复 |

AI 自动判断何时需要调用这些子能力，整个过程对你透明，结果无缝流回主对话。

### 💾 智能提示缓存

三段式系统提示模板，基于 SHA256 哈希的增量缓存：

1. **Agent Rules** —— 静态安全规则，高优先级服务端缓存
2. **User Profile** —— 用户信息与长期记忆，客户端缓存
3. **User-Defined Prompt** —— 用户自定义指令，客户端缓存

仅变更的模块会重新发送给 LLM 提供商，显著降低 token 消耗和请求延迟。

### 🧠 长期记忆系统

Tessera 拥有一个受生物记忆启发的长期记忆系统，随你的对话不断进化：

- **MemoryExtractor（记忆提取器）** —— 定期调用 LLM，从对话轮次中提取结构化事实（用户偏好、知识、事件）
- **MemoryRetriever（记忆检索器）** —— 使用 SimHash（128 位）分桶索引 + 汉明距离评分，实现快速语义记忆搜索
- **MemoryCompressor（记忆压缩器）** —— 通过简化 DBSCAN 聚类相似记忆，用 LLM 摘要合并；自动清理低重要性、过时事件
- **MemoryForgetter（记忆遗忘器）** —— 应用指数时间衰减和访问衰减计算遗忘评分；未被使用的记忆会自然淡出
- **ConversationalMemoryManager（对话记忆管理器）** —— 每 N 轮对话生成滚动摘要，保持上下文完整且不无限膨胀

> 记忆不只是被存储——它有生命。被提取、检索、压缩、遗忘。和你一样。

### 🎤 语音交互

- **语音输入**：自然说话，实时转录为文字（Speech-to-Text）
- **语音输出**：让 AI 回复朗读出来，支持中文（Text-to-Speech）

### 📚 对话管理

- **SQLite** 本地持久化存储 —— 对话永不丢失
- 创建、重命名、删除对话
- **媒体库**：管理图片、视频、音频文件，可在对话中直接引用

### 🎨 用户体验

- **Material 3** 设计语言
- 亮色 / 暗色 / 跟随系统 三档主题
- 桌面端窗口可拖拽调整大小：最小 400×600，默认 480×720，启动居中
- 媒体附件预览（图片、视频、音频）
- 流式 Markdown 渲染与代码高亮
- 全局异常捕获，专设错误页面

### 🌐 国际化

- 已内置英文和中文完整本地化
- 基于 Flutter l10n 系统，易于扩展更多语言

---

## 快速开始

### 环境要求

- [Flutter SDK](https://docs.flutter.dev/get-started/install) 3.11+
- 各平台对应的构建工具（Xcode、Android Studio、Visual Studio 等）

### 安装与运行

```bash
# 克隆项目
git clone https://github.com/NaivG/tessera.git
cd tessera

# 安装依赖
flutter pub get

# 运行（自动检测当前平台）
flutter run
```

桌面端启动后自动配置窗口：最小 400×600，默认 480×720，居中显示。

### 配置 API Key

1. 启动应用后进入 **设置** 页面
2. 添加一个 LLM 提供商（OpenAI / Anthropic / Google / Ollama）
3. 填入 API Key 和可选的 Base URL
4. 配置该提供商提供的模型
5. 选择主对话模型，以及各能力方向的专用模型
6. 返回主页开始对话

---

## 架构设计

### 提供商抽象

所有 LLM 提供商实现统一的 `LlmProvider` 接口：

```dart
abstract class LlmProvider {
  Future<List<ModelInfo>> listAvailableModels({String? apiKey, String? baseUrl});
  Future<bool> validateConfig(LlmConfig config);
  Future<Message> chat({required LlmConfig config, required List<Message> history, ...});
  Stream<StreamChunk> chatStream({required LlmConfig config, required List<Message> history, ...});
}
```

业务逻辑无需感知具体 SDK，通过 `ProviderFactory.get(providerId)` 即可获取实例。

### 能力转译

主文本模型处理对话，专用模型处理多模态任务。`CapabilityAdapter` 读取 `ModelSelectionConfig` 定义的模型矩阵，将工具注册到 `ToolRegistry` 中。AI 按需调用这些工具，执行结果以文字形式返回主模型。

```
┌──────────────────────────────────────────────────────────┐
│                    主对话模型                              │
│   （例如 GPT-5.5、Claude 4.7、Gemini 3 Pro）               │
└──────────┬──────────┬──────────┬──────────┬──────────────┘
           │          │          │          │
     ┌─────▼──┐ ┌────▼───┐ ┌───▼────┐ ┌───▼──────┐
     │视觉模型 │ │ 音频模型 │ │ 图像生  │ │ 语音合成  │
     │        │ │        │ │ 成模型  │ │ 模型      │
     └────────┘ └────────┘ └────────┘ └──────────┘
```

### 提示缓存

`CacheManager` 将系统提示词分解为独立的 `PromptSection`，每个段落通过 SHA256 哈希追踪变更。未变更的段落复用上次请求的缓存标记，减少重复 token 发送。

### 模型选择矩阵

`ModelSelectionConfig` 定义了灵活的槽位矩阵：

- **主模型** —— 主要的对话 LLM
- **输入模态** —— 视觉、音频（可逐模态指定专用模型）
- **输出类型** —— 图像生成、语音合成
- **其他模型** —— 嵌入、重排序等

每个槽位是一个 `ModelSlot`，通过稳定的 UUID 引用指向特定提供商配置和模型实例——增删和排序不会导致引用失效。

### 记忆系统流水线

```
对话轮次
    ↓ （累积 N 轮）
MemoryExtractor（记忆提取器）
    ↓ （LLM 提取事实）
结构化记忆（user / knowledge / event 三类）
    ↓
MemoryRetriever（记忆检索器）← SimHash 索引 ← SQLite
    ↓ （查询时检索）
MemoryContext 注入到系统提示词
    ↑
MemoryCompressor（记忆压缩器：聚类 + LLM 合并）
MemoryForgetter（记忆遗忘器：时间衰减评分）
```

---

## 技术栈

| 类别 | 技术 |
|------|------|
| 框架 | Flutter 3.11+ / Dart |
| 状态管理 | ChangeNotifier + ListenableBuilder |
| 持久化 | sqflite（对话）+ shared_preferences（设置） |
| LLM SDK | openai_dart / anthropic_sdk_dart / googleai_dart / ollama_dart |
| 语音 | speech_to_text / flutter_tts |
| UI | Material 3 / flutter_streaming_text_markdown / flutter_context_menu |
| 媒体 | image_picker / file_picker / video_player / gal |
| 平台 | window_manager（桌面端）/ flutter_local_notifications |
| 记忆检索 | SimHash（128 位）+ jieba（结巴分词） |
| 国际化 | Flutter l10n（intl） |

---

## 项目结构

```
tessera/
├── lib/
│   ├── main.dart                      # 入口，窗口初始化，全局错误处理
│   ├── app.dart                       # MaterialApp、路由、主题、国际化
│   ├── core/                          # 核心抽象
│   │   ├── llm_provider.dart          # 统一 LLM 提供商接口
│   │   ├── capability_adapter.dart    # 能力转译路由
│   │   ├── tool_registry.dart         # 工具注册与执行
│   │   ├── system_prompt_builder.dart # 三段式系统提示词组装
│   │   └── prompt_template_store.dart # 提示模板存储
│   ├── llm/                           # LLM SDK 封装
│   │   ├── openai_provider.dart
│   │   ├── anthropic_provider.dart
│   │   ├── google_provider.dart
│   │   ├── ollama_provider.dart
│   │   └── provider_factory.dart
│   ├── models/                        # 数据模型
│   │   ├── message.dart / conversation.dart / tool.dart
│   │   ├── llm_config.dart / model_info.dart
│   │   ├── model_selection_config.dart / stream_chunk.dart
│   │   ├── media_attachment.dart / prompt_template.dart
│   │   ├── memory_entry.dart / memory_type.dart / memory_relation.dart / memory_extraction.dart
│   │   └── llm_provider_config.dart
│   ├── services/                      # 业务服务
│   │   ├── conversation_service.dart  # SQLite 对话持久化
│   │   ├── memory_service.dart        # 记忆持久化
│   │   ├── speech_service.dart        # 语音识别/合成
│   │   ├── media_library.dart         # 媒体文件管理
│   │   └── settings_service.dart      # 设置持久化
│   ├── state/                         # 状态管理（ChangeNotifier）
│   │   ├── chat_state.dart            # 对话流状态
│   │   ├── settings_state.dart        # 设置状态
│   │   └── memory_state.dart          # 记忆状态
│   ├── cache/                         # 提示缓存系统
│   │   ├── cache_manager.dart
│   │   ├── cache_store.dart
│   │   └── prompt_section.dart
│   ├── memory/                        # 长期记忆系统
│   │   ├── memory_extractor.dart      # 基于 LLM 的事实提取
│   │   ├── memory_retriever.dart      # SimHash 语义搜索
│   │   ├── memory_compressor.dart     # 聚类与合并
│   │   ├── memory_forgetter.dart      # 时间衰减遗忘
│   │   ├── memory_middleware.dart     # 对话摘要管理
│   │   └── simhash.dart              # 128 位 SimHash 引擎（结巴分词）
│   ├── ui/
│   │   ├── pages/                     # 页面
│   │   │   ├── main_page.dart / chat_page.dart
│   │   │   ├── settings_page.dart / user_profile_page.dart
│   │   │   ├── library_page.dart / memory_page.dart
│   │   │   ├── model_selection_page.dart / model_edit_page.dart
│   │   │   └── error_page.dart
│   │   └── widgets/                   # 可复用组件
│   │       ├── chat_bubble.dart / chat_content_view.dart
│   │       ├── message_input.dart / processing_block.dart
│   │       └── sidebar.dart
│   ├── l10n/                          # 国际化
│   │   ├── app_en.arb / app_zh.arb
│   │   ├── app_localizations.dart
│   │   └── model_localization.dart
│   └── utils/
│       └── logger.dart
├── assets/
│   ├── system_prompt.txt              # 三段式系统提示模板
│   └── dict*.txt / idf_dict.txt       # 结巴分词词典
├── android/ ios/ macos/ windows/ linux/ web/
└── test/
```

---

## 截图

> *（即将推出 —— 聊天、设置、模型选择、记忆查看器、媒体库界面截图）*

---

## 许可证

版权所有（C）2026 NaivG 与所有贡献者。

本程序是自由软件：你可以重新发布和/或修改它，但请遵守由自由软件基金会发布的 **GNU Affero 通用公共许可证第三版**（GNU AGPLv3）的条款——详情请见 [LICENSE](LICENSE) 文件。

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
