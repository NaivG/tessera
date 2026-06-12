# Tessera 文档（中文）

本目录包含 Tessera 各大子系统的深入参考文档。

---

## 架构亮点

### 可靠的 LLM 结构化输出

辅助 LLM 调用——记忆提取、主题生成、内容摘要以及压缩合并——均要求模型提供结构化输出。LLM 的响应本质上是不一致的：有些模型会将 JSON 包裹在 Markdown 代码块中，附带解释性文本，或添加额外的空白。

Tessera 通过两层方法处理这一问题：

1. **提示词规范** —— 每个辅助提示词都明确要求纯 JSON 输出（例如 `仅返回一个 JSON 对象 —— 无 Markdown、无解释、无其他文本：{"summary": "..."}`）
2. **稳健解析** — [`lib/utils/json_extractor.dart`](../../lib/utils/json_extractor.dart) 提供了 `JsonExtractor`，这是一个支持多种策略的备用解析器：

| 策略 | 处理内容 |
|----------|----------------|
| 直接 `jsonDecode` | 干净的 JSON 响应 |
| Markdown JSON 代码块 | 包裹在 ` ```json ... ``` ` 中的响应 |
| 任意 Markdown 代码块 | 包裹在 ` ``` ... ``` ` 中的响应 |
| 分隔符扫描（`{`/`}` 或 `[`/`]`） | 包围 JSON 有效负载的文本 |

便捷方法 — `tryExtract()`、`tryExtractMap()`、`tryExtractList()`、`tryExtractField()` — 提供了无需冗余代码的类型安全访问。如果所有策略均未成功，该方法将返回 `null`，调用方将回退到 `trim()` 处理。

### 提示缓存

`CacheManager` 将系统提示词分解为独立的 `PromptSection`，每个段落通过 SHA256 哈希追踪变更。未变更的段落复用上次请求的缓存标记，减少重复 token 发送。

三段式系统提示词模板：

| 块 | 内容 | 缓存层级 |
|-------|---------|------------|
| **Agent Rules** | 静态安全规则 | 高优先级服务端缓存 |
| **User Profile** | 用户信息与长期记忆 | 客户端缓存 |
| **User-Defined Prompt** | 用户自定义指令 | 客户端缓存 |

仅变更的块会重新发送给 LLM 提供商，显著降低 token 消耗和请求延迟。

---

## 技术栈

| 类别 | 技术 |
|----------|-----------|
| 框架 | Flutter 3.11+ / Dart |
| 状态管理 | Riverpod（ref.watch / ref.read） |
| 持久化 | sqflite（对话）+ shared_preferences（设置） |
| LLM SDK | openai_dart / anthropic_sdk_dart / googleai_dart / ollama_dart |
| 语音 | speech_to_text / flutter_tts |
| UI | Material 3 / flutter_streaming_text_markdown / flutter_context_menu |
| 媒体 | image_picker / file_picker / video_player / gal |
| 平台 | window_manager（桌面端）/ flutter_local_notifications |
| 记忆检索 | SimHash（128 位）+ jieba（结巴分词） |
| 插件运行时 | 来自 `NaivG/LuaDardo` fork 的 [`lua_dardo_plus`](https://pub.dev/packages/lua_dardo_plus)（Lua 5.3）+ archive（`.plugin` zip）+ path_provider |
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
│   ├── providers/                     # 状态管理（Riverpod）
│   │   ├── chat_provider.dart         # 对话流状态
│   │   ├── settings_provider.dart     # 设置状态
│   │   ├── memory_provider.dart       # 记忆状态
│   │   ├── conversation_service_provider.dart # 对话服务
│   │   ├── memory_service_provider.dart       # 记忆服务
│   │   ├── settings_service_provider.dart      # 设置服务
│   │   └── providers.dart             # Barrel 导出
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
│   ├── plugin/                        # Lua 插件运行时
│   │   ├── plugin.dart                # Barrel 导出
│   │   ├── plugin_metadata.dart       # Manifest schema（plugin.json）
│   │   ├── lua_plugin_host.dart       # 单插件 LuaState + tessera 桥接
│   │   ├── plugin_manager.dart        # 捆绑 + 已安装的发现
│   │   └── plugin_registry.dart       # 生命周期、启用/禁用、TOOL 注册
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
│       ├── logger.dart
│       └── json_extractor.dart              # LLM JSON 输出提取（多策略容错）
├── assets/
│   ├── system_prompt.txt              # 三段式系统提示模板
│   ├── dict*.txt / idf_dict.txt       # 结巴分词词典
│   └── plugins/                       # 捆绑插件（随应用一起发布）
│       ├── plugins_index.json         # 捆绑插件 id 白名单
│       └── example_hello/             # 问候 SKILL + TOOL 示例
├── plugins/                           # 插件源码开发工作区
│   └── pack_plugin.py                 # 校验/打包 .plugin zip 的 CLI
├── android/ ios/ macos/ windows/ linux/ web/
└── test/
```

---

## 目录

- [**插件系统**](plugin-system.md) —— 沙箱化 Lua 运行时、`plugin.json` manifest、`tessera` 桥接 API、生命周期、`.plugin` 分发格式、本项目作者维护的 `NaivG/LuaDardo` fork、编写指南、内置示例
- [**记忆系统**](memory-system.md) —— 长期记忆流水线：SimHash 索引、抽取、检索打分、压缩（DBSCAN + LLM 合并）、指数衰减遗忘、`memory.db` 持久化层
- [**LLM 提供商抽象**](llm-providers.md) —— 跨 OpenAI / Anthropic / Ollama / Google 的统一 `LlmProvider` 接口、`Stream<StreamChunk>` 流式协议、`LlmProviderConfig`、`JsonExtractor` 4 步结构化输出解析
- [**能力转译**](capability-adapter.md) —— 多模态路由：视觉 / 音频 / 文生图 / TTS 子模型如何以 function-call 工具形式暴露给纯文本主模型，以及基于 slot 的 `ModelSelectionConfig`
