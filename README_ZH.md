<!-- ![Tessera](docs/logo.png) -->
<div align="center">

<div>
    <img src="./docs/favicon.png" alt="logo" style="width: 20%; height: auto;">
</div>

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
  <a href="docs/zh/README.md">文档</a> •
  <a href="#快速开始">快速开始</a> •
  <a href="#截图">截图</a> •
  <a href="#许可证">许可证</a>
</p>

<p style="font-size: 1.1em;">
  <a href="README.md">English</a> |
  <a>中文文档</a>
</p>

</div>

---

**Tessera**（τέσσερα，希腊语意为"四"——四角合一的一块拼片）是一个用 Flutter 构建的跨平台 AI 聊天客户端。它将多个大语言模型提供商汇聚在一个界面下，将多模态任务——视觉识别、音频处理、图像生成、语音合成——无缝路由到对应模型，你无需离开对话窗口。内置的实验性长期记忆系统会提取、检索、压缩、遗忘对话中的信息，超越简单的聊天机器人界面。

---

## 功能特性

- **🤖 多提供商 LLM 接入** — OpenAI、Anthropic、Google AI、Ollama，每个提供商拥有独立的 API Key、Base URL 与模型配置。
- **🔄 流式对话** — 逐 token 实时响应，完整 Markdown 渲染与代码语法高亮。
- **🧠 能力转译系统** — 通过 function-calling 自动将视觉、音频、图像生成、TTS 任务路由到专用子模型。
- **💾 智能提示缓存** — 三段式系统提示 + SHA256 增量缓存，只重传变更的段落。
- **🧠 长期记忆** — 基于 SimHash 的语义检索、DBSCAN 聚类 + LLM 压缩、指数衰减遗忘、滚动式对话摘要。
- **🧩 可扩展的插件系统** — 沙箱化 Lua 5.3 运行时，写几行脚本就能注册工具与技能，无需重新编译。
- **🎤 语音交互** — 语音输入（STT）与语音输出（TTS）。
- **📚 对话管理** — SQLite 持久化存储，支持创建、重命名、删除对话，附带媒体库。
- **🎨 用户体验** — Material 3 设计、亮/暗主题、桌面端窗口管理、流式 Markdown 与代码高亮。
- **🌐 国际化** — 完整中英文本地化，基于 Flutter l10n，易于扩展。

深入架构、技术栈与项目结构请参见 [**文档**](docs/zh/README.md)。

---

## 快速开始

### 环境要求

- [Flutter SDK](https://docs.flutter.dev/get-started/install) 3.11+
- 各平台对应的构建工具（Xcode、Android Studio、Visual Studio 等）

### 安装与运行

```bash
git clone https://github.com/NaivG/tessera.git
cd tessera
flutter pub get
flutter run
```

桌面端启动后自动配置窗口：最小 400×600，默认 480×720，居中显示。

### 配置 API 与模型

1. 启动应用后进入 **设置** 页面
2. 添加一个 LLM 提供商（OpenAI / Anthropic / Google / Ollama）
3. 填入 API Key 和可选的 Base URL
4. 配置该提供商提供的模型
5. 选择主对话模型，以及各能力方向的专用模型
6. 返回主页开始对话

---

## 文档

Tessera 各大子系统的深入参考文档位于 [**docs/zh/**](docs/zh/README.md)：

- [**插件系统**](docs/zh/plugin-system.md) —— 沙箱化 Lua 运行时、manifest、`tessera` 桥接 API、生命周期、`.plugin` 分发格式、运行时补丁、编写指南
- [**记忆系统**](docs/zh/memory-system.md) —— 长期记忆流水线：SimHash 索引、抽取、检索打分、压缩（DBSCAN + LLM 合并）、指数衰减遗忘
- [**LLM 提供商抽象**](docs/zh/llm-providers.md) —— 跨 OpenAI / Anthropic / Ollama / Google 的统一 `LlmProvider` 接口、流式协议、结构化输出
- [**能力转译**](docs/zh/capability-adapter.md) —— 多模态路由：视觉 / 音频 / 文生图 / TTS 子模型如何以 function-call 工具形式暴露给纯文本主模型

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
