# Sub-Agents

Tessera's parallel streaming sub-task runner.

## Overview

Some requests are naturally parallel: "research A, research B, research C, then
synthesize." A single chat model that has to do A, B, C sequentially wastes
wall-clock time. Tessera's **sub-agent** layer lets the main model fan out N
independent sub-tasks; each sub-task runs as its own streaming LLM call with
its own session id, system prompt, and live delta stream; the main UI shows
each sub-agent as a card that updates as the LLM streams.

Two entry points:

- **Agent / Agent-Cluster conversation mode** ([`lib/models/conversation_mode.dart`](../../lib/models/conversation_mode.dart))
  — the chat pipeline itself splits the request into a list of `SubAgentTask`
  and dispatches them via `SubAgentManager.runParallelStreaming`.
- **The `spawn_sub_agent` TOOL** ([`lib/core/sub_agent_tool.dart`](../../lib/core/sub_agent_tool.dart))
  — exposed to the main LLM, lets it spawn a single sub-agent mid-conversation
  and wait for the result. Handled by `SubAgentManager.runSingle` (the
  non-streaming sibling).

| Concern | Source |
|---|---|
| Manager (parallel streaming, lifecycle) | [`lib/core/sub_agent_manager.dart`](../../lib/core/sub_agent_manager.dart) |
| The `spawn_sub_agent` TOOL | [`lib/core/sub_agent_tool.dart`](../../lib/core/sub_agent_tool.dart) |
| Per-session state | [`lib/providers/session_provider.dart`](../../lib/providers/session_provider.dart) |
| Per-conversation mode flag | [`lib/models/conversation_mode.dart`](../../lib/models/conversation_mode.dart) |
| UI card | [`lib/ui/widgets/sub_agent_card.dart`](../../lib/ui/widgets/sub_agent_card.dart) |
| Plan-mode counterpart | [`lib/ui/widgets/plan_block.dart`](../../lib/ui/widgets/plan_block.dart), [`lib/utils/plan_parser.dart`](../../lib/utils/plan_parser.dart) |

## Conversation modes

`ConversationMode` (defined in [`lib/models/conversation_mode.dart`](../../lib/models/conversation_mode.dart))
is a per-conversation flag that drives the chat pipeline:

| Mode | Behavior |
|---|---|
| `normal` | Plain single-stream chat; no sub-agents, no plan |
| `plan` | LLM first emits a structured `Plan` (parsed by `PlanParser`); user approves steps; the pipeline then runs them one by one |
| `agent` | LLM can call the `spawn_sub_agent` tool mid-conversation to delegate subtasks |
| `agentCluster` | LLM emits a list of sub-tasks up front; `SubAgentManager.runParallelStreaming` runs them in parallel; results are aggregated and a final synthesis turn is generated |

The mode is stored on the `Conversation` model and switched from the
sidebar / conversation menu (`lib/ui/widgets/conversation_menu.dart`).

## `SubAgentManager` — parallel streaming

`SubAgentManager.runParallelStreaming(...)` is the heart of `agentCluster` mode
and of any custom fan-out. The signature:

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

What it does, step by step:

1. **Pre-create sessions** — call `createSessionCallback(task)` for each task to
   materialize a session in the database. `onStatusChange(sessionId, running)`
   is fired so the UI can flip the card to "running".
