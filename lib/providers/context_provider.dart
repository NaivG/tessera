/// 上下文 Token 状态 Provider
///
/// 独立的 Riverpod 状态，管理当前对话的上下文 Token 用量。
/// 不污染 ChatData，仅供 UI 层（Token 指示器）和发送逻辑消费。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 上下文 Token 状态（不可变）
class ContextTokenState {
  /// 当前估算 Token 数
  final int currentTokens;

  /// 模型上下文窗口上限
  final int contextLimit;

  /// 使用比例 (currentTokens / contextLimit)
  final double usageRatio;

  /// 是否正在压缩
  final bool isCompressing;

  /// 是否截断了 system prompt
  final bool systemPromptTruncated;

  /// 压缩通知文本
  final String? compressionNotice;

  const ContextTokenState({
    this.currentTokens = 0,
    this.contextLimit = 8192,
    this.usageRatio = 0.0,
    this.isCompressing = false,
    this.systemPromptTruncated = false,
    this.compressionNotice,
  });

  /// 格式化展示文本，如 "12K / 128K"
  String get displayText {
    final currentStr = currentTokens >= 1000
        ? '${(currentTokens / 1000).toStringAsFixed(1)}K'
        : '$currentTokens';
    final limitStr = contextLimit >= 1000
        ? '${(contextLimit / 1000).toStringAsFixed(1)}K'
        : '$contextLimit';
    return '$currentStr / $limitStr';
  }

  ContextTokenState copyWith({
    int? currentTokens,
    int? contextLimit,
    double? usageRatio,
    bool? isCompressing,
    bool? systemPromptTruncated,
    String? compressionNotice,
    bool clearCompressionNotice = false,
    bool clearTruncated = false,
  }) {
    return ContextTokenState(
      currentTokens: currentTokens ?? this.currentTokens,
      contextLimit: contextLimit ?? this.contextLimit,
      usageRatio: usageRatio ?? this.usageRatio,
      isCompressing: isCompressing ?? this.isCompressing,
      systemPromptTruncated:
          clearTruncated ? false : (systemPromptTruncated ?? this.systemPromptTruncated),
      compressionNotice: clearCompressionNotice
          ? null
          : (compressionNotice ?? this.compressionNotice),
    );
  }
}

/// 上下文 Token 状态 Notifier
class ContextTokenNotifier extends Notifier<ContextTokenState> {
  @override
  ContextTokenState build() => const ContextTokenState();

  /// 更新当前 Token 计数
  void update(int tokens, int limit) {
    state = state.copyWith(
      currentTokens: tokens,
      contextLimit: limit,
      usageRatio: limit > 0 ? tokens / limit : 0.0,
    );
  }

  /// 设置压缩中状态
  void setCompressing(bool value, {String? notice}) {
    state = state.copyWith(
      isCompressing: value,
      compressionNotice: notice,
    );
  }

  /// 设置 system prompt 截断状态
  void setTruncated(bool value) {
    state = state.copyWith(systemPromptTruncated: value);
  }

  /// 重置到初始状态
  void reset() {
    state = const ContextTokenState();
  }
}

/// 上下文 Token Provider
final contextTokenProvider =
    NotifierProvider<ContextTokenNotifier, ContextTokenState>(
  ContextTokenNotifier.new,
);
