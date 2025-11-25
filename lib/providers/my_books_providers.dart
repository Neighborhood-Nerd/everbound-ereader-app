import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/book_model.dart';
import '../services/local_database_service.dart';
import '../services/book_import_service.dart';
import '../services/logger_service.dart';

const String _viewModeTag = 'ViewMode';
const String _sortByTag = 'SortBy';
const String _sortOrderTag = 'SortOrder';

// State provider for refreshing books list
final booksRefreshProvider = StateProvider<int>((ref) => 0);

// Provider for all books from database
final myBooksProvider = FutureProvider<List<BookModel>>((ref) async {
  // Watch refresh trigger
  ref.watch(booksRefreshProvider);

  final dbService = LocalDatabaseService.instance;
  await dbService.initialize();
  final localBooks = dbService.getAllBooks();

  // Convert LocalBook to BookModel
  final books = <BookModel>[];
  for (final localBook in localBooks) {
    // Convert genre string to list if available
    List<String>? genres;
    if (localBook.genre != null && localBook.genre!.isNotEmpty) {
      genres = localBook.genre!.split(',').map((g) => g.trim()).toList();
    }

    // Convert rating string to double if available
    double? rating;
    if (localBook.rating != null && localBook.rating!.isNotEmpty) {
      rating = double.tryParse(localBook.rating!);
    }

    // Convert pageCount string to int if available
    int? pages;
    if (localBook.pageCount != null && localBook.pageCount!.isNotEmpty) {
      pages = int.tryParse(localBook.pageCount!);
    }

    // Convert ratingsCount string to int if available
    int? reviewsCount;
    if (localBook.ratingsCount != null && localBook.ratingsCount!.isNotEmpty) {
      reviewsCount = int.tryParse(localBook.ratingsCount!);
    }

    // Resolve cover image path (relative to absolute)
    String? coverImageUrl;
    if (localBook.coverImagePath != null) {
      coverImageUrl = await BookImportService.instance.resolvePath(localBook.coverImagePath!);
    }

    books.add(
      BookModel(
        id: localBook.id?.toString() ?? '',
        title: localBook.title,
        author: localBook.author,
        coverImageUrl: coverImageUrl,
        progressPercentage: localBook.progressPercentage ?? 0.0,
        lastReadStatus: localBook.lastReadStatus,
        lastReadAt: localBook.lastReadAt,
        epubFilePath: localBook.filePath,
        genres: genres,
        description: localBook.description,
        rating: rating,
        pages: pages,
        reviewsCount: reviewsCount,
      ),
    );
  }

  return books;
});

final finishedBooksCountProvider = Provider<int>((ref) {
  final booksAsync = ref.watch(myBooksProvider);
  return booksAsync.when(
    data: (books) => books.where((book) => book.progressPercentage == 1.0).length,
    loading: () => 0,
    error: (_, __) => 0,
  );
});

final searchQueryProvider = StateProvider<String>((ref) => '');

final filteredMyBooksProvider = Provider<List<BookModel>>((ref) {
  final booksAsync = ref.watch(myBooksProvider);
  final query = ref.watch(searchQueryProvider);
  final sortBy = ref.watch(sortByProvider);
  final sortOrder = ref.watch(sortOrderProvider);

  return booksAsync.when(
    data: (books) {
      // Filter by search query
      var filteredBooks = books;
      if (query.isNotEmpty) {
        final lowerQuery = query.toLowerCase();
        filteredBooks = books.where((book) {
          return book.title.toLowerCase().contains(lowerQuery) || book.author.toLowerCase().contains(lowerQuery);
        }).toList();
      }

      // Sort books
      final sortedBooks = List<BookModel>.from(filteredBooks);
      sortedBooks.sort((a, b) {
        int comparison = 0;

        switch (sortBy) {
          case SortBy.title:
            comparison = a.title.toLowerCase().compareTo(b.title.toLowerCase());
            break;
          case SortBy.author:
            comparison = a.author.toLowerCase().compareTo(b.author.toLowerCase());
            break;
          case SortBy.dateRead:
            // Sort by last read time (most recent first by default)
            final aLastRead = a.lastReadAt;
            final bLastRead = b.lastReadAt;
            if (aLastRead == null && bLastRead == null) {
              // Both null - sort by progress as fallback
              final aProgress = a.progressPercentage ?? 0.0;
              final bProgress = b.progressPercentage ?? 0.0;
              comparison = bProgress.compareTo(aProgress);
            } else if (aLastRead == null) {
              comparison = 1; // Books without last read time go to end
            } else if (bLastRead == null) {
              comparison = -1; // Books without last read time go to end
            } else {
              comparison = bLastRead.compareTo(aLastRead); // Most recent first
            }
            break;
          case SortBy.dateAdded:
            // Sort by id (assuming higher id = more recent)
            final aId = int.tryParse(a.id) ?? 0;
            final bId = int.tryParse(b.id) ?? 0;
            comparison = bId.compareTo(aId);
            break;
        }

        return sortOrder == SortOrder.ascending ? comparison : -comparison;
      });

      return sortedBooks;
    },
    loading: () => [],
    error: (_, __) => [],
  );
});

// View mode provider (list or grid)
enum ViewMode { list, grid }

