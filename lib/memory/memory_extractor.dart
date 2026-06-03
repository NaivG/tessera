import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/llm_provider.dart';
import '../models/llm_config.dart';
import '../models/message.dart';
import '../models/memory_extraction.dart';
import '../state/memory_state.dart';

/// 记忆提取器 — 调用 LLM 从对话轮次中提取结构化记忆
///
/// 提取流程：
/// ```
/// 对话轮次
///   ↓ 积累 N 轮（可配置，默认 5 轮）
///   ↓ 拼接最近 N 轮 user + assistant 文本
///   ↓ 调用 LLM（轻量 prompt）提取事实
///   ↓ 解析 JSON → MemoryExtraction 列表
///   ↓ 追加到提取缓冲区（累积多批）
///   ↓ 批次内调用 MemoryState.insertExtractions（含去重）
/// ```
class MemoryExtractor {
  /// 提取 LLM 的 prompt 模板
  static const _extractionPrompt = '''
你是一个记忆提取助手。请从以下对话轮次中提取有价值的信息，分类为：

- **user**：关于用户的偏好、身份、习惯、技能等信息
- **knowledge**：事实、知识点、技术信息
- **event**：发生的事件、完成的任务、达成的决定

**规则**：
1. 每条提取必须简洁、独立可理解（无需上下文即可读懂）
2. importance 评分 0.0~1.0：用户偏好/个人信息 0.7-0.9，重要知识点 0.5-0.7，一般事件 0.3-0.5
3. 只提取有实质内容的信息，忽略闲聊和过渡性内容
4. 不要重复提取已明确的内容

请以 JSON 数组格式返回：
```json
[
  {"type": "user", "content": "用户是 Python 开发者", "importance": 0.8},
  {"type": "knowledge", "content": "Dart 3.11 支持扩展类型", "importance": 0.6},
  {"type": "event", "content": "2026-05-31 用户完成了 XX 功能", "importance": 0.4}
]
```

以下是最近的对话轮次：

''';

  /// 积累多少轮对话后触发一次提取
  final int extractRoundCount;

  /// 累积的最近 N 轮消息（user + assistant 对）
  final List<Message> _buffer = [];

  /// 轮计数器（每完成一轮 user→assistant 计 1 轮）
  int _roundCount = 0;

  /// 提取结果缓冲区（累积多批提取结果，批量去重）
  final List<MemoryExtraction> _extractionBuffer = [];

  /// 批量写入阈值
  final int batchWriteThreshold;

  MemoryExtractor({this.extractRoundCount = 5, this.batchWriteThreshold = 3});

  /// 添加一对 user→assistant 消息到缓冲区
  ///
  /// [userMsg] 用户消息
  /// [assistantMsg] AI 回复消息
  void addTurn(Message userMsg, Message assistantMsg) {
    _buffer.add(userMsg);
    _buffer.add(assistantMsg);
    _roundCount++;

    // 保持缓冲区为最近 extractRoundCount 轮
    while (_buffer.length > extractRoundCount * 2) {
      _buffer.removeAt(0);
    }
  }

  /// 是否达到提取阈值
  bool get shouldExtract =>
      _roundCount > 0 && _roundCount % extractRoundCount == 0;

  /// 重置轮计数（提取后调用）
  void resetRoundCount() {
    _roundCount = 0;
  }

  /// 获取当前提取缓冲区的对话文本
  String get dialogueText {
    final sb = StringBuffer();
    for (final msg in _buffer) {
      final role = msg.role.name == 'user' ? '用户' : 'AI';
      sb.writeln('$role: ${msg.content}');
    }
    return sb.toString();
  }

  /// 调用 LLM 提取记忆
  ///
  /// [provider] LLM 提供商
  /// [config] LLM 配置
  /// [systemPrompt] 可选的系统提示（追加在提取 prompt 之前）
  ///
  /// 返回提取到的结构化记忆列表。
  Future<List<MemoryExtraction>> extract({
    required LlmProvider provider,
    required LlmConfig config,
    String? systemPrompt,
  }) async {
    if (_buffer.isEmpty) return [];

    final fullPrompt = '$_extractionPrompt\n\n$dialogueText';

    try {
      final response = await provider.chat(
        config: config,
        history: [
          Message(
            id: 'extract-1',
            role: MessageRole.user,
            content: fullPrompt,
            status: MessageStatus.completed,
            timestamp: DateTime.now(),
          ),
        ],
        systemPrompt:
            systemPrompt ??
            '你是一个精确的记忆提取助手。只返回 JSON 数组，不返回其他内容。'
                '如果没有值得记忆的内容，返回空数组 []。',
        tools: null,
      );

      final jsonStr = _extractJsonArray(response.content);
      if (jsonStr == null || jsonStr.isEmpty) return [];

      final list = jsonDecode(jsonStr);
      final extractions = MemoryExtraction.listFromJson(list);

      debugPrint('[MemoryExtractor] 提取完成，获得 ${extractions.length} 条候选记忆');
      return extractions;
    } catch (e) {
      debugPrint('[MemoryExtractor] 提取失败: $e');
      return [];
    }
  }

  /// 累计提取结果到缓冲区
  void bufferExtractions(List<MemoryExtraction> extractions) {
    _extractionBuffer.addAll(extractions);
  }

  /// 是否需要批量写入
  bool get shouldFlush => _extractionBuffer.length >= batchWriteThreshold;

  /// 将缓冲区中的提取结果写入 MemoryState（含去重）
  ///
  /// [memoryState] 记忆状态管理器
  /// [conversationId] 当前对话 ID
  /// [sourceMessageId] 来源消息 ID
  ///
  /// 返回实际插入的条目数。
  Future<int> flushToMemory({
    required MemoryState memoryState,
    String? conversationId,
    String? sourceMessageId,
  }) async {
    if (_extractionBuffer.isEmpty) return 0;

    final toInsert = List<MemoryExtraction>.from(_extractionBuffer);
    _extractionBuffer.clear();

    return memoryState.insertExtractions(
      toInsert,
      conversationId: conversationId,
      sourceMessageId: sourceMessageId,
    );
  }

  /// 清除所有缓冲
  void clear() {
    _buffer.clear();
    _extractionBuffer.clear();
    _roundCount = 0;
  }

  /// 从 LLM 回复中提取 JSON 数组字符串
  static String? _extractJsonArray(String content) {
    // 尝试直接解析
    content = content.trim();
    if (content.startsWith('[') && content.endsWith(']')) {
      return content;
    }

    // 尝试从 markdown code block 中提取
    final codeBlockRe = RegExp(
      r'```(?:json)?\s*\n?(\[.*?\])\s*\n?```',
      dotAll: true,
    );
    final match = codeBlockRe.firstMatch(content);
    if (match != null) {
      return match.group(1)?.trim();
    }

    // 尝试找到第一个 [ 和最后一个 ]
    final startIdx = content.indexOf('[');
    final endIdx = content.lastIndexOf(']');
    if (startIdx >= 0 && endIdx > startIdx) {
      return content.substring(startIdx, endIdx + 1);
    }

    return null;
  }
}
