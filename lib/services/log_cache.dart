import 'dart:async';
import 'dart:collection';
import 'package:flutter/material.dart';
import '../models/log_entry.dart';

/// Custom logger output that caches logs in memory for real-time viewing
class MemoryCacheOutput {
  static const int _maxLogEntries = 1000;

  final Queue<LogEntry> _logEntries = Queue<LogEntry>();
  final StreamController<LogEntry> _logController =
      StreamController<LogEntry>.broadcast();

  Stream<LogEntry> get logStream => _logController.stream;
  List<LogEntry> get logs => List.unmodifiable(_logEntries);

  /// Add a log entry to the cache
  void addLog(LogEntry logEntry) {
    // Add to cache
    _logEntries.add(logEntry);

    // Maintain max size
    if (_logEntries.length > _maxLogEntries) {
      _logEntries.removeFirst();
    }

    // Notify listeners
    _logController.add(logEntry);
  }

  /// Clear all cached logs
  void clearLogs() {
    _logEntries.clear();
    _logController.add(LogEntry(
      timestamp: DateTime.now(),
      level: LogLevel.info,
      tag: 'Logger',
      message: 'Logs cleared',
      color: Colors.blue,
    ));
  }

  /// Get logs as formatted text for sharing
  String getLogsAsText() {
    return _logEntries.map((entry) => entry.formattedForShare).join('\n');
  }

  /// Dispose resources
  void dispose() {
    _logController.close();
  }
}

/// Global log cache instance
final MemoryCacheOutput logCache = MemoryCacheOutput();

