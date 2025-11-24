import 'dart:async';
import 'local_database_service.dart';
import 'koreader_sync_service.dart';
import '../models/sync_server_model.dart';
import 'logger_service.dart';

const String _tag = 'SyncManagerService';

/// Sync state enum
enum SyncState { idle, checking, synced, error, conflict }

/// Sync strategy enum
enum SyncStrategy {
  send, // Only push local progress
  receive, // Only pull remote progress
  prompt, // Ask user on conflict
  silent, // Use newer automatically
  disabled, // Don't sync
}

/// Conflict details for user resolution
class SyncConflictDetails {
  final LocalBook book;
  final String localPreview;
  final String? localCfi;
  final double localPercentage;
  final String remotePreview;
  final String? remoteProgress;
  final double? remotePercentage;
  final int remoteTimestamp;

  SyncConflictDetails({
    required this.book,
    required this.localPreview,
    this.localCfi,
    required this.localPercentage,
    required this.remotePreview,
    this.remoteProgress,
    this.remotePercentage,
    required this.remoteTimestamp,
  });
}

/// Debounced function with flush and cancel support
class DebouncedFunction<T> {
  final Future<T> Function() _function;
  final Duration _delay;
  Timer? _timer;
  Completer<T?>? _completer;

  DebouncedFunction(this._function, this._delay);

  Future<T?> call() async {
    _timer?.cancel();
    // Only complete the old completer if it hasn't been completed yet
    if (_completer != null && !_completer!.isCompleted) {
      _completer!.complete(null);
    }

    _completer = Completer<T?>();

    _timer = Timer(_delay, () async {
      if (_completer != null && !_completer!.isCompleted) {
        try {
          final result = await _function();
          _completer!.complete(result);
        } catch (e) {
          _completer!.completeError(e);
        }
      }
    });

    return _completer!.future;
  }

  void flush() {
    _timer?.cancel();
    _timer = null;
    // Execute immediately
    _function();
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
    // Only complete the completer if it hasn't been completed yet
    if (_completer != null && !_completer!.isCompleted) {
      _completer!.complete(null);
    }
    _completer = null;
  }

  void dispose() {
    cancel();
  }
}

/// Service for managing sync operations and state
class SyncManagerService {
  static final SyncManagerService instance = SyncManagerService._internal();
  factory SyncManagerService() => instance;
  SyncManagerService._internal();

  final Map<int, SyncState> _syncStates = {}; // bookId -> syncState
  final Map<int, SyncConflictDetails?> _conflictDetails =
      {}; // bookId -> conflictDetails
  final Map<int, DebouncedFunction<void>> _pushProgressDebouncers =
      {}; // bookId -> debouncer
  final Map<int, String?> _lastPushedProgress = {}; // bookId -> lastPushedCfi

  SyncStrategy _strategy = SyncStrategy.prompt;
  double _percentageTolerance = 0.01; // 1% tolerance
  String _checksumMethod =
      'binary'; // Default to 'binary' to match KOReader's 'Binary' method
  SyncServer? _activeServer;

  // Getters
  SyncState getSyncState(int bookId) => _syncStates[bookId] ?? SyncState.idle;
  SyncConflictDetails? getConflictDetails(int bookId) =>
      _conflictDetails[bookId];
  SyncStrategy get strategy => _strategy;
  double get percentageTolerance => _percentageTolerance;
  String get checksumMethod => _checksumMethod;
  SyncServer? get activeServer => _activeServer;

  // Setters
  void setStrategy(SyncStrategy strategy) => _strategy = strategy;
  void setPercentageTolerance(double tolerance) =>
      _percentageTolerance = tolerance;
  void setChecksumMethod(String method) => _checksumMethod = method;
  void setActiveServer(SyncServer? server) => _activeServer = server;

  /// Initialize sync for a book
  void initializeSync(int bookId) {
    _syncStates[bookId] = SyncState.idle;
    _conflictDetails[bookId] = null;
    _lastPushedProgress[bookId] = null;
  }

  /// Cleanup sync for a book
  void cleanupSync(int bookId) {
    _pushProgressDebouncers[bookId]?.dispose();
    _pushProgressDebouncers.remove(bookId);
    _syncStates.remove(bookId);
    _conflictDetails.remove(bookId);
    _lastPushedProgress.remove(bookId);
  }

