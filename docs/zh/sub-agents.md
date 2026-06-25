# 子 Agent

Tessera 的并行流式子任务执行器。

## 概述

有些请求天然就是并行的：「研究 A、研究 B、研究 C，然后综合」。让单个 chat 模型顺序做 A、B、C 会浪费墙钟时间。Tessera 的**子 Agent** 层让主模型把 N 个独立子任务扇出；每个子任务作为一次独立的流式 LLM 调用，拥有自己的 session id、系统提示词以及实时 delta 流；主 UI 中每个子 Agent 是一张随 LLM 流式输出而更新的卡片。

两个入口：

- **Agent / Agent-Cluster 对话模式**（[`lib/models/conversation_mode.dart`](../../lib/models/conversation_mode.dart)）—— chat pipeline 自身把请求拆成 `SubAgentTask` 列表，通过 `SubAgentManager.runParallelStreaming` 分发。
- **`spawn_sub_agent` 工具**（[`lib/core/sub_agent_tool.dart`](../../lib/core/sub_agent_tool.dart)）—— 暴露给主 LLM，让它可以在对话中途派生一个子 Agent 并等待结果；由 `SubAgentManager.runSingle`（非流式版本）处理。

| 关注点 | 位置 |
|---|---|
| Manager（并行流式、生命周期） | [`lib/core/sub_agent_manager.dart`](../../lib/core/sub_agent_manager.dart) |
| `spawn_sub_agent` 工具 | [`lib/core/sub_agent_tool.dart`](../../lib/core/sub_agent_tool.dart) |
| Per-session 状态 | [`lib/providers/session_provider.dart`](../../lib/providers/session_provider.dart) |
| Per-conversation 模式标志 | [`lib/models/conversation_mode.dart`](../../lib/models/conversation_mode.dart) |
| UI 卡片 | [`lib/ui/widgets/sub_agent_card.dart`](../../lib/ui/widgets/sub_agent_card.dart) |
| Plan 模式搭档 | [`lib/ui/widgets/plan_block.dart`](../../lib/ui/widgets/plan_block.dart)、[`lib/utils/plan_parser.dart`](../../lib/utils/plan_parser.dart) |

## 对话模式

`ConversationMode`（在 [`lib/models/conversation_mode.dart`](../../lib/models/conversation_mode.dart) 中定义）是 per-conversation 的标志，驱动 chat pipeline：

| 模式 | 行为 |
|---|---|
| `normal` | 普通单流对话；无子 Agent，无 Plan |
| `plan` | LLM 先输出一份结构化 `Plan`（由 `PlanParser` 解析）；用户审批步骤后，pipeline 逐项执行 |
| `agent` | LLM 可以在对话中调用 `spawn_sub_agent` 工具来委派子任务 |
| `agentCluster` | LLM 一次性给出子任务列表；`SubAgentManager.runParallelStreaming` 并行执行；结果被汇总后做一次最终综合 turn |

模式存放在 `Conversation` 模型上，通过侧边栏 / `conversation_menu.dart` 切换。

## `SubAgentManager` —— 并行流式

`SubAgentManager.runParallelStreaming(...)` 是 `agentCluster` 模式以及任何自定义扇出的核心。签名：

```dart
Future<List<SubAgentStreamHandle>> runParallelStreaming({
  required List<SubAgentTask> tasks,
  required LlmConfig config,
  required String conversationId,
  required String parentSessionId,
  required String systemPrompt,
  required void Function(String sessionId, SessionStatus status) onStatusChange,
  required Future<String> Function(SubAgentTask task) createSessionCallback,
  String? pluginSkills,
  String? memoryContext,
});
```

执行步骤：

1. **预创建 session** —— 对每个 task 调用 `createSessionCallback(task)`，在数据库中物化一个 session。`onStatusChange(sessionId, running)` 被触发，UI 把卡片翻成「运行中」。
2. **每个 task 拉起一个流式调用** —— 为每个 task 构造一个 `SubAgentStreamHandle`（持有 `contentController` 与 `thinkingController`，均为 broadcast `StreamController<String>`），然后用单消息 history（`[ userMsg ]`，其中 `userMsg` 打包 task title、description、可选 context）调用 provider 的 `chatStream`。
3. **并行运行，不阻塞** —— 这些 future 通过 `unawaited(Future.wait(futures))` 调度，调用方立刻拿到 handles 列表，可以独立监听每个 handle 的流。
4. **Per-chunk 分发** —— `_runStreaming` 的 listener 把 `contentDelta` 与 `thinkingDelta` chunk 分别送入对应 handle 的 controller；`done` 时把最终的 `userMsg` + `assistantMsg` 持久化到 conversation service，并触发 `onStatusChange(sessionId, completed)`。错误触发 `failed` 并把错误加进 content 流。
5. **子 Agent 提示词变体** —— `buildSubAgentPrompt(...)` 在继承的系统提示词后追加一段子 Agent 框架（"You are a sub-agent working on a specific task…"）以及可选的 `pluginSkills`、`memoryContext` 段。

