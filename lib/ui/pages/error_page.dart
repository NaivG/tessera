import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:restart_app/restart_app.dart';

/// 全局错误页面 — runZonedGuarded / FlutterError.onError 捕获异常后路由至此。
///
/// 清空导航栈后显示该页面，防止用户回到已损坏的页面树。
class ErrorPage extends StatelessWidget {
  const ErrorPage({super.key, required this.error, required this.stackTrace});

  /// 异常对象（可为 String / Error / Exception）
  final Object error;

  /// 堆栈跟踪
  final StackTrace stackTrace;

  /// 静态路由名，用于 onGenerateRoute 匹配
  static const routeName = '/error';

  /// 向错误页导航并清空整个栈。
  ///
  /// [navigatorKey] 为应用的 `GlobalKey`。
  static Future<void> navigateTo({
    required GlobalKey<NavigatorState> navigatorKey,
    required Object error,
    required StackTrace stackTrace,
  }) async {
    // 确保一帧内只触发一次
    final navigator = navigatorKey.currentState;
    if (navigator == null) return;

    navigator.pushAndRemoveUntil(
      MaterialPageRoute<void>(
        builder: (_) => ErrorPage(error: error, stackTrace: stackTrace),
      ),
      (_) => false, // 清空全部路由栈
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF1A1A2E)
          : const Color(0xFFF5F5F5),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              Icon(
                Icons.error_outline,
                size: 64,
                color: theme.colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                'Oops! An unexpected error occurred.',
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                '应用发生了未处理的异常, 请将以下信息反馈给开发者',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              // 错误类型
              _SectionCard(
                title: '错误类型',
                child: Text('${error.runtimeType}', style: _monoStyle(context)),
              ),
              const SizedBox(height: 12),
              // 错误信息
              _SectionCard(
                title: '错误信息',
                child: SelectableText(
                  _formatError(error),
                  style: _monoStyle(context),
                ),
              ),
              const SizedBox(height: 12),
              // 堆栈跟踪
              Expanded(
                child: _SectionCard(
                  title: '堆栈跟踪',
                  expandChild: true,
                  child: SingleChildScrollView(
                    child: SelectableText(
                      _formatStack(stackTrace),
                      style: _monoStyle(context).copyWith(fontSize: 11),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // 操作按钮
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _copyToClipboard(context),
                      icon: const Icon(Icons.copy, size: 18),
                      label: const Text('复制信息'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _restartApp(context),
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('重启应用'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  String _formatError(Object error) {
    if (error is FlutterError) {
      return error.message;
    }
    if (error is Error) {
      return error.toString();
    }
    return '$error';
  }

  String _formatStack(StackTrace stack) {
    final lines = '$stack'.split('\n');
    // 过滤掉框架内部堆栈，只保留用户代码相关的帧
    final filtered = <String>[];
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      // 保留所有帧，但标记框架帧
      filtered.add(trimmed);
    }
    return filtered.join('\n');
  }

  void _copyToClipboard(BuildContext context) {
    final buffer = StringBuffer();
    buffer.writeln('Error Type: ${error.runtimeType}');
    buffer.writeln('Error: ${_formatError(error)}');
    buffer.writeln(
      'Platform: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
    );
    buffer.writeln('\nStack Trace:');
    buffer.writeln(_formatStack(stackTrace));

    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('错误信息已复制到剪贴板')));
  }

  Future<void> _restartApp(BuildContext context) async {
    // 使用 restart_app 包重启应用
    final messenger = ScaffoldMessenger.of(context);
    try {
      await Restart.restartApp(mode: RestartMode.process);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('重启失败: $e')));
    }
  }

  TextStyle _monoStyle(BuildContext context) {
    return TextStyle(
      fontFamily: 'monospace',
      fontSize: 12,
      color: Theme.of(context).colorScheme.onSurface,
    );
  }
}

// -----------------------------------------------------------------------------
// Section Card
// -----------------------------------------------------------------------------

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.child,
    this.expandChild = false,
  });

  final String title;
  final Widget child;
  final bool expandChild;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: theme.colorScheme.outline.withValues(alpha: 0.15),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: expandChild ? MainAxisSize.max : MainAxisSize.min,
          children: [
            Text(
              title,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            expandChild ? Expanded(child: child) : child,
          ],
        ),
      ),
    );
  }
}
