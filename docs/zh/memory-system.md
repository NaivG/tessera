# 记忆系统

本页是 Tessera 长期记忆子系统的深入讲解。

## 概述

Tessera 内置一个**实验性**的、仿生启发的**长期记忆**引擎：从对话中抽取事实、去重、查询时取回、合并近似项、随时间遗忘低重要性条目 —— 整个过程无需用户手工整理。

这与简单的"对话历史"层（[`lib/services/conversation_service.dart`](../../lib/services/conversation_service.dart) 中的 `tessera.db`，仅用于持久化聊天记录）是不同的概念。记忆子系统位于独立的 [`lib/memory/`](../../lib/memory/) 包中，使用单独的 `memory.db` 数据库文件。

| 关注点 | 位置 |
|---|---|
| 存储 | `memory.db`（sqflite），与 `tessera.db` 分离 |
| 数据表 | `memory_entries`、`memory_relations` + 9 个索引 |
| 状态层（Riverpod） | [`lib/providers/memory_provider.dart`](../../lib/providers/memory_provider.dart) |
| UI | [`lib/ui/pages/memory_page.dart`](../../lib/ui/pages/memory_page.dart) |

## 架构

记忆子系统由 [`lib/memory/`](../../lib/memory/) 下的六个协作模块组成：

| 模块 | 职责 |
|---|---|
| [`simhash.dart`](../../lib/memory/simhash.dart) | 128 位 SimHash：结巴分词 + SHA256 种子伪随机向量 + SWAR popcount 汉明距离；含 16 位分桶加速检索 |
| [`memory_retriever.dart`](../../lib/memory/memory_retriever.dart) | 桶内候选查找 + `score = α·simSimilarity + β·importance + γ·recency` 综合排序（一周 recency 半衰期）；另提供 `findClosest()` 用于去重 |
| [`memory_extractor.dart`](../../lib/memory/memory_extractor.dart) | 缓冲 N 轮对话（默认 5），调用 LLM 用 JSON prompt 抽取事实，分类为 `user` / `knowledge` / `event`，批量写入 |
| [`memory_compressor.dart`](../../lib/memory/memory_compressor.dart) | 简化的 DBSCAN 聚类（SimHash 距离 ≤ 10）+ LLM 合并摘要；自动清理 30 天以上低重要性 `event`；记录 `MemoryRelation.mergedInto` 边 |
| [`memory_forgetter.dart`](../../lib/memory/memory_forgetter.dart) | 指数衰减打分：`score = importance × confidence × e^(-λt) × e^(-μ·daysSinceAccess)`，按类型阈值判定；低于阈值即**删除** |
| [`memory_middleware.dart`](../../lib/memory/memory_middleware.dart) | `ConversationalMemoryManager`：每 5 轮滚动生成一次对话摘要（初次 / 更新 / 收尾），以 `MemoryType.conversational` 形式存储并绑定到 conversation id，对话结束时清理 |

## 记忆流水线

```
对话轮次
       ↓ (累积 N 轮，默认 N=5)
MemoryExtractor
       ↓ (LLM 抽取事实；JSON 输出)
结构化记忆 (user / knowledge / event)
       ↓
MemoryNotifier.insertExtractions
       ↓ (SimHash + 桶索引)
SQLite (memory.db)
       ↑
MemoryRetriever ← 桶内查找 ← 取 Top-K
       ↓ (score = α·sim + β·importance + γ·recency)
MemoryContext 注入到系统提示
       ↑
MemoryCompressor (聚类 + LLM 合并，定期)
MemoryForgetter   (时间衰减打分，定期)
```

两个后台循环独立于对话循环运行：
- **Compressor** 周期性在 SimHash 距离 ≤ 10 上聚类，调用 LLM 合并每个簇的内容，并记录 `mergedInto` 边指向被吸收的条目。
- **Forgetter** 周期性评估每条记忆的 `forgettingScore` 与类型阈值，删除低于阈值的条目。

## 数据模型

### `MemoryEntry`（[`lib/models/memory_entry.dart`](../../lib/models/memory_entry.dart)）

