import 'dart:async';
import 'dart:io' as io;
import 'dart:io';
import 'package:Everbound/colors.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:modal_bottom_sheet/modal_bottom_sheet.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../services/local_database_service.dart';
import '../providers/my_books_providers.dart';
import '../providers/reader_providers.dart';
import '../providers/sync_providers.dart';
import '../providers/home_providers.dart';
import '../services/sync_manager_service.dart';
import '../services/volume_key_service.dart';
import '../services/logger_service.dart';
import '../services/book_import_service.dart';
import '../services/highlights_service.dart';
import '../widgets/wiktionary_popup.dart';
import '../widgets/theme_bottom_sheet.dart';
import '../widgets/koreader_sync_settings_widget.dart';
import '../widgets/sync_conflict_bottom_sheet.dart';
import '../models/app_theme_model.dart';
import '../models/highlight_model.dart';
import '../models/epub_models.dart';
import '../widgets/foliate_webview.dart';
import '../screens/book_detail_screen.dart';
import '../models/book_model.dart';
import 'dart:math';

const String _tag = 'ReaderScreen';

const Color darkIconColor = Color(0xFFc6c6c6);
const Color lightIconColor = Color(0xFF49454f);

const bool colorTapZones = false;
const bool showDebugRects = false;

// Helper enum for triangle direction
enum TriangleDirection { up, down }

// Custom painter for triangle pointer
class TrianglePainter extends CustomPainter {
  final TriangleDirection direction;
  final Color color;

  TrianglePainter({required this.direction, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path();
    if (direction == TriangleDirection.down) {
      // Pointing down (bar is above selection)
      path.moveTo(0, 0);
      path.lineTo(size.width / 2, size.height);
      path.lineTo(size.width, 0);
    } else {
      // Pointing up (bar is below selection)
      path.moveTo(0, size.height);
      path.lineTo(size.width / 2, 0);
      path.lineTo(size.width, size.height);
    }
    path.close();

    // Draw shadow offset slightly
    canvas.save();
    canvas.translate(0, 1);
    canvas.restore();

    // Draw triangle
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(TrianglePainter oldDelegate) {
    return oldDelegate.direction != direction || oldDelegate.color != color;
  }
}

// Custom clipper for selection overlay with triangle
class _SelectionOverlayClipper extends CustomClipper<Path> {
  final double triangleLeft;
  final double triangleWidth;
  final double triangleHeight;
  final double cardHeight;
  final double borderRadius;

  _SelectionOverlayClipper({
    required this.triangleLeft,
    required this.triangleWidth,
    required this.triangleHeight,
    required this.cardHeight,
    required this.borderRadius,
  });

  @override
  Path getClip(Size size) {
    final path = Path();
    final width = size.width;
    final height = size.height - triangleHeight; // Card height without triangle

    // Rounded rectangle for the card
    path.addRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, width, height),
        Radius.circular(borderRadius),
      ),
    );

    // Triangle at bottom (pointing down)
    // triangleLeft is already the center position relative to the card
    final triangleCenterX = triangleLeft.clamp(
      triangleWidth / 2,
      width - triangleWidth / 2,
    );
    final triangleTop = height;
    path.moveTo(triangleCenterX - triangleWidth / 2, triangleTop);
    path.lineTo(triangleCenterX, triangleTop + triangleHeight);
    path.lineTo(triangleCenterX + triangleWidth / 2, triangleTop);
    path.close();

    return path;
  }

  @override
  bool shouldReclip(_SelectionOverlayClipper oldClipper) {
    return oldClipper.triangleLeft != triangleLeft ||
        oldClipper.triangleWidth != triangleWidth ||
        oldClipper.triangleHeight != triangleHeight ||
        oldClipper.cardHeight != cardHeight ||
        oldClipper.borderRadius != borderRadius;
  }
}

class ReaderScreen extends ConsumerStatefulWidget {
  final BookModel book;

