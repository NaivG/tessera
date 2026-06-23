import 'dart:convert';

import '../models/message.dart';
import '../models/tool.dart';
import 'tool_registry.dart';

// =============================================================================
// ToolCallValidator — 运行时参数校验
//
// 设计：LLM 通过 `discover` 看到工具摘要后直接发起调用；
// Runtime 在此拦截，校验参数是否符合 schema。
// 若失败，返回包含完整 schema 的错误消息，LLM 据此重试。
//
// 路径 A（默认）：校验 + 错误反馈
// =============================================================================

/// 校验结果
class ValidationResult {
  final bool isValid;
  final String? errorMessage; // 校验失败时的错误 + schema

  const ValidationResult._({
    required this.isValid,
    this.errorMessage,
  });

  factory ValidationResult.pass() => const ValidationResult._(isValid: true);
  factory ValidationResult.fail(String message) =>
      ValidationResult._(isValid: false, errorMessage: message);
}

/// 运行时工具调用参数校验器
class ToolCallValidator {
  /// 校验 [call] 的参数是否符合 [definition] 的 schema。
  ///
  /// 返回 [ValidationResult]：
  /// - `pass` — 参数符合要求
  /// - `fail` — 参数不符合，errorMessage 包含：
  ///   - 缺哪些 required 字段
  ///   - 类型不匹配详情
  ///   - 完整 schema JSON
  ValidationResult validate(ToolCall call, ToolDefinition definition) {
    final errors = <String>[];

    // 1. 检查 required 字段
    for (final entry in definition.parameters.entries) {
      if (entry.value is Map && (entry.value as Map)['required'] == true) {
        if (!call.arguments.containsKey(entry.key)) {
          errors.add('Missing required parameter: "${entry.key}"');
        }
      }
    }

    // 2. 检查类型（仅检查已提供的参数）
    for (final argEntry in call.arguments.entries) {
      final paramName = argEntry.key;
      final paramDef = definition.parameters[paramName];
      if (paramDef == null) {
        // 未知参数 — 不阻塞，可能是模型推测了额外参数
        continue;
      }

      if (paramDef is! Map) continue;

      final expectedType = paramDef['type'] as String?;
      if (expectedType == null) continue;

      final actualValue = argEntry.value;
      final typeError = _checkType(paramName, actualValue, expectedType);
      if (typeError != null) {
        errors.add(typeError);
      }
    }

    if (errors.isNotEmpty) {
      final schemaJSON = const JsonEncoder.withIndent('  ')
          .convert(definition.parameters);
      final message = StringBuffer()
        ..writeln('Tool call validation failed for "${call.name}":')
        ..writeAll(errors.map((e) => '  - $e\n'))
        ..writeln()
        ..writeln('Full parameter schema for "${call.name}":')
        ..writeln('```json')
        ..writeln(schemaJSON)
        ..writeln('```')
        ..writeln()
        ..writeln('Please correct your arguments and call the tool again.');
      return ValidationResult.fail(message.toString());
    }

    return ValidationResult.pass();
  }

  /// 检查单个参数的类型
  String? _checkType(String name, dynamic value, String expectedType) {
    switch (expectedType) {
      case 'string':
        if (value is! String) {
          return 'Parameter "$name" expected string but got ${value.runtimeType}';
        }
        return null;
      case 'number':
      case 'integer':
        if (value is! int && value is! double) {
          return 'Parameter "$name" expected $expectedType but got ${value.runtimeType}';
        }
        return null;
      case 'boolean':
        if (value is! bool) {
          return 'Parameter "$name" expected boolean but got ${value.runtimeType}';
        }
        return null;
      case 'array':
        if (value is! List) {
          return 'Parameter "$name" expected array but got ${value.runtimeType}';
        }
        return null;
      case 'object':
        if (value is! Map<String, dynamic>) {
          return 'Parameter "$name" expected object but got ${value.runtimeType}';
        }
        return null;
      default:
        // 未知类型不校验
        return null;
    }
  }

  /// 批量校验。返回通过的工具调用列表和方法列表。
  ///
  /// 对不通过的工具调用，生成 tool result 错误消息直接注入。
  BatchValidationResult validateAll(
    List<ToolCall> calls,
    ToolRegistry registry,
  ) {
    final valid = <ToolCall>[];
    final errors = <ToolResult>[];

    for (final call in calls) {
      final def = registry.get(call.name);
      if (def == null) {
        errors.add(ToolResult(
          toolCallId: call.id,
          content: 'Tool "${call.name}" is not registered. Use `discover` to find available tools.',
          isError: true,
        ));
        continue;
      }

      final result = validate(call, def);
      if (result.isValid) {
        valid.add(call);
      } else {
        errors.add(ToolResult(
          toolCallId: call.id,
          content: result.errorMessage ?? 'Validation failed.',
          isError: true,
        ));
      }
    }

    return BatchValidationResult(validCalls: valid, errors: errors);
  }
}

class BatchValidationResult {
  final List<ToolCall> validCalls;
  final List<ToolResult> errors;

  const BatchValidationResult({
    this.validCalls = const [],
    this.errors = const [],
  });

  bool get hasErrors => errors.isNotEmpty;
}
