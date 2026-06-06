# 能力转译

本页是 Tessera 多模态路由层的深入讲解 —— 一个纯文本主模型如何调用视觉子模型。

## 概述

主对话模型并不总是多模态的：用户可能为省钱把一个快的小型纯文本 LLM 设为主模型，但仍希望助手能读懂他粘贴的图片、播放一段 TTS 语音、按需生成一张图。

**能力转译适配器**（[`lib/core/capability_adapter.dart`](../../lib/core/capability_adapter.dart)）就是这道桥梁。它读取用户的 [`ModelSelectionConfig`](../../lib/models/model_selection_config.dart)，对**主模型原生不支持**的每种能力，把一个 **TOOL** 注册到全局 [`ToolRegistry`](../../lib/core/tool_registry.dart) 中。当 LLM 发出对应的 `ToolCall`，适配器把它路由到正确的子模型，发起请求，再把结果以 `ToolResult` 形式合并回对话。

主模型全程不需要知道自己正在跟另一个模型说话 —— 它只管调用工具，剩下的事 adapter 都包了。

## 架构图

```
┌─────────────────────────────────────────────────────────┐
│                   主对话模型                              │
│   (如 GPT-4o、Claude 4、Gemini 3 Pro)                  │
└──────────┬──────────┬──────────┬──────────┬──────────────┘
           │          │          │          │
           │          │          │          │
     ┌─────▼──┐  ┌────▼───┐  ┌───▼────┐ ┌───▼──────┐
     │视觉     │  │音频    │   │图像    │ │语音      │
     │模型     │  │模型    │   │生成    │ │生成模型   │
     │(任意)   │  │(任意)  │   │(任意)  │ │(任意)    │
     └────────┘  └────────┘  └────────┘ └──────────┘
            ↑ CapabilityAdapter 路由工具调用
            ↑ ToolRegistry 按工具名分发
```

## 多模态工具注册

`CapabilityAdapter.buildTools()` 审视 `ModelSelectionConfig`，按需产出以下工具之一：

| 工具 | 触发条件 | 子模型槽位 |
|---|---|---|
| `vision` | 配置了视觉模型，且主模型**不**原生带 `vision` tag | `ModelSelectionConfig.resolveInput(ModelTag.vision, state)` |
| `audible` | 配置了音频模型，且主模型不带 `audible` tag | `resolveInput(ModelTag.audible, state)` |
| `image_generate` | 配置了文生图输出模型 | `resolveOutput(ModelType.image, state)` |
| `speech_generate` | 配置了文生语音输出模型 | `resolveOutput(ModelType.speech, state)` |

如果主模型原生支持该模态（即解析出的 slot 等于 `config.mainModel`），对应工具就**不会**注册 —— 由主模型直接处理。这就是"优雅降级"特性：用一个完整多模态主模型的用户完全感受不到额外的工具开销。

`registerTools(toolRegistry)` 把每个产出的 `ToolDefinition` 绑定到一个 handler，handler 内部委托给 `executeTool(toolCall)`。

## 工具分发与执行

主模型发出 `ToolCall` 后，对话流水线走 `ToolRegistry.execute(call)` → `CapabilityAdapter.executeTool(call)`：

| 工具 | Handler | 行为 |
|---|---|---|
| `vision` | `_executeVision` | 加载被引用的图片 / 视频（object key、文件名、URL、data URI），用 LLM 的问题调用视觉模型，把描述以文本形式返回 |
| `audible` | `_executeAudible` | 加载被引用的音频，调用音频模型，返回转写 / 描述 |
| `image_generate` | `_executeImageGenerate` | 用 LLM 的 prompt 调用文生图模型，返回 `libraryId` 引用（或描述，取决于流水线） |
| `speech_generate` | `_executeSpeechGenerate` | 调用 TTS 模型，返回 `libraryId` 引用，作为音频注入对话 |

返回的 `ToolResult` 合并为对话中一条合成的 tool-role 消息；主模型看到结果后继续本轮。这是与[插件工具调用](plugin-system.md)完全一样的信封。

## 模型选择矩阵

用户的配置是一个 [`ModelSelectionConfig`](../../lib/models/model_selection_config.dart)，共 5 个逻辑槽位：