  const ReaderScreen({super.key, required this.book});

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen> {
  // Replaced flutter_epub_viewer with custom foliate-js based implementation.
  final FoliateReaderController _epubController = FoliateReaderController();
  final GlobalKey _epubViewerKey =
      GlobalKey(); // Key to preserve WebView across rebuilds
  final VolumeKeyService _volumeKeyService = VolumeKeyService.instance;
  final HighlightsService _highlightsService = HighlightsService();
  final _random = Random();

  /// Get current notes (highlights with non-empty note text)
  List<HighlightModel> get _currentNotes {
    if (_currentHighlights == null) return [];
    return _currentHighlights!.values.where((h) => h.isNote).toList();
  }

  String? _savedCfi; // Saved CFI to resume from
  String? _savedXPath; // Saved XPath to resume from (for KOReader sync)
  bool _progressLoaded =
      false; // Track if progress has been loaded from database
  double? _savedProgress; // Saved progress percentage (for UI display)
  // Legacy display settings from flutter_epub_viewer (kept for now to avoid large refactor).
  // The new foliate-js implementation derives theme settings directly.
  EpubDisplaySettings? _displaySettings;
  String?
  _resolvedEpubPath; // Resolved EPUB file path (handles iOS container ID changes)
  String? _cachedEpubPath; // Track path used for cached source
  bool _isNavigating = false; // Prevent rapid navigation calls
  Timer? _navigationDebounceTimer;
  String? _pendingNoteNavigationCfi; // Track CFI we're navigating to for a note
  Timer?
  _noteNavigationTimer; // Timer to clear the pending note navigation flag
  bool _initialLoadComplete =
      false; // Track if initial load/navigation is complete
  bool _initialPositionLoaded =
      false; // Track if initial position has been loaded
  bool _conflictDialogShown =
      false; // Track if conflict dialog has been shown to prevent duplicates
  bool?
  _progressMatchesRemote; // Track if local progress matches remote (null = not checked yet, true = matches, false = doesn't match)
  String?
  _lastSavedXPath; // Track last saved XPath to avoid saving stale/duplicate positions
  double?
  _lastSavedProgress; // Track last saved progress to detect meaningful changes
  double? _bottomSheetHeight; // Track actual height of bottom sheet
  final GlobalKey _bottomSheetKey = GlobalKey();
  final GlobalKey _overlayMenuKey = GlobalKey();
  double? _overlayMenuWidth; // Track actual width of overlay menu
  Offset? _touchDownPosition; // Store touch down position to detect swipes
  Offset? _touchUpPosition; // Store touch up position to detect swipes
  bool _screenAwakeLockEnabled = false; // Track if wakelock is currently active
  bool _annotationClicked =
      false; // Track if annotation was clicked (to prevent control toggle)
  bool _selectionHappened =
      false; // Track if selection event happened after touch up (to prevent control toggle)
  final MenuController _syncMenuController =
      MenuController(); // Controller for sync menu
  Timer? _touchUpTimer; // Timer for delayed touch up processing
  bool _isDisposing =
      false; // Track if widget is disposing to prevent callbacks from executing
  Map<String, HighlightModel>?
  _currentHighlights; // Cache of current highlights for quick lookup
  List<EpubChapter>?
  _pendingChapters; // Cache chapters until initial position is loaded
  List<HighlightModel>?
  _pendingHighlights; // Highlights to be added when sections load
  final Set<int> _loadedSectionIndices = {}; // Track which sections have loaded
  // Page number tracking for displaying current page and total pages
  Map<String, int>?
  _currentPageInfo; // {current: int, total: int} for page numbers
  Map<String, int>?
  _currentSectionInfo; // {current: int, total: int} for section numbers (fixed layout)

  // Padding around FoliateEpubViewer - used for both the viewer and overlay positioning
  // When keepMenusOpen is true, top and bottom padding match nav bar heights
  EdgeInsets _getEpubViewerPadding(bool keepMenusOpen) {
    if (keepMenusOpen) {
      // Top nav height: 100, Bottom nav height: 96
      return const EdgeInsets.only(
        left: 8.0,
        right: 8.0,
        top: 100.0,
        bottom: 96.0,
      );
    }
    return const EdgeInsets.only(
      left: 8.0,
      right: 8.0,
      top: 16.0,
      bottom: 32.0,
    );
  }

  // Helper getters for Riverpod state (only for values actually used throughout the code)
  List<EpubChapter> get _chapters => ref.read(epubStateProvider).chapters;
  EpubLocation? get _currentLocation =>
      ref.read(epubStateProvider).currentLocation;
  bool get _themeManuallySet =>
      ref.read(readingSettingsProvider).themeManuallySet;

  @override
  void initState() {
    super.initState();
    logger.info(
      _tag,
      'Initializing reader for book: ${widget.book.title} (ID: ${widget.book.id})',
    );
    _loadSavedProgressAndSync();
    _initializeScreenAwakeLock();
    // Note: Volume key listener setup is now done in build method
    // to ensure ref.listen can be used properly
  }

  /// Initialize screen awake lock if enabled in settings
  Future<void> _initializeScreenAwakeLock() async {
    try {
      final keepAwakeSetting = ref.read(keepScreenAwakeSettingProvider);
      if (keepAwakeSetting.enabled) {
        await WakelockPlus.enable();
        _screenAwakeLockEnabled = true;
        logger.info(_tag, 'Screen awake lock enabled');
      }
    } catch (e) {
      logger.error(_tag, 'Error enabling screen awake lock', e);
    }
  }

  /// Load saved progress, sync with server, then initialize EPUB
  Future<void> _loadSavedProgressAndSync() async {
    await _loadSavedProgress();

    // Perform sync before initializing EPUB so we use the latest progress
    await _initializeSync();

    // Now initialize EPUB with the synced progress
    _initializeEpub();
  }

  /// Initialize sync for this book and update local progress if needed
  Future<void> _initializeSync() async {
    try {
      final dbService = LocalDatabaseService.instance;
      await dbService.initialize();

      int? bookId = int.tryParse(widget.book.id);
      if (bookId == null) {
        final book = dbService.getBookByFilePath(
          widget.book.epubFilePath ?? '',
        );
        if (book != null && book.id != null) {
          bookId = book.id;
        }
      }

      if (bookId != null) {
        final syncManager = SyncManagerService.instance;
        syncManager.initializeSync(bookId);

        // Load active server and perform initial sync
        final activeServer = await ref.read(activeSyncServerProvider.future);
        if (activeServer != null && mounted) {
          final book = dbService.getBookById(bookId);
          if (book != null) {
            // Check if progress matches remote BEFORE sync runs (so we can preserve CFI if it's legit)
            final remote = await syncManager.getRemoteProgress(book);
            if (remote != null &&
                remote.percentage != null &&
                remote.timestamp != null) {
              final localProgress = book.progressPercentage ?? 0.0;
              final remoteProgress = remote.percentage ?? 0.0;
              // Use same tolerance logic as sync manager (0.01 = 1%)
              const percentageTolerance = 0.01;
              final progressDifference = (localProgress - remoteProgress).abs();
              final averageProgress = (localProgress + remoteProgress) / 2.0;
              final relativeDifference = averageProgress > 0
                  ? progressDifference / averageProgress
                  : progressDifference;
              final isProgressIdentical =
                  relativeDifference < percentageTolerance;

              // If progress matches and we have a valid CFI, preserve it
              final hasValidCfi =
                  book.lastReadCfi != null &&
                  book.lastReadCfi!.isNotEmpty &&
                  book.lastReadCfi!.startsWith('epubcfi');
              // Set _progressMatchesRemote based on whether progress matches and we have valid CFI
              if (isProgressIdentical && hasValidCfi) {
                _progressMatchesRemote = true; // Progress matches - use CFI
              } else {
                _progressMatchesRemote =
                    false; // Progress doesn't match - use XPath
              }
            } else {
              // No remote progress to compare - default to trusting local CFI if available
              // This means we'll use CFI instead of XPath (faster, no "loading book" message)
              _progressMatchesRemote =
                  null; // null means "not checked" or "no remote to compare" - default to CFI
            }

            // Store CFI before sync to restore if needed
            final cfiBeforeSync = book.lastReadCfi;

            await syncManager.performInitialSync(book);

            // Reload progress from database after sync (may have been updated)
            final updatedBook = dbService.getBookById(bookId);
            if (updatedBook != null && mounted) {
              _savedCfi = updatedBook.lastReadCfi;
              _savedXPath = updatedBook.lastReadXPath;
              _savedProgress = updatedBook.progressPercentage;

              // If progress matched and we should preserve CFI, restore it if sync cleared it
              if (_progressMatchesRemote == true &&
                  _savedCfi == null &&
                  cfiBeforeSync != null) {
                // Restore CFI to database
                dbService.updateProgress(
                  bookId,
                  updatedBook.progressPercentage ?? 0.0,
                  null,
                  lastReadCfi: cfiBeforeSync,
                  lastReadXPath: updatedBook.lastReadXPath,
                );
                _savedCfi = cfiBeforeSync;
              }
            }

            // Don't check for conflict here - we'll check after initial navigation completes
            // This ensures the book is fully loaded before showing the conflict dialog
          }
        }
      }
    } catch (e) {
      print('Error initializing sync: $e');
    }
  }

  /// Check for sync conflict and show dialog if needed
  void _checkSyncConflict(int bookId) {
    // Prevent showing conflict dialog multiple times
    if (_conflictDialogShown) return;

    final syncManager = SyncManagerService.instance;
    final conflictDetails = syncManager.getConflictDetails(bookId);
    final syncState = syncManager.getSyncState(bookId);

    if (syncState == SyncState.conflict && conflictDetails != null && mounted) {
      _conflictDialogShown = true; // Mark as shown before displaying
      _showConflictDialog(conflictDetails, bookId);
    }
  }

  /// Show conflict resolution dialog
  void _showConflictDialog(SyncConflictDetails conflict, int bookId) async {
    if (!mounted) return;

    // Double-check flag to prevent showing multiple dialogs
    if (_conflictDialogShown) return;

    await SyncConflictBottomSheet.show(
      context,
      conflict,
      bookId,
      () async => await _resolveConflictWithLocal(bookId),
      () async => await _resolveConflictWithRemote(bookId, conflict),
    );
  }

  /// Resolve conflict by using local progress
  Future<void> _resolveConflictWithLocal(int bookId) async {
    logger.info(
      _tag,
      'User chose to resolve sync conflict with LOCAL progress for book ID: $bookId',
    );
    final syncManager = SyncManagerService.instance;
    await syncManager.resolveConflictWithLocal(bookId);

    // Navigate to local saved position
    if (!mounted) return;

    // Wait for EPUB to be ready
    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;

    // Navigate to saved position (local)
    if (_savedXPath != null && _savedXPath!.isNotEmpty) {
      try {
        print('Navigating to local XPath: $_savedXPath');
        await _epubController.goToLocation({'cfi': _savedXPath!});
        setState(() {
          _initialPositionLoaded = true;
          _initialLoadComplete = true;
        });
      } catch (e) {
        print('Error navigating to local XPath: $e');
        // Fallback to CFI if available
        if (_savedCfi != null && _savedCfi!.isNotEmpty) {
          try {
            _epubController.goToLocation({'cfi': _savedCfi!});
            setState(() {
              _initialPositionLoaded = true;
              _initialLoadComplete = true;
            });
          } catch (e2) {
            print('Error navigating to local CFI: $e2');
          }
        }
      }
    } else if (_savedCfi != null && _savedCfi!.isNotEmpty) {
      try {
        print('Navigating to local CFI: $_savedCfi');
        _epubController.goToLocation({'cfi': _savedCfi!});
        setState(() {
          _initialPositionLoaded = true;
          _initialLoadComplete = true;
        });
      } catch (e) {
        print('Error navigating to local CFI: $e');
      }
    } else if (_savedProgress != null && _savedProgress! > 0.0) {
      try {
        print('Navigating to local percentage: $_savedProgress');
        _navigateToPercentage(_savedProgress!);
        setState(() {
          _initialPositionLoaded = true;
          _initialLoadComplete = true;
        });
      } catch (e) {
        print('Error navigating to local percentage: $e');
      }
    } else {
      // No saved position, mark as complete
      setState(() {
        _initialPositionLoaded = true;
        _initialLoadComplete = true;
      });
    }
  }

  /// Resolve conflict by using remote progress
  Future<void> _resolveConflictWithRemote(
    int bookId,
    SyncConflictDetails conflict,
  ) async {
    logger.info(
      _tag,
      'User chose to resolve sync conflict with REMOTE progress for book ID: $bookId',
    );
    final syncManager = SyncManagerService.instance;
    final dbService = LocalDatabaseService.instance;
    await dbService.initialize();

    final book = dbService.getBookById(bookId);
    if (book != null) {
      final remote = await syncManager.getRemoteProgress(book);
      if (remote != null) {
        await syncManager.resolveConflictWithRemote(bookId, book, remote);

        // Use XPath directly from remote progress (KOReader sync provides XPath in remote.progress)
        String? xpathToUse;
        double? remotePercentage =
            remote.percentage ?? conflict.remotePercentage;

        // remote.progress contains the XPath string from KOReader (starts with /body) or page number
        if (remote.progress != null && remote.progress!.startsWith('/body')) {
          xpathToUse = remote.progress;
        }

        // Reload book to update UI state
        final updatedBook = dbService.getBookById(bookId);
        if (updatedBook != null && mounted) {
          _savedCfi = updatedBook.lastReadCfi;
          _savedXPath = updatedBook
              .lastReadXPath; // Load XPath from database (saved by _applyRemoteProgress)
          _savedProgress = updatedBook.progressPercentage;

          // Use saved XPath if we don't have one from remote.progress
          if ((xpathToUse == null || xpathToUse.isEmpty) &&
              _savedXPath != null &&
              _savedXPath!.isNotEmpty) {
            xpathToUse = _savedXPath;
          }
        }

        if (!mounted) return;

        // Reload saved progress to ensure state is updated
        await _loadSavedProgress();

        if (!mounted) return;

        // Book is already loaded and ready (we navigated to local first)
        // Just wait a brief moment to ensure any pending operations complete
        await Future.delayed(const Duration(milliseconds: 300));
        if (!mounted) return;

        // Navigate to remote saved position
        if (xpathToUse != null && xpathToUse.isNotEmpty) {
          try {
            print('Navigating to remote XPath: $xpathToUse');
            await _epubController.goToLocation({'cfi': xpathToUse});
            // Wait a bit to ensure navigation completed
            await Future.delayed(const Duration(milliseconds: 300));
            setState(() {
              _initialPositionLoaded = true;
              _initialLoadComplete = true;
            });
            print('✅ Successfully navigated to remote XPath');
          } catch (e) {
            print('Error navigating to remote XPath: $e');
            // Fallback to CFI if available
            if (_savedCfi != null && _savedCfi!.isNotEmpty) {
              try {
                print('Falling back to remote CFI: $_savedCfi');
                await _epubController.goToLocation({'cfi': _savedCfi!});
                await Future.delayed(const Duration(milliseconds: 300));
                setState(() {
                  _initialPositionLoaded = true;
                  _initialLoadComplete = true;
                });
                print('✅ Successfully navigated to remote CFI');
              } catch (e2) {
                print('Error navigating to remote CFI: $e2');
                // Fallback to percentage navigation if CFI fails
                if (remotePercentage != null && remotePercentage > 0.0) {
                  try {
                    print(
                      'Falling back to percentage navigation: $remotePercentage',
                    );
                    _navigateToPercentage(remotePercentage);
                    await Future.delayed(const Duration(milliseconds: 200));
                    setState(() {
                      _initialPositionLoaded = true;
                      _initialLoadComplete = true;
                    });
                    print('✅ Successfully navigated to remote percentage');
                  } catch (e3) {
                    print('Error navigating to percentage: $e3');
                  }
                }
              }
            } else if (remotePercentage != null && remotePercentage > 0.0) {
              // Fallback to percentage navigation if XPath fails
              try {
                print(
                  'Falling back to percentage navigation: $remotePercentage',
                );
                _navigateToPercentage(remotePercentage);
                await Future.delayed(const Duration(milliseconds: 200));
                setState(() {
                  _initialPositionLoaded = true;
                  _initialLoadComplete = true;
                });
                print('✅ Successfully navigated to remote percentage');
              } catch (e2) {
                print('Error navigating to percentage: $e2');
              }
            }
          }
        } else if (_savedCfi != null && _savedCfi!.isNotEmpty) {
          try {
            print('Navigating to remote CFI: $_savedCfi');
            await _epubController.goToLocation({'cfi': _savedCfi!});
            await Future.delayed(const Duration(milliseconds: 300));
            setState(() {
              _initialPositionLoaded = true;
              _initialLoadComplete = true;
            });
            print('✅ Successfully navigated to remote CFI');
          } catch (e) {
            print('Error navigating to remote CFI: $e');
            // Fallback to percentage if CFI fails
            if (remotePercentage != null && remotePercentage > 0.0) {
              try {
                print(
                  'Falling back to percentage navigation: $remotePercentage',
                );
                _navigateToPercentage(remotePercentage);
                await Future.delayed(const Duration(milliseconds: 300));
                setState(() {
                  _initialPositionLoaded = true;
                  _initialLoadComplete = true;
                });
                print('✅ Successfully navigated to remote percentage');
              } catch (e2) {
                print('Error navigating to percentage: $e2');
              }
            }
          }
        } else if (remotePercentage != null && remotePercentage > 0.0) {
          // Fallback to percentage if no XPath or CFI available
          try {
            print(
              'No XPath/CFI available, using percentage navigation: $remotePercentage',
            );
            _navigateToPercentage(remotePercentage);
            await Future.delayed(const Duration(milliseconds: 300));
            setState(() {
              _initialPositionLoaded = true;
              _initialLoadComplete = true;
            });
            print('✅ Successfully navigated to remote percentage');
          } catch (e) {
            print('Error navigating to percentage: $e');
          }
        } else {
          // No saved position, mark as complete
          setState(() {
            _initialPositionLoaded = true;
            _initialLoadComplete = true;
          });
        }
      }
    }
  }

  /// Navigate to a specific percentage position using chapter-based navigation
  /// This is more reliable than toProgressPercentage which doesn't work on initial load
  /// Takes a double between 0.0 and 1.0 representing the progress percentage
  void _navigateToPercentageUsingChapters(
    double percentage,
    List<EpubChapter> chapters,
  ) {
    if (chapters.isEmpty) return;

    try {
      // Calculate which chapter corresponds to the percentage
      final targetChapterIndex = (percentage * chapters.length).floor().clamp(
        0,
        chapters.length - 1,
      );
      final targetChapter = chapters[targetChapterIndex];

      // Navigate to the chapter using its CFI/href
      _epubController.goToLocation({'href': targetChapter.href});
    } catch (e) {
      print('Error navigating to percentage using chapters: $e');
    }
  }

  /// Navigate to a specific percentage position (legacy method for conflict resolution)
  /// Uses chapter-based navigation which is more reliable
  void _navigateToPercentage(double percentage) {
    if (_chapters.isNotEmpty) {
      _navigateToPercentageUsingChapters(percentage, _chapters);
    } else {
      // Fallback: try fraction based navigation if chapters aren't loaded yet
      _epubController.goToFraction(percentage);
    }
  }

  /// Load saved progress and CFI from database
  Future<void> _loadSavedProgress() async {
    try {
      final dbService = LocalDatabaseService.instance;
      await dbService.initialize();

      // Try to find book ID from BookModel
      int? bookId = int.tryParse(widget.book.id);
      if (bookId == null) {
        // Look up book by file path
        final book = dbService.getBookByFilePath(
          widget.book.epubFilePath ?? '',
        );
        if (book != null && book.id != null) {
          bookId = book.id;
        }
      }

      if (bookId != null) {
        // Update last read timestamp when book is opened
        dbService.updateLastReadAt(bookId);

        final book = dbService.getBookById(bookId);
        if (book != null) {
          // Load progress percentage
          _savedProgress = book.progressPercentage;

          // Load CFI (primary) if available
          if (book.lastReadCfi != null && book.lastReadCfi!.isNotEmpty) {
            _savedCfi = book.lastReadCfi;
            print(
              '📖 Loaded CFI: ${_savedCfi!.substring(0, _savedCfi!.length > 50 ? 50 : _savedCfi!.length)}',
            );
          }

          // Load XPath if available (for KOReader sync support)
          if (book.lastReadXPath != null && book.lastReadXPath!.isNotEmpty) {
            _savedXPath = book.lastReadXPath;
            print('📖 Loaded XPath: $_savedXPath');
          }

          print(
            '📖 Loaded progress: CFI=${_savedCfi != null}, XPath=${_savedXPath != null}, Progress=${_savedProgress}',
          );
        } else {
          print('📖 No book found in database for bookId: $bookId');
        }

        // Mark progress as loaded and trigger rebuild
        if (mounted) {
          setState(() {
            _progressLoaded = true;
          });
        }

        // Refresh the books list to show updated last read time
        ref.read(booksRefreshProvider.notifier).state++;
      }

      // Mark progress as loaded even if no book was found
      if (mounted) {
        setState(() {
          _progressLoaded = true;
        });
      }
    } catch (e) {
      print('Error loading saved progress: $e');
      // Still mark as loaded even on error to prevent infinite loading
      if (mounted) {
        setState(() {
          _progressLoaded = true;
        });
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Only update theme from context if user hasn't manually set it
    if (_displaySettings != null && !_themeManuallySet) {
      final theme = Theme.of(context);
      final isDarkMode = theme.brightness == Brightness.dark;
      final currentDarkMode = ref.read(readingSettingsProvider).isDarkMode;
      if (isDarkMode != currentDarkMode) {
        ref.read(readingSettingsProvider.notifier).setDarkMode(isDarkMode);
        _updateTheme();
      }
    }
  }

  @override
  void dispose() {
    _isDisposing = true;
    _navigationDebounceTimer?.cancel();
    _touchUpTimer?.cancel();
    // Stop volume key service
    _volumeKeyService.stopListening();
    // Cleanup sync
    _cleanupSync();
    // Disable screen awake lock when leaving
    _disableScreenAwakeLock();
    // Restore system UI mode when leaving reader
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  /// Disable screen awake lock when leaving reader
  Future<void> _disableScreenAwakeLock() async {
    try {
      if (_screenAwakeLockEnabled) {
        await WakelockPlus.disable();
        _screenAwakeLockEnabled = false;
        print('Screen awake lock disabled');
      }
    } catch (e) {
      print('Error disabling screen awake lock: $e');
    }
  }

  bool _volumeKeyListenerSetup = false;
  bool _lastVolumeKeyEnabled = false;

  /// Set up volume key listener based on settings (called from initState)
  void _setupVolumeKeyListener() {
    if (!mounted || _volumeKeyListenerSetup) return;
    _volumeKeyListenerSetup = true;

    logger.debug(_tag, 'Setting up volume key listener (mounted: $mounted)');

    // Set up initial listener based on current state
    final volumeKeySetting = ref.read(volumeKeySettingProvider);
    logger.debug(
      _tag,
      'Initial volume key setting: ${volumeKeySetting.enabled}',
    );
    _lastVolumeKeyEnabled = volumeKeySetting.enabled;

    // Initialize volume key service with callbacks
    _volumeKeyService.initialize(
      enabled: volumeKeySetting.enabled,
      onVolumeUp: _nextPage,
      onVolumeDown: _previousPage,
    );
  }

  /// Update volume key listener based on enabled state
  void _updateVolumeKeyListener(bool enabled) {
    if (!mounted) return;

    // Only update if state actually changed
    if (_lastVolumeKeyEnabled == enabled) {
      return;
    }

    _lastVolumeKeyEnabled = enabled;
    logger.debug(_tag, 'Updating volume key listener: $enabled');

    // Update volume key service
    _volumeKeyService.setEnabled(enabled);
    _volumeKeyService.updateCallbacks(
      onVolumeUp: enabled ? _nextPage : null,
      onVolumeDown: enabled ? _previousPage : null,
    );
  }

  /// Cleanup sync for this book
  Future<void> _cleanupSync() async {
    try {
      final dbService = LocalDatabaseService.instance;
      await dbService.initialize();

      int? bookId = int.tryParse(widget.book.id);
      if (bookId == null) {
        final book = dbService.getBookByFilePath(
          widget.book.epubFilePath ?? '',
        );
        if (book != null && book.id != null) {
          bookId = book.id;
        }
      }

      if (bookId != null) {
        SyncManagerService.instance.cleanupSync(bookId);
        SyncManagerService.instance.flushProgress(bookId);
      }
    } catch (e) {
      print('Error cleaning up sync: $e');
    }
  }

  Future<void> _initializeEpub() async {
    try {
      // Resolve the file path (handles relative paths and iOS container ID changes)
      final epubFilePath = widget.book.epubFilePath ?? '';
      if (epubFilePath.isEmpty) {
        final errorMsg = 'EPUB file path not available for this book.';
        print(errorMsg);
        ref.read(epubStateProvider.notifier).setError(errorMsg);
        return;
      }

      final resolvedPath = await BookImportService.instance.resolvePath(
        epubFilePath,
      );
      final file = io.File(resolvedPath);

      if (!await file.exists()) {
        final errorMsg =
            'EPUB file not found.\n'
            'Path: $epubFilePath\n'
            'Resolved: $resolvedPath\n'
            'This can happen on iOS/iPad if the app was reinstalled or updated.\n'
            'Please re-import the book from your file sources.';
        print(errorMsg);
        ref.read(epubStateProvider.notifier).setError(errorMsg);
        return;
      }

      // Store resolved path for use in _buildReadingContent
      setState(() {
        _resolvedEpubPath = resolvedPath;
      });

      // Initialize display settings with pagination and theme colors
      final readingSettings = ref.read(readingSettingsProvider);
      final selectedTheme = AppThemes.getThemeByName(
        readingSettings.selectedThemeName,
      );
      final variant = selectedTheme.getVariant(readingSettings.isDarkMode);
      _displaySettings = EpubDisplaySettings(
        flow: EpubFlow.paginated, // Use pagination instead of scrolling
        snap: true, // Enable snap to pages
        fontSize: readingSettings.fontSize,
        backgroundColor: variant.readerBackgroundColor,
        textColor: variant.textColor,
      );

      ref.read(epubStateProvider.notifier).setLoading(false);
    } catch (e) {
      print('Error initializing EPUB: $e');
      ref.read(epubStateProvider.notifier).setError('Error loading EPUB: $e');
      ref.read(epubStateProvider.notifier).setLoading(false);
    }
  }

  void _updateTheme() {
    if (_isDisposing || !mounted) return;
    final readingSettings = ref.read(readingSettingsProvider);
    final selectedTheme = AppThemes.getThemeByName(
      readingSettings.selectedThemeName,
    );
    final variant = selectedTheme.getVariant(readingSettings.isDarkMode);
    if (!_isDisposing && mounted) {
      // Update display settings with new colors
      _displaySettings = EpubDisplaySettings(
        flow: _displaySettings?.flow ?? EpubFlow.paginated,
        snap: _displaySettings?.snap ?? true,
        fontSize: readingSettings.fontSize,
        backgroundColor: variant.readerBackgroundColor,
        textColor: variant.textColor,
        spread: _displaySettings?.spread ?? EpubSpread.auto,
        allowScriptedContent: _displaySettings?.allowScriptedContent ?? false,
        defaultDirection:
            _displaySettings?.defaultDirection ?? EpubDefaultDirection.ltr,
        manager: _displaySettings?.manager ?? EpubManager.continuous,
        useSnapAnimationAndroid:
            _displaySettings?.useSnapAnimationAndroid ?? false,
        theme: _displaySettings?.theme,
      );

      // Apply theme to webview
      _epubController.setTheme(
        backgroundColor: variant.readerBackgroundColor,
        textColor: variant.textColor,
        fontSize: readingSettings.fontSize.toDouble(),
      );
    }
  }

  void _toggleControls() {
    // If "Keep menus open" is enabled, don't allow toggling controls
    final readingSettings = ref.read(readingSettingsProvider);
    if (readingSettings.keepMenusOpen) {
      return;
    }
    ref.read(uiControlsProvider.notifier).toggleControls();
  }

  /// Deselect text in the EPUB reader
  void _deselectText() {
    // Clear selection in WebView and in our local state.
    _epubController.clearSelection();
    // Update state (will preserve popup data if popup is showing)
    ref.read(selectionStateProvider.notifier).clearSelection();
  }

  /// Get the current progress value for display (0.0 to 1.0)
  double _getProgressValue() {
    // Use current location progress if available and > 0
    if (_currentLocation != null && _currentLocation!.progress > 0.0) {
      return _currentLocation!.progress;
    }
    // Fallback to saved progress if current is 0 (workaround for issue #28)
    if (_savedProgress != null && _savedProgress! > 0.0) {
      return _savedProgress!;
    }
    return 0.0;
  }

  /// Build a thin progress bar at the bottom of the navigation bar
  Widget _buildProgressBar() {
    final progress = _getProgressValue();

    // Don't show progress bar if progress is 0
    if (progress <= 0.0) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      height: 3, // Couple pixels high
      width: double.infinity,
      child: ClipRRect(
        borderRadius: BorderRadius.zero,
        child: LinearProgressIndicator(
          value: progress,
          minHeight: 2,
          backgroundColor: Colors.transparent,
          valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Watch reactive state for UI updates
    final epubState = ref.watch(epubStateProvider);
    final selectionState = ref.watch(selectionStateProvider);
    final variant = ref.watch(themeVariantProvider);

    // Update theme when reading settings change (dark mode, selected theme, or font size)
    ref.listen<ReadingSettingsState>(readingSettingsProvider, (previous, next) {
      if (_isDisposing || !mounted) return;
      if (previous != null) {
        // Check if "Keep menus open" was just enabled - show controls if they're hidden
        final keepMenusOpenChanged =
            previous.keepMenusOpen != next.keepMenusOpen;
        if (keepMenusOpenChanged && next.keepMenusOpen) {
          // When "Keep menus open" is enabled, ensure controls are visible
          final uiControls = ref.read(uiControlsProvider);
          if (!uiControls.showControls) {
            ref.read(uiControlsProvider.notifier).showControls();
          }
        }

        // Check if theme/style settings changed
        final isDarkModeChanged = previous.isDarkMode != next.isDarkMode;
        final isThemeChanged =
            previous.selectedThemeName != next.selectedThemeName;
        final isFontSizeChanged = previous.fontSize != next.fontSize;

        if (isDarkModeChanged || isThemeChanged || isFontSizeChanged) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!_isDisposing && mounted) {
              final readingSettings = ref.read(readingSettingsProvider);
              final selectedTheme = AppThemes.getThemeByName(
                readingSettings.selectedThemeName,
              );
              final variant = selectedTheme.getVariant(
                readingSettings.isDarkMode,
              );

              // Always call setTheme to update the webview
              _epubController.setTheme(
                backgroundColor: variant.readerBackgroundColor,
                textColor: variant.textColor,
                fontSize: readingSettings.fontSize.toDouble(),
              );

              // For dark mode or theme name changes, also rebuild the Flutter UI
              if (isDarkModeChanged || isThemeChanged) {
                _updateTheme();
                setState(() {});
              }
            }
          });
        }
      } else {
        // Initial load - check if "Keep menus open" is enabled and show controls if needed
        if (next.keepMenusOpen) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!_isDisposing && mounted) {
              final uiControls = ref.read(uiControlsProvider);
              if (!uiControls.showControls) {
                ref.read(uiControlsProvider.notifier).showControls();
              }
            }
          });
        }
      }
    });

    // if (epubState.isLoading) {
    //   return Scaffold(
    //     backgroundColor: readingSettings.isDarkMode ? Colors.grey[900] : Colors.white,
    //     body: Center(
    //       child: Column(
    //         mainAxisAlignment: MainAxisAlignment.center,
    //         children: [
    //           const CircularProgressIndicator(),
    //           const SizedBox(height: 16),
    //           Text('Loading book...', style: TextStyle(color: Colors.grey[600])),
    //         ],
    //       ),
    //     ),
    //   );
    // }

    if (epubState.error != null) {
      final readingSettings = ref.watch(readingSettingsProvider);
      return Scaffold(
        backgroundColor: readingSettings.isDarkMode
            ? Colors.grey[900]
            : Colors.white,
        appBar: AppBar(
          leading: IconButton(
            icon: Icon(Icons.close, color: variant.secondaryTextColor),
            color: readingSettings.isDarkMode ? darkIconColor : lightIconColor,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text(epubState.error!, style: const TextStyle(fontSize: 16)),
            ],
          ),
        ),
      );
    }

    // Watch volume key setting to enable/disable listener
    final volumeKeySetting = ref.watch(volumeKeySettingProvider);

    // Set up listener on first build if not already set up
    if (!_volumeKeyListenerSetup && !_isDisposing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_isDisposing && mounted) {
          _setupVolumeKeyListener();
        }
      });
    }

    // React to volume key setting changes in build method
    // This ensures we catch changes when the setting is toggled
    if (_volumeKeyListenerSetup &&
        _lastVolumeKeyEnabled != volumeKeySetting.enabled &&
        !_isDisposing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_isDisposing && mounted) {
          _updateVolumeKeyListener(volumeKeySetting.enabled);
        }
      });
    }

    // Also use ref.listen in build method (this is allowed here)
    ref.listen<VolumeKeySettingState>(volumeKeySettingProvider, (
      previous,
      next,
    ) {
      if (_isDisposing || !mounted) return;
      _updateVolumeKeyListener(next.enabled);
    });

    // Listen to UI controls to hide/show status bar
    final uiControls = ref.watch(uiControlsProvider);
    // Set initial status bar state
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isDisposing && mounted) {
        if (uiControls.showControls) {
          SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
        } else {
          SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
        }
      }
    });
    ref.listen<UIControlsState>(uiControlsProvider, (previous, next) {
      if (_isDisposing || !mounted) return;
      // Hide status bar when controls are hidden, show when controls are visible
      if (next.showControls) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      } else {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      }
    });

    final readingSettings = ref.watch(readingSettingsProvider);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: readingSettings.isDarkMode
            ? Brightness.light
            : Brightness.dark,
        statusBarBrightness: readingSettings.isDarkMode
            ? Brightness.dark
            : Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: variant.readerBackgroundColor,
        resizeToAvoidBottomInset: false,
        body: SafeArea(
          top: false,
          bottom: false,
          child: Focus(
            autofocus: true,
            onKeyEvent: volumeKeySetting.enabled
                ? (node, event) {
                    // Try to handle volume keys via native key events as fallback
                    // Note: This might not work for volume keys on all platforms
                    return KeyEventResult.ignored;
                  }
                : null,
            child: Stack(
              children: [
                // Reading content with gesture detection (always full screen)
                // FoliateEpubViewer must be rendered for onInitialPositionLoaded to fire
                Positioned.fill(child: _buildReadingContentWithGesture()),
                // Dismiss overlay - tapping outside selection menu dismisses it
                if (selectionState.selectionRect != null)
                  _buildDismissOverlay(),
                // Selection overlay box
                if (selectionState.selectionRect != null &&
                    selectionState.viewRect != null)
                  _buildSelectionOverlay(),
                // Debug rect overlay (same Stack as selection overlay for consistent positioning)
                if (selectionState.selectionRect != null && showDebugRects)
                  _buildDebugRectOverlay(),
                // Annotation bar overlay (style + color picker)
                if (selectionState.showAnnotationBar &&
                    selectionState.selectionRect != null)
                  _buildAnnotationBar(),
                // Wiktionary bottom sheet overlay (non-modal, allows interaction with book)
                if (selectionState.wiktionaryWord != null)
                  _buildWiktionaryBottomSheetOverlay(),
                // Navigation tap zones (left and right)
                if (selectionState.selectionRect == null)
                  _buildNavigationZones(),
                // Touch position test square
                // if (_touchPosition != null)
                //   Builder(
                //     builder: (context) {
                //       // Convert percentage coordinates (relative to viewRect) to screen coordinates
                //       final screenWidth = MediaQuery.of(context).size.width;
                //       final screenHeight = MediaQuery.of(context).size.height;
                //       // Calculate viewRect dimensions (screen size minus padding)
                //       final viewRectWidth = screenWidth - _epubViewerPadding.left - _epubViewerPadding.right;
                //       final viewRectHeight = screenHeight - _epubViewerPadding.top - _epubViewerPadding.bottom;
                //       // x and y are percentages (0.0 to 1.0) relative to viewRect, convert to screen coordinates
                //       final screenX = _epubViewerPadding.left + (_touchPosition!.dx * viewRectWidth);
                //       final screenY = _epubViewerPadding.top + (_touchPosition!.dy * viewRectHeight);
                //       return Positioned(
                //         left: screenX - 4, // Center the 8px square
                //         top: screenY - 4,
                //         child: Container(
                //           width: 8,
                //           height: 8,
                //           decoration: BoxDecoration(
                //             color: Colors.red,
                //             border: Border.all(color: Colors.black, width: 1),
                //           ),
                //         ),
                //       );
                //     },
                //   ),
                // Loading overlay - show until initial position is loaded (if we have a saved position)
                // if ((_savedCfi != null || _savedXPath != null) && !_initialPositionLoaded)
                //   Positioned.fill(
                //     child: Container(
                //       color: readingSettings.isDarkMode ? Colors.grey[900] : Colors.white,
                //       child: Center(
                //         child: Column(
                //           mainAxisAlignment: MainAxisAlignment.center,
                //           children: [
                //             const CircularProgressIndicator(),
                //             const SizedBox(height: 16),
                //             Text('Loading book...', style: TextStyle(color: Colors.grey[600])),
                //           ],
                //         ),
                //       ),
                //     ),
                //   ),
                // Navigation bar with slide animation (overlaid)
                _buildAnimatedNavigationBar(),
                // Bottom toolbar with slide animation (overlaid)
                _buildAnimatedBottomToolbar(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAnimatedNavigationBar() {
    final uiControls = ref.watch(uiControlsProvider);
    final variant = ref.watch(themeVariantProvider);
    final barHeight = //iOS 120, Android 100
    Platform.isIOS
        ? 120
        : 100;
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeInOut,
      top: uiControls.showControls
          ? 0
          : -barHeight.toDouble(), // Slide off-screen when hidden
      left: 0,
      right: 0,
      height: barHeight.toDouble(),
      child: Container(
        decoration: BoxDecoration(
          color: variant.cardColor,
          border: Border(
            bottom: BorderSide(
              color: variant.isDark ? Colors.grey[700]! : Colors.grey[300]!,
            ),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.max,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
              child: Row(
                children: [
                  // Close button with indicator
                  IconButton(
                    icon: Icon(Icons.close, color: variant.secondaryTextColor),
                    color: variant.secondaryTextColor,
                    onPressed: () => Navigator.of(context).pop(),
                  ),

                  // Book title
                  // Expanded(
                  //   child:
                  //   Text(
                  //     widget.book.title,
                  //     textAlign: TextAlign.center,
                  //     style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: variant.secondaryTextColor),
                  //     maxLines: 1,
                  //     overflow: TextOverflow.ellipsis,
                  //   ),
                  // ),
                  Spacer(),
                  Row(
                    children: [
                      MenuAnchor(
                        controller: _syncMenuController,
                        builder: (context, controller, child) {
                          return IconButton(
                            icon: Icon(
                              Icons.more_vert,
                              color: variant.secondaryTextColor,
                            ),
                            onPressed: () {
                              controller.open();
                            },
                            tooltip: 'Sync Menu',
                          );
                        },
                        menuChildren: [
                          Consumer(
                            builder: (context, ref, child) {
                              final activeServerAsync = ref.watch(
                                activeSyncServerProvider,
                              );
                              final hasActiveServer =
                                  activeServerAsync.valueOrNull != null;

                              return Column(
                                children: [
                                  MenuItemButton(
                                    leadingIcon: Icon(Icons.settings),
                                    child: const Text('KOReader Sync Settings'),
                                    onPressed: () {
                                      _syncMenuController.close();
                                      _showSyncSettings();
                                    },
                                  ),
                                  MenuItemButton(
                                    leadingIcon: Icon(Icons.upload),
                                    child: const Text('Push Progress'),
                                    onPressed: hasActiveServer
                                        ? () {
                                            _syncMenuController.close();
                                            _manualPushProgress();
                                          }
                                        : null,
                                  ),
                                  MenuItemButton(
                                    leadingIcon: Icon(Icons.download),
                                    child: const Text('Pull Progress'),
                                    onPressed: hasActiveServer
                                        ? () {
                                            _syncMenuController.close();
                                            _manualPullProgress();
                                          }
                                        : null,
                                  ),
                                ],
                              );
                            },
                          ),
                        ],
                      ),
                      // IconButton(
                      //   icon: Icon(
                      //     uiControls.isBookmarked ? Icons.bookmark : Icons.bookmark_add_outlined,
                      //     color: uiControls.isBookmarked ? primaryColor : (variant.secondaryTextColor),
                      //   ),
                      //   color: uiControls.isBookmarked ? primaryColor : null,
                      //   onPressed: () {
                      //     ref.read(uiControlsProvider.notifier).toggleBookmark();
                      //   },
                      // ),
                    ],
                  ),
                ],
              ),
            ),
            // Progress bar directly under the navigation bar with no padding
            _buildProgressBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildAnimatedBottomToolbar() {
    final uiControls = ref.watch(uiControlsProvider);
    final variant = ref.watch(themeVariantProvider);

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: AnimatedSlide(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeInOut,
        offset: uiControls.showControls
            ? Offset.zero
            : const Offset(0, 1), // Slide down when hidden
        child: Container(
          height: 96,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(color: variant.cardColor),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconButton(
                icon: Icon(Icons.menu, color: variant.secondaryTextColor),
                onPressed: () {
                  _showTableOfContents();
                },
                tooltip: 'Table of Contents',
              ),
              IconButton(
                icon: Icon(
                  variant.isDark ? Icons.dark_mode : Icons.light_mode,
                  color: variant.secondaryTextColor,
                ),
                onPressed: () {
                  _showThemeSettings();
                },
                tooltip: 'Brightness',
              ),
              IconButton(
                icon: Text(
                  'Aa',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: variant.secondaryTextColor,
                  ),
                ),
                onPressed: () {
                  _showFontSettings();
                },
                tooltip: 'Font Settings',
              ),
              // Reader settings button
              IconButton(
                icon: Icon(Icons.tune, color: variant.secondaryTextColor),
                onPressed: () {
                  _showReaderSettings();
                },
                tooltip: 'Reader Settings',
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showTableOfContents() async {
    // Use chapters from state, which should be populated when foliate-js has loaded the book.
    List<EpubChapter> chapters = _chapters;

    if (chapters.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('No chapters available')));
      }
      return;
    }

    // Use book model passed to ReaderScreen
    final bookModel = widget.book;

    // Show modal bottom sheet with chapters
    if (!mounted) return;
    final readingSettings = ref.read(readingSettingsProvider);
    final variant = AppThemes.getThemeByName(
      readingSettings.selectedThemeName,
    ).getVariant(readingSettings.isDarkMode);

    showModalBottomSheet(
      context: context,
      backgroundColor: variant.backgroundColor,
      isScrollControlled: true,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.9,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Book info section at the top
              Row(
                children: [
                  // Book cover
                  Container(
                    width: 60,
                    height: 100,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.15),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child:
                        bookModel.coverImageUrl != null &&
                            io.File(bookModel.coverImageUrl!).existsSync()
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.file(
                              io.File(bookModel.coverImageUrl!),
                              width: double.infinity,
                              height: double.infinity,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return Center(
                                  child: Icon(
                                    Icons.book,
                                    size: 40,
                                    color: Colors.grey[600],
                                  ),
                                );
                              },
                            ),
                          )
                        : Center(
                            child: Icon(
                              Icons.book,
                              size: 40,
                              color: Colors.grey[600],
                            ),
                          ),
                  ),
                  const SizedBox(width: 16),
                  // Book title and author
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          bookModel.title,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: variant.secondaryTextColor,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'By ${bookModel.author}',
                          style: TextStyle(
                            fontSize: 14,
                            color: variant.secondaryTextColor.withValues(
                              alpha: 0.7,
                            ),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  // Info button
                  IconButton(
                    icon: Icon(
                      Icons.info_outline,
                      color: variant.secondaryTextColor,
                    ),
                    onPressed: () {
                      Navigator.of(context).pop(); // Close TOC sheet
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) =>
                              BookDetailScreen(book: bookModel),
                        ),
                      );
                    },
                    tooltip: 'Book Info',
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // Table of Contents header
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Table of Contents',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: variant.secondaryTextColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Chapters list
              Expanded(
                child: ListView.builder(
                  itemCount: chapters.length,
                  itemBuilder: (context, index) {
                    return _buildChapterItem(chapters[index], 0);
                  },
                ),
              ),
              // Notes button docked at the bottom
              Container(
                padding: const EdgeInsets.only(top: 16),
                decoration: BoxDecoration(
                  color: variant.backgroundColor,
                  border: Border(
                    top: BorderSide(
                      color: variant.secondaryTextColor.withValues(alpha: 0.1),
                      width: 1,
                    ),
                  ),
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop(); // Close TOC sheet
                      _showNotesList();
                    },
                    icon: Icon(
                      Icons.edit_document,
                      color: variant.isDark ? Colors.white : Colors.white,
                    ),
                    label: const Text(
                      'Notes',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: variant.isDark
                          ? variant.cardColor
                          : variant.primaryColor,
                      foregroundColor: variant.isDark
                          ? variant.textColor
                          : Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildChapterItem(EpubChapter chapter, int indent) {
    final readingSettings = ref.watch(readingSettingsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () {
            Navigator.of(context).pop(); // Close the modal
            // Navigate to chapter using href
            _epubController.goToLocation({'href': chapter.href});
          },
          child: SizedBox(
            width: double.infinity,
            child: Padding(
              padding: EdgeInsets.only(
                left: indent * 16.0,
                top: 8,
                bottom: 8,
                right: 8,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      chapter.title,
                      style: TextStyle(
                        color: readingSettings.isDarkMode
                            ? Colors.white
                            : Colors.black,
                        fontSize: 14,
                        height: 1.2,
                      ),
                    ),
                  ),
                  // Show page number if location is available
                  if (chapter.location != null &&
                      chapter.location!['current'] != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Text(
                        '${(chapter.location!['current'] ?? 0) + 1}', // Display is 1-indexed
                        style: TextStyle(
                          color:
                              (readingSettings.isDarkMode
                                      ? Colors.white
                                      : Colors.black)
                                  .withOpacity(0.5),
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        // Render subchapters recursively
        ...chapter.subitems.map(
          (subchapter) => _buildChapterItem(subchapter, indent + 1),
        ),
      ],
    );
  }

  Widget _buildReadingContentWithGesture() {
    return Stack(
      children: [
        // WebView first (bottom layer)
        _buildReadingContent(),
      ],
    );
  }

  Widget _buildReadingContent() {
    // Only sync theme from context if user hasn't manually set it
    if (!_themeManuallySet && !_isDisposing) {
      final theme = Theme.of(context);
      final isDarkMode = theme.brightness == Brightness.dark;
      final currentDarkMode = ref.read(readingSettingsProvider).isDarkMode;
      if (isDarkMode != currentDarkMode) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_isDisposing && mounted) {
            ref.read(readingSettingsProvider.notifier).setDarkMode(isDarkMode);
            _updateTheme();
          }
        });
      }
    }

    // Use resolved path if available, otherwise fall back to original path
    final epubPath = _resolvedEpubPath ?? widget.book.epubFilePath ?? '';
    _cachedEpubPath = epubPath;

    // Check if there's a conflict that requires user prompt - if so, don't set initial position
    // We'll navigate after conflict resolution instead
    final syncManager = SyncManagerService.instance;
    final syncStrategyState = ref.read(syncStrategyProvider);
    final syncStrategy = syncStrategyState.strategy;
    int? bookId = int.tryParse(widget.book.id);
    if (bookId == null) {
      final dbService = LocalDatabaseService.instance;
      final book = dbService.getBookByFilePath(widget.book.epubFilePath ?? '');
      if (book != null && book.id != null) {
        bookId = book.id;
      }
    }

    // Always navigate to local progress first, then show conflict dialog if needed
    // This ensures the book is fully loaded before we try to navigate to remote
    final hasValidCfi =
        _savedCfi != null &&
        _savedCfi!.isNotEmpty &&
        _savedCfi!.startsWith('epubcfi');
    // Use CFI if we have a valid CFI and either:
    // 1. Progress matches remote (confirmed by sync), OR
    // 2. We haven't checked remote yet (_progressMatchesRemote is null) - default to trusting local CFI
    // Only use XPath if we explicitly know progress doesn't match (_progressMatchesRemote == false) OR we don't have CFI
    final useCfi = hasValidCfi && (_progressMatchesRemote != false);

    // Build initial location map for resuming from saved position (always use local)
    Map<String, dynamic>? initialLocation;
    if (useCfi && _savedCfi != null && _savedCfi!.isNotEmpty) {
      initialLocation = {'cfi': _savedCfi};
      final cfiPreview = _savedCfi!.length > 50
          ? '${_savedCfi!.substring(0, 50)}...'
          : _savedCfi!;
      print('📍 Resuming from local CFI: $cfiPreview');
    } else if (_savedXPath != null && _savedXPath!.isNotEmpty) {
      initialLocation = {'cfi': _savedXPath};
      print('📍 Resuming from local XPath: $_savedXPath');
    } else {
      print(
        '📍 No saved position: CFI=${_savedCfi != null}, XPath=${_savedXPath != null}, useCfi=$useCfi',
      );
    }

    final readingSettings = ref.watch(readingSettingsProvider);
    return Padding(
      padding: _getEpubViewerPadding(readingSettings.keepMenusOpen),
      child: Builder(
        builder: (context) {
          // Get current theme values to pass to webview
          final readingSettings = ref.read(readingSettingsProvider);
          final selectedTheme = AppThemes.getThemeByName(
            readingSettings.selectedThemeName,
          );
          final variant = selectedTheme.getVariant(readingSettings.isDarkMode);

          // Wait for progress to load before building FoliateWebView
          // This ensures initialLocation is set correctly
          if (!_progressLoaded) {
            return const Center(child: CircularProgressIndicator());
          }

          return Stack(
            children: [
              Column(
                children: [
                  Expanded(
                    child: FoliateWebView(
                      key: _epubViewerKey,
                      controller: _epubController,
                      epubFilePath:
                          _resolvedEpubPath ?? widget.book.epubFilePath ?? '',
                      suppressNativeContextMenu: true,
                      initialLocation: initialLocation,
                      backgroundColor: variant.readerBackgroundColor,
                      textColor: variant.textColor,
                      fontSize: readingSettings.fontSize.toDouble(),
                      enableAnimations: true,
                      onTouchEvent: (touchData) => _handleTouchEvent(touchData),

                      onBookLoaded: () {
                        logger.verbose(
                          _tag,
                          'Foliate bridge: onBookLoaded event received',
                        );
                        _handleEpubLoaded();
                      },
                      onRelocated: (location) {
                        // location is a Map from foliate-js (see view.js #onRelocate)
                        logger.verbose(
                          _tag,
                          'Foliate bridge: onRelocated event received - progress: ${location['fraction'] ?? location['progress']}, CFI: ${location['cfi']?.toString().substring(0, (location['cfi']?.toString().length ?? 0).clamp(0, 50))}...',
                        );
                        _handleRelocatedFromFoliate(location);
                      },
                      onAnnotationEvent: (detail) {
                        _handleAnnotationEventFromFoliate(detail);
                      },
                      onSectionLoaded: (detail) {
                        // When a section loads, add annotations for that section
                        // This ensures annotations are added when the overlay infrastructure is ready
                        logger.verbose(
                          _tag,
                          'Foliate bridge: onSectionLoaded event received - section index: ${detail['index']}',
                        );
                        _handleSectionLoaded(detail);
                      },
                      onTocReceived: (toc) {
                        // Convert TOC from foliate (uses 'label') to EpubChapter (uses 'title')
                        logger.verbose(
                          _tag,
                          'Foliate bridge: onTocReceived event received - ${toc.length} TOC items',
                        );
                        _handleTocReceived(toc);
                      },
                      onSelection: (detail) {
                        logger.verbose(
                          _tag,
                          'Foliate bridge: onSelection event received - text length: ${detail['text']?.toString().length ?? 0}, CFI: ${detail['cfi']?.toString().substring(0, (detail['cfi']?.toString().length ?? 0).clamp(0, 50))}...',
                        );
                        try {
                          final text = detail['text']?.toString() ?? '';
                          final cfi = detail['cfi']?.toString() ?? '';
                          final chapterIndex = detail['chapterIndex'] as int?;
                          if (text.isEmpty || cfi.isEmpty) return;
                          Rect selectionRect = Rect.zero;
                          Rect viewRect = Rect.zero;

                          try {
                            final rectData = detail['rect'];
                            final containerRectData =
                                detail['containerRect']
                                    as Map<String, dynamic>?;
                            // Get the FoliateWebView's render box to get WebView size
                            final renderBox =
                                _epubViewerKey.currentContext
                                        ?.findRenderObject()
                                    as RenderBox?;
                            if (rectData is Map && renderBox != null) {
                              final webViewSize = renderBox.size;
                              // Get WebView's global position for coordinate conversion
                              final webViewPosition = renderBox.localToGlobal(
                                Offset.zero,
                              );

                              // Rect is now raw pixel coordinates from foliate-bridge.js (viewport-relative)
                              // getClientRects() returns coordinates relative to the viewport
                              // The WebView position converts viewport coordinates to screen coordinates
                              final jsLeft =
                                  (rectData['left'] as num?)?.toDouble() ?? 0.0;
                              final jsTop =
                                  (rectData['top'] as num?)?.toDouble() ?? 0.0;
                              final width =
                                  (rectData['width'] as num?)?.toDouble() ??
                                  0.0;
                              final height =
                                  (rectData['height'] as num?)?.toDouble() ??
                                  0.0;

                              // Get container rect from JavaScript for debugging (viewport-relative)
                              final containerLeft =
                                  (containerRectData?['left'] as num?)
                                      ?.toDouble() ??
                                  0.0;
                              final containerTop =
                                  (containerRectData?['top'] as num?)
                                      ?.toDouble() ??
                                  0.0;

                              // Rect is viewport-relative from JavaScript, convert to screen coordinates
                              final left = jsLeft + webViewPosition.dx;
                              final top =
                                  jsTop +
                                  webViewPosition
                                      .dy; // Additional 22px offset for top

                              print(
                                'Selection: JS=($jsLeft, $jsTop), Container=($containerLeft, $containerTop), WebView=(${webViewPosition.dx}, ${webViewPosition.dy}), Final=($left, $top)',
                              );

                              // Coordinates are now in screen space (matching the full-screen Stack)
                              selectionRect = Rect.fromLTWH(
                                left,
                                top,
                                width,
                                height,
                              );

                              // ViewRect is the WebView's content size
                              viewRect = Rect.fromLTWH(
                                0,
                                0,
                                webViewSize.width,
                                webViewSize.height,
                              );
                            }
                          } catch (e) {
                            print(
                              'Error computing selection rect from foliate: $e',
                            );
                          }
                          _handleSelection(
                            text,
                            cfi,
                            selectionRect,
                            viewRect,
                            chapterIndex,
                          );
                        } catch (e) {
                          print('Error handling selection from foliate: $e');
                        }
                      },
                    ),
                  ),
                  // Page number display showing current page and total pages
                  _buildPageNumberDisplay(variant),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  /// Build page number display widget showing current page and total pages
  Widget _buildPageNumberDisplay(ThemeVariant variant) {
    // Use pageinfo for regular books, section for fixed layout
    final pageInfo = _currentPageInfo ?? _currentSectionInfo;

    if (pageInfo == null ||
        pageInfo['total'] == null ||
        pageInfo['total'] == 0) {
      return const SizedBox.shrink();
    }

    final current = (pageInfo['current'] ?? 0) + 1; // Display is 1-indexed
    final total = pageInfo['total'] ?? 0;
    final pageText = '$current / $total';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      alignment: Alignment.centerRight,
      child: Text(
        pageText,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w300,
          color: variant.secondaryTextColor.withOpacity(0.7),
        ),
      ),
    );
  }

  /// Handle relocate events coming from foliate-js.
  /// The detail map corresponds to View.#onRelocate in foliate-js/view.js.
  void _handleRelocatedFromFoliate(Map<String, dynamic> detail) {
    try {
      final progress =
          (detail['fraction'] as num?)?.toDouble() ??
          (detail['progress'] as num?)?.toDouble() ??
          0.0;
      final cfi = detail['cfi']?.toString() ?? '';
      logger.verbose(
        _tag,
        'Handling relocated event - progress: $progress, CFI: ${cfi.substring(0, cfi.length.clamp(0, 50))}..., XPath: ${detail['startXpath'] ?? detail['xpointer'] ?? 'none'}',
      );
      // XPath can come from:
      // 1. startXpath (converted from CFI in JavaScript bridge)
      // 2. xpointer (converted from CFI in JavaScript bridge)
      // 3. range (original Range object, converted to string - legacy)
      final startXpath =
          detail['startXpath']?.toString() ??
          detail['xpointer']?.toString() ??
          detail['range']?.toString();

      // Extract pageinfo and section from relocate event for page number tracking
      // The relocate event detail structure (from view.js #onRelocate):
      // - progress object from SectionProgress.getProgress() contains:
      //   - location: {current, next, total} - THIS IS THE PAGE NUMBERS for the entire book
      //   - section: {current, total} - section/chapter numbers
      // - The progress object is spread into lastLocation, so:
      //   - detail.location = page numbers (from progress.location)
      //   - detail.section = section numbers (from progress.section)
      //   - detail.pageItem = TOC item reference (NOT page numbers!)
      final pageInfo = detail['location'] as Map<String, dynamic>?;
      final sectionInfo = detail['section'] as Map<String, dynamic>?;

      // Update page info state (location contains page numbers for the entire book)
      if (pageInfo != null) {
        final current = (pageInfo['current'] as num?)?.toInt();
        final total = (pageInfo['total'] as num?)?.toInt();
        if (current != null && total != null && total > 0) {
          setState(() {
            _currentPageInfo = {'current': current, 'total': total};
          });
        }
      }

      // Update section info state (for fixed layout books or section tracking)
      if (sectionInfo != null) {
        final current = (sectionInfo['current'] as num?)?.toInt();
        final total = (sectionInfo['total'] as num?)?.toInt();
        if (current != null && total != null && total > 0) {
          setState(() {
            _currentSectionInfo = {'current': current, 'total': total};
          });
        }
      }

      final location = EpubLocation(
        startCfi: cfi,
        endCfi: cfi,
        startXpath: startXpath,
        endXpath: startXpath,
        progress: progress,
      );

      _handleRelocated(location);
    } catch (e, stackTrace) {
      if (mounted) {
        logger.error(
          _tag,
          'Error handling foliate relocate detail',
          e,
          stackTrace,
        );
      }
    }
  }

  /// Handle annotation events from foliate-js (e.g., when a highlight is tapped).
  void _handleAnnotationEventFromFoliate(Map<String, dynamic> detail) {
    logger.debug(
      _tag,
      '_handleAnnotationEventFromFoliate called with detail keys: ${detail.keys}',
    );
    logger.debug(_tag, 'detail: $detail');
    try {
      final value = detail['value']?.toString();
      logger.debug(_tag, 'extracted value: $value');
      if (value == null || value.isEmpty) {
        logger.warning(_tag, 'Annotation event: value is null or empty');
        return;
      }

      logger.debug(
        _tag,
        'Annotation event received for CFI: ${value.substring(0, value.length.clamp(0, 50))}...',
      );
      logger.debug(
        _tag,
        'Current highlights count: ${_currentHighlights?.length ?? 0}, notes count: ${_currentNotes.length}',
      );

      // Check for both highlight and note - annotations can be either
      final highlight = _getHighlightForCfi(value);
      final note = _getNoteForCfi(value);
      if (note != null) {
        logger.debug(_tag, 'Found note for CFI');
      } else {
        logger.debug(_tag, 'No note found for CFI');
      }

      if (highlight != null) {
        logger.debug(_tag, 'Found highlight for CFI');
      } else {
        logger.debug(_tag, 'No highlight found for CFI');
      }

      if (highlight != null || note != null) {
        logger.debug(
          _tag,
          'Processing annotation click (highlight: ${highlight != null}, note: ${note != null})',
        );
        // Set the flag early to prevent _handleTouchUp from clearing the selection
        // This must be done synchronously before any async operations
        setState(() {
          _annotationClicked = true;
        });

        final rect = detail['rect'] as Map<String, dynamic>?;
        final containerRect = detail['containerRect'] as Map<String, dynamic>?;
        logger.debug(_tag, 'Rect: $rect, ContainerRect: $containerRect');
        _handleAnnotationClicked(value, rect, containerRect);
      } else {
        logger.warning(
          _tag,
          'No highlight or note found - skipping annotation click handling',
        );
      }
    } catch (e, stackTrace) {
      if (mounted) {
        logger.error(
          _tag,
          'Error handling foliate annotation event',
          e,
          stackTrace,
        );
      }
    }
  }

  // Stable callback references to prevent widget recreation
  void _handleOnInitialPositionLoaded() {
    if (mounted) {
      // Defer state updates to next frame to prevent WebView disposal
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _initialPositionLoaded = true;
            _initialLoadComplete = true;
          });
          // Now that initial position is loaded, set any pending chapters
          if (_pendingChapters != null) {
            ref.read(epubStateProvider.notifier).setChapters(_pendingChapters!);
            _pendingChapters = null;
          }

          // Check for sync conflict after initial navigation completes
          // This ensures the book is fully loaded before showing conflict dialog
          Future.delayed(const Duration(milliseconds: 500), () async {
            if (!mounted) return;
            final dbService = LocalDatabaseService.instance;
            await dbService.initialize();
            int? bookId = int.tryParse(widget.book.id);
            if (bookId == null && mounted) {
              final book = dbService.getBookByFilePath(
                widget.book.epubFilePath ?? '',
              );
              if (book != null && book.id != null) {
                bookId = book.id;
              }
            }
            if (bookId != null && mounted) {
              _checkSyncConflict(bookId);
            }
          });

          // Restore highlights after initial position is loaded and JavaScript is ready
          // Add a small delay to ensure JavaScript functions are fully available
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) {
              _restoreHighlights();
              _loadNotes();
            }
          });
        }
      });
    }
  }

  void _handleEpubLoaded() {
    logger.info(_tag, 'EPUB loaded successfully');
    if (mounted) {
      // Set initial theme after EPUB loads
      // Add a delay to ensure renderer is fully initialized
      // Try multiple times to ensure theme is applied
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) {
          _updateTheme();
        }
      });
      // Also try again after a longer delay as fallback
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted) {
          _updateTheme();
        }
      });

      // If there's no saved position (CFI or XPath), mark initial position and load as complete (nothing to wait for)
      // Defer setState to prevent WebView disposal
      if (_savedCfi == null && _savedXPath == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {
              _initialPositionLoaded = true;
              _initialLoadComplete = true; // Enable progress saving immediately
            });
          }
        });
      }
      // Navigation will happen in onLocationLoaded when locations are ready

      // Don't restore highlights here - wait for onLocationLoaded to ensure JavaScript is ready
      // Highlights will be restored in _handleOnInitialPositionLoaded() after JavaScript is fully initialized
    }
  }

  /// Restore saved highlights for this book
  /// Stores highlights and adds them when sections load to ensure overlay infrastructure is ready
  Future<void> _restoreHighlights() async {
    if (!mounted) return; // Don't restore if widget is disposed

    try {
      final highlights = await _highlightsService.loadHighlights(
        int.tryParse(widget.book.id)?.toString(),
        widget.book.epubFilePath ?? '',
      );

      if (!mounted) return; // Check again after async operation

      // Cache highlights for quick lookup
      _currentHighlights = {for (var h in highlights) h.cfi: h};

      // Store highlights to be added when sections load
      // This ensures annotations are added when the overlay infrastructure is ready
      _pendingHighlights = highlights;

      if (mounted) {
        print('Loaded ${highlights.length} highlights');

        // If any sections have already loaded, add annotations for them now
        if (_loadedSectionIndices.isNotEmpty) {
          print(
            'Found ${_loadedSectionIndices.length} already-loaded sections, adding annotations...',
          );
          for (final sectionIndex in _loadedSectionIndices) {
            _addAnnotationsForSection(sectionIndex);
          }
        } else {
          print(
            'No sections loaded yet, will add annotations when sections load',
          );
        }
      }
    } catch (e) {
      if (mounted) {
        print('Error loading highlights: $e');
      }
    }
  }

  /// Load notes for this book (now part of unified highlights)
  Future<void> _loadNotes() async {
    if (!mounted) return;
    try {
      // Notes are now part of highlights, so just refresh highlights cache
      await _updateHighlightsCache();
      if (mounted) {
        final notes = _currentNotes;
        print('Loaded ${notes.length} notes (from unified highlights)');
      }
    } catch (e) {
      print('Error loading notes: $e');
    }
  }

  /// Show note dialog for adding or editing a note
  void _showNoteDialog({
    String? noteId,
    required String cfi,
    required String selectedText,
  }) async {
    final readingSettings = ref.read(readingSettingsProvider);
    final isDarkMode = readingSettings.isDarkMode;
    HighlightModel? existingNote;
    if (noteId != null) {
      try {
        existingNote = _currentNotes.firstWhere((n) => n.id == noteId);
      } catch (e) {
        existingNote = null;
      }
    }

    final textController = TextEditingController(
      text: existingNote?.note ?? '',
    );

    if (!mounted) return;

    await showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 500),
          decoration: BoxDecoration(
            color: isDarkMode ? Colors.grey[850] : Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Title bar
              Container(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                decoration: BoxDecoration(),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        existingNote != null ? 'Edit Note' : 'Add Note',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: isDarkMode ? Colors.white : Colors.black,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.close,
                        color: isDarkMode ? Colors.white70 : Colors.black54,
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),
              // Content
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (selectedText.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.all(12),
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: isDarkMode
                                ? Colors.grey[800]
                                : Colors.grey[200],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            selectedText,
                            style: TextStyle(
                              color: isDarkMode
                                  ? Colors.white70
                                  : Colors.black87,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                      TextField(
                        controller: textController,
                        autofocus: true,
                        maxLines: 3,
                        style: TextStyle(
                          color: isDarkMode ? Colors.white : Colors.black,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Enter your note...',
                          hintStyle: TextStyle(
                            color: isDarkMode ? Colors.white54 : Colors.black54,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          filled: true,
                          fillColor: isDarkMode
                              ? Colors.grey[800]
                              : Colors.grey[100],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Actions
              Container(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(
                        'Cancel',
                        style: TextStyle(
                          color: isDarkMode ? Colors.white70 : Colors.black87,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () async {
                        final text = textController.text.trim();
                        if (text.isEmpty) {
                          Navigator.of(context).pop();
                          return;
                        }

                        if (existingNote != null) {
                          // Update existing note (update highlight with new note text)
                          final updatedHighlight = existingNote.copyWith(
                            note: text,
                            updatedAt: DateTime.now(),
                          );
                          await _highlightsService.updateAnnotation(
                            int.tryParse(widget.book.id)?.toString(),
                            widget.book.epubFilePath ?? '',
                            updatedHighlight,
                          );
                          // Update cache
                          await _updateHighlightsCache();
                        } else {
                          // Create new note as a highlight with note text filled
                          const yellowColor = Color(0xFFFFEB3B);
                          const opacity = 0.4;
                          final noteId =
                              '${DateTime.now().millisecondsSinceEpoch}_${_random.nextInt(1000000)}';
                          final now = DateTime.now();

                          // Check if highlight already exists at this CFI
                          final existingHighlight = _getHighlightForCfi(cfi);
                          if (existingHighlight != null &&
                              existingHighlight.isHighlight) {
                            // Convert existing highlight to note by adding note text
                            final updatedHighlight = existingHighlight.copyWith(
                              id: noteId, // Use new note ID
                              note: text,
                              updatedAt: now,
                            );
                            await _highlightsService.updateAnnotation(
                              int.tryParse(widget.book.id)?.toString(),
                              widget.book.epubFilePath ?? '',
                              updatedHighlight,
                            );
                          } else {
                            // Create new highlight with note text (unified model)
                            final newHighlight = HighlightModel(
                              id: noteId,
                              cfi: cfi,
                              colorHex: '#FFEB3B', // Yellow
                              opacity: opacity,
                              createdAt: now,
                              updatedAt: now,
                              note: text, // Fill note text to mark as note
                              selectedText: selectedText,
                              type: 'highlight',
                            );

                            // Add visual annotation
                            await _epubController.addAnnotation(
                              value: cfi,
                              type: 'highlight',
                              color: yellowColor,
                              note: selectedText,
                            );

                            // Save to unified storage
                            await _highlightsService.addHighlight(
                              int.tryParse(widget.book.id)?.toString(),
                              widget.book.epubFilePath ?? '',
                              newHighlight,
                            );
                          }

                          // Update cache immediately so annotation clicks work
                          await _updateHighlightsCache();
                        }

                        await _loadNotes();
                        if (mounted) {
                          Navigator.of(context).pop();
                        }
                      },
                      style: TextButton.styleFrom(
                        backgroundColor: isDarkMode
                            ? Colors.blue[700]
                            : Colors.blue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                      ),
                      child: const Text('Save'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Show notes list bottom sheet
  void _showNotesList() {
    final readingSettings = ref.read(readingSettingsProvider);
    final isDarkMode = readingSettings.isDarkMode;

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: isDarkMode ? Colors.grey[850] : Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) => Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: isDarkMode ? Colors.grey[700]! : Colors.grey[300]!,
                      width: 1,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Text(
                      'Notes',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: isDarkMode ? Colors.white : Colors.black,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                      color: isDarkMode ? Colors.white : Colors.black,
                    ),
                  ],
                ),
              ),
              // Notes list
              Expanded(
                child: _currentNotes.isEmpty
                    ? Center(
                        child: Text(
                          'No notes yet',
                          style: TextStyle(
                            color: isDarkMode ? Colors.white70 : Colors.black54,
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: scrollController,
                        padding: const EdgeInsets.all(16),
                        itemCount: _currentNotes.length,
                        itemBuilder: (context, index) {
                          final note = _currentNotes[index];
                          return _buildNoteItem(
                            note,
                            isDarkMode,
                            setModalState,
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Build a note item widget
  Widget _buildNoteItem(
    HighlightModel note,
    bool isDarkMode,
    StateSetter setModalState,
  ) {
    return Card(
      color: isDarkMode ? Colors.grey[800] : Colors.grey[100],
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () {
          // Navigate to note location
          Navigator.of(context).pop(); // Close notes list
          _navigateToNote(note.cfi);
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (note.selectedText != null && note.selectedText!.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(8),
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: isDarkMode ? Colors.grey[700] : Colors.grey[200],
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    note.selectedText!,
                    style: TextStyle(
                      color: isDarkMode ? Colors.white70 : Colors.black87,
                      fontStyle: FontStyle.italic,
                      fontSize: 14,
                    ),
                  ),
                ),
              Text(
                note.note,
                style: TextStyle(
                  color: isDarkMode ? Colors.white : Colors.black,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _formatDate(note.updatedAt),
                    style: TextStyle(
                      color: isDarkMode ? Colors.white54 : Colors.black54,
                      fontSize: 12,
                    ),
                  ),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit, size: 20),
                        onPressed: () {
                          Navigator.of(context).pop(); // Close notes list
                          _showNoteDialog(
                            noteId: note.id,
                            cfi: note.cfi,
                            selectedText: note.selectedText ?? '',
                          );
                        },
                        color: isDarkMode ? Colors.white70 : Colors.black54,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.delete, size: 20),
                        onPressed: () async {
                          // Remove the visual annotation
                          _epubController.removeAnnotation(note.cfi);
                          // Remove from unified storage (note is stored as highlight with note text)
                          await _highlightsService.removeNote(
                            int.tryParse(widget.book.id)?.toString(),
                            widget.book.epubFilePath ?? '',
                            note.id,
                          );
                          await _loadNotes();
                          if (mounted) {
                            setState(() {}); // Refresh main state
                            setModalState(() {}); // Refresh modal state
                          }
                        },
                        color: Colors.red[300],
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Format date for display
  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      if (difference.inHours == 0) {
        if (difference.inMinutes == 0) {
          return 'Just now';
        }
        return '${difference.inMinutes}m ago';
      }
      return '${difference.inHours}h ago';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return '${date.month}/${date.day}/${date.year}';
    }
  }

  /// Navigate to a note's location
  Future<void> _navigateToNote(String cfi) async {
    try {
      // Set flag to track that we're navigating to a note
      // This prevents other relocations from interfering
      _pendingNoteNavigationCfi = cfi;

      // Clear the flag after a delay to allow navigation to complete
      _noteNavigationTimer?.cancel();
      _noteNavigationTimer = Timer(const Duration(milliseconds: 2000), () {
        _pendingNoteNavigationCfi = null;
      });

      // Navigation happens asynchronously - we'll be notified via the 'relocated' event
      _epubController.goToLocation({'cfi': cfi});
      print(
        'Navigated to note at CFI: ${cfi.substring(0, cfi.length.clamp(0, 50))}...',
      );
    } catch (e) {
      print('Error navigating to note: $e');
      _pendingNoteNavigationCfi = null;
    }
  }

  /// Handle TOC received from foliate-js - convert and store chapters
  void _handleTocReceived(List<Map<String, dynamic>> toc) {
    if (!mounted) return;

    logger.verbose(_tag, '_handleTocReceived called with ${toc.length} items');

    try {
      // Convert foliate TOC format to EpubChapter format
      // Foliate uses: { label, href, subitems }
      // EpubChapter uses: { title, href, id, subitems }
      final chapters = toc
          .map((item) => _convertTocItemToChapter(item))
          .toList();

      if (mounted) {
        logger.info(_tag, 'Setting ${chapters.length} chapters in provider');
        ref.read(epubStateProvider.notifier).setChapters(chapters);
        logger.info(_tag, 'Loaded ${chapters.length} chapters from TOC');
      }
    } catch (e, st) {
      if (mounted) {
        logger.error(_tag, 'Error processing TOC', e, st);
      }
    }
  }

  /// Recursively convert foliate TOC item to EpubChapter
  EpubChapter _convertTocItemToChapter(Map<String, dynamic> item) {
    // Extract location if available (for page numbers in TOC)
    Map<String, int>? location;
    if (item['location'] != null) {
      final loc = item['location'] as Map<String, dynamic>;
      final current = (loc['current'] as num?)?.toInt();
      final next = (loc['next'] as num?)?.toInt();
      final total = (loc['total'] as num?)?.toInt();
      if (current != null && total != null) {
        location = {
          'current': current,
          'next': next ?? current + 1,
          'total': total,
        };
      }
    }

    return EpubChapter(
      title: item['label']?.toString() ?? '',
      href: item['href']?.toString() ?? '',
      id:
          item['href']?.toString() ??
          '', // Use href as id since foliate doesn't provide one
      subitems: (item['subitems'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>()
          .map((subitem) => _convertTocItemToChapter(subitem))
          .toList(),
      location: location,
    );
  }

  /// Handle section loaded event - add annotations for this section
  /// IMPORTANT: The JavaScript side (flutter-bridge.js) now handles annotation restoration
  /// when the 'create-overlay' event fires, ensuring the overlayer is fully ready.
  /// We just need to ensure pending highlights are set up before the first section loads.
  void _handleSectionLoaded(Map<String, dynamic> detail) {
    if (_isDisposing || !mounted) return;

    try {
      final sectionIndex = (detail['index'] as int?) ?? -1;
      if (sectionIndex < 0) return;

      // Track this section as loaded
      _loadedSectionIndices.add(sectionIndex);

      // If highlights are already loaded, add annotations for this section
      if (_pendingHighlights != null && _pendingHighlights!.isNotEmpty) {
        _addAnnotationsForSection(sectionIndex);
      } else {
        logger.verbose(
          _tag,
          'Section $sectionIndex loaded, but highlights not yet restored. Will add when highlights load.',
        );
      }
    } catch (e) {
      if (mounted) {
        print('Error handling section loaded: $e');
      }
    }
  }

  /// Add annotations for a specific section
  void _addAnnotationsForSection(int sectionIndex) {
    if (_isDisposing || !mounted || _pendingHighlights == null) return;

    // Add annotations with a small delay to ensure document is fully ready
    // foliate-js will store them and add them when 'create-overlay' fires for this section
    Future.delayed(const Duration(milliseconds: 50), () async {
      if (_isDisposing || !mounted || _pendingHighlights == null) return;

      // Add all pending annotations - the JavaScript side handles timing and state
      // The 'create-overlay' event listener in flutter-bridge.js will ensure they're
      // drawn when the overlayer is fully initialized
      int addedCount = 0;
      for (final highlight in _pendingHighlights!) {
        if (_isDisposing || !mounted) return;
        try {
          final color = _colorFromHex(highlight.colorHex);
          await _epubController.addAnnotation(
            value: highlight.cfi,
            type: highlight.type,
            color: color,
            note: highlight.note,
          );
          addedCount++;
          // Minimal delay between annotations to avoid overwhelming the bridge
          await Future.delayed(const Duration(milliseconds: 5));
        } catch (e) {
          // Ignore errors - the JavaScript side will retry if needed
          if (kDebugMode) {
            print('Could not add annotation ${highlight.cfi}: $e');
          }
        }
      }

      if (kDebugMode) {
        print('Added $addedCount annotations for section $sectionIndex');
      }
    });
  }

  /// Check if a CFI has an existing highlight and return it
  HighlightModel? _getHighlightForCfi(String cfi) {
    if (_currentHighlights == null) return null;
    // First try exact match
    if (_currentHighlights!.containsKey(cfi)) {
      return _currentHighlights![cfi];
    }
    // Try prefix match - CFI from annotation click might be a range, stored CFI might be a point or vice versa
    // Check if any stored CFI starts with the clicked CFI, or if clicked CFI starts with any stored CFI
    for (final entry in _currentHighlights!.entries) {
      final storedCfi = entry.key;
      if (cfi.startsWith(storedCfi) || storedCfi.startsWith(cfi)) {
        return entry.value;
      }
    }
    return null;
  }

  /// Get note for a CFI, with flexible matching
  HighlightModel? _getNoteForCfi(String cfi) {
    final notes = _currentNotes;
    try {
      // First try exact match
      return notes.firstWhere((n) => n.cfi == cfi);
    } catch (e) {
      // Try prefix match - CFI from annotation click might be a range, stored CFI might be a point or vice versa
      try {
        return notes.firstWhere(
          (n) => cfi.startsWith(n.cfi) || n.cfi.startsWith(cfi),
        );
      } catch (e2) {
        return null;
      }
    }
  }

  /// Update highlights cache after adding a highlight
  Future<void> _updateHighlightsCache() async {
    try {
      final highlights = await _highlightsService.loadHighlights(
        int.tryParse(widget.book.id)?.toString(),
        widget.book.epubFilePath ?? '',
      );
      _currentHighlights = {for (var h in highlights) h.cfi: h};
    } catch (e) {
      print('Error updating highlights cache: $e');
    }
  }

  /// Convert hex color string to Color
  Color _colorFromHex(String hexString) {
    String hex = hexString.replaceFirst('#', '');
    // If hex doesn't have alpha, add it (fully opaque)
    if (hex.length == 6) {
      hex = 'FF$hex';
    }
    return Color(int.parse(hex, radix: 16));
  }

  /// Convert Color to hex string (RGB only, no alpha)
  String _colorToHex(Color color) {
    final hex = color.value.toRadixString(16).padLeft(8, '0');
    // Return RGB part (last 6 digits) with # prefix
    return '#${hex.substring(2)}';
  }

  /// Save a highlight or underline
  Future<void> _saveHighlight(
    String cfi,
    Color color,
    double opacity,
    String? selectedText, {
    String type = 'highlight',
    String? id,
    String note = '',
  }) async {
    try {
      final now = DateTime.now();
      final highlight = HighlightModel(
        id: id ?? 'highlight_${cfi}_${now.millisecondsSinceEpoch}',
        cfi: cfi,
        colorHex: _colorToHex(color),
        opacity: opacity,
        createdAt: now,
        updatedAt: now,
        note: note,
        selectedText: selectedText,
        type: type,
      );
      await _highlightsService.addHighlight(
        int.tryParse(widget.book.id)?.toString(),
        widget.book.epubFilePath ?? '',
        highlight,
      );
      // Update cache
      await _updateHighlightsCache();
    } catch (e) {
      print('Error saving highlight: $e');
    }
  }

  /// Remove a saved highlight
  Future<void> _removeSavedHighlight(String cfi) async {
    try {
      await _highlightsService.removeHighlight(
        int.tryParse(widget.book.id)?.toString(),
        widget.book.epubFilePath ?? '',
        cfi,
      );
      // Update cache
      await _updateHighlightsCache();
    } catch (e) {
      print('Error removing highlight: $e');
    }
  }

  void _handleSelection(
    String text,
    String cfi,
    Rect selectionRect,
    Rect viewRect,
    int? chapterIndex,
  ) {
    // Cancel the touch up timer to prevent control toggle
    _touchUpTimer?.cancel();

    // Set the flag to prevent control toggle
    setState(() {
      _selectionHappened = true;
    });

    final readingSettings = ref.read(readingSettingsProvider);
    String? cleanedWord;

    // Check if this CFI has an existing highlight
    final existingHighlight = _getHighlightForCfi(cfi);
    if (existingHighlight != null) {
      // Set the highlight color to match the existing highlight
      final highlightColor = _colorFromHex(existingHighlight.colorHex);
      ref.read(highlightColorProvider.notifier).selectColor(highlightColor);
    } else {
      // Reset to default color if no highlight exists
      ref
          .read(highlightColorProvider.notifier)
          .selectColor(const Color(0xFFFFEB3B));
    }

    // Always set the selection state to show the overlay
    ref
        .read(selectionStateProvider.notifier)
        .onSelection(text, cfi, selectionRect, viewRect);

    // Log chapter index if available
    if (chapterIndex != null) {
      print('Selection from chapter index: $chapterIndex');
    }

    // Auto-open Wiktionary if setting is enabled and selection is a single word
    if (readingSettings.autoOpenWiktionary) {
      final trimmedText = text.trim();
      // Check if it's a single word (no spaces, no punctuation except at the end)
      final words = trimmedText.split(RegExp(r'\s+'));
      if (words.length == 1 && words[0].isNotEmpty) {
        // Remove trailing punctuation
        cleanedWord = words[0].replaceAll(RegExp(r'[.,;:!?]+$'), '');
        if (cleanedWord.isNotEmpty) {
          // Set wiktionary word in selection state
          ref
              .read(selectionStateProvider.notifier)
              .setWiktionaryWord(cleanedWord);
        }
      }
    }
  }

  void _handleTouchUp(double x, double y) {
    // Store touch up position
    // Check if annotation was clicked BEFORE resetting the flag
    final wasAnnotationClicked = _annotationClicked;
    setState(() {
      _touchUpPosition = Offset(x, y);
      _annotationClicked = false; // Reset annotation flag
      _selectionHappened = false; // Reset selection flag
    });
    //if overlay menu is open, close it and return
    // BUT: don't clear selection if an annotation was just clicked (annotation click sets the selection)
    final selectionState = ref.watch(selectionStateProvider);
    if (selectionState.selectionRect != null && !wasAnnotationClicked) {
      ref.read(selectionStateProvider.notifier).clearSelection();
      return;
    }

    // If an annotation was clicked, don't process other touch actions (controls toggle, page navigation)
    if (wasAnnotationClicked) {
      return;
    }

    // Check if touch is in center zone (for toggling controls)
    if (x > 0.20 && x < 0.80) {
      _toggleControls();
    }
    if (x < 0.20) {
      _previousPage();
    }
    if (x > 0.80) {
      _nextPage();
    }
  }

  void _handleAnnotationClicked(
    String cfiRange,
    Map<String, dynamic>? rect,
    Map<String, dynamic>? containerRect,
  ) async {
    print('Annotation clicked: $cfiRange, rect: $rect');

    // Cancel the touch up timer to prevent control toggle
    _touchUpTimer?.cancel();

    // Set the flag to prevent control toggle and clear previous debug rect
    setState(() {
      _annotationClicked = true;
    });

    // Use stored highlight text if available, otherwise check for note
    final highlight = _getHighlightForCfi(cfiRange);
    var extractedText = highlight?.selectedText;

    // If no highlight text, check if there's a note for this CFI
    if (extractedText == null || extractedText.isEmpty) {
      final note = _getNoteForCfi(cfiRange);
      if (note != null) {
        extractedText = note.selectedText;
      }
    }

    try {
      if (mounted && extractedText != null && extractedText.isNotEmpty) {
        // Get the FoliateWebView's render box to get WebView size (same as _handleSelection in epub_viewer.dart)
        final renderBox =
            _epubViewerKey.currentContext?.findRenderObject() as RenderBox?;
        if (renderBox == null) {
          print('Could not get render box for FoliateEpubViewer');
          return;
        }
        final webViewSize = renderBox.size;
        // Get WebView's global position for coordinate conversion
        final webViewPosition = renderBox.localToGlobal(Offset.zero);

        // Convert viewport-relative coordinates to screen coordinates
        // Note: The rect from JavaScript is viewport-relative, convert to screen space
        Rect? selectionRect;
        if (rect != null) {
          try {
            // Get content area offsets (same as selection handler)
            // These account for WebView's internal content area position
            final containerLeft =
                (containerRect?['left'] as num?)?.toDouble() ?? 0.0;
            final contentOffsetX =
                containerLeft; // WebView content area left offset (from container rect)
            final contentOffsetY = MediaQuery.of(
              context,
            ).padding.top; // Status bar height

            // Rect is viewport-relative from JavaScript, convert to screen coordinates
            final left = (rect['left'] as num).toDouble() + webViewPosition.dx;
            final top = (rect['top'] as num).toDouble() + webViewPosition.dy;
            final width = (rect['width'] as num).toDouble();
            final height = (rect['height'] as num).toDouble();

            // Coordinates are now in screen space (matching the full-screen Stack)
            selectionRect = Rect.fromLTWH(left, top, width, height);
            print('Using rect from annotation click: $selectionRect');
          } catch (e) {
            print('Error parsing annotation rect: $e');
          }
        }

        // Create viewRect in WebView-relative coordinates (same as _handleSelection in epub_viewer.dart)
        // This matches exactly what epub_viewer.dart passes to onSelection
        final viewRect = Rect.fromLTWH(
          0,
          0,
          webViewSize.width,
          webViewSize.height,
        );

        if (selectionRect != null) {
          // Show the selection overlay using the extracted text and rect
          _handleSelection(
            extractedText,
            cfiRange,
            selectionRect,
            viewRect,
            null,
          );

          // Open annotation bar and set style/color to match existing annotation
          // Use post-frame callback to ensure selection state is set first
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && !_isDisposing) {
              if (highlight != null) {
                // Use highlight's style and color
                ref
                    .read(annotationProvider.notifier)
                    .selectStyle(highlight.type);
                final annotationColor = _colorFromHex(highlight.colorHex);
                ref
                    .read(annotationProvider.notifier)
                    .selectColor(annotationColor);
              } else {
                // Default to yellow highlight for notes
                ref.read(annotationProvider.notifier).selectStyle('highlight');
                ref
                    .read(annotationProvider.notifier)
                    .selectColor(const Color(0xFFFFEB3B));
              }
              ref.read(selectionStateProvider.notifier).toggleAnnotationBar();
            }
          });
        } else {
          // Fallback: if no rect, try to use touch position or skip showing overlay
          if (_touchUpPosition != null) {
            final screenWidth = MediaQuery.of(context).size.width;
            final screenHeight = MediaQuery.of(context).size.height;
            final touchX = _touchUpPosition!.dx * screenWidth;
            final touchY = _touchUpPosition!.dy * screenHeight;
            final estimatedWidth = 100.0;
            final estimatedHeight = 20.0;
            final readingSettings = ref.read(readingSettingsProvider);
            final padding = _getEpubViewerPadding(
              readingSettings.keepMenusOpen,
            );
            final fallbackRect = Rect.fromLTWH(
              touchX - padding.left - (estimatedWidth / 2),
              touchY - padding.top - (estimatedHeight / 2),
              estimatedWidth,
              estimatedHeight,
            );
            print('Using estimated rect from touch: $fallbackRect');
            _handleSelection(
              extractedText,
              cfiRange,
              fallbackRect,
              viewRect,
              null,
            );

            // Open annotation bar and set style/color to match existing annotation
            // Use post-frame callback to ensure selection state is set first
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && !_isDisposing) {
                if (highlight != null) {
                  // Use highlight's style and color
                  ref
                      .read(annotationProvider.notifier)
                      .selectStyle(highlight.type);
                  final annotationColor = _colorFromHex(highlight.colorHex);
                  ref
                      .read(annotationProvider.notifier)
                      .selectColor(annotationColor);
                } else {
                  // Default to yellow highlight for notes
                  ref
                      .read(annotationProvider.notifier)
                      .selectStyle('highlight');
                  ref
                      .read(annotationProvider.notifier)
                      .selectColor(const Color(0xFFFFEB3B));
                }
                ref.read(selectionStateProvider.notifier).toggleAnnotationBar();
              }
            });
          } else {
            print('No rect or touch position available for annotation');
          }
        }
      }
    } catch (e) {
      print('Error extracting text from annotation: $e');
    }
  }

  void _handleRelocated(EpubLocation location) {
    // Handle page location changes
    if (mounted) {
      // If we're navigating to a note, check if this relocation matches the target CFI
      if (_pendingNoteNavigationCfi != null) {
        final targetCfi = _pendingNoteNavigationCfi!;
        final currentCfi = location.startCfi;

        // Normalize CFIs for comparison - CFI formats can vary:
        // Target: epubcfi(/6/14!/4/16,/1:3,/1:60)
        // Relocation: epubcfi(/6/14!/4,/16/1:739,/20/1:855)
        // Both refer to the same section (6), so we match on the section part
        String? extractSectionPath(String? cfi) {
          if (cfi == null) return null;
          // Extract the section path: epubcfi(/6/14!/4...) -> /6/14!/4
          // Find the pattern /N/ where N is the section number
          final match = RegExp(
            r'epubcfi\((/[^/]+/[^/]+!/[^,)]+)',
          ).firstMatch(cfi);
          if (match != null && match.groupCount > 0) {
            return match.group(1);
          }
          // Fallback: extract up to first comma or closing paren
          final commaIndex = cfi.indexOf(',');
          final parenIndex = cfi.indexOf(')');
          final endIndex = commaIndex > 0 && parenIndex > 0
              ? (commaIndex < parenIndex ? commaIndex : parenIndex)
              : (commaIndex > 0
                    ? commaIndex
                    : (parenIndex > 0 ? parenIndex : cfi.length));
          if (endIndex > 0) {
            return cfi.substring(0, endIndex).replaceAll('epubcfi(', '');
          }
          return cfi.replaceAll('epubcfi(', '').replaceAll(')', '');
        }

        final targetSection = extractSectionPath(targetCfi);
        final currentSection = extractSectionPath(currentCfi);

        // Check if we've reached the target section (exact match or one is prefix of the other)
        final reachedTarget =
            currentSection != null &&
            targetSection != null &&
            (currentSection == targetSection ||
                currentSection.startsWith(targetSection) ||
                targetSection.startsWith(currentSection));

        if (reachedTarget) {
          print(
            '✅ Reached note navigation target CFI: ${targetCfi.substring(0, targetCfi.length.clamp(0, 50))}...',
          );
          print(
            '   Target section: $targetSection, Current section: $currentSection',
          );
          // Clear the pending navigation flag since we've reached the target
          _pendingNoteNavigationCfi = null;
          _noteNavigationTimer?.cancel();
          _noteNavigationTimer = null;
        } else {
          // Still navigating - ignore this relocation to prevent interference
          print('⏳ Note navigation in progress, ignoring relocation');
          print(
            '   Target section: $targetSection, Current section: $currentSection',
          );
          return;
        }
      }

      // Reset navigation flag when relocation completes
      _navigationDebounceTimer?.cancel();
      _isNavigating = false;

      // Don't update state or save if progress is 0 (workaround for issue #28 where progress is 0 initially)
      // This prevents UI "spazzing" when clearing selections
      if (location.progress > 0.0) {
        // On the first meaningful relocation, treat initial position as loaded so
        // we can hide the "Loading book..." overlay and restore highlights.
        if (!_initialPositionLoaded) {
          _handleOnInitialPositionLoaded();
        }

        // Defer provider update to prevent interrupting WebView rendering
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ref.read(epubStateProvider.notifier).setCurrentLocation(location);
          }
        });

        // Check if position has actually changed (either XPath or progress changed significantly)
        final xpathChanged =
            _lastSavedXPath == null ||
            location.startXpath == null ||
            location.startXpath != _lastSavedXPath;

        // Consider progress changed if difference is > 0.1% (to avoid saving tiny fluctuations)
        final progressChanged =
            _lastSavedProgress == null ||
            (location.progress - _lastSavedProgress!).abs() > 0.001;

        // Check if we have a CFI but haven't saved it yet (e.g., loaded with XPath, now have CFI)
        final startCfi = location.startCfi;
        final hasCfiToSave =
            startCfi != null &&
            startCfi.isNotEmpty &&
            startCfi.startsWith('epubcfi');
        final cfiNeedsSaving =
            hasCfiToSave && (_savedCfi == null || _savedCfi != startCfi);

        // Save if position has meaningfully changed OR if we have a CFI that needs to be saved
        if (xpathChanged || progressChanged || cfiNeedsSaving) {
          _saveProgress(
            location.progress,
            location.startCfi,
            location.startXpath,
          );
          _pushSyncProgress(
            location.progress,
            location.startCfi,
            location.startXpath,
          );
          _lastSavedXPath = location.startXpath; // Track last saved XPath
          _lastSavedProgress = location.progress; // Track last saved progress
          // Update _savedCfi if we just saved a new CFI
          if (cfiNeedsSaving && startCfi != null) {
            _savedCfi = startCfi;
          }
        }
      }
    }
  }

  void _nextPage() {
    if (_isNavigating) {
      print('Navigation already in progress, ignoring next page call');
      return;
    }

    _navigationDebounceTimer?.cancel();
    _navigationDebounceTimer = Timer(const Duration(milliseconds: 300), () {
      _isNavigating = false;
    });

    _isNavigating = true;
    _epubController.nextPage().catchError((e) {
      print('Error navigating to next page: $e');
      _isNavigating = false;
    });
  }

  void _previousPage() {
    if (_isNavigating) {
      print('Navigation already in progress, ignoring previous page call');
      return;
    }

    _navigationDebounceTimer?.cancel();
    _navigationDebounceTimer = Timer(const Duration(milliseconds: 300), () {
      _isNavigating = false;
    });

    _isNavigating = true;
    _epubController.prevPage().catchError((e) {
      print('Error navigating to previous page: $e');
      _isNavigating = false;
    });
  }

  /// Save reading progress and CFI to database
  Future<void> _saveProgress(
    double progressPercentage,
    String? cfi,
    String? xpath,
  ) async {
    // Don't save if progress is 0 (workaround for issue #28)
    if (progressPercentage <= 0.0) return;

    try {
      final dbService = LocalDatabaseService.instance;
      await dbService.initialize();

      // Try to find book ID from BookModel
      int? bookId = int.tryParse(widget.book.id);
      if (bookId == null) {
        // Look up book by file path
        final book = dbService.getBookByFilePath(
          widget.book.epubFilePath ?? '',
        );
        if (book != null && book.id != null) {
          bookId = book.id;
        } else {
          return;
        }
      }

      // Generate last read status based on progress
      String? lastReadStatus;
      if (progressPercentage >= 1.0) {
        lastReadStatus = 'All pages finish';
      } else if (progressPercentage >= 0.9) {
        lastReadStatus = 'Almost finished';
      } else if (progressPercentage >= 0.5) {
        lastReadStatus = 'Just read recently';
      } else if (progressPercentage > 0.0) {
        lastReadStatus = 'Reading in progress';
      }

      // Save progress (with full precision) and CFI to database
      final result = dbService.updateProgress(
        bookId!,
        progressPercentage,
        lastReadStatus,
        lastReadCfi: cfi,
        lastReadXPath: xpath,
      );

      // Verify CFI was saved by reloading from database
      if (result == 1 && cfi != null && cfi.isNotEmpty) {
        final savedBook = dbService.getBookById(bookId);
        if (savedBook != null) {
          final savedCfi = savedBook.lastReadCfi;
          if (savedCfi != null && savedCfi == cfi) {
            // Update in-memory _savedCfi to match database
            _savedCfi = savedCfi;
          }
        }
      }

      // Refresh the books list to show updated progress
      if (result == 1) {
        ref.read(booksRefreshProvider.notifier).state++;
      }
    } catch (e, stackTrace) {
      print('Error saving progress: $e');
      print('Stack trace: $stackTrace');
    }
  }

  /// Manual push progress to sync server
  Future<void> _manualPushProgress() async {
    try {
      final dbService = LocalDatabaseService.instance;
      await dbService.initialize();

      int? bookId = int.tryParse(widget.book.id);
      if (bookId == null) {
        final book = dbService.getBookByFilePath(
          widget.book.epubFilePath ?? '',
        );
        if (book != null && book.id != null) {
          bookId = book.id;
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Error: Book not found')),
            );
          }
          return;
        }
      }

      if (bookId == null) return;

      final book = dbService.getBookById(bookId);
      if (book == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Error: Book not found')),
          );
        }
        return;
      }

      // Check if sync is enabled for this book
      if (book.syncEnabled == false) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Sync is disabled for this book')),
          );
        }
        return;
      }

      // Get current progress from the last saved state
      final currentProgress = book.progressPercentage ?? 0.0;
      if (currentProgress <= 0.0) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('No progress to push')));
        }
        return;
      }

      // Show loading dialog
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Text('Pushing progress...'),
            ],
          ),
        ),
      );

      try {
        final syncManager = SyncManagerService.instance;

        // Get progress string (XPath or page number)
        String? progressStr;
        if (book.lastReadXPath != null && book.lastReadXPath!.isNotEmpty) {
          progressStr = book.lastReadXPath;
        } else if (book.lastReadCfi != null && book.lastReadCfi!.isNotEmpty) {
          // If we have CFI but no XPath, we can't push (XPath is required for KOReader)
          if (mounted) {
            Navigator.of(context).pop(); // Close loading dialog
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Error: XPath not available. Please navigate to a page first.',
                ),
              ),
            );
          }
          return;
        } else {
          if (mounted) {
            Navigator.of(context).pop(); // Close loading dialog
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Error: No progress location available'),
              ),
            );
          }
          return;
        }

        if (progressStr == null || progressStr.isEmpty) {
          if (mounted) {
            Navigator.of(context).pop(); // Close loading dialog
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Error: No progress to push')),
            );
          }
          return;
        }

        // Flush any pending progress and push immediately
        syncManager.flushProgress(bookId);
        syncManager.pushProgress(bookId, book, progressStr, currentProgress);
        syncManager.flushProgress(
          bookId,
        ); // Flush again to ensure immediate push

        // Wait a moment for the push to complete
        await Future.delayed(const Duration(milliseconds: 500));

        if (mounted) {
          Navigator.of(context).pop(); // Close loading dialog
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Progress pushed successfully')),
          );
        }
      } catch (e) {
        if (mounted) {
          Navigator.of(context).pop(); // Close loading dialog
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error pushing progress: $e')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  /// Manual pull progress from sync server
  Future<void> _manualPullProgress() async {
    try {
      final dbService = LocalDatabaseService.instance;
      await dbService.initialize();

      int? bookId = int.tryParse(widget.book.id);
      if (bookId == null) {
        final book = dbService.getBookByFilePath(
          widget.book.epubFilePath ?? '',
        );
        if (book != null && book.id != null) {
          bookId = book.id;
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Error: Book not found')),
            );
          }
          return;
        }
      }

      if (bookId == null) return;

      final book = dbService.getBookById(bookId);
      if (book == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Error: Book not found')),
          );
        }
        return;
      }

      // Check if sync is enabled for this book
      if (book.syncEnabled == false) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Sync is disabled for this book')),
          );
        }
        return;
      }

      // Show loading dialog
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Text('Pulling progress...'),
            ],
          ),
        ),
      );

      try {
        final syncManager = SyncManagerService.instance;
        final syncStrategy = ref.read(syncStrategyProvider).strategy;

        // Perform sync check
        await syncManager.performInitialSync(book);

        // Check sync state
        final syncState = syncManager.getSyncState(bookId);

        if (mounted) {
          Navigator.of(context).pop(); // Close loading dialog
        }

        if (syncState == SyncState.conflict &&
            syncStrategy == SyncStrategy.prompt) {
          // Show conflict resolution bottom sheet
          final conflictDetails = syncManager.getConflictDetails(bookId);
          if (conflictDetails != null && mounted) {
            _showConflictDialog(conflictDetails, bookId);
          }
        } else if (syncState == SyncState.synced) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Progress synced successfully')),
            );
            // Reload the book to show updated progress
            _loadSavedProgress();
          }
        } else if (syncState == SyncState.error) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Error syncing progress')),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('No remote progress available')),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          Navigator.of(context).pop(); // Close loading dialog
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error pulling progress: $e')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  /// Push progress to sync server (debounced)
  void _pushSyncProgress(
    double progressPercentage,
    String? cfi,
    String? xpath,
  ) async {
    try {
      final dbService = LocalDatabaseService.instance;
      await dbService.initialize();

      int? bookId = int.tryParse(widget.book.id);
      if (bookId == null) {
        final book = dbService.getBookByFilePath(
          widget.book.epubFilePath ?? '',
        );
        if (book != null && book.id != null) {
          bookId = book.id;
        } else {
          return;
        }
      }

      if (bookId != null) {
        final book = dbService.getBookById(bookId);
        if (book != null) {
          final syncManager = SyncManagerService.instance;
          // For KOReader sync, prioritize XPath for reflowable EPUBs
          // XPath is what KOReader expects for reflowable EPUBs
          // The JavaScript bridge now converts CFI to XPointer automatically,
          // so we should always have XPath when we have CFI
          String? progressStr;
          if (xpath != null && xpath.isNotEmpty) {
            // Use XPath if available for KOReader compatibility
            progressStr = xpath;
          } else if (cfi != null && cfi.isNotEmpty) {
            // If we have CFI but no XPath, it means conversion failed
            // Log a warning but don't send progress (KOReader requires XPath)
            print(
              '⚠️ Skipping sync progress: CFI available but XPath conversion failed (CFI: ${cfi.substring(0, cfi.length > 50 ? 50 : cfi.length)}...)',
            );
            return;
          } else {
            // No CFI or XPath - can't determine position
            print('⚠️ Skipping sync progress: No CFI or XPath available');
            return;
          }

          if (progressStr != null && progressStr.isNotEmpty) {
            syncManager.pushProgress(
              bookId,
              book,
              progressStr,
              progressPercentage,
            );
          }
        }
      }
    } catch (e) {
      print('Error pushing sync progress: $e');
    }
  }

  void _showThemeSettings() {
    showMaterialModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => const ThemeBottomSheet(),
    );
  }

  void _showFontSettings() {
    final readingSettings = ref.read(readingSettingsProvider);
    // Track font size locally in the modal - initialized OUTSIDE the builder
    double modalFontSize = readingSettings.fontSize.toDouble();

    showModalBottomSheet(
      context: context,
      backgroundColor: readingSettings.isDarkMode
          ? Colors.grey[850]
          : Colors.white,
      builder: (context) {
        // Use StatefulBuilder to make the slider reactive within the modal
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Container(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Font Settings',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: readingSettings.isDarkMode
                          ? Colors.white
                          : Colors.black,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Font Size: ${modalFontSize.toInt()}',
                    style: TextStyle(
                      color: readingSettings.isDarkMode
                          ? Colors.white
                          : Colors.black,
                    ),
                  ),
                  Slider(
                    value: modalFontSize,
                    min: 12,
                    max: 28,
                    divisions: 16,
                    onChanged: (value) {
                      // Update modal state to rebuild the slider
                      setModalState(() {
                        modalFontSize = value;
                      });
                      // Update parent state
                      ref
                          .read(readingSettingsProvider.notifier)
                          .setFontSize(value.toInt());
                      // Update font size in EPUB viewer via theme update
                      _updateTheme();
                    },
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showReaderSettings() {
    showMaterialModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Consumer(
        builder: (context, ref, child) {
          final currentReadingSettings = ref.watch(readingSettingsProvider);
          final volumeKeySetting = ref.watch(volumeKeySettingProvider);
          final textColor = currentReadingSettings.isDarkMode
              ? Colors.white
              : Colors.black;

          return Material(
            color: currentReadingSettings.isDarkMode
                ? Colors.grey[850]
                : Colors.white,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            clipBehavior: Clip.antiAlias,
            child: StatefulBuilder(
              builder: (BuildContext context, StateSetter setModalState) {
                return SafeArea(
                  top: false,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(24, 8, 8, 20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Reader Settings',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: textColor,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: Icon(
                                Icons.close,
                                color: currentReadingSettings.isDarkMode
                                    ? darkIconColor
                                    : lightIconColor,
                              ),
                              onPressed: () => Navigator.of(context).pop(),
                            ),
                          ],
                        ),

                        // Auto-Open Dictionary Toggle
                        SwitchListTile(
                          dense: true,
                          visualDensity: const VisualDensity(
                            horizontal: -4,
                            vertical: -4,
                          ),
                          title: Text(
                            'Auto-Open Dictionary',
                            style: TextStyle(color: textColor),
                          ),
                          subtitle: Text(
                            'Automatically open dictionary for single-word selections',
                            style: TextStyle(color: textColor.withOpacity(0.7)),
                          ),
                          value: currentReadingSettings.autoOpenWiktionary,
                          inactiveTrackColor: currentReadingSettings.isDarkMode
                              ? Colors.grey[800]
                              : Colors.grey[200],
                          onChanged: (value) {
                            ref
                                .read(readingSettingsProvider.notifier)
                                .setAutoOpenWiktionary(value);
                          },
                          secondary: Icon(
                            Icons.book,
                            color: currentReadingSettings.isDarkMode
                                ? darkIconColor
                                : lightIconColor,
                          ),
                        ),

                        const Divider(),

                        //volume keys turn pages
                        SwitchListTile(
                          dense: true,
                          visualDensity: const VisualDensity(
                            horizontal: -4,
                            vertical: -4,
                          ),
                          title: Text(
                            'Volume Keys Turn Pages',
                            style: TextStyle(color: textColor),
                          ),
                          subtitle: Text(
                            'Use volume buttons to navigate pages',
                            style: TextStyle(color: textColor.withOpacity(0.7)),
                          ),
                          value: volumeKeySetting.enabled,
                          onChanged: (value) {
                            ref
                                .read(volumeKeySettingProvider.notifier)
                                .setEnabled(value);
                          },
                          inactiveTrackColor: currentReadingSettings.isDarkMode
                              ? Colors.grey[800]
                              : Colors.grey[200],
                          secondary: Icon(
                            Icons.volume_up,
                            color: currentReadingSettings.isDarkMode
                                ? darkIconColor
                                : lightIconColor,
                          ),
                        ),

                        const Divider(),

                        // Keep Screen Awake Toggle
                        Consumer(
                          builder: (context, ref, child) {
                            final keepScreenAwakeSetting = ref.watch(
                              keepScreenAwakeSettingProvider,
                            );
                            return SwitchListTile(
                              dense: true,
                              visualDensity: const VisualDensity(
                                horizontal: -4,
                                vertical: -4,
                              ),
                              title: Text(
                                'Keep Screen Awake',
                                style: TextStyle(color: textColor),
                              ),
                              subtitle: Text(
                                'Prevent screen from sleeping while reading',
                                style: TextStyle(
                                  color: textColor.withOpacity(0.7),
                                ),
                              ),
                              value: keepScreenAwakeSetting.enabled,
                              inactiveTrackColor:
                                  currentReadingSettings.isDarkMode
                                  ? Colors.grey[800]
                                  : Colors.grey[200],

                              onChanged: (value) async {
                                await ref
                                    .read(
                                      keepScreenAwakeSettingProvider.notifier,
                                    )
                                    .setEnabled(value);
                                // Update wakelock immediately if in reader
                                if (value) {
                                  await WakelockPlus.enable();
                                  _screenAwakeLockEnabled = true;
                                } else {
                                  await WakelockPlus.disable();
                                  _screenAwakeLockEnabled = false;
                                }
                              },
                              secondary: Icon(
                                Icons.screen_lock_portrait,
                                color: currentReadingSettings.isDarkMode
                                    ? darkIconColor
                                    : lightIconColor,
                              ),
                            );
                          },
                        ),

                        const Divider(),

                        // Keep Menus Open Toggle
                        SwitchListTile(
                          dense: true,
                          visualDensity: const VisualDensity(
                            horizontal: -4,
                            vertical: -4,
                          ),
                          title: Text(
                            'Keep Menus Open',
                            style: TextStyle(color: textColor),
                          ),
                          subtitle: Text(
                            'Keep navigation bars visible while reading',
                            style: TextStyle(color: textColor.withOpacity(0.7)),
                          ),
                          value: currentReadingSettings.keepMenusOpen,
                          inactiveTrackColor: currentReadingSettings.isDarkMode
                              ? Colors.grey[800]
                              : Colors.grey[200],
                          onChanged: (value) {
                            ref
                                .read(readingSettingsProvider.notifier)
                                .setKeepMenusOpen(value);
                            // Update UI controls to show menus if enabled
                            if (value) {
                              ref
                                  .read(uiControlsProvider.notifier)
                                  .toggleControls();
                            }
                            // Trigger rebuild to update padding
                            setModalState(() {});
                            setState(() {});
                          },
                          secondary: Icon(
                            Icons.menu_open,
                            color: currentReadingSettings.isDarkMode
                                ? darkIconColor
                                : lightIconColor,
                          ),
                        ),

                        const Divider(),

                        // KoReader Sync Settings
                        ListTile(
                          dense: true,
                          visualDensity: const VisualDensity(
                            horizontal: -4,
                            vertical: -4,
                          ),
                          leading: Icon(
                            Icons.cloud_sync,
                            color: currentReadingSettings.isDarkMode
                                ? darkIconColor
                                : lightIconColor,
                          ),
                          title: Text(
                            'KoReader Sync Settings',
                            style: TextStyle(color: textColor),
                          ),
                          subtitle: Text(
                            'Configure sync server and strategy',
                            style: TextStyle(color: textColor.withOpacity(0.7)),
                          ),
                          trailing: Icon(
                            Icons.chevron_right,
                            color: currentReadingSettings.isDarkMode
                                ? darkIconColor
                                : lightIconColor,
                          ),
                          onTap: () {
                            Navigator.of(context).pop();
                            _showSyncSettings();
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  void _showSyncSettings() async {
    final readingSettings = ref.read(readingSettingsProvider);
    final dbService = LocalDatabaseService.instance;
    await dbService.initialize();

    // Get current book
    int? bookId = int.tryParse(widget.book.id);
    if (bookId == null) {
      final book = dbService.getBookByFilePath(widget.book.epubFilePath ?? '');
      bookId = book?.id;
    }

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: readingSettings.isDarkMode
          ? Colors.grey[850]
          : Colors.white,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Container(
            height: MediaQuery.of(context).size.height * 0.9,
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'KOReader Sync Settings',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: readingSettings.isDarkMode
                              ? Colors.white
                              : Colors.black,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.close,
                        color: readingSettings.isDarkMode
                            ? darkIconColor
                            : lightIconColor,
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Flexible(
                  child: KoreaderSyncSettingsWidget(
                    bookId: bookId,
                    showBookSyncToggle: bookId != null,
                    onClose: () {
                      if (mounted) {
                        Navigator.of(context).pop();
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildNavigationZones() {
    final screenWidth = MediaQuery.of(context).size.width;
    final zoneWidth = screenWidth / 7;

    return Stack(
      children: [
        // Top Zone - toggle menu
        Positioned(
          left: 0,
          top: 0,
          height: 40,
          width: screenWidth,
          child: _TapZoneWidget(
            debugShowZone: colorTapZones,
            color: Colors.green,
            onTap: () {
              _toggleControls();
            },
          ),
        ),
        // Bottom Zone - toggle menu
        Positioned(
          left: 0,
          bottom: 0,
          height: 100,
          width: screenWidth,
          child: _TapZoneWidget(
            debugShowZone: colorTapZones,
            color: Colors.orange,
            onTap: () {
              _toggleControls();
            },
          ),
        ),
        // Left zone - previous page
        // Positioned(
        //   left: 0,
        //   top: 0,
        //   bottom: 0,
        //   width: zoneWidth,
        //   child: _TapZoneWidget(
        //     debugShowZone: colorTapZones,
        //     color: Colors.red,
        //     onTap: () {
        //       _previousPage();
        //     },
        //   ),
        // ),
        // Right zone - next page
        // Positioned(
        //   right: 0,
        //   top: 0,
        //   bottom: 0,
        //   width: zoneWidth,
        //   child: _TapZoneWidget(
        //     debugShowZone: colorTapZones,
        //     color: Colors.blue,
        //     onTap: () {
        //       _nextPage();
        //     },
        //   ),
        // ),
      ],
    );
  }

  Widget _buildDismissOverlay() {
    // Dismiss overlay only covers the center area (excluding navigation zones)
    // This allows long presses in navigation zones to work immediately
    const edgeWidth = 100.0;
    const topBottomHeight = 150.0;

    return Stack(
      children: [
        // Center area - dismiss overlay
        Positioned(
          left: edgeWidth,
          right: edgeWidth,
          top: topBottomHeight,
          bottom: topBottomHeight,
          child: _DismissOverlayWidget(
            onTap: () {
              _deselectText();
              // Bottom sheet will automatically close when selection is cleared
            },
          ),
        ),
      ],
    );
  }

  Widget _buildDebugRectOverlay() {
    final selectionState = ref.watch(selectionStateProvider);
    if (selectionState.selectionRect == null) return const SizedBox.shrink();

    // Use the same rect as the selection overlay (which is positioned correctly)
    final rect = selectionState.selectionRect!;
    return Positioned(
      left: rect.left,
      top: rect.top,
      width: rect.width,
      height: rect.height,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.red, width: 3),
          color: Colors.red.withOpacity(0.2),
        ),
        child: Center(
          child: Text(
            'DEBUG\n${rect.width.toStringAsFixed(1)}x${rect.height.toStringAsFixed(1)}',
            style: const TextStyle(
              color: Colors.red,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }

  Widget _buildSelectionOverlay() {
    final selectionState = ref.watch(selectionStateProvider);
    final variant = ref.watch(themeVariantProvider);

    // Don't show overlay if no selection rect or selection is being changed
    if (selectionState.selectionRect == null ||
        selectionState.viewRect == null ||
        selectionState.isSelectionChanging)
      return const SizedBox.shrink();

    // Get screen dimensions
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    // Calculate card position - show above or below selection
    final cardHeight = 56.0;
    final estimatedCardWidth = 320.0; // Estimated width for initial positioning
    final actualCardWidth =
        _overlayMenuWidth ?? estimatedCardWidth; // Use actual width if measured
    final padding = 8.0;

    // Center the card horizontally on screen (dead center)
    final cardLeft = (screenWidth - actualCardWidth) / 2;

    // Check if bottom sheet is open
    final bottomSheetOpen = selectionState.wiktionaryWord != null;
    final bottomSheetMaxHeight =
        screenHeight * 0.5; // Max height of bottom sheet
    final actualBottomSheetHeight =
        _bottomSheetHeight ??
        bottomSheetMaxHeight; // Use actual height if available

    final minSpaceNeeded = cardHeight + padding;

    // Calculate normal overlay position (above or below selection)
    final showAbove = selectionState.selectionRect!.top >= minSpaceNeeded;
    final normalCardTop = showAbove
        ? selectionState
              .selectionRect!
              .top // Bottom of overlay aligns with top of selection
        : selectionState.selectionRect!.bottom +
              padding; // Show below with padding

    // Check if bottom sheet would overlap with the normal overlay position
    final bottomSheetTop = screenHeight - actualBottomSheetHeight;
    final overlayBottom = normalCardTop + cardHeight;
    final wouldOverlap = bottomSheetOpen && overlayBottom > bottomSheetTop;

    double cardTop;
    if (wouldOverlap) {
      // Position overlay above the bottom sheet with extra spacing
      cardTop = screenHeight - actualBottomSheetHeight - cardHeight;
    } else {
      // Use normal position - bottom sheet won't reach the menu
      cardTop = normalCardTop;
    }

    // Calculate triangle position for main menu - triangle follows the selected word
    final triangleWidth = 16.0; // Wider
    final triangleHeight = 8.0; // Shorter
    final selectionCenterX =
        selectionState.selectionRect!.left +
        (selectionState.selectionRect!.width / 2);
    // Calculate triangle center relative to the card (card is centered on screen)
    final triangleCenterRelativeToCard = selectionCenterX - cardLeft;
    // Triangle at bottom of card (pointing down)
    final cardTopPosition = cardTop - cardHeight - padding;

    return Stack(
      clipBehavior: Clip.none, // Allow triangle to extend beyond card bounds
      children: [
        // Action buttons card with triangle as part of it
        Positioned(
          left: cardLeft,
          top: cardTopPosition,
          child: ClipPath(
            clipper: _SelectionOverlayClipper(
              triangleLeft: triangleCenterRelativeToCard,
              triangleWidth: triangleWidth,
              triangleHeight: triangleHeight,
              cardHeight: cardHeight,
              borderRadius: 8.0,
            ),
            child: Container(
              height: cardHeight + triangleHeight, // Include triangle height
              decoration: BoxDecoration(
                color: variant.cardColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Material(
                key: _overlayMenuKey,
                elevation:
                    0, // No elevation on inner Material, parent handles it
                color: Colors.transparent,
                child: Builder(
                  builder: (context) {
                    // Measure the actual width after build
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!_isDisposing &&
                          mounted &&
                          _overlayMenuKey.currentContext != null) {
                        final RenderBox? renderBox =
                            _overlayMenuKey.currentContext?.findRenderObject()
                                as RenderBox?;
                        if (renderBox != null) {
                          final width = renderBox.size.width;
                          if (_overlayMenuWidth != width) {
                            setState(() {
                              _overlayMenuWidth = width;
                            });
                          }
                        }
                      }
                    });
                    return Align(
                      alignment: Alignment.topCenter,
                      child: Container(
                        height: cardHeight,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        alignment: Alignment.center,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _buildActionButton(
                              icon: Icons.copy,
                              tooltip: 'Copy',
                              onTap: () {
                                if (selectionState.selectedText != null) {
                                  Clipboard.setData(
                                    ClipboardData(
                                      text: selectionState.selectedText!,
                                    ),
                                  );
                                }
                                _deselectText();
                              },
                            ),
                            _buildActionButton(
                              icon: Icons.edit,
                              tooltip: 'Note',
                              onTap: () {
                                final selectionState = ref.read(
                                  selectionStateProvider,
                                );
                                if (selectionState.selectedCfi != null &&
                                    selectionState.selectedText != null) {
                                  _showNoteDialog(
                                    cfi: selectionState.selectedCfi!,
                                    selectedText: selectionState.selectedText!,
                                  );
                                }
                                _deselectText();
                              },
                            ),
                            _buildHighlightButton(),
                            // _buildActionButton(
                            //   icon: Icons.search,
                            //   tooltip: 'Search',
                            //   onTap: () {
                            //     // Handle search action
                            //     _deselectText();
                            //   },
                            // ),
                            _buildActionButton(
                              svgPath: 'assets/icons/ic_dictionary.svg',
                              tooltip: 'Define',
                              isHighlighted:
                                  selectionState.wiktionaryWord != null,
                              onTap: () {
                                // Toggle Wiktionary sheet
                                if (selectionState.wiktionaryWord != null) {
                                  // Close if already open
                                  ref
                                      .read(selectionStateProvider.notifier)
                                      .setWiktionaryWord(null);
                                } else {
                                  // Open if closed
                                  if (selectionState.selectedText != null) {
                                    // Clean the word before showing
                                    final trimmedText = selectionState
                                        .selectedText!
                                        .trim();
                                    final words = trimmedText.split(
                                      RegExp(r'\s+'),
                                    );
                                    String wordToLookup = trimmedText;
                                    if (words.length == 1 &&
                                        words[0].isNotEmpty) {
                                      // Remove trailing punctuation for single words
                                      wordToLookup = words[0].replaceAll(
                                        RegExp(r'[.,;:!?]+$'),
                                        '',
                                      );
                                    }
                                    if (wordToLookup.isNotEmpty) {
                                      ref
                                          .read(selectionStateProvider.notifier)
                                          .setWiktionaryWord(wordToLookup);
                                      // Don't clear selection - keep overlay visible
                                    }
                                  }
                                }
                              },
                            ),
                            _buildActionButton(
                              icon: Icons.language,
                              tooltip: 'Translate',
                              onTap: () {
                                // Handle translate action
                                _deselectText();
                              },
                            ),
                            // _buildActionButton(
                            //   icon: Icons.headphones,
                            //   tooltip: 'Listen',
                            //   onTap: () {
                            //     // Handle text-to-speech action
                            //     _deselectText();
                            //   },
                            // ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton({
    IconData? icon,
    String? svgPath,
    required String tooltip,
    required VoidCallback onTap,
    bool isHighlighted = false,
  }) {
    final variant = ref.watch(themeVariantProvider);
    final iconColor = isHighlighted ? variant.primaryColor : variant.iconColor;

    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          child: svgPath != null
              ? SvgPicture.asset(
                  svgPath,
                  width: 20,
                  height: 20,
                  colorFilter: ColorFilter.mode(iconColor, BlendMode.srcIn),
                )
              : Icon(icon, size: 20, color: iconColor),
        ),
      ),
    );
  }

  Widget _buildHighlightButton() {
    final readingSettings = ref.watch(readingSettingsProvider);
    final annotationState = ref.watch(annotationProvider);
    final selectionState = ref.watch(selectionStateProvider);

    // Check if current selection has an annotation
    HighlightModel? existingAnnotation;
    if (selectionState.selectedCfi != null) {
      existingAnnotation = _getHighlightForCfi(selectionState.selectedCfi!);
    }

    final hasAnnotation = existingAnnotation != null;

    return Tooltip(
      message: hasAnnotation ? 'Remove Annotation' : 'Annotate',
      child: InkWell(
        onTap: () {
          final currentSelectionState = ref.read(selectionStateProvider);
          if (currentSelectionState.selectedCfi != null) {
            final cfi = currentSelectionState.selectedCfi!;

            // If annotation exists, remove it and close
            final existingAnnotation = _getHighlightForCfi(cfi);
            if (existingAnnotation != null) {
              // Remove the annotation
              _epubController.removeAnnotation(cfi);
              _removeSavedHighlight(cfi);
              // Close annotation bar if open
              ref.read(selectionStateProvider.notifier).closeAnnotationBar();
              // Deselect text
              _deselectText();
            } else {
              // No annotation exists - apply default annotation and open annotation bar
              final selectedText = currentSelectionState.selectedText;
              final defaultColor = const Color(0xFFFFEB3B); // Yellow
              final defaultStyle = 'highlight';
              final opacity = 0.4;

              // Set the default style and color
              ref.read(annotationProvider.notifier).selectStyle(defaultStyle);
              ref.read(annotationProvider.notifier).selectColor(defaultColor);

              // Apply the default annotation
              _epubController.addAnnotation(
                value: cfi,
                type: defaultStyle,
                color: defaultColor,
                note: selectedText,
              );
              _saveHighlight(
                cfi,
                defaultColor,
                opacity,
                selectedText,
                type: defaultStyle,
              );

              // Open annotation bar
              ref.read(selectionStateProvider.notifier).toggleAnnotationBar();
              // Don't deselect here - the annotation bar needs the CFI to apply annotations
            }
          }
        },
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          child: hasAnnotation
              ? Icon(
                  Icons.delete_outline,
                  size: 20,
                  color: readingSettings.isDarkMode
                      ? darkIconColor
                      : lightIconColor,
                )
              : Stack(
                  alignment: Alignment.center,
                  children: [
                    SvgPicture.asset(
                      'assets/icons/highlighter.svg',
                      width: 20,
                      height: 20,
                      colorFilter: ColorFilter.mode(
                        readingSettings.isDarkMode
                            ? darkIconColor
                            : lightIconColor,
                        BlendMode.srcIn,
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      child: Container(
                        width: 16,
                        height: 3,
                        decoration: BoxDecoration(
                          color: annotationState.selectedColor,
                          borderRadius: BorderRadius.circular(1.5),
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildAnnotationBar() {
    final selectionState = ref.watch(selectionStateProvider);
    final annotationState = ref.watch(annotationProvider);
    final variant = ref.watch(themeVariantProvider);

    // Get screen dimensions
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    // Bar dimensions
    final barHeight = 54.0;
    final barWidth =
        300.0; // Wider to accommodate style + color buttons (was 280, need more space)
    final cardHeight = 56.0;
    final padding = 8.0;

    // Center annotation bar horizontally on screen (dead center, same as main menu)
    final barLeft = (screenWidth - barWidth) / 2;

    // Position annotation bar above the main menu
    // Use same logic as main menu for vertical positioning
    final minSpaceNeeded = cardHeight + padding;
    final showAbove = selectionState.selectionRect!.top >= minSpaceNeeded;
    final normalCardTop = showAbove
        ? selectionState.selectionRect!.top
        : selectionState.selectionRect!.bottom + padding;

    // Check if bottom sheet would overlap
    final bottomSheetOpen = selectionState.wiktionaryWord != null;
    final bottomSheetMaxHeight = screenHeight * 0.5;
    final actualBottomSheetHeight = _bottomSheetHeight ?? bottomSheetMaxHeight;
    final bottomSheetTop = screenHeight - actualBottomSheetHeight;
    final overlayBottom = normalCardTop + cardHeight;
    final wouldOverlap = bottomSheetOpen && overlayBottom > bottomSheetTop;

    double cardTop;
    if (wouldOverlap) {
      cardTop = screenHeight - actualBottomSheetHeight - cardHeight;
    } else {
      cardTop = normalCardTop;
    }

    // Position annotation bar above the main menu
    final barTop =
        (cardTop - cardHeight - padding) -
        barHeight -
        padding; // Above main menu

    // Check if current selection has an annotation
    HighlightModel? existingAnnotation;
    if (selectionState.selectedCfi != null) {
      existingAnnotation = _getHighlightForCfi(selectionState.selectedCfi!);
    }

    final selectionCenterX =
        selectionState.selectionRect!.left +
        (selectionState.selectionRect!.width / 2);

    return Positioned(
      left: barLeft,
      top: barTop,
      child: Stack(
        clipBehavior: Clip.none, // Allow triangle to extend beyond card bounds
        children: [
          // Material card with triangle as part of it
          Material(
            elevation: 0,
            borderRadius: BorderRadius.circular(27),
            color: variant.cardColor, // Dark gray background
            child: Container(
              height: barHeight,
              constraints: BoxConstraints(maxWidth: barWidth, minWidth: 200),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Style buttons (left side): Highlight, Underline, Squiggly
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildStyleButton(
                        'highlight',
                        Icons.format_color_text,
                        annotationState,
                        existingAnnotation,
                      ),
                      const SizedBox(width: 6),
                      _buildStyleButton(
                        'underline',
                        Icons.format_underline,
                        annotationState,
                        existingAnnotation,
                      ),
                      const SizedBox(width: 6),
                      _buildStyleButton(
                        'squiggly',
                        Icons.format_color_fill,
                        annotationState,
                        existingAnnotation,
                      ),
                    ],
                  ),
                  const SizedBox(
                    width: 8,
                  ), // Gap between style and color buttons
                  // Color buttons (right side)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: annotationState.colors.map((color) {
                      final isSelected =
                          annotationState.selectedColor.value == color.value;
                      // Only show check for existing annotation if it matches both style AND color
                      final matchesExisting =
                          existingAnnotation != null &&
                          existingAnnotation.type ==
                              annotationState.selectedStyle &&
                          _colorFromHex(existingAnnotation.colorHex).value ==
                              color.value;

                      // Only show check mark if this is the selected color (mutually exclusive)
                      final showCheck = isSelected;

                      return Padding(
                        padding: const EdgeInsets.only(left: 2),
                        child: InkWell(
                          onTap: () {
                            final selectionState = ref.read(
                              selectionStateProvider,
                            );
                            if (selectionState.selectedCfi != null) {
                              final cfi = selectionState.selectedCfi!;
                              final selectedText = selectionState.selectedText;
                              final currentAnnotation = _getHighlightForCfi(
                                cfi,
                              );

                              // If clicking the same style+color as existing annotation, remove it
                              if (matchesExisting) {
                                _epubController.removeAnnotation(cfi);
                                _removeSavedHighlight(cfi);
                                ref
                                    .read(selectionStateProvider.notifier)
                                    .closeAnnotationBar();
                                _deselectText();
                              } else {
                                // Apply new color (don't close menu)
                                ref
                                    .read(annotationProvider.notifier)
                                    .selectColor(color);

                                // Remove any existing annotation at this CFI first
                                if (currentAnnotation != null) {
                                  _epubController.removeAnnotation(cfi);
                                  _removeSavedHighlight(cfi);
                                }

                                // Add new annotation with selected style and color
                                final style = annotationState.selectedStyle;
                                final opacity = style == 'highlight'
                                    ? 0.4
                                    : 1.0;
                                _epubController.addAnnotation(
                                  value: cfi,
                                  type: style,
                                  color: color,
                                  note: selectedText,
                                );
                                _saveHighlight(
                                  cfi,
                                  color,
                                  opacity,
                                  selectedText,
                                  type: style,
                                );
                              }
                            }
                          },
                          borderRadius: BorderRadius.circular(15),
                          child: Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                            ),
                            child: showCheck
                                ? const Icon(
                                    Icons.check,
                                    color: Colors.white,
                                    size: 18,
                                  )
                                : null,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStyleButton(
    String style,
    IconData icon,
    AnnotationState annotationState,
    HighlightModel? existingAnnotation,
  ) {
    final isSelected = annotationState.selectedStyle == style;
    final matchesExisting =
        existingAnnotation != null && existingAnnotation.type == style;
    final isActive = isSelected || matchesExisting;

    final variant = ref.watch(themeVariantProvider);

    return InkWell(
      onTap: () {
        final selectionState = ref.read(selectionStateProvider);
        if (selectionState.selectedCfi != null) {
          final cfi = selectionState.selectedCfi!;
          final selectedText = selectionState.selectedText;
          final currentAnnotation = _getHighlightForCfi(cfi);

          // Select the style
          ref.read(annotationProvider.notifier).selectStyle(style);

          // Apply annotation immediately with current color
          final color = annotationState.selectedColor;
          final opacity = style == 'highlight' ? 0.4 : 1.0;

          // Remove any existing annotation at this CFI first
          if (currentAnnotation != null) {
            _epubController.removeAnnotation(cfi);
            _removeSavedHighlight(cfi);
          }

          // Add new annotation with selected style and current color
          _epubController.addAnnotation(
            value: cfi,
            type: style,
            color: color,
            note: selectedText,
          );
          _saveHighlight(cfi, color, opacity, selectedText, type: style);
        }
      },
      borderRadius: BorderRadius.circular(15),
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: isActive ? Colors.white.withOpacity(0.2) : Colors.transparent,
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          size: 18,
          color: isActive ? variant.primaryColor : variant.iconColor,
        ),
      ),
    );
  }

  void _measureBottomSheetHeight() {
    if (_isDisposing || !mounted || _bottomSheetKey.currentContext == null)
      return;
    final RenderBox? renderBox =
        _bottomSheetKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox != null) {
      final height = renderBox.size.height;
      if (_bottomSheetHeight != height && !_isDisposing && mounted) {
        setState(() {
          _bottomSheetHeight = height;
        });
      }
    }
  }

  Widget _buildWiktionaryBottomSheetOverlay() {
    final selectionState = ref.watch(selectionStateProvider);
    final readingSettings = ref.read(readingSettingsProvider);

    return Align(
      alignment: Alignment.bottomCenter,
      child: Dismissible(
        key: Key('wiktionary_${selectionState.wiktionaryWord}'),
        direction: DismissDirection.down,
        onDismissed: (_) {
          setState(() {
            _bottomSheetHeight = null;
          });
          ref.read(selectionStateProvider.notifier).setWiktionaryWord(null);
        },
        child: Material(
          key: _bottomSheetKey,
          color: readingSettings.isDarkMode ? Colors.grey[850] : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          elevation: 8,
          child: Builder(
            builder: (context) {
              // Measure height after every build and when word changes
              final currentWord = selectionState.wiktionaryWord;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!_isDisposing && mounted) {
                  _measureBottomSheetHeight();
                }
              });
              // Also measure after a short delay to catch content loading
              Future.delayed(const Duration(milliseconds: 100), () {
                if (!_isDisposing &&
                    mounted &&
                    selectionState.wiktionaryWord == currentWord) {
                  _measureBottomSheetHeight();
                }
              });
              Future.delayed(const Duration(milliseconds: 500), () {
                if (!_isDisposing &&
                    mounted &&
                    selectionState.wiktionaryWord == currentWord) {
                  _measureBottomSheetHeight();
                }
              });
              return WiktionaryBottomSheet(
                word: selectionState.wiktionaryWord!,
                onClose: () {
                  setState(() {
                    _bottomSheetHeight = null;
                  });
                  ref
                      .read(selectionStateProvider.notifier)
                      .setWiktionaryWord(null);
                },
              );
            },
          ),
        ),
      ),
    );
  }

  void _handleTouchEvent(Map<String, dynamic> touchData) {
    // JavaScript sends normalized coordinates (0.0 to 1.0) relative to the WebView's viewport
    // Use these directly for touch zone detection
    final normalizedX = (touchData['normalizedX'] as num?)?.toDouble();
    final normalizedY = (touchData['normalizedY'] as num?)?.toDouble();

    if (normalizedX != null && normalizedY != null) {
      _handleTouchUp(normalizedX, normalizedY);

      print('Touch event (normalized): $normalizedX, $normalizedY');
    }
  }
}

// Widget that allows taps but lets long presses pass through to EPUB viewer
class _TapZoneWidget extends StatefulWidget {
  final VoidCallback onTap;
  final bool debugShowZone;
  final Color? color;

  const _TapZoneWidget({
    required this.onTap,
    this.debugShowZone = false,
    this.color,
  });

  @override
  State<_TapZoneWidget> createState() => _TapZoneWidgetState();
}

class _TapZoneWidgetState extends State<_TapZoneWidget> {
  DateTime? _tapStartTime;
  Timer? _longPressTimer;
  bool _isLongPress = false;
  Offset? _pointerDownPosition;

  @override
  void dispose() {
    _longPressTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Always use Listener with translucent behavior - this allows events to pass through
    // We just don't handle taps when it's a long press, but events still reach EPUB viewer
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        _tapStartTime = DateTime.now();
        _isLongPress = false;
        _pointerDownPosition = event.position;
        // Very short timeout - if still holding after 80ms, likely a long press
        _longPressTimer?.cancel();
        _longPressTimer = Timer(const Duration(milliseconds: 80), () {
          // If still holding, mark as long press (don't rebuild, just track state)
          if (mounted && _tapStartTime != null) {
            _isLongPress = true;
          }
        });
      },
      onPointerMove: (event) {
        // If pointer moves significantly, it's likely a drag/selection, not a tap
        if (_tapStartTime != null &&
            _pointerDownPosition != null &&
            !_isLongPress) {
          final distance = (event.position - _pointerDownPosition!).distance;
          if (distance > 10) {
            _longPressTimer?.cancel();
            _isLongPress = true;
          }
        }
      },
      onPointerUp: (event) {
        _longPressTimer?.cancel();
        if (_tapStartTime != null && !_isLongPress) {
          final duration = DateTime.now().difference(_tapStartTime!);
          // Only trigger if it was a very quick tap (< 150ms)
          if (duration < const Duration(milliseconds: 150)) {
            widget.onTap();
          }
        }
        // Reset state for next interaction
        _tapStartTime = null;
        _isLongPress = false;
        _pointerDownPosition = null;
      },
      onPointerCancel: (event) {
        _longPressTimer?.cancel();
        _tapStartTime = null;
        _isLongPress = false;
        _pointerDownPosition = null;
      },
      child: widget.debugShowZone
          ? Container(
              color:
                  widget.color?.withOpacity(0.3) ?? Colors.red.withOpacity(0.3),
            )
          : Container(color: Colors.transparent),
    );
  }
}

// Widget for dismiss overlay that allows long presses to pass through
class _DismissOverlayWidget extends StatefulWidget {
  final VoidCallback onTap;

  const _DismissOverlayWidget({required this.onTap});

  @override
  State<_DismissOverlayWidget> createState() => _DismissOverlayWidgetState();
}

class _DismissOverlayWidgetState extends State<_DismissOverlayWidget> {
  DateTime? _tapStartTime;
  Timer? _longPressTimer;
  bool _isLongPress = false;

  @override
  void dispose() {
    _longPressTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // If we detected a long press, completely remove from hit testing
    if (_isLongPress) {
      return IgnorePointer(
        ignoring: true,
        child: Container(color: Colors.transparent),
      );
    }

    // Use Listener but immediately stop participating in hit testing if it looks like a long press
    // This allows long presses to pass through to EPUB viewer immediately
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        _tapStartTime = DateTime.now();
        _isLongPress = false;
        // Very short timeout - if still holding after 100ms, likely a long press
        _longPressTimer?.cancel();
        _longPressTimer = Timer(const Duration(milliseconds: 100), () {
          // If still holding, remove ourselves from hit testing immediately
          // This allows the long press to reach EPUB viewer
          if (mounted && _tapStartTime != null) {
            // Schedule setState safely through the scheduler to avoid build scope issues
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _tapStartTime != null) {
                setState(() {
                  _isLongPress = true;
                });
              }
            });
          }
        });
      },
      onPointerUp: (event) {
        _longPressTimer?.cancel();
        if (_tapStartTime != null && !_isLongPress) {
          final duration = DateTime.now().difference(_tapStartTime!);
          // Only trigger if it was a very quick tap (< 150ms)
          if (duration < const Duration(milliseconds: 150)) {
            widget.onTap();
          }
        }
        _tapStartTime = null;
        _isLongPress = false;
      },
      onPointerCancel: (event) {
        _longPressTimer?.cancel();
        _tapStartTime = null;
        _isLongPress = false;
      },
      child: Container(color: Colors.transparent),
    );
  }
}
