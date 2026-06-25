/// 上下文窗口管理器
///
/// 负责上下文 Token 预算计算和超限时的消息压缩。
/// 核心职责：
/// - 估算当前上下文各部分 Token 用量
/// - 计算使用比例，判断是否需要压缩
/// - 调用 LLM 将早期消息压缩为摘要（增量合并）
library;

import 'dart:convert';

import '../models/conversation.dart';
import '../models/llm_config.dart';
import '../models/message.dart';
import '../models/model_info.dart';
import '../models/tool.dart';
import '../utils/token_counter.dart';
import '../utils/model_context_defaults.dart';

/// 上下文预算快照
class ContextBudget {
  /// 当前上下文总 Token 估算
  final int totalTokens;

  /// 模型上下文窗口上限
  final int contextLimit;

  /// 使用比例 (totalTokens / contextLimit)
  final double usageRatio;

  /// 是否需要压缩 (usageRatio > 0.8)
  final bool needsCompression;

  /// 系统提示词 Token
  final int systemTokens;

  /// 工具定义 Token
  final int toolTokens;

  /// 消息 Token
  final int messageTokens;

  /// 保留给输出的 Token (maxTokens)
  final int reservedTokens;

  const ContextBudget({
    required this.totalTokens,
    required this.contextLimit,
    required this.usageRatio,
    required this.needsCompression,
    this.systemTokens = 0,
    this.toolTokens = 0,
    this.messageTokens = 0,
    this.reservedTokens = 0,
  });
}

/// 压缩结果
class CompressionResult {
  /// 压缩后的消息列表（含摘要系统消息）
  final List<Message> messages;

  /// 增强后的 system prompt（注入摘要）
  final String? enhancedSystemPrompt;

  /// 摘要文本
  final String summary;

  /// 被压缩的消息数量
  final int compressedCount;

  const CompressionResult({
    required this.messages,
    this.enhancedSystemPrompt,
    this.summary = '',
    this.compressedCount = 0,
  });
}

/// 上下文压缩 prompt 模板
const _compressionPrompt = '''
你是一个对话压缩助手。请将以下对话内容压缩为一段简洁的摘要。

要求：
1. 保留关键决策、重要信息、核心讨论点
2. 省略闲聊和过渡性内容
3. 保持时间顺序

返回 ONLY 一个 JSON 对象 — 不要 markdown、不要解释、不要其他文字：
{"summary": "摘要文本"}

需要压缩的对话：
''';

/// 上下文窗口管理器
class ContextWindowManager {
  /// 压缩阈值比例
  static const double _compressionThreshold = 0.8;

  /// 压缩时保留最近 N 轮的消息（N*2 条消息）
  static const int _recentRoundsToKeep = 2;

  /// 现有的摘要（增量压缩时使用）
  String? _existingSummary;

  /// 重置状态（新对话时调用）
  void reset() {
    _existingSummary = null;
  }

  // ── 上下文窗口查找 ──

  /// 三级查找模型上下文窗口：
  /// 1. 用户手动覆盖值
  /// 2. ModelInfo.contextWindow 字段
  /// 3. 内置默认值表
  int getContextWindowLimit(
    LlmConfig config, {
    int? userOverride,
    ModelInfo? modelInfo,
  }) {
    if (userOverride != null && userOverride > 0) {
      return userOverride;
    }
    if (modelInfo?.contextWindow != null) {
      return modelInfo!.contextWindow!;
    }
    return getContextWindow(config.modelId);
  }

  // ── 上下文预算计算 ──

  /// 准备上下文，计算各部分 Token 并返回预算快照
  ContextBudget prepareContext({
    required Conversation conversation,
    required String systemPrompt,
    required List<ToolDefinition> tools,
    int? userOverride,
    ModelInfo? modelInfo,
  }) {
    final contextLimit = getContextWindowLimit(
      conversation.config,
      userOverride: userOverride,
      modelInfo: modelInfo,
    );

    // 各部分 Token 估算
    final systemTokens = TokenCounter.estimateSystemPromptTokens(systemPrompt);
    final toolTokens = TokenCounter.estimateToolTokens(tools);

    // 消息 Token
    int messageTokens = 0;
    final allMessages = conversation.messages;
    // 排除最后一条（正在发送的用户消息将在发送后计算，这里计算已有历史）
    final historyMessages = allMessages.length > 1
        ? allMessages.sublist(0, allMessages.length - 1)
        : allMessages;
    for (final msg in historyMessages) {
      messageTokens += TokenCounter.estimateMessageTokens(msg);
    }

    // 输出保留：maxTokens 若配置则用它，否则预留 contextLimit 的 20%
    final reservedTokens = conversation.config.maxTokens ??
        (contextLimit * 0.2).ceil();

    // 摘要 Token（如果有）
    final summaryTokens = _existingSummary != null
        ? TokenCounter.estimateTokens(_existingSummary!)
        : 0;

    // 总 Token：不含 reserved（那是预留给输出的空间）
    final totalTokens =
        systemTokens + toolTokens + messageTokens + summaryTokens + reservedTokens;

    final usageRatio = totalTokens / contextLimit;

    return ContextBudget(
      totalTokens: totalTokens,
      contextLimit: contextLimit,
      usageRatio: usageRatio,
      needsCompression: usageRatio > _compressionThreshold,
      systemTokens: systemTokens,
      toolTokens: toolTokens,
      messageTokens: messageTokens,
      reservedTokens: reservedTokens,
    );
  }