  /// Perform initial sync check when book is opened
  Future<void> performInitialSync(LocalBook book) async {
    if (_activeServer == null || _strategy == SyncStrategy.disabled) {
      logger.verbose(_tag, 'Initial sync skipped - server: ${_activeServer != null}, strategy: ${_strategy.name}');
      _syncStates[book.id ?? 0] = SyncState.idle;
      return;
    }

    if (book.id == null) return;
    final bookId = book.id!;

    // Check if sync is disabled for this book
    if (book.syncEnabled == false) {
      logger.verbose(_tag, 'Initial sync skipped - sync disabled for book ID: $bookId');
      _syncStates[bookId] = SyncState.idle;
      return;
    }

    if (_strategy == SyncStrategy.send) {
      logger.verbose(_tag, 'Initial sync skipped - strategy is send-only for book ID: $bookId');
      _syncStates[bookId] = SyncState.synced;
      return;
    }

    logger.info(_tag, 'Starting initial sync for book ID: $bookId (title: ${book.title}, strategy: ${_strategy.name})');
    _syncStates[bookId] = SyncState.checking;

    try {
      final syncService = KOSyncService(
        server: _activeServer!,
        checksumMethod: _checksumMethod,
      );

      final remote = await syncService.getProgress(book);
      _lastPushedProgress[bookId] = book.lastReadCfi;

      if (remote == null ||
          remote.progress == null ||
          remote.timestamp == null) {
        // No remote progress, mark as synced and push local if needed
        logger.info(_tag, 'No remote progress found for book ID: $bookId - pushing local progress');
        _syncStates[bookId] = SyncState.synced;
        if (_strategy != SyncStrategy.receive) {
          await _pushProgressInternal(bookId);
        }
        return;
      }

      // Compare local and remote progress
      final localProgress = book.progressPercentage ?? 0.0;
      final remoteProgress = remote.percentage ?? 0.0;
      final localTimestamp = book.importedAt.millisecondsSinceEpoch;
      final remoteTimestamp =
          remote.timestamp! * 1000; // Convert to milliseconds
      final remoteIsNewer = remoteTimestamp > localTimestamp;
      
      logger.verbose(_tag, 'Sync comparison for book ID: $bookId - local: ${localProgress.toStringAsFixed(2)}% (${DateTime.fromMillisecondsSinceEpoch(localTimestamp)}), remote: ${remoteProgress.toStringAsFixed(2)}% (${DateTime.fromMillisecondsSinceEpoch(remoteTimestamp.toInt())}), remote newer: $remoteIsNewer');

      // Check if progress is identical (within tolerance)
      // Use relative tolerance: compare difference as percentage of the average progress
      // This is more accurate than absolute tolerance, especially for progress values away from 0
      final progressDifference = (localProgress - remoteProgress).abs();
      final averageProgress = (localProgress + remoteProgress) / 2.0;
      // Calculate relative difference: if average is 0, use absolute difference
      final relativeDifference = averageProgress > 0
          ? progressDifference / averageProgress
          : progressDifference;
      final isProgressIdentical = relativeDifference < _percentageTolerance;

      // Remote will never have epubcfi (it's always XPath from KOReader/Kindle)
      // If remote is newer, we should update progress and clear CFI so reader uses toProgressPercentage
      if (isProgressIdentical) {
        // Progress is identical - nothing to update
        _syncStates[bookId] = SyncState.synced;
        return;
      }

      // If local progress is 0% (unread), prefer remote progress regardless of timestamps
      // This handles the case where a book was just imported but has remote progress from KOReader
      // BUT: Don't apply remote progress if it's 0% - that would reset the book
      final isLocalUnread = localProgress < _percentageTolerance;
      final isRemoteValid =
          remoteProgress > 0.0; // Remote must be > 0% to be valid
      final shouldUseRemote = (isLocalUnread || remoteIsNewer) && isRemoteValid;

      // Handle conflict based on strategy
      if (_strategy == SyncStrategy.receive ||
          (_strategy == SyncStrategy.silent && shouldUseRemote)) {
        // Apply remote progress (will update percentage and clear CFI since remote has XPath, not epubcfi)
        // _applyRemoteProgress will also check for 0% progress as a safety measure
        logger.info(_tag, 'Applying remote progress for book ID: $bookId (strategy: ${_strategy.name}, shouldUseRemote: $shouldUseRemote)');
        await _applyRemoteProgress(book, remote);
        _syncStates[bookId] = SyncState.synced;
      } else if (_strategy == SyncStrategy.prompt) {
        // Show conflict dialog
        logger.info(_tag, 'Sync conflict detected for book ID: $bookId - showing prompt dialog');
        _conflictDetails[bookId] = SyncConflictDetails(
          book: book,
          localPreview: _formatProgressPreview(book, localProgress),
          localCfi: book.lastReadCfi,
          localPercentage: localProgress,
          remotePreview: _formatRemoteProgressPreview(remote),
          remoteProgress: remote.progress,
          remotePercentage: remote.percentage,
          remoteTimestamp: remote.timestamp!,
        );
        _syncStates[bookId] = SyncState.conflict;
      } else {
        // Default: mark as synced (will push local later)
        logger.verbose(_tag, 'Sync complete for book ID: $bookId - will push local progress later');
        _syncStates[bookId] = SyncState.synced;
      }
    } catch (e) {
      logger.error(_tag, 'Error during initial sync', e);
      _syncStates[bookId] = SyncState.error;
    }
  }