### `SubAgentStreamHandle`

```dart
class SubAgentStreamHandle {
  final String sessionId;
  final StreamController<String> contentController;  // broadcast
  final StreamController<String> thinkingController; // broadcast
  void cancel();  // 停止底层流订阅
}
```

chat pipeline / UI 监听两个流，累积 delta 并渲染正在运行的卡片。`cancel()` 拆掉订阅并关闭两个 controller（用于用户中止整个运行）。

### `SubAgentTask` 与 `SubAgentResult`

```dart
class SubAgentTask {
  final String title;
  final String description;
  final String? context;
}

class SubAgentResult {
  final String sessionId;
  final String title;
  final String content;
  final bool success;
  final String? error;
}
```

`SubAgentTask` 是输入；`SubAgentResult` 是非流式版 `runSingle` 的返回（供 `spawn_sub_agent` 工具使用）。

## `spawn_sub_agent` 工具

当对话处于 `agent` 模式时，主模型可以针对 `spawn_sub_agent` 发出 `ToolCall`：

```json
{
  "name": "spawn_sub_agent",
  "arguments": {
    "task": "调研 Postgres vs SQLite 在嵌入式场景下的取舍",
    "context": "聚焦写密集工作负载与 FTS"
  }
}
```

工具的 handler（在 `chat_provider.dart` 中）创建一个 session，调用 `SubAgentManager.runSingle`，等待最终 `SubAgentResult`，并把它作为 `ToolResult` 合回主对话。主模型在下一轮中就能看到子 Agent 的完整输出并据其推理。

## 子 Agent 卡片 UI

`SubAgentCard`（[`lib/ui/widgets/sub_agent_card.dart`](../../lib/ui/widgets/sub_agent_card.dart)）是 per-task 的 UI 表面。展示：

- 任务标题
- 实时更新的内容区（订阅 `contentController.stream`）
- 思考区（若 `thinkingController` 产生内容，Claude / Gemini 风格的 chain-of-thought）
- 状态徽章 —— `running` / `completed` / `failed` —— 由 `onStatusChange` 驱动

卡片以 `sessionId` 为 key，所以多个子 Agent 可以同时流式输出而互不干扰。中止主运行会逐个 `cancel()` 所有 handle。

## Plan 模式（搭配特性）

Plan 模式是子 Agent 的「之前」：LLM 先输出一份结构化 Plan（一组 `Plan` 条目 —— `lib/models/plan.dart`），用户可以编辑/审批，然后 pipeline 再按步骤执行。Plan 由 `PlanParser`（`lib/utils/plan_parser.dart`）解析。

`agentCluster` 模式是自然延伸：把 `plan` 风格的拆解通过 `runParallelStreaming` 并行执行，每个 plan item 一个子 Agent，最后再来一轮综合。

## 端到端：agentCluster 模式

```
用户：「比较 A、B、C 在我们场景下的优劣」
   ↓
Chat pipeline（agentCluster 模式）→ SubAgentManager.runParallelStreaming
   ├─ task 1 → sessionId_1, runParallel streaming, contentStream_1
   ├─ task 2 → sessionId_2, runParallel streaming, contentStream_2
   └─ task 3 → sessionId_3, runParallel streaming, contentStream_3
   ↓
三张 SubAgentCard，实时更新
   ↓
三路 `done` → 对主模型做一次综合 turn
   ↓
主模型产出比较
```

## 参见

- [发现系统](discover-system.md) —— 子 Agent 看到同一份紧凑 skill 目录
- [工作空间工具](workspace-tools.md) —— 子 Agent 可以被指向某个工作空间来执行任务
- [LLM 提供商抽象](llm-providers.md) —— 子 Agent 消费的 `Stream<StreamChunk>` 协议
- [`lib/core/sub_agent_manager.dart`](../../lib/core/sub_agent_manager.dart) —— `SubAgentManager` 源码
- [`lib/core/sub_agent_tool.dart`](../../lib/core/sub_agent_tool.dart) —— `spawn_sub_agent` 工具