| 字段 | 类型 | 说明 |
|---|---|---|
| `id` | String（UUID） | 主键 |
| `type` | `MemoryType` | `user` / `knowledge` / `event` / `conversational` / `longTerm` 之一 |
| `content` | String | 核心文本 |
| `hash` | String（128 位） | SimHash 二进制串，用于相似度比较 |
| `importance` | double | 0.0 – 1.0，越高越持久 |
| `confidence` | double | 0.0 – 1.0，被印证的次数比例 |
| `conversationId` | String? | `conversational` 类型必填 |
| `sourceMessageId` | String? | 来源消息，可追溯 |
| `accessCount` | int | 被检索命中的次数 |
| `createdAt` / `updatedAt` / `lastAccessed` | DateTime | 时间与最近访问 |

### `MemoryType`（[`lib/models/memory_type.dart`](../../lib/models/memory_type.dart)）

| 类型 | 生命周期 | 遗忘阈值 |
|---|---|---|
| `user` | 永久（偏好、身份、习惯） | 0.05 —— 几乎不遗忘 |
| `knowledge` | 永久（事实、技术信息） | 0.1 |
| `event` | 长期（发生过的事情） | 0.2 —— 遗忘更快 |
| `conversational` | 与对话同生命周期 | 0.0 —— 对话结束即清理，不参与打分 |
| `longTerm` | 永久（用户升级后的条目） | 0.05 |

### `MemoryRelation`（[`lib/models/memory_relation.dart`](../../lib/models/memory_relation.dart)）

记录两条 `MemoryEntry` 之间的边：

| 类型 | 含义 |
|---|---|
| `derived_from` | 一条记忆从另一条衍生而来 |
| `contradicts` | 两条记忆相互矛盾 |
| `supports` | 一条记忆印证另一条（检索器在距离 ≤ 16 的近重复上做 confidence 提升时会用到） |
| `merged_into` | 源条目已被合并到目标；源在逻辑上已删除 |

## SimHash 索引

[`lib/memory/simhash.dart`](../../lib/memory/simhash.dart) 为每段文本计算一个 128 位的 SimHash 指纹：

