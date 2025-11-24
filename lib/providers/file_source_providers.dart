import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/file_source_model.dart';
import '../services/local_database_service.dart';
import '../services/file_source_service.dart';

export '../services/file_source_service.dart' show ScanResult;

/// Model for tracking per-source scan progress
class SourceScanProgress {
  final int sourceId;
  final int booksFound;
  final int booksImported;
  final bool isScanning;

  SourceScanProgress({
    required this.sourceId,
    required this.booksFound,
    required this.booksImported,
    required this.isScanning,
  });

  SourceScanProgress copyWith({
    int? sourceId,
    int? booksFound,
    int? booksImported,
    bool? isScanning,
  }) {
    return SourceScanProgress(
      sourceId: sourceId ?? this.sourceId,
      booksFound: booksFound ?? this.booksFound,
      booksImported: booksImported ?? this.booksImported,
      isScanning: isScanning ?? this.isScanning,
    );
  }
}

/// Provider for refreshing file sources list
final fileSourcesRefreshProvider = StateProvider<int>((ref) => 0);

/// Provider for all file sources
final fileSourcesProvider = FutureProvider<List<FileSource>>((ref) async {
  // Watch refresh trigger
  ref.watch(fileSourcesRefreshProvider);

  final dbService = LocalDatabaseService.instance;
  await dbService.initialize();
  return dbService.getAllFileSources();
});

/// Provider for scan progress status
final scanProgressProvider = StateProvider<String?>((ref) => null);

/// Provider for scan result
final scanResultProvider = StateProvider<ScanResult?>((ref) => null);

/// Provider for per-source scan progress
/// Maps source ID to progress information
final sourceScanProgressProvider = StateProvider<Map<int, SourceScanProgress>>(
  (ref) => {},
);

/// Provider for scanning a single source
final scanSingleSourceProvider = FutureProvider.family<ScanResult, int>((
  ref,
  sourceId,
) async {
  final fileSourceService = FileSourceService.instance;

  // Don't modify state during initialization - wait for the first await
  // This ensures the provider is fully initialized before we modify other providers
  await Future<void>.value(); // Yield to allow initialization to complete

  // Now safe to update progress
  ref.read(sourceScanProgressProvider.notifier).state = {
    ...ref.read(sourceScanProgressProvider),
    sourceId: SourceScanProgress(
      sourceId: sourceId,
      booksFound: 0,
      booksImported: 0,
      isScanning: true,
    ),
  };

  try {
    final result = await fileSourceService.scanSource(
      sourceId,
      onProgress: (booksFound, booksImported) {
        ref.read(sourceScanProgressProvider.notifier).state = {
          ...ref.read(sourceScanProgressProvider),
          sourceId: SourceScanProgress(
            sourceId: sourceId,
            booksFound: booksFound,
            booksImported: booksImported,
            isScanning: true,
          ),
        };
      },
    );

    // Mark source as done scanning
    ref.read(sourceScanProgressProvider.notifier).state = {
      ...ref.read(sourceScanProgressProvider),
      sourceId: SourceScanProgress(
        sourceId: sourceId,
        booksFound: result.scanned,
        booksImported: result.imported,
        isScanning: false,
      ),
    };

    // Clear progress after a short delay
    Future.delayed(const Duration(seconds: 3), () {
      final current = ref.read(sourceScanProgressProvider);
      if (current.containsKey(sourceId)) {
        final updated = Map<int, SourceScanProgress>.from(current);
        updated.remove(sourceId);
        ref.read(sourceScanProgressProvider.notifier).state = updated;
      }
    });

    return result;
  } catch (e) {
    // Clear progress on error
    final current = ref.read(sourceScanProgressProvider);
    final updated = Map<int, SourceScanProgress>.from(current);
    updated.remove(sourceId);
    ref.read(sourceScanProgressProvider.notifier).state = updated;
    rethrow;
  }
});

/// Provider for scanning operation
final scanSourcesProvider = FutureProvider.family<ScanResult, bool>((
  ref,
  isManualScan,
) async {
  final fileSourceService = FileSourceService.instance;

  // Don't modify state during initialization - wait for the first await
  // This ensures the provider is fully initialized before we modify other providers
  await Future<void>.value(); // Yield to allow initialization to complete

  // Now safe to update progress
  ref.read(scanProgressProvider.notifier).state = 'Starting scan...';

  try {
    final result = await fileSourceService.scanAllSources(
      onProgress: (message) {
        // Update progress - this is called from within the async operation, so it's safe
        ref.read(scanProgressProvider.notifier).state = message;
      },
      onSourceProgress: (sourceId, booksFound, booksImported) {
        ref.read(sourceScanProgressProvider.notifier).state = {
          ...ref.read(sourceScanProgressProvider),
          sourceId: SourceScanProgress(
            sourceId: sourceId,
            booksFound: booksFound,
            booksImported: booksImported,
            isScanning: true,
          ),
        };
      },
    );

    // Update result and clear progress after scan completes
    ref.read(scanResultProvider.notifier).state = result;
    ref.read(scanProgressProvider.notifier).state = null;

    // Clear all source progress after a short delay
    Future.delayed(const Duration(seconds: 3), () {
      ref.read(sourceScanProgressProvider.notifier).state = {};
    });

    return result;
  } catch (e) {
    // Clear progress on error
    ref.read(scanProgressProvider.notifier).state = null;
    ref.read(sourceScanProgressProvider.notifier).state = {};
    ref.read(scanResultProvider.notifier).state = ScanResult(
      scanned: 0,
      imported: 0,
      errors: ['Error: $e'],
    );
    rethrow;
  }
});

/// Provider for background scan timer
final backgroundScanTimerProvider = StateProvider<DateTime?>((ref) => null);

/// Initialize background scanning
/// Scans daily or on app start
void initializeBackgroundScanning(WidgetRef ref) {
  // Check if we should perform a background scan
  final lastScan = ref.read(backgroundScanTimerProvider);
  final now = DateTime.now();

  // Scan if:
  // 1. Never scanned before, OR
  // 2. Last scan was more than 24 hours ago
  if (lastScan == null || now.difference(lastScan).inHours >= 24) {
    // Perform background scan
    ref
        .read(scanSourcesProvider(false).future)
        .then((_) {
          ref.read(backgroundScanTimerProvider.notifier).state = now;
        })
        .catchError((e) {
          print('Background scan error: $e');
        });
  }

  // Set up periodic scanning (every 24 hours)
  // Note: In a real app, you might want to use a background task scheduler
  // For now, this will scan when the app starts if needed
}
