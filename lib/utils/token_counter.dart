/// Token 估算纯静态工具类
///
/// 使用字符级采样估算文本的 Token 数量。
/// - 英文/拉丁字符: ~4 chars/token
/// - CJK 字符: ~1.5 chars/token
///
/// 采样前 1000 个字符确定 CJK 比例，然后按比例推算全文字数。
library;

import '../models/message.dart';
import '../models/tool.dart';

class TokenCounter {
  TokenCounter._();

  // CJK Unicode 范围
  static const _cjkRanges = [
    _Range(0x4E00, 0x9FFF), // CJK Unified Ideographs
    _Range(0xF900, 0xFAFF), // CJK Compatibility Ideographs
    _Range(0x3040, 0x309F), // Hiragana
    _Range(0x30A0, 0x30FF), // Katakana
    _Range(0xAC00, 0xD7AF), // Hangul Syllables
    _Range(0xFF01, 0xFF60), // Fullwidth forms
    _Range(0x3000, 0x303F), // CJK Symbols and Punctuation
  ];

  static const _sampleSize = 1000;
  static const _charsPerTokenLatin = 4.0;
  static const _charsPerTokenCjk = 1.5;

  /// 估算文本的 Token 数量
  ///
  /// 采样前 [_sampleSize] 字符确定 CJK 比例，然后推算全文。
  /// 空字符串返回 0。
  static int estimateTokens(String text) {
    if (text.isEmpty) return 0;

    final runes = text.runes.toList();
    final sampleLen = runes.length < _sampleSize ? runes.length : _sampleSize;

    int cjkCount = 0;
    for (var i = 0; i < sampleLen; i++) {
      if (_isCjk(runes[i])) {
        cjkCount++;
      }
    }

    final cjkRatio = cjkCount / sampleLen;
    final totalRunes = runes.length;

    final cjkTokens = (totalRunes * cjkRatio) / _charsPerTokenCjk;
    final latinTokens =
        (totalRunes * (1.0 - cjkRatio)) / _charsPerTokenLatin;

    return (cjkTokens + latinTokens).ceil();
  }

  /// 估算单条消息的 Token 数量
  ///
  /// 包括 content、thinking、toolCalls JSON、附件 Token 估算。
  static int estimateMessageTokens(Message msg) {
    int tokens = 0;

    // 内容文本
    tokens += estimateTokens(msg.content);

    // 思考内容
    if (msg.thinking != null && msg.thinking!.isNotEmpty) {
      tokens += estimateTokens(msg.thinking!);
    }

    // 工具调用 JSON
    if (msg.toolCalls != null && msg.toolCalls!.isNotEmpty) {
      final json = _toolCallsToJsonString(msg.toolCalls!);
      tokens += estimateTokens(json);
    }

    // 附件估算：每张图片约 1000 token
    if (msg.mediaAttachments != null) {
      tokens += msg.mediaAttachments!.length * 1000;
    }

    return tokens;
  }

  /// 估算工具定义列表的 Token 数量（序列化为 JSON 后估算）
  static int estimateToolTokens(List<ToolDefinition> tools) {
    if (tools.isEmpty) return 0;
    final json = _toolsToJsonString(tools);
    return estimateTokens(json);
  }

  /// 估算系统提示词的 Token 数量
  static int estimateSystemPromptTokens(String? prompt) {
    if (prompt == null || prompt.isEmpty) return 0;
    return estimateTokens(prompt);
  }

  // ── 内部辅助 ──

  static bool _isCjk(int rune) {
    for (final range in _cjkRanges) {
      if (rune >= range.start && rune <= range.end) return true;
    }
    return false;
  }

  static String _toolCallsToJsonString(List<ToolCall> calls) {
    final buf = StringBuffer();
    buf.write('[');
    for (var i = 0; i < calls.length; i++) {
      if (i > 0) buf.write(',');
      buf.write('{"id":"');
      buf.write(calls[i].id);
      buf.write('","name":"');
      buf.write(calls[i].name);
      buf.write('","arguments":');
      buf.write(_mapToJson(calls[i].arguments));
      buf.write('}');
    }
    buf.write(']');
    return buf.toString();
  }

  static String _toolsToJsonString(List<ToolDefinition> tools) {
    final buf = StringBuffer();
    buf.write('[');
    for (var i = 0; i < tools.length; i++) {
      if (i > 0) buf.write(',');
      buf.write(tools[i].toOpenAiSchema().toString());
    }
    buf.write(']');
    return buf.toString();
  }

  static String _mapToJson(Map<String, dynamic> map) {
    final buf = StringBuffer();
    buf.write('{');
    final entries = map.entries.toList();
    for (var i = 0; i < entries.length; i++) {
      if (i > 0) buf.write(',');
      buf.write('"${entries[i].key}":');
      final value = entries[i].value;
      if (value is String) {
        buf.write('"$value"');
      } else {
        buf.write('$value');
      }
    }
    buf.write('}');
    return buf.toString();
  }
}

class _Range {
  final int start;
  final int end;
  const _Range(this.start, this.end);
}
