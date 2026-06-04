import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/llm_provider.dart';
import '../models/llm_config.dart';
import '../models/message.dart';
import '../models/memory_type.dart';
import '../models/memory_entry.dart';
import '../state/memory_state.dart';
import '../utils/json_extractor.dart';

/// 对话记忆管理器 — 延迟 Summary 模型
class ConversationalMemoryManager {
  final MemoryState _memoryState;

  /// 每 N 轮触发一次摘要
  final int summaryInterval;

  /// 当前对话的摘要记忆 ID
  String? _summaryMemoryId;

  /// 轮计数器
  int _turnCount = 0;

  /// 上次摘要时的轮数
  int _lastSummaryTurn = 0;

  /// 摘要 prompt 模板
  static const _summaryPrompt = '''
你是一个对话摘要助手。请将以下对话轮次压缩为一段简洁的摘要。

要求：
1. 保留关键决策、重要信息、核心讨论点
2. 省略闲聊和过渡性内容
3. 保持时间顺序

返回 ONLY 一个 JSON 对象 — 不要 markdown、不要解释、不要其他文字：
{"summary": "摘要文本"}

需要摘要的对话：
''';

  ConversationalMemoryManager({
    required MemoryState memoryState,
    this.summaryInterval = 5,
  }) : _memoryState = memoryState;

  void incrementTurn() {
    _turnCount++;
  }

  bool get shouldSummarize =>
      _turnCount > 0 && _turnCount % summaryInterval == 0;

  int get turnsSinceLastSummary => _turnCount - _lastSummaryTurn;

  String? get currentSummary =>
      _summaryMemoryId != null ? _lastSummaryText : null;
  String? _lastSummaryText;

  bool get hasSummary => _summaryMemoryId != null;

  Future<String?> generateInitialSummary({
    required LlmProvider provider,
    required LlmConfig config,
    required List<Message> messages,
    required String conversationId,
  }) async {
    if (messages.isEmpty) return null;

    final text = _formatMessages(messages);
    final summary = await _callLLMSummary(
      provider: provider,
      config: config,
      text: text,
    );

    if (summary != null && summary.isNotEmpty) {
      final entry = await _memoryState.createLongTermMemory(
        summary,
        importance: 0.7,
        confidence: 1.0,
      );
      final convEntry = entry.copyWith(
        type: MemoryType.conversational,
        conversationId: conversationId,
      );
      await _memoryState.updateMemory(convEntry);

      _summaryMemoryId = convEntry.id;
      _lastSummaryText = summary;
      _lastSummaryTurn = _turnCount;

      debugPrint('[ConversationalMemory] 生成初始摘要，轮数: $_turnCount');
    }

    return summary;
  }

  Future<String?> updateSummary({
    required LlmProvider provider,
    required LlmConfig config,
    required List<Message> messages,
    required String conversationId,
  }) async {
    if (_lastSummaryText == null || messages.isEmpty) return null;

    final newText = _formatMessages(messages);
    final summary = await _callLLMSummary(
      provider: provider,
      config: config,
      text: '现有摘要:\n$_lastSummaryText\n\n新增对话:\n$newText',
    );

    if (summary != null && summary.isNotEmpty) {
      if (_summaryMemoryId != null) {
        final entry = MemoryEntry.create(
          id: _summaryMemoryId!,
          type: MemoryType.conversational,
          content: summary,
          hash: '',
          importance: 0.7,
          confidence: 1.0,
          conversationId: conversationId,
        );
        await _memoryState.updateMemory(entry);
      }

      _lastSummaryText = summary;
      _lastSummaryTurn = _turnCount;

      debugPrint('[ConversationalMemory] 更新摘要，轮数: $_turnCount');
    }

    return summary;
  }

  Future<String?> finalizeSummary({
    required LlmProvider provider,
    required LlmConfig config,
    required List<Message> allMessages,
    required String conversationId,
  }) async {
    final text = _formatMessages(allMessages);
    final summary = await _callLLMSummaryFinal(
      provider: provider,
      config: config,
      text: text,
    );

    if (summary != null && summary.isNotEmpty) {
      if (_summaryMemoryId != null) {
        final entry = MemoryEntry.create(
          id: _summaryMemoryId!,
          type: MemoryType.conversational,
          content: summary,
          hash: '',
          importance: 0.8,
          confidence: 1.0,
          conversationId: conversationId,
        );
        await _memoryState.updateMemory(entry);
      }
      _lastSummaryText = summary;
      debugPrint('[ConversationalMemory] 最终摘要完成');
    }

    return summary;
  }

  Future<String?> _callLLMSummary({
    required LlmProvider provider,
    required LlmConfig config,
    required String text,
  }) async {
    final history = <Message>[
      Message(
        id: 'summary-1',
        role: MessageRole.user,
        content: '$_summaryPrompt\n\n$text',
        status: MessageStatus.completed,
        timestamp: DateTime.now(),
      ),
    ];

    try {
      final response = await provider.chat(
        config: config,
        history: history,
        systemPrompt: '你是一个精确的对话摘要助手。只返回 JSON 对象，不返回 markdown、不返回解释、不返回其他内容。',
      );
      return JsonExtractor.tryExtractField(response.content, 'summary') ??
          (response.content.trim().isNotEmpty ? response.content.trim() : null);
    } catch (e) {
      debugPrint('[ConversationalMemory] 摘要生成失败: $e');
      return null;
    }
  }

  Future<String?> _callLLMSummaryFinal({
    required LlmProvider provider,
    required LlmConfig config,
    required String text,
  }) async {
    final history = <Message>[
      Message(
        id: 'final-summary-1',
        role: MessageRole.user,
        content:
            '请对整个对话做一个全面的最终摘要。包含以下要素：\n'
            '1. 对话主题和背景\n'
            '2. 达成的关键决策和结论\n'
            '3. 未解决的问题或待办事项\n'
            '4. 用户表达的重要信息\n\n'
            '返回 ONLY 一个 JSON 对象 — 不要 markdown、不要解释、不要其他文字：\n'
            '{"summary": "摘要文本"}\n\n'
            '对话内容：\n\n$text',
        status: MessageStatus.completed,
        timestamp: DateTime.now(),
      ),
    ];

    try {
      final response = await provider.chat(
        config: config,
        history: history,
        systemPrompt: '你是一个精确的对话摘要助手。只返回 JSON 对象，不返回 markdown、不返回解释、不返回其他内容。',
      );
      return JsonExtractor.tryExtractField(response.content, 'summary') ??
          (response.content.trim().isNotEmpty ? response.content.trim() : null);
    } catch (e) {
      debugPrint('[ConversationalMemory] 最终摘要生成失败: $e');
      return null;
    }
  }

  String _formatMessages(List<Message> messages) {
    final sb = StringBuffer();
    for (final msg in messages) {
      final role = msg.role.name == 'user' ? '用户' : 'AI';
      final content = msg.content.length > 500
          ? '${msg.content.substring(0, 500)}...'
          : msg.content;
      sb.writeln('$role: $content');
    }
    return sb.toString();
  }

  void reset() {
    _summaryMemoryId = null;
    _lastSummaryText = null;
    _turnCount = 0;
    _lastSummaryTurn = 0;
  }
}
