import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'package:window_manager/window_manager.dart';

import 'app.dart';
import 'services/media_library.dart';
import 'ui/pages/error_page.dart';
import 'utils/logger.dart';

final _log = Logger('main');

/// 防抖——避免同一个错误被多条路径重复触发导航
Object? _lastErrorIdentity;
StackTrace? _lastStackIdentity;

/// 正在处理中的标志，避免在导航过程中重复触发
bool _isRoutingToErrorPage = false;

void main() {
  ui.PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    _handleGlobalError(error, stack);
    return true; // 已处理
  };
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      if (kIsWeb) {
        // Web 端 sqflite FFI 初始化
        databaseFactory = databaseFactoryFfiWeb;
        _log.warn('Web 端 sqflite 为实验性功能，可能存在兼容性问题');
      } else if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
        // 桌面端 sqflite FFI 初始化
        sqfliteFfiInit();
        databaseFactory = databaseFactoryFfi;
      }

      // 初始化 MediaLibrary 缓存目录
      final appDir = (await getApplicationDocumentsDirectory()).path;
      await MediaLibrary.instance.init(appDir);

      // 桌面端：配置窗口
      try {
        await windowManager.ensureInitialized();
        await windowManager.setTitle('Tessera');
        await windowManager.setMinimumSize(const Size(400, 600));
        await windowManager.setSize(const Size(480, 720));
        await windowManager.center();
        await windowManager.show();
      } catch (_) {
        // 非桌面平台或初始化失败时忽略
      }

      // 1. 接管 FlutterError.onError —— 保留控制台输出，抑制红屏，路由到错误页
      final originalOnError = FlutterError.onError!;
      FlutterError.onError = (FlutterErrorDetails details) {
        // Debug 模式下保留原始输出（控制台可见）
        originalOnError(details);
        // 抑制红屏：不再调用 presentError
        // 路由到错误页
        _handleGlobalError(
          details.exception,
          details.stack ?? StackTrace.empty,
        );
      };

      // 2. 替换 build 异常的红屏 widget 为透明容器
      ErrorWidget.builder = (FlutterErrorDetails details) {
        // 延迟一帧后路由到错误页（此时 Navigator 应当已就绪）
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _handleGlobalError(
            details.exception,
            details.stack ?? StackTrace.empty,
          );
        });
        return Container(color: Colors.transparent);
      };

      runApp(const ProviderScope(child: TesseraApp()));
    },
    (Object error, StackTrace stack) {
      // Zone 级别未捕获异常（同 Zone 内的同步/异步异常）
      _handleGlobalError(error, stack);
    },
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) {
        // 保留所有 print 输出
        parent.print(zone, line);
      },
    ),
  );
}
// Future<void> main() async { // original main without global error handling
//       WidgetsFlutterBinding.ensureInitialized();

//       // 初始化 MediaLibrary 缓存目录
//       final appDir = (await getApplicationDocumentsDirectory()).path;
//       await MediaLibrary.instance.init(appDir);

//       // 桌面端：配置窗口
//       try {
//         await windowManager.ensureInitialized();
//         await windowManager.setTitle('Tessera');
//         await windowManager.setMinimumSize(const Size(400, 600));
//         await windowManager.setSize(const Size(480, 720));
//         await windowManager.center();
//         await windowManager.show();
//       } catch (_) {
//         // 非桌面平台或初始化失败时忽略
//       }

//       runApp(const ProviderScope(child: TesseraApp()));
// }

// -----------------------------------------------------------------------------
// 全局错误处理核心
// -----------------------------------------------------------------------------

/// 统一的全局错误入口。
///
/// 内建防抖机制：同一个错误对象只处理一次，避免 FlutterError.onError 和
/// runZonedGuarded 对同一异常重复路由。
void _handleGlobalError(Object error, StackTrace stack) {
  // 防抖：同一 error 实例不重复处理
  if (identical(error, _lastErrorIdentity) &&
      identical(stack, _lastStackIdentity)) {
    return;
  }
  if (_isRoutingToErrorPage) {
    // 忽略：正在处理中
    return;
  }
  _lastErrorIdentity = error;
  _lastStackIdentity = stack;

  _log.error('未处理的全局异常', error, stack);

  // 暂存异常，供 app.dart 中 onGenerateRoute 消费
  stashErrorForRouting(error, stack);

  // 导航到错误页并清空栈
  _navigateToErrorPage();

  _isRoutingToErrorPage = true; // 标记正在路由中
}

void _navigateToErrorPage() {
  // 始终延迟到下一帧，避免 Navigator 在 build/transition 期间被锁定
  WidgetsBinding.instance.addPostFrameCallback((_) {
    final navigator = globalNavigatorKey.currentState;
    if (navigator == null) {
      _log.error('无法导航到错误页：Navigator 未就绪');
      return;
    }
    try {
      navigator.pushNamedAndRemoveUntil(ErrorPage.routeName, (_) => false);
    } catch (e) {
      _log.error('导航到错误页失败: ', e);
    }
  });
}
