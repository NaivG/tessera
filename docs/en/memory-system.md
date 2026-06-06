# Memory System

Tessera's long-term memory subsystem.

## Overview

Tessera ships an experimental, biologically-inspired **long-term memory** engine that extracts facts from conversations, deduplicates them, retrieves the right ones at query time, compresses near-duplicates, and forgets low-importance entries over time — all without explicit user curation.

This is distinct from the simpler conversation history layer in [`lib/services/conversation_service.dart`](../../lib/services/conversation_service.dart) (the `tessera.db` SQLite store that simply persists chat transcripts). The memory subsystem lives in its own [`lib/memory/`](../../lib/memory/) package and uses a separate `memory.db` database file.

| Concern | Where |
|---|---|
| Storage | `memory.db` (sqflite) — separate from `tessera.db` |
| Tables | `memory_entries`, `memory_relations` + 9 indices |
| State (Riverpod) | [`lib/providers/memory_provider.dart`](../../lib/providers/memory_provider.dart) |
| UI | [`lib/ui/pages/memory_page.dart`](../../lib/ui/pages/memory_page.dart) |

## Architecture

The memory subsystem is composed of six cooperating modules under [`lib/memory/`](../../lib/memory/):

| Module | Role |
|---|---|
| [`simhash.dart`](../../lib/memory/simhash.dart) | 128-bit SimHash via jieba tokenization + SHA256-seeded random vectors + SWAR popcount hamming distance. Includes 16-bit bucket indexing for fast retrieval. |
| [`memory_retriever.dart`](../../lib/memory/memory_retriever.dart) | Bucket-based candidate lookup + `score = α·simSimilarity + β·importance + γ·recency` ranking with a one-week recency half-life. Also exposes `findClosest()` for deduplication. |
| [`memory_extractor.dart`](../../lib/memory/memory_extractor.dart) | Buffers N conversation turns (default 5), calls the LLM with a JSON extraction prompt, categorizes into `user` / `knowledge` / `event` types, batches writes. |
| [`memory_compressor.dart`](../../lib/memory/memory_compressor.dart) | Simplified DBSCAN clustering on SimHash distance ≤ 10, LLM-merged summaries, auto-purge of low-importance `event` entries older than 30 days. Records `MemoryRelation.mergedInto` edges. |
| [`memory_forgetter.dart`](../../lib/memory/memory_forgetter.dart) | Exponential-decay scoring: `score = importance × confidence × e^(-λt) × e^(-μ·daysSinceAccess)`, with per-type thresholds. Forgetting = deletion when the score falls below threshold. |
| [`memory_middleware.dart`](../../lib/memory/memory_middleware.dart) | `ConversationalMemoryManager`: rolling conversation summaries every 5 turns (initial / update / final), stored as `MemoryType.conversational` entries tied to the conversation id and cleaned at conversation end. |

## The Memory Pipeline

```
Conversation Turns
       ↓ (accumulate N rounds, default N=5)
MemoryExtractor
       ↓ (LLM extracts facts; JSON output)
Structured Memories (user / knowledge / event)
       ↓
MemoryNotifier.insertExtractions
       ↓ (SimHash + bucket index)
SQLite (memory.db)
       ↑
MemoryRetriever ← bucket lookup ← top-K
       ↓ (score = α·sim + β·importance + γ·recency)
MemoryContext injected into system prompt
       ↑
MemoryCompressor (clustering + LLM merge, every cycle)
MemoryForgetter   (time-decay scoring, every cycle)
```

Two background cycles operate independently of the chat loop:
- **Compressor** periodically clusters the table on SimHash distance ≤ 10, calls the LLM to merge each cluster's contents, and records `mergedInto` edges for the absorbed entries.
- **Forgetter** periodically evaluates `forgettingScore` against per-type thresholds and deletes entries that fall below.

## Data Model

### `MemoryEntry` ([`lib/models/memory_entry.dart`](../../lib/models/memory_entry.dart))

