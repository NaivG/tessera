import 'dart:convert';

import '../models/plan.dart';

/// 计划 JSON 解析器
class PlanParser {
  /// 从 LLM 响应中解析计划 JSON。
  ///
  /// 支持两种格式：
  /// 1. 纯 JSON：`{"steps": [{"title": "...", "description": "..."}]}`
  /// 2. Markdown 代码块包裹的 JSON：```json ... ```
  static Plan? parse(String content) {
    final jsonStr = _extractJson(content);
    if (jsonStr == null) return null;

    try {
      final json = jsonDecode(jsonStr);
      if (json is! Map<String, dynamic>) return null;
      return Plan.fromJson(json);
    } catch (e) {
      return null;
    }
  }

  /// 从 Agent Cluster 响应中解析并行任务列表。
  ///
  /// 格式：`{"tasks": [{"title": "...", "description": "..."}]}`
  static List<PlanStep> parseTasks(String content) {
    final jsonStr = _extractJson(content);
    if (jsonStr == null) return [];

    try {
      final json = jsonDecode(jsonStr);
      if (json is! Map<String, dynamic>) return [];
      final tasks = json['tasks'] as List<dynamic>?;
      if (tasks == null) return [];
      return tasks
          .map((e) => PlanStep.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      return [];
    }
  }

  /// 从文本中提取 JSON 字符串
  static String? _extractJson(String content) {
    final trimmed = content.trim();

    // 尝试直接解析
    if (trimmed.startsWith('{')) return trimmed;

    // 尝试从 markdown 代码块中提取
    final codeBlockPattern = RegExp(r'```(?:json)?\s*\n?([\s\S]*?)\n?```');
    final match = codeBlockPattern.firstMatch(trimmed);
    if (match != null) {
      return match.group(1)?.trim();
    }

    // 尝试找到第一个 { 和最后一个 } 之间的内容
    final firstBrace = trimmed.indexOf('{');
    final lastBrace = trimmed.lastIndexOf('}');
    if (firstBrace >= 0 && lastBrace > firstBrace) {
      return trimmed.substring(firstBrace, lastBrace + 1);
    }

    return null;
  }
}
