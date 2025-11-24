import '../models/log_entry.dart';
import '../services/log_cache.dart';

/// Logger service that outputs to console and memory cache
class Logger {
  static bool get _isDebugBuild {
    var debug = false;
    assert(debug = true);
    return debug;
  }

  bool _loggingEnabled = false;
  bool get loggingEnabled => _loggingEnabled;
  
  void setLoggingEnabled(bool enabled) {
    _loggingEnabled = enabled;
  }

  /// Format timestamp for log output
  String _formatTime() {
    final t = DateTime.now();
    var h = t.hour.toString().padLeft(2, '0');
    var m = t.minute.toString().padLeft(2, '0');
    var s = t.second.toString().padLeft(2, '0');
    var l = t.millisecond.toString().padLeft(3, '0');
    return '$h:$m:$s.$l';
  }

  /// Internal log method
  void _log(String tag, LogLevel level, String message, [dynamic error, StackTrace? stackTrace]) {
    final time = _formatTime();
    final logString = '$time ${level.symbol} $tag: $message';
    
    // Always print to console in debug mode
    if (_isDebugBuild) {
      print(logString);
      if (error != null) {
        print(error);
      }
      if (stackTrace != null) {
        print(stackTrace);
      }
    }

    // Add to cache only if logging is enabled
    if (_loggingEnabled) {
      final logEntry = LogEntry(
        timestamp: DateTime.now(),
        level: level,
        tag: tag,
        message: message,
        color: level.color,
      );
      logCache.addLog(logEntry);

      // Add error and stack trace as separate entries if present
      if (error != null) {
        final errorEntry = LogEntry(
          timestamp: DateTime.now(),
          level: LogLevel.error,
          tag: tag,
          message: error.toString(),
          color: LogLevel.error.color,
        );
        logCache.addLog(errorEntry);
      }

      if (stackTrace != null) {
        final stackEntry = LogEntry(
          timestamp: DateTime.now(),
          level: LogLevel.error,
          tag: tag,
          message: stackTrace.toString(),
          color: LogLevel.error.color,
        );
        logCache.addLog(stackEntry);
      }
    }
  }

  void verbose(String tag, String message) {
    _log(tag, LogLevel.verbose, message);
  }

  void debug(String tag, String message) {
    _log(tag, LogLevel.debug, message);
  }

  void info(String tag, String message) {
    _log(tag, LogLevel.info, message);
  }

  void warning(String tag, String message) {
    _log(tag, LogLevel.warning, message);
  }

  void error(String tag, String message, [dynamic error, StackTrace? stackTrace]) {
    _log(tag, LogLevel.error, message, error, stackTrace);
  }
}

/// Global logger instance
final Logger logger = Logger();