// Sort options
enum SortBy { title, author, dateRead, dateAdded }

enum SortOrder { ascending, descending }

// View Mode State Notifier with persistence
class ViewModeNotifier extends StateNotifier<ViewMode> {
  static const String _prefsKey = 'view_mode';

  ViewModeNotifier() : super(ViewMode.list) {
    _loadViewMode();
  }

  Future<void> _loadViewMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedMode = prefs.getString(_prefsKey);
      if (savedMode != null) {
        state = ViewMode.values.firstWhere((e) => e.toString() == savedMode, orElse: () => ViewMode.list);
      }
    } catch (e) {
      logger.error(_viewModeTag, 'Error loading view mode', e);
    }
  }

  Future<void> setViewMode(ViewMode mode) async {
    state = mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, mode.toString());
    } catch (e) {
      logger.error(_viewModeTag, 'Error saving view mode', e);
    }
  }
}

final viewModeProvider = StateNotifierProvider<ViewModeNotifier, ViewMode>((ref) {
  return ViewModeNotifier();
});

// Sort By State Notifier with persistence
class SortByNotifier extends StateNotifier<SortBy> {
  static const String _prefsKey = 'sort_by';

  SortByNotifier() : super(SortBy.dateRead) {
    _loadSortBy();
  }

  Future<void> _loadSortBy() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedSort = prefs.getString(_prefsKey);
      if (savedSort != null) {
        state = SortBy.values.firstWhere((e) => e.toString() == savedSort, orElse: () => SortBy.dateRead);
      }
    } catch (e) {
      logger.error(_sortByTag, 'Error loading sort by', e);
    }
  }

  Future<void> setSortBy(SortBy sortBy) async {
    state = sortBy;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, sortBy.toString());
    } catch (e) {
      logger.error(_sortByTag, 'Error saving sort by', e);
    }
  }
}

final sortByProvider = StateNotifierProvider<SortByNotifier, SortBy>((ref) {
  return SortByNotifier();
});

// Sort Order State Notifier with persistence
class SortOrderNotifier extends StateNotifier<SortOrder> {
  static const String _prefsKey = 'sort_order';

  SortOrderNotifier() : super(SortOrder.descending) {
    _loadSortOrder();
  }

  Future<void> _loadSortOrder() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedOrder = prefs.getString(_prefsKey);
      if (savedOrder != null) {
        state = SortOrder.values.firstWhere((e) => e.toString() == savedOrder, orElse: () => SortOrder.descending);
      }
    } catch (e) {
      logger.error(_sortOrderTag, 'Error loading sort order', e);
    }
  }

  Future<void> setSortOrder(SortOrder order) async {
    state = order;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, order.toString());
    } catch (e) {
      logger.error(_sortOrderTag, 'Error saving sort order', e);
    }
  }
}

final sortOrderProvider = StateNotifierProvider<SortOrderNotifier, SortOrder>((ref) {
  return SortOrderNotifier();
});

// Section collapse states - both can be expanded at the same time
class ExpandedSectionsState {
  final bool continueReading;
  final bool myBooks;

  const ExpandedSectionsState({
    this.continueReading = true,
    this.myBooks = true,
  });

  ExpandedSectionsState copyWith({
    bool? continueReading,
    bool? myBooks,
  }) {
    return ExpandedSectionsState(
      continueReading: continueReading ?? this.continueReading,
      myBooks: myBooks ?? this.myBooks,
    );
  }
}

// Expanded Sections State Notifier with persistence
class ExpandedSectionsNotifier extends StateNotifier<ExpandedSectionsState> {
  static const String _continueReadingKey = 'expanded_section_continue_reading';
  static const String _myBooksKey = 'expanded_section_my_books';

  ExpandedSectionsNotifier() : super(const ExpandedSectionsState()) {
    _loadExpandedSections();
  }

  Future<void> _loadExpandedSections() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final continueReading = prefs.getBool(_continueReadingKey) ?? true;
      final myBooks = prefs.getBool(_myBooksKey) ?? true;
      state = ExpandedSectionsState(
        continueReading: continueReading,
        myBooks: myBooks,
      );
    } catch (e) {
      logger.error('ExpandedSections', 'Error loading expanded sections', e);
    }
  }

  Future<void> setContinueReading(bool expanded) async {
    state = state.copyWith(continueReading: expanded);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_continueReadingKey, expanded);
    } catch (e) {
      logger.error('ExpandedSections', 'Error saving continue reading state', e);
    }
  }

  Future<void> setMyBooks(bool expanded) async {
    state = state.copyWith(myBooks: expanded);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_myBooksKey, expanded);
    } catch (e) {
      logger.error('ExpandedSections', 'Error saving my books state', e);
    }
  }

  Future<void> setBoth(bool expanded) async {
    state = state.copyWith(
      continueReading: expanded,
      myBooks: expanded,
    );
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_continueReadingKey, expanded);
      await prefs.setBool(_myBooksKey, expanded);
    } catch (e) {
      logger.error('ExpandedSections', 'Error saving both sections state', e);
    }
  }
}

final expandedSectionsProvider = StateNotifierProvider<ExpandedSectionsNotifier, ExpandedSectionsState>((ref) {
  return ExpandedSectionsNotifier();
});
