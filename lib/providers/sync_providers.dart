import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/sync_server_model.dart';
import '../services/local_database_service.dart';
import '../services/sync_manager_service.dart';

/// Provider for refreshing sync servers list
final syncServersRefreshProvider = StateProvider<int>((ref) => 0);

/// Provider for all sync servers
final syncServersProvider = FutureProvider<List<SyncServer>>((ref) async {
  // Watch refresh trigger
  ref.watch(syncServersRefreshProvider);

  final dbService = LocalDatabaseService.instance;
  await dbService.initialize();
  return dbService.getAllSyncServers();
});

/// Provider for active sync server
final activeSyncServerProvider = FutureProvider<SyncServer?>((ref) async {
  // Watch refresh trigger
  ref.watch(syncServersRefreshProvider);

  final dbService = LocalDatabaseService.instance;
  await dbService.initialize();
  final server = dbService.getActiveSyncServer();

  // Update sync manager with active server
  if (server != null) {
    SyncManagerService.instance.setActiveServer(server);
  }

  // Ensure sync strategy is loaded (this will be done by syncStrategyProvider, but we can trigger it here)
  // The syncStrategyProvider will load and set the strategy automatically

  return server;
});

/// Provider for sync manager service
final syncManagerProvider = Provider<SyncManagerService>((ref) {
  return SyncManagerService.instance;
});

/// Sync strategy state
class SyncStrategyState {
  final SyncStrategy strategy;

  SyncStrategyState({required this.strategy});
}

class SyncStrategyNotifier extends StateNotifier<SyncStrategyState> {
  static const String _prefsKey = 'sync_strategy';

  SyncStrategyNotifier()
    : super(SyncStrategyState(strategy: SyncStrategy.prompt)) {
    _loadStrategy();
  }

  Future<void> _loadStrategy() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final strategyString = prefs.getString(_prefsKey);
      SyncStrategy strategy;
      if (strategyString != null) {
        strategy = SyncStrategy.values.firstWhere(
          (e) => e.name == strategyString,
          orElse: () => SyncStrategy.prompt,
        );
      } else {
        strategy = SyncStrategy.prompt; // Default strategy
      }
      state = SyncStrategyState(strategy: strategy);
      // Update SyncManagerService with loaded strategy
      SyncManagerService.instance.setStrategy(strategy);
    } catch (e) {
      print('Error loading sync strategy: $e');
      // Keep default value (prompt)
      SyncManagerService.instance.setStrategy(SyncStrategy.prompt);
    }
  }

  Future<void> setStrategy(SyncStrategy strategy) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, strategy.name);
      state = SyncStrategyState(strategy: strategy);
      // Update SyncManagerService
      SyncManagerService.instance.setStrategy(strategy);
    } catch (e) {
      print('Error saving sync strategy: $e');
    }
  }
}

/// Provider for sync strategy
final syncStrategyProvider =
    StateNotifierProvider<SyncStrategyNotifier, SyncStrategyState>((ref) {
      return SyncStrategyNotifier();
    });

/// Provider for sync enabled state
final syncEnabledProvider = Provider<bool>((ref) {
  final strategyState = ref.watch(syncStrategyProvider);
  return strategyState.strategy != SyncStrategy.disabled;
});

/// Provider for sync state per book
final bookSyncStateProvider = StateProvider.family<SyncState, int>((
  ref,
  bookId,
) {
  return SyncState.idle;
});

/// Provider for sync conflict details per book
final bookSyncConflictProvider =
    StateProvider.family<SyncConflictDetails?, int>((ref, bookId) {
      return null;
    });
