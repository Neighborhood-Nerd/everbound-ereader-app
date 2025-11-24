import 'package:flutter/material.dart';

/// Represents a single log entry with metadata
class LogEntry {
  final DateTime timestamp;
  final LogLevel level;
  final String tag;
  final String message;
  final Color color;

  const LogEntry({
    required this.timestamp,
    required this.level,
    required this.tag,
    required this.message,
    required this.color,
  });

  /// Parse a log entry from the logger output format
  factory LogEntry.fromLogString(String logString) {
    // Parse format: "HH:MM:SS.mmm LEVEL TAG: message"
    final parts = logString.split(' ');
    if (parts.length < 3) {
      return LogEntry(
        timestamp: DateTime.now(),
        level: LogLevel.info,
        tag: 'Unknown',
        message: logString,
        color: Colors.grey,
      );
    }

    // Extract timestamp
    final timePart = parts[0];
    final now = DateTime.now();
    DateTime timestamp = now;

    try {
      final timeComponents = timePart.split(':');
      if (timeComponents.length >= 3) {
        final hour = int.parse(timeComponents[0]);
        final minute = int.parse(timeComponents[1]);
        final secondParts = timeComponents[2].split('.');
        final second = int.parse(secondParts[0]);
        final millisecond =
            secondParts.length > 1 ? int.parse(secondParts[1]) : 0;

        timestamp = DateTime(
            now.year, now.month, now.day, hour, minute, second, millisecond);
      }
    } catch (e) {
      // If parsing fails, use current time
      timestamp = now;
    }

    // Extract level
    final levelString = parts[1];
    final level = LogLevel.fromString(levelString);

    // Extract tag and message
    final tagAndMessage = parts.skip(2).join(' ');
    final colonIndex = tagAndMessage.indexOf(':');
    final tag =
        colonIndex > 0 ? tagAndMessage.substring(0, colonIndex) : 'Unknown';
    final message = colonIndex > 0
        ? tagAndMessage.substring(colonIndex + 1).trim()
        : tagAndMessage;

    return LogEntry(
      timestamp: timestamp,
      level: level,
      tag: tag,
      message: message,
      color: level.color,
    );
  }

  /// Format log entry for display
  String get formattedTime {
    return '${timestamp.hour.toString().padLeft(2, '0')}:'
        '${timestamp.minute.toString().padLeft(2, '0')}:'
        '${timestamp.second.toString().padLeft(2, '0')}.'
        '${timestamp.millisecond.toString().padLeft(3, '0')}';
  }

  /// Format log entry for sharing (plain text)
  String get formattedForShare {
    return '$formattedTime ${level.displayName} $tag: $message';
  }

  /// Check if log entry matches search query
  bool matchesSearch(String query) {
    if (query.isEmpty) return true;
    final lowerQuery = query.toLowerCase();
    return tag.toLowerCase().contains(lowerQuery) ||
        message.toLowerCase().contains(lowerQuery);
  }
}

/// Log levels with associated colors and display names
enum LogLevel {
  verbose('V', 'VERBOSE', Colors.grey),
  debug('D', 'DEBUG', Colors.blueGrey),
  info('I', 'INFO', Colors.green),
  warning('⚠️', 'WARNING', Colors.orange),
  error('❗️', 'ERROR', Colors.red);

  const LogLevel(this.symbol, this.displayName, this.color);

  final String symbol;
  final String displayName;
  final Color color;

  static LogLevel fromString(String levelString) {
    switch (levelString) {
      case 'V':
        return LogLevel.verbose;
      case 'D':
        return LogLevel.debug;
      case 'I':
        return LogLevel.info;
      case '⚠️':
      case 'W':
        return LogLevel.warning;
      case '❗️':
      case 'E':
        return LogLevel.error;
      default:
        return LogLevel.info;
    }
  }
}