| Field | Type | Notes |
|---|---|---|
| `id` | String (UUID) | Primary key |
| `type` | `MemoryType` | One of `user` / `knowledge` / `event` / `conversational` / `longTerm` |
| `content` | String | Core text |
| `hash` | String (128 bits) | SimHash binary string for similarity |
| `importance` | double | 0.0 – 1.0; higher = more persistent |
| `confidence` | double | 0.0 – 1.0; how often it's been corroborated |
| `conversationId` | String? | Required for `conversational` entries |
| `sourceMessageId` | String? | Provenance back to the message |
| `accessCount` | int | Retrieval hit count |
| `createdAt` / `updatedAt` / `lastAccessed` | DateTime | Time + access tracking |

### `MemoryType` ([`lib/models/memory_type.dart`](../../lib/models/memory_type.dart))

| Type | Lifecycle | Forgetting threshold |
|---|---|---|
| `user` | Permanent (preferences, identity, habits) | 0.05 — almost never forgotten |
| `knowledge` | Permanent (facts, technical info) | 0.1 |
| `event` | Long-term (things that happened) | 0.2 — forgotten faster |
| `conversational` | Tied to conversation lifetime | 0.0 — purged at conversation end, not scored |
| `longTerm` | Permanent (user-promoted entries) | 0.05 |

### `MemoryRelation` ([`lib/models/memory_relation.dart`](../../lib/models/memory_relation.dart))

Edges between two `MemoryEntry`s:

| Type | Meaning |
|---|---|
| `derived_from` | One memory was derived from another |
| `contradicts` | Two memories disagree |
| `supports` | One memory corroborates another (used by the retriever for near-duplicate confidence boosting at distance ≤ 16) |
| `merged_into` | Source has been absorbed into target; source is logically deleted |

## SimHash Indexing

[`lib/memory/simhash.dart`](../../lib/memory/simhash.dart) computes a 128-bit SimHash fingerprint per text:

