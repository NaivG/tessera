import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'l10n/app_localizations.dart';
import 'state/settings_state.dart';
import 'ui/pages/error_page.dart';
import 'ui/pages/library_page.dart';
import 'ui/pages/main_page.dart';
import 'ui/pages/memory_page.dart';
import 'ui/pages/settings_page.dart';
import 'ui/pages/user_profile_page.dart';

// -----------------------------------------------------------------------------
// 全局错误暂存 —— 由 main.dart 中的错误处理器写入，路由生成时消费
// -----------------------------------------------------------------------------

/// 最近一次未处理异常的暂存信息
class _ErrorPayload {
  const _ErrorPayload({required this.error, required this.stackTrace});
  final Object error;
  final StackTrace stackTrace;
}

/// 最近一次未处理异常（线程不安全，仅限主 isolate 使用）
_ErrorPayload? _pendingError;

// -----------------------------------------------------------------------------
// 顶层公开 API —— main.dart 通过此入口访问私有 State 的静态成员
// -----------------------------------------------------------------------------

/// 全局 Navigator Key 的公开 getter，main.dart 中的错误处理器依赖它完成导航。
GlobalKey<NavigatorState> get globalNavigatorKey =>
    _TesseraAppState.globalNavigatorKey;

/// 暂存一个未处理异常，供下次 /error 路由消费。
void stashErrorForRouting(Object error, StackTrace stackTrace) =>
    _TesseraAppState.stashError(error, stackTrace);

/// 应用根组件 — 初始化状态并提供路由配置
class TesseraApp extends StatefulWidget {
  const TesseraApp({super.key});

  @override
  State<TesseraApp> createState() => _TesseraAppState();
}

class _TesseraAppState extends State<TesseraApp> {
  // ---------------------------------------------------------------------------
  // Navigator Key —— 暴露给 main.dart 的错误处理器用于全局导航
  // ---------------------------------------------------------------------------

  /// 全局 Navigator Key，main.dart 中的错误处理器依赖此 Key 导航到错误页。
  static final GlobalKey<NavigatorState> globalNavigatorKey =
      GlobalKey<NavigatorState>();

  // ---------------------------------------------------------------------------
  // 错误暂存 API
  // ---------------------------------------------------------------------------

  /// 暂存一个未处理异常，准备被下一次路由生成消费。
  static void stashError(Object error, StackTrace stackTrace) {
    _pendingError = _ErrorPayload(error: error, stackTrace: stackTrace);
  }

  /// 消费暂存的错误信息并返回；消费后清空。
  static _ErrorPayload? consumePendingError() {
    final payload = _pendingError;
    _pendingError = null;
    return payload;
  }

  final SettingsState _settingsState = SettingsState();
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _settingsState.load();
    setState(() => _initialized = true);
  }

  /// 解析主题模式
  ThemeMode _parseThemeMode(String mode) {
    return switch (mode) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  /// 解析语言环境，返回 null 使用系统默认
  Locale? _resolveLocale() {
    final localeStr = _settingsState.locale;
    if (localeStr == 'system') return null;
    return Locale(localeStr);
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: const [Locale('zh'), Locale('en')],
        home: const Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

    return ListenableBuilder(
      listenable: _settingsState,
      builder: (context, _) {
        return MaterialApp(
          title:
              'Tessera', // this should use localization, however, since AppLocalizations is in builder, we can't access it here. Ingore it for now.
          debugShowCheckedModeBanner: false,
          locale: _resolveLocale(),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: const [Locale('zh'), Locale('en')],
          navigatorKey: globalNavigatorKey,
          themeMode: _parseThemeMode(_settingsState.themeMode),
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.deepPurple,
              brightness: Brightness.light,
            ),
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.deepPurple,
              brightness: Brightness.dark,
            ),
            useMaterial3: true,
          ),
          home: MainPage(settingsState: _settingsState),
          onGenerateRoute: (settings) {
            if (settings.name == ErrorPage.routeName) {
              final payload = consumePendingError();
              return MaterialPageRoute<void>(
                builder: (_) => ErrorPage(
                  error: payload?.error ?? '未知错误',
                  stackTrace: payload?.stackTrace ?? StackTrace.empty,
                ),
              );
            }
            return null; // 回退到 routes 静态表
          },
          routes: {
            '/settings': (_) => SettingsPage(settingsState: _settingsState),
            '/profile': (_) => UserProfilePage(settingsState: _settingsState),
            '/library': (_) => const LibraryPage(),
            '/memory': (_) => const MemoryPage(),
          },
        );
      },
    );
  }
}
