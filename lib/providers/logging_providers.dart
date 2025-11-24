import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/logger_service.dart';

/// Logging enabled state
class LoggingEnabledState {
  final bool enabled;

  LoggingEnabledState({required this.enabled});
}

/// Logging enabled notifier
class LoggingEnabledNotifier extends StateNotifier<LoggingEnabledState> {
  LoggingEnabledNotifier() : super(LoggingEnabledState(enabled: false)) {
    // Always start with logging disabled on app launch
    // This prevents users from accidentally leaving it on
    logger.setLoggingEnabled(false);
  }

  Future<void> setEnabled(bool enabled) async {
    // Don't persist to SharedPreferences - logging should not persist across app launches
    // This prevents users from accidentally leaving it on
    state = LoggingEnabledState(enabled: enabled);
    // Update logger service
    logger.setLoggingEnabled(enabled);
  }

  Future<void> toggle() async {
    await setEnabled(!state.enabled);
  }
}

/// Provider for logging enabled state
final loggingEnabledProvider =
    StateNotifierProvider<LoggingEnabledNotifier, LoggingEnabledState>((ref) {
  return LoggingEnabledNotifier();
});