  // ── 消息压缩 ──

  /// 判断是否需要压缩
  bool shouldCompress(ContextBudget budget) => budget.needsCompression;

  /// 执行消息压缩（同步部分：选择需要压缩的消息，异步部分由调用方处理 LLM 调用）
  ///
  /// 保留最近 `_recentRoundsToKeep * 2` 条消息（即 N 轮对话），
  /// 将其之前的所有非 system 消息压缩为摘要。
  ///
  /// 返回需要传递给 LLM 的压缩 prompt 文本，以及被压缩的消息范围。
  ({String prompt, List<Message> toCompress, List<Message> toKeep})
      prepareCompression(List<Message> messages) {
    final keepCount = _recentRoundsToKeep * 2;
    final toCompress = messages.length > keepCount
        ? messages.sublist(0, messages.length - keepCount)
        : <Message>[];
    final toKeep = toCompress.isNotEmpty
        ? messages.sublist(messages.length - keepCount)
        : messages;

    final text = _formatMessagesForCompression(toCompress);
    final prompt = _existingSummary != null
        ? '$_compressionPrompt\n现有摘要:\n$_existingSummary\n\n新增对话:\n$text'
        : '$_compressionPrompt\n$text';

    return (prompt: prompt, toCompress: toCompress, toKeep: toKeep);
  }

  /// 应用压缩结果到消息列表
  ///
  /// 生成一条 system 角色摘要消息并放在消息列表最前面。
  CompressionResult applyCompression({
    required String summary,
    required List<Message> toKeep,
    required String? originalSystemPrompt,
  }) {
    _existingSummary = summary;

    // 构建增强的 system prompt：原始 + 摘要前缀
    String? enhancedSystemPrompt;
    if (originalSystemPrompt != null && originalSystemPrompt.isNotEmpty) {
      enhancedSystemPrompt =
          '$originalSystemPrompt\n\n[对话历史摘要]\n$summary';
    } else {
      enhancedSystemPrompt = '[对话历史摘要]\n$summary';
    }

    // 摘要注入为 system 消息放在最前面
    final summaryMsg = Message(
      id: 'summary-${DateTime.now().microsecondsSinceEpoch}',
      role: MessageRole.system,
      content: summary,
      timestamp: DateTime.now(),
    );

    final newMessages = [summaryMsg, ...toKeep];

    return CompressionResult(
      messages: newMessages,
      enhancedSystemPrompt: enhancedSystemPrompt,
      summary: summary,
      compressedCount: toKeep.length < newMessages.length
          ? newMessages.length - toKeep.length - 1 // minus summary msg
          : 0,
    );
  }

  /// 压缩失败时的 fallback：直接丢弃最早的消息
  ///
  /// 保留最近 `_recentRoundsToKeep * 2` 条消息。
  CompressionResult fallbackCompression(
    List<Message> messages, {
    String? originalSystemPrompt,
  }) {
    final keepCount = _recentRoundsToKeep * 2;
    if (messages.length <= keepCount) {
      return CompressionResult(messages: messages);
    }
    final toKeep = messages.sublist(messages.length - keepCount);
    return CompressionResult(
      messages: toKeep,
      enhancedSystemPrompt: originalSystemPrompt,
    );
  }

  // ── 内部 ──

  String _formatMessagesForCompression(List<Message> messages) {
    final buf = StringBuffer();
    for (final msg in messages) {
      buf.writeln('[${msg.role.name}]: ${msg.content}');
      if (msg.thinking != null && msg.thinking!.isNotEmpty) {
        buf.writeln('[thinking]: ${msg.thinking}');
      }
    }
    return buf.toString();
  }

  /// 从 LLM 响应中提取摘要文本
  static String? extractSummary(String responseText) {
    try {
      final json = jsonDecode(responseText) as Map<String, dynamic>;
      final summary = json['summary'] as String?;
      if (summary != null && summary.isNotEmpty) return summary;
    } catch (_) {
      // 如果 JSON 解析失败，直接用原文本
      if (responseText.isNotEmpty) return responseText.trim();
    }
    return null;
  }
}