| 槽位 | 类型 | 用途 | 解析方式 |
|---|---|---|---|
| `mainModel` | `ModelSlot` | 主文本 LLM | 始终用于对话 |
| `inputModalities` | `Map<ModelTag, ModelSlot?>` | 按输入模态的子模型 | `resolveInput(tag, state)` |
| `outputModalities` | `Map<ModelType, ModelSlot?>` | 按输出类型的子模型 | `resolveOutput(type, state)` |
| `otherModels` | `Map<String, ModelSlot?>` | 嵌入、重排、…… | `resolveOther(key, state)` |

### `ModelTag`（输入模态）

| Tag | 含义 |
|---|---|
| `text` | 文本输入 / 输出 |
| `vision` | 图像输入（视觉理解） |
| `audible` | 音频输入 / 输出 |
| `video` | 视频输入 / 输出 |

当一个模型同时具备 `text` + `vision` + `audible` + `video` 时，被视为**全模态（omni）**模型。[`ModelInfo`](../../lib/models/model_info.dart) 的 `tags` 字段保存这个集合。

### `ModelType`（输出类型）

| 类型 | 含义 | 短名 |
|---|---|---|
| `text` | 文本生成（LLM） | `LLM` |
| `image` | 文生图 | `TTI` |
| `video` | 文生视频 | `TTV` |
| `speech` | 文生语音 | `TTS` |
| `embedding` | 嵌入向量 | `EMB` |
| `ranking` | 重排 / 打分 | `RNK` |

### 为什么用 UUID 而非数组下标

`ModelSlot` 用 UUID 引用其提供商 + 模型：

```dart
class ModelSlot {
  final String providerConfigId;  // LlmProviderConfig.id
  final String modelUid;          // ModelInfo.uid
}
```

这替代了旧的整数下标方案（`pi` / `mi` 数组）—— 后者在用户删除或重排提供商时容易失效。UUID 能跨重排、跨删除、跨磁盘上的模型列表重建保持稳定。`ModelSlot.fromJson` 仍能读取旧格式（`pi` / `mi` 强制转成空串），加载阶段用兼容逻辑兜底。

传给 `resolveInput / resolveOutput` 的 `state` 参数是 `SettingsState`（或任何具有 `providerConfigs` + 每项 `models` / `format` / `apiKey` / `baseUrl` 字段的对象）。Slot 按需解析为完整的 [`LlmConfig`](../../lib/models/llm_config.dart) —— API key 与 base URL 从用户设置中**实时**取，不复制进序列化结果，因此保存的配置不会泄露密钥。

## 端到端工具执行流

```
用户: "这张图里有什么？"
   ↓
对话流水线构建系统提示 + 工具列表
   ↓
主模型发出 ToolCall(name="vision", args={type:"image", object:"img_42", question:"这张图里有什么？"})
   ↓
ToolRegistry.execute(call) → CapabilityAdapter._executeVision(call)
   ↓
CapabilityAdapter 解析 vision slot → LlmConfig
   ↓
ProviderFactory.get(format).chat(config, history, …) 调用视觉模型
   ↓
视觉模型的描述作为 ToolResult 返回
   ↓
工具结果消息合并到对话
   ↓
主模型看到描述，写出面向用户的回答
```

## 配置 UI

两个相关页面：

- [`lib/ui/pages/model_selection_page.dart`](../../lib/ui/pages/model_selection_page.dart) —— 选主模型 + 各槽位的子模型
- [`lib/ui/pages/model_edit_page.dart`](../../lib/ui/pages/model_edit_page.dart) —— 在 provider config 中新增 / 编辑模型条目（UID、display name、capability tags、model type）

两页都属于设置流程，通过 `ModelSelectionConfig.toJson()` 持久化。

## 参见

- [LLM 提供商抽象](llm-providers.md) —— 适配器调用 `LlmProvider` 驱动各子模型
- [插件系统](plugin-system.md) —— 插件工具共享同一个 `ToolDefinition` / `ToolCall` / `ToolResult` 信封与 `ToolRegistry`
- [记忆系统](memory-system.md) —— 检索到的记忆是 system prompt 的多个输入之一
- [`lib/core/tool_registry.dart`](../../lib/core/tool_registry.dart) —— 全局分发表
- [`lib/models/model_selection_config.dart`](../../lib/models/model_selection_config.dart) —— 基于 slot 的配置模型