1. **Tokenize** the input via [`jieba_flutter`](https://pub.dev/packages/jieba_flutter) (Chinese segmentation + basic Latin splitting).
2. For each unique token, deterministically generate a 128-dim Gaussian random vector seeded by `SHA256(token)`. The same token always gets the same vector.
3. Sum all token vectors.
4. Threshold each dimension to a bit (≥ 0 → 1, < 0 → 0). Output is a 128-character binary string.

Two texts are similar iff their SimHash bit-strings have small **Hamming distance** (popcount of XOR). The implementation uses SWAR popcount and reports a 0.0 – 1.0 similarity as `1 - hamming / 128`.

### Bucket index

The first 16 bits of the hash prefix the entry into one of 65,536 buckets. The retriever's `getByBucketPrefix(16)` does a fast SQL `LIKE '0110…%'` lookup; if the candidate set is too small (`< minBucketSize`, default 3), it falls back to an 8-bit prefix for an expanded search. There are dedicated `idx_memory_hash16` and `idx_memory_hash32` indices on `SUBSTR(hash, 1, 16/32)` for this.

Dedup thresholds: distance ≤ 8 → near-duplicate (boost confidence), distance ≤ 16 → `supports` relation candidate.

## Retrieval Scoring

[`MemoryRetriever.search`](../../lib/memory/memory_retriever.dart):

```
score = α · simSimilarity + β · importance + γ · recency
```

Default weights: `α = 0.5`, `β = 0.3`, `γ = 0.2`. `recency` is `1 / (1 + hoursSinceAccess / 168)` — i.e. a one-week half-life: a memory accessed 1 week ago scores 0.5, 2 weeks ago 0.33, 4 weeks 0.2. The top-K results (default K = 5) are returned, and each hit increments the entry's `accessCount` and updates `lastAccessed`.

## Extraction

[`MemoryExtractor`](../../lib/memory/memory_extractor.dart) is the write-side counterpart. Every N turns (default 5) the chat pipeline calls it with a JSON extraction prompt:

```text
你是一个记忆提取助手。请从以下对话轮次中提取有价值的信息，分类为：
- user：关于用户的偏好、身份、习惯、技能等信息
- knowledge：事实、知识点、技术信息
- event：发生的事件、完成的任务、达成的决定

规则：
1. 每条提取必须简洁、独立可理解（无需上下文即可读懂）
2. importance 评分 0.0~1.0
3. 只提取有实质内容的信息，忽略闲聊和过渡性内容
4. 不要重复提取已明确的内容

返回 ONLY 一个 JSON 数组 — 不要 markdown 代码块、不要解释、不要其他任何文字。
如果没有值得记忆的内容，返回空数组 []。
```

The output is parsed via [`JsonExtractor`](../../lib/utils/json_extractor.dart) (see [LLM Provider Abstraction → Structured Output](llm-providers.md#structured-output)). Extractions are buffered and batch-flushed at `batchWriteThreshold` (default 3) — `MemoryNotifier.insertExtractions` does the SimHash + dedup write.

## Compression

[`MemoryCompressor.compressAll`](../../lib/memory/memory_compressor.dart):

1. Load all non-`conversational` entries.
2. Run simplified DBSCAN clustering on SimHash distance ≤ `clusterDistance` (default 10).
3. For each cluster of size ≥ 2, sort by importance; ask the LLM to merge all entries into a single concise summary.
4. Update the highest-importance cluster member with the merged content, the cluster's max `confidence` and max `importance`.
5. For every absorbed entry, insert a `mergedInto` relation pointing to the survivor.

## Forgetting

[`MemoryForgetter.run`](../../lib/memory/memory_forgetter.dart) walks all non-`conversational` entries and computes:

```
forgettingScore = importance × confidence × e^(-λ·daysSinceCreated) × e^(-μ·daysSinceAccess)
```

with `λ = 0.01/day` (≈ 70-day time half-life) and `μ = 0.05/day` (≈ 14-day access half-life). When `forgettingScore < type.forgettingThreshold`, the entry is **deleted** (a comment in the file notes that an `memory_archived` table is the planned future extension; for now it's hard delete).

## Persistence

[`MemoryService`](../../lib/services/memory_service.dart) opens `memory.db` (version 1). Schema:

- `memory_entries(id, type, content, hash, importance, confidence, conversation_id, source_message_id, access_count, created_at, updated_at, last_accessed)`
- `memory_relations(id, source_id, target_id, relation_type, weight)` with `ON DELETE CASCADE` on both FKs

Indices: `idx_memory_type`, `idx_memory_hash`, `idx_memory_hash16`, `idx_memory_hash32`, `idx_memory_conv`, `idx_memory_importance` (DESC), `idx_memory_last_accessed` (DESC), `idx_memory_rel_source`, `idx_memory_rel_target`. The two hash-prefix indices are the bucket-acceleration indices used by the retriever.

## State & UI

[`MemoryNotifier`](../../lib/providers/memory_provider.dart) is a Riverpod `Notifier<MemoryData>` that wraps the service. It exposes:

- `init()` — boot: ensures `SimHash.init()` has run, refreshes stats, sets `initialized = true`
- `insertExtractions(...)` — batched write path with dedup-on-insert; near-duplicates (distance ≤ 8) get a confidence boost instead of a new row
- `search(query)` — proxies `MemoryRetriever.search`
- `createLongTermMemory(...)` — promotes a `conversational` summary into a permanent `longTerm` entry

The Memory page ([`lib/ui/pages/memory_page.dart`](../../lib/ui/pages/memory_page.dart)) shows total counts by type, the last search results, and a list of `longTerm` entries the user can edit or promote.

## How the Chat Pipeline Uses Memory

On each turn, the chat pipeline calls `MemoryRetriever.search` with the latest user input, takes the top-K results, and renders them into a markdown section that's appended to the system prompt. The main model sees the retrieved facts as part of its context and can reason over them. Retrieval also touches each hit's `accessCount` and `lastAccessed`, which is what keeps the recency half-life honest.

Conversational memory (the rolling 5-turn summary) is computed by [`ConversationalMemoryManager`](../../lib/memory/memory_middleware.dart) and stored as `MemoryType.conversational` entries scoped to the active conversation id — they're cleaned up when the conversation ends and don't participate in forgetting.

## See Also

- [Architecture Overview](../README.md) — prompt caching, structured output, and subsystem context
- [LLM Provider Abstraction](llm-providers.md) — the LLM calls that drive extraction, summarization, and compression
- [Capability Adapter](capability-adapter.md) — how memory is one of several inputs to the per-turn system prompt
- [Plugin System](plugin-system.md) — tool calls share the same `ToolDefinition` / `ToolResult` envelope