1. **分词**：使用 [`jieba_flutter`](https://pub.dev/packages/jieba_flutter)（中文分词 + 基础拉丁文切分）。
2. 对每个**唯一** token，用 `SHA256(token)` 作为种子，确定性生成一个 128 维高斯随机向量。同一个 token 总是得到同一个向量。
3. 把所有 token 的向量逐维累加。
4. 逐维阈值化：≥ 0 → 1，< 0 → 0。输出是 128 字符的二进制串。

两段文本的相似度定义为 SimHash 串的**汉明距离**（XOR 后 popcount）。实现用 SWAR popcount，并以 `1 - hamming/128` 映射到 0.0 – 1.0 相似度。

### 桶索引

hash 串的前 16 位把条目分到 65,536 个桶之一。检索器的 `getByBucketPrefix(16)` 走一个 `LIKE '0110…%'` 形式的快速 SQL 查找；如果候选数过小（< `minBucketSize`，默认 3），就回退到 8 位前缀做扩展搜索。`idx_memory_hash16` 与 `idx_memory_hash32` 是为此专门建立的 `SUBSTR(hash, 1, 16/32)` 索引。

去重阈值：距离 ≤ 8 → 近重复（confidence 提升），距离 ≤ 16 → `supports` 关系的候选。

## 检索打分

[`MemoryRetriever.search`](../../lib/memory/memory_retriever.dart) 的核心公式：

```
score = α · simSimilarity + β · importance + γ · recency
```

默认权重 `α = 0.5`、`β = 0.3`、`γ = 0.2`。`recency = 1 / (1 + hoursSinceAccess / 168)`，即**一周半衰期**：1 周前访问的记忆得 0.5，2 周前 0.33，4 周前 0.2。返回 Top-K（默认 K = 5），并把每次命中累加到对应条目的 `accessCount` 与 `lastAccessed`。

## 抽取

[`MemoryExtractor`](../../lib/memory/memory_extractor.dart) 是写侧对应物。每 N 轮（默认 5）对话流水线会调用它，传入一个 JSON 抽取 prompt：

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

输出经 [`JsonExtractor`](../../lib/utils/json_extractor.dart) 解析（详见 [LLM 提供商抽象 → 结构化输出](llm-providers.md#结构化输出)）。抽取结果先进入缓冲区，达到 `batchWriteThreshold`（默认 3）后批量冲刷 —— `MemoryNotifier.insertExtractions` 负责 SimHash + 去重写入。

## 压缩

[`MemoryCompressor.compressAll`](../../lib/memory/memory_compressor.dart) 的流程：

1. 加载所有非 `conversational` 条目。
2. 在 SimHash 距离 ≤ `clusterDistance`（默认 10）上跑简化版 DBSCAN 聚类。
3. 对每个 size ≥ 2 的簇，按 importance 降序排序，调用 LLM 合并为一段精炼摘要。
4. 用合并内容、最高 `confidence`、最高 `importance` 更新簇中 importance 最高的成员。
5. 对每个被吸收的条目插入一条 `mergedInto` 关系，指向幸存者。

## 遗忘

[`MemoryForgetter.run`](../../lib/memory/memory_forgetter.dart) 遍历所有非 `conversational` 条目，计算：

```
forgettingScore = importance × confidence × e^(-λ·daysSinceCreated) × e^(-μ·daysSinceAccess)
```

`λ = 0.01/天`（≈ 70 天时间半衰期），`μ = 0.05/天`（≈ 14 天访问半衰期）。当 `forgettingScore < type.forgettingThreshold` 时，条目被**删除**（文件注释里说明未来计划扩展为 `memory_archived` 表做软删；目前是硬删）。

## 持久化

[`MemoryService`](../../lib/services/memory_service.dart) 打开 `memory.db`（version 1）。Schema：

- `memory_entries(id, type, content, hash, importance, confidence, conversation_id, source_message_id, access_count, created_at, updated_at, last_accessed)`
- `memory_relations(id, source_id, target_id, relation_type, weight)`，两个外键都 `ON DELETE CASCADE`

索引：`idx_memory_type`、`idx_memory_hash`、`idx_memory_hash16`、`idx_memory_hash32`、`idx_memory_conv`、`idx_memory_importance` (DESC)、`idx_memory_last_accessed` (DESC)、`idx_memory_rel_source`、`idx_memory_rel_target`。两个 hash 前缀索引就是为检索器分桶加速专门建立的。

## 状态层 & UI

[`MemoryNotifier`](../../lib/providers/memory_provider.dart) 是一个 Riverpod `Notifier<MemoryData>`，包装 service。关键接口：

- `init()` —— 启动：确保 `SimHash.init()` 已运行，刷新统计，将 `initialized` 置为 true
- `insertExtractions(...)` —— 批量写入路径，写入时去重；近重复（距离 ≤ 8）改为 confidence 提升而非新增行
- `search(query)` —— 代理 `MemoryRetriever.search`
- `createLongTermMemory(...)` —— 将一条 `conversational` 摘要提升为永久的 `longTerm` 条目

记忆页面（[`lib/ui/pages/memory_page.dart`](../../lib/ui/pages/memory_page.dart)）展示按类型分组的总数、最近一次检索结果，以及用户可以编辑 / 提升的 `longTerm` 条目列表。

## 对话流水线如何使用记忆

每一轮，对话流水线用最新的用户输入调用 `MemoryRetriever.search`，取 Top-K 结果，并渲染成一段 Markdown 追加到系统提示中。主模型在自己的上下文里看到这些事实，并据此推理。检索同时会更新命中的 `accessCount` 和 `lastAccessed`，让 recency 半衰期的衰减保持"诚实"。

对话记忆（每 5 轮滚动摘要）由 [`ConversationalMemoryManager`](../../lib/memory/memory_middleware.dart) 计算，以 `MemoryType.conversational` 形式绑定到当前 conversation id —— 对话结束时统一清理，不参与遗忘打分。

## 参见

- [根 README → 架构设计 → 记忆系统流水线](../../README_ZH.md#架构设计) —— 顶层概览
- [LLM 提供商抽象](llm-providers.md) —— 抽取、摘要、合并都用 LLM 调用驱动
- [能力转译](capability-adapter.md) —— 记忆是构成 system prompt 的多种输入之一
- [插件系统](plugin-system.md) —— 插件工具调用共享同一个 `ToolDefinition` / `ToolResult` 信封
