/// 简易日志工具
class Logger {
  final String tag;

  Logger(this.tag);

  void info(String message) {
    _log('INFO', message);
  }

  void warn(String message) {
    _log('WARN', message);
  }

  void error(String message, [Object? error, StackTrace? stack]) {
    _log('ERROR', message);
    if (error != null) _log('ERROR', '  $error');
    if (stack != null) _log('ERROR', '  $stack');
  }

  void debug(String message) {
    _log('DEBUG', message);
  }

  void _log(String level, String message) {
    // ignore: avoid_print
    print('[$level] [$tag] $message');
  }
}
