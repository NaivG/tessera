# Tessera AI

<p align="center">
  <strong>一个跨平台的 AI 聊天客户端，一站式接入多个大语言模型</strong>
</p>

<p align="center">
  Flutter 构建 | macOS · Windows · Linux · Android · iOS · Web
</p>

---

## 功能

### 🤖 多提供商 LLM 接入
同一界面无缝切换多个 AI 模型提供商：

- **OpenAI** — GPT 系列模型
- **Anthropic** — Claude 系列模型
- **Google AI** — Gemini 系列模型
- **Ollama** — 本地部署的开源模型

每个提供商支持独立的 API Key、Base URL 和模型配置。

### 🔄 流式对话
实时逐 token 显示 AI 回复，支持 Markdown 渲染、代码高亮。对话过程中可随时取消、继续或切换话题。

### 🧠 能力转译系统 (Capability Adapter)
当主对话模型不具备某些能力时，自动路由到专用模型：

| 能力 | 说明 |
|------|------|
| **Vision** | 将图片/视频发送给视觉模型分析，返回文字描述 |
| **Audible** | 将音频发送给音频模型处理 |
| **Image Generate** | 调用文生图模型生成图片 |
| **Speech Generate** | 调用文生语音模型生成语音 |

AI 自动判断何时需要调用这些子能力，对用户透明。

### 💾 智能提示缓存
三块可拆分系统提示词模板，基于内容哈希的增量缓存：

1. **Agent Rules** — 静态安全规则，高优先级服务端缓存
2. **User Profile** — 用户信息与长期记忆，客户端缓存
3. **User-Defined Prompt** — 用户自定义指令，客户端缓存

仅变更的部分会发送给 LLM 提供商，显著降低 token 消耗。

### 🎤 语音交互
- **语音输入**：Speech-to-Text，边说边识别
- **语音输出**：Text-to-Speech，朗读 AI 回复（支持中文）

### 📚 对话管理
- SQLite 本地持久化存储，对话永不丢失
- 对话列表：创建、重命名、删除
- 媒体库：图片、视频、音频文件管理，可在对话中引用

### 🎨 用户体验
- Material 3 设计语言
- 亮色 / 暗色 / 跟随系统 三档主题
- 桌面端可拖拽调整窗口大小
- 媒体附件预览

---

## 快速开始

### 环境要求

- [Flutter SDK](https://docs.flutter.dev/get-started/install) 3.11+
- 各平台对应的构建工具（Xcode、Android Studio、Visual Studio 等）

### 安装与运行

```bash
# 克隆项目
git clone <your-repo-url> tessera
cd tessera

# 安装依赖
flutter pub get

# 运行（自动检测当前平台）
flutter run
```

桌面端运行后会自动配置窗口：最小 400×600，默认 480×720。

### 配置 API Key

1. 启动应用后进入 **设置** 页面
2. 选择需要使用的 LLM 提供商（OpenAI / Anthropic / Google / Ollama）
3. 填入 API Key 和可选的 Base URL
4. 选择主对话模型及各项专用模型
5. 返回主页开始对话

---

## 项目结构

```
tessera/
├── lib/
│   ├── main.dart                  # 入口，窗口初始化
│   ├── app.dart                   # MaterialApp、路由、主题配置
│   ├── core/                      # 核心抽象
│   │   ├── llm_provider.dart      # LLM 提供商统一接口
│   │   ├── capability_adapter.dart# 能力转译路由
│   │   ├── tool_registry.dart     # 工具注册与执行
│   │   ├── system_prompt_builder.dart # 系统提示构建
│   │   ├── prompt_template_store.dart # 提示模板存储
│   │   └── models/                # 数据模型
│   │       ├── message.dart
│   │       ├── conversation.dart
│   │       ├── llm_config.dart
│   │       ├── model_info.dart
│   │       ├── stream_chunk.dart
│   │       └── tool.dart
│   ├── providers/                 # 各 LLM SDK 封装
│   │   ├── openai_provider.dart
│   │   ├── anthropic_provider.dart
│   │   ├── google_provider.dart
│   │   ├── ollama_provider.dart
│   │   └── provider_factory.dart
│   ├── services/                  # 业务服务
│   │   ├── conversation_service.dart # 对话持久化 (SQLite)
│   │   ├── speech_service.dart       # STT/TTS
│   │   ├── media_library.dart        # 媒体文件管理
│   │   └── settings_service.dart     # 设置持久化
│   ├── state/                     # 状态管理 (ChangeNotifier)
│   │   ├── chat_state.dart        # 对话流状态
│   │   └── settings_state.dart    # 设置状态
│   ├── cache/                     # 提示缓存系统
│   │   ├── cache_manager.dart
│   │   ├── cache_store.dart
│   │   └── prompt_section.dart
│   ├── ui/
│   │   ├── pages/                 # 页面
│   │   │   ├── main_page.dart
│   │   │   ├── chat_page.dart
│   │   │   ├── settings_page.dart
│   │   │   ├── library_page.dart
│   │   │   ├── model_selection_page.dart
│   │   │   └── model_edit_page.dart
│   │   └── widgets/               # 复用组件
│   │       ├── chat_bubble.dart
│   │       ├── chat_content_view.dart
│   │       ├── message_input.dart
│   │       ├── processing_block.dart
│   │       └── sidebar.dart
│   └── utils/
│       └── logger.dart
├── assets/
│   └── system_prompt.txt          # 三块系统提示模板
├── ai_clients_dart/               # 上游 Dart SDK 源码（submodule）
│   └── packages/
│       ├── openai_dart/
│       ├── anthropic_sdk_dart/
│       ├── googleai_dart/
│       ├── ollama_dart/
│       └── ...
├── android/                       # Android 平台文件
├── ios/                           # iOS 平台文件
├── macos/                         # macOS 平台文件
├── windows/                       # Windows 平台文件
├── linux/                         # Linux 平台文件
├── web/                           # Web 平台文件
└── test/                          # 测试
```

---

## 技术栈

| 类别 | 技术 |
|------|------|
| 框架 | Flutter 3.11+ / Dart |
| 状态管理 | ChangeNotifier + ListenableBuilder |
| 持久化 | sqflite (对话) + shared_preferences (设置) |
| LLM SDK | openai_dart / anthropic_sdk_dart / googleai_dart / ollama_dart |
| 语音 | speech_to_text / flutter_tts |
| UI | Material 3 / flutter_streaming_text_markdown / flutter_context_menu |
| 媒体 | image_picker / file_picker / video_player / gal |
| 平台 | window_manager (桌面端) / flutter_local_notifications |

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

上层业务逻辑无需感知具体 SDK，通过 `ProviderFactory.get(providerId)` 即可获取实例。

### 能力转译

主模型处理对话，专用模型处理多模态任务。`CapabilityAdapter` 根据用户配置的模型矩阵自动注册工具到 `ToolRegistry`，AI 按需调用对应工具，结果以文字形式返回主模型。

### 提示缓存

`CacheManager` 将提示词分解为独立分块，通过 SHA256 哈希追踪变更。不变的分块复用上次请求的缓存标记，减少重复 token 发送。

## 📄 许可证

本项目采用 GNU AFFERO GENERAL PUBLIC LICENSE v3.0 许可证，详情请参见 [LICENSE](LICENSE) 文件。

```license
Copyright (C) 2026 NaivG and contributors.

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