  // Temporary storage for push data
  final Map<int, LocalBook> _currentPushBook = {};
  final Map<int, String> _currentPushProgress = {};
  final Map<int, double?> _currentPushPercentage = {};

  /// Push progress to server (debounced)
  void pushProgress(
    int bookId,
    LocalBook book,
    String progressStr,
    double? percentage,
  ) {
    if (_activeServer == null ||
        _strategy == SyncStrategy.disabled ||
        _strategy == SyncStrategy.receive) {
      logger.verbose(_tag, 'Push progress skipped - server: ${_activeServer != null}, strategy: ${_strategy.name}');
      return;
    }

    if (bookId == 0 || book.id == null) return;

    // Check if sync is disabled for this book
    if (book.syncEnabled == false) {
      logger.verbose(_tag, 'Push progress skipped - sync disabled for book ID: $bookId');
      return;
    }

    // Don't push 0% progress - this would reset the book for other devices
    if (percentage != null && percentage <= 0.0) {
      logger.verbose(_tag, 'Push progress skipped - percentage is 0% for book ID: $bookId');
      return;
    }

    // Skip if same progress was already pushed
    if (_lastPushedProgress[bookId] == progressStr) {
      logger.verbose(_tag, 'Push progress skipped - same progress already pushed for book ID: $bookId');
      return;
    }

    logger.verbose(_tag, 'Queuing progress push for book ID: $bookId - progress: $progressStr, percentage: ${percentage?.toStringAsFixed(2)}%');

    // Store current book data for the push
    _currentPushBook[bookId] = book;
    _currentPushProgress[bookId] = progressStr;
    _currentPushPercentage[bookId] = percentage;

    // Get or create debouncer for this book
    var debouncer = _pushProgressDebouncers[bookId];
    if (debouncer == null) {
      debouncer = DebouncedFunction<void>(
        () => _pushProgressInternal(bookId),
        const Duration(seconds: 5),
      );
      _pushProgressDebouncers[bookId] = debouncer;
    }

    debouncer.call();
  }

  /// Internal method to actually push progress
  Future<void> _pushProgressInternal(int bookId) async {
    final book = _currentPushBook[bookId];
    final progressStr = _currentPushProgress[bookId];
    final percentage = _currentPushPercentage[bookId];

    if (book == null || progressStr == null || _activeServer == null) {
      logger.warning(_tag, 'Push progress internal skipped - missing data for book ID: $bookId');
      return;
    }

    try {
      logger.info(_tag, 'Pushing progress to server for book ID: $bookId (title: ${book.title}) - progress: $progressStr, percentage: ${percentage?.toStringAsFixed(2)}%');
      final syncService = KOSyncService(
        server: _activeServer!,
        checksumMethod: _checksumMethod,
      );

      await syncService.updateProgress(book, progressStr, percentage);
      _lastPushedProgress[bookId] = progressStr;
      logger.info(_tag, 'Successfully pushed progress for book ID: $bookId');
    } catch (e) {
      logger.error(_tag, 'Error pushing progress', e);
      _syncStates[bookId] = SyncState.error;
    }
  }

  /// Flush pending progress pushes
  void flushProgress(int bookId) {
    _pushProgressDebouncers[bookId]?.flush();
  }