2. **Spin up one streaming call per task** — for each task, build a
   `SubAgentStreamHandle` (which owns a `contentController` and a
   `thinkingController`, both broadcast `StreamController<String>`s), then
   start the provider's `chatStream` against a single-message history (`[
   userMsg ]` where `userMsg` packs the task title, description, and optional
   context).
3. **Run in parallel, don't block** — the futures are scheduled with
   `unawaited(Future.wait(futures))`. The caller gets back the list of
   handles immediately and can listen to each handle's stream independently.
4. **Per-chunk dispatch** — the `_runStreaming` listener fans `contentDelta`
   and `thinkingDelta` chunks into the corresponding handle's controllers; on
   `done` it persists the final `userMsg` + `assistantMsg` to the conversation
   service and fires `onStatusChange(sessionId, completed)`. Errors fire
   `failed` and add the error to the content stream.
5. **Sub-agent prompt variant** — `buildSubAgentPrompt(...)` appends a
   sub-agent framing sentence ("You are a sub-agent working on a specific
   task. Focus on completing the assigned task thoroughly and return a
   comprehensive result.") plus optional `pluginSkills` and `memoryContext`
   blocks to the inherited system prompt.

### `SubAgentStreamHandle`

```dart
class SubAgentStreamHandle {
  final String sessionId;
  final StreamController<String> contentController;  // broadcast
  final StreamController<String> thinkingController; // broadcast
  void cancel();  // stops the underlying stream subscription
}
```

The chat pipeline / UI listens to both streams, accumulates the deltas, and
renders the running card. `cancel()` tears down the subscription and closes
both controllers (used when the user aborts the run).

### `SubAgentTask` and `SubAgentResult`

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

`SubAgentTask` is the input; `SubAgentResult` is the non-streaming sibling
returned by `runSingle` (used by the `spawn_sub_agent` tool).

## The `spawn_sub_agent` tool

When the conversation is in `agent` mode, the main model can emit a
`ToolCall` against `spawn_sub_agent`:

```json
{
  "name": "spawn_sub_agent",
  "arguments": {
    "task": "Investigate the trade-offs of Postgres vs SQLite for embedded use",
    "context": "Focus on write-heavy workloads and FTS"
  }
}
```

The tool's handler (in `chat_provider.dart`) creates a session, calls
`SubAgentManager.runSingle`, awaits the final `SubAgentResult`, and returns it
as a `ToolResult` merged into the main conversation. The main model sees the
sub-agent's full output and can reason over it in its next turn.

## Sub-agent card UI

`SubAgentCard` ([`lib/ui/widgets/sub_agent_card.dart`](../../lib/ui/widgets/sub_agent_card.dart))
is the per-task UI surface. It shows:

- The task title
- A live-updating content area (subscribed to `contentController.stream`)
- A thinking area, if `thinkingController` produces anything (Claude / Gemini
  style chain-of-thought)
- A status pill — `running` / `completed` / `failed` — driven by
  `onStatusChange`

The card is keyed by `sessionId`, so multiple sub-agents can stream
concurrently without stepping on each other. Cancelling the main run cancels
each handle in turn.

## Plan mode (companion feature)

Plan mode is the "before" to sub-agents' "during": the LLM first emits a
structured plan (a list of `Plan` entries — `lib/models/plan.dart`), the
user can edit/approve it, and the pipeline then executes the plan. Plans are
parsed by `PlanParser` (`lib/utils/plan_parser.dart`).

`agentCluster` mode is the natural extension: a `plan`-style decomposition
runs in parallel via `runParallelStreaming`, with one sub-agent per plan
item, and a final synthesis turn at the end.

## End-to-end: agentCluster mode

```
User: "Compare A, B, and C for our use case"
   ↓
Chat pipeline (agentCluster mode) → SubAgentManager.runParallelStreaming
   ├─ task 1 → sessionId_1, runParallel streaming, contentStream_1
   ├─ task 2 → sessionId_2, runParallel streaming, contentStream_2
   └─ task 3 → sessionId_3, runParallel streaming, contentStream_3
   ↓
Three SubAgentCards, each updating live
   ↓
All three `done` → final synthesis turn against the main model
   ↓
Main model produces the comparison
```

## See also

- [Discover System](discover-system.md) — sub-agents see the same compact skill catalog
- [Workspace Tools](workspace-tools.md) — sub-agents can be pointed at a workspace to do their work
- [LLM Provider Abstraction](llm-providers.md) — the `Stream<StreamChunk>` protocol that sub-agents consume
- [`lib/core/sub_agent_manager.dart`](../../lib/core/sub_agent_manager.dart) — `SubAgentManager` source
- [`lib/core/sub_agent_tool.dart`](../../lib/core/sub_agent_tool.dart) — the `spawn_sub_agent` tool