  /// Apply remote progress to local book
  Future<void> _applyRemoteProgress(
    LocalBook book,
    KoSyncProgress remote,
  ) async {
    if (book.id == null) return;

    logger.info(_tag, 'Applying remote progress for book ID: ${book.id} (title: ${book.title}) - remote progress: ${remote.progress}, percentage: ${remote.percentage?.toStringAsFixed(2)}%');

    final dbService = LocalDatabaseService.instance;
    await dbService.initialize();

    // Remote will never have epubcfi (it's always XPath from KOReader/Kindle)
    // When we apply remote progress, we should:
    // 1. Update the progress percentage
    // 2. Save the XPath from remote.progress
    // 3. Clear the CFI (set to null) so reader screen uses initialXPath instead of initialCfi

    // Use remote percentage if available, otherwise keep existing progress
    final progressToUse = remote.percentage ?? book.progressPercentage ?? 0.0;

    // Don't apply 0% progress - this would reset the book to the beginning
    if (progressToUse <= 0.0) {
      logger.warning(_tag, 'Skipping remote progress application - progress is 0% for book ID: ${book.id}');
      return;
    }

    // Extract XPath from remote progress (remote.progress is XPath for reflowable EPUBs, or page number for fixed layout)
    // Only use it if it looks like an XPath (starts with /body) or is a page number (numeric)
    String? xpathToSave;
    if (remote.progress != null && remote.progress!.isNotEmpty) {
      if (remote.progress!.startsWith('/body') ||
          RegExp(r'^\d+$').hasMatch(remote.progress!)) {
        xpathToSave = remote.progress;
      }
    }

    // Update local progress with remote percentage, save XPath, and clear CFI
    logger.verbose(_tag, 'Updating local book progress - book ID: ${book.id}, progress: ${progressToUse.toStringAsFixed(2)}%, XPath: ${xpathToSave ?? "none"}');
    dbService.updateProgress(
      book.id!,
      progressToUse,
      null,
      lastReadCfi: null,
      lastReadXPath: xpathToSave,
    );
    logger.info(_tag, 'Successfully applied remote progress to local book ID: ${book.id}');
  }

  /// Format progress preview for local
  String _formatProgressPreview(LocalBook book, double progress) {
    final percentage = (progress * 100).toStringAsFixed(0);
    return '$percentage%';
  }

  /// Format progress preview for remote
  String _formatRemoteProgressPreview(KoSyncProgress remote) {
    if (remote.percentage != null) {
      final percentage = (remote.percentage! * 100).toStringAsFixed(0);
      return 'Approximately $percentage%';
    }
    return 'Current position';
  }

  /// Resolve conflict by using local progress
  Future<void> resolveConflictWithLocal(int bookId) async {
    logger.info(_tag, 'Resolving sync conflict with LOCAL progress for book ID: $bookId');
    final debouncer = _pushProgressDebouncers[bookId];
    if (debouncer != null) {
      debouncer.flush();
    }
    _syncStates[bookId] = SyncState.synced;
    _conflictDetails[bookId] = null;
    logger.info(_tag, 'Conflict resolved - using local progress for book ID: $bookId');
  }

  /// Resolve conflict by using remote progress
  Future<void> resolveConflictWithRemote(
    int bookId,
    LocalBook book,
    KoSyncProgress remote,
  ) async {
    logger.info(_tag, 'Resolving sync conflict with REMOTE progress for book ID: $bookId (title: ${book.title})');
    await _applyRemoteProgress(book, remote);
    _syncStates[bookId] = SyncState.synced;
    _conflictDetails[bookId] = null;
    logger.info(_tag, 'Conflict resolved - using remote progress for book ID: $bookId');
  }

  /// Cleanup all resources
  void dispose() {
    for (final debouncer in _pushProgressDebouncers.values) {
      debouncer.dispose();
    }
    _pushProgressDebouncers.clear();
    _syncStates.clear();
    _conflictDetails.clear();
    _lastPushedProgress.clear();
    _currentPushBook.clear();
    _currentPushProgress.clear();
    _currentPushPercentage.clear();
  }

  /// Get remote progress for conflict resolution
  Future<KoSyncProgress?> getRemoteProgress(LocalBook book) async {
    if (_activeServer == null) {
      logger.verbose(_tag, 'getRemoteProgress skipped - no active server');
      return null;
    }

    try {
      logger.verbose(_tag, 'Getting remote progress for book: ${book.title} (ID: ${book.id})');
      final syncService = KOSyncService(
        server: _activeServer!,
        checksumMethod: _checksumMethod,
      );
      final progress = await syncService.getProgress(book);
      if (progress != null) {
        logger.info(_tag, 'Retrieved remote progress for book ID: ${book.id} - progress: ${progress.progress}, percentage: ${progress.percentage?.toStringAsFixed(2)}%');
      } else {
        logger.verbose(_tag, 'No remote progress found for book ID: ${book.id}');
      }
      return progress;
    } catch (e) {
      logger.error(_tag, 'Error getting remote progress', e);
      return null;
    }
  }
}
