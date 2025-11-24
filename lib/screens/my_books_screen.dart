import 'dart:io';
import 'package:Everbound/models/app_theme_model.dart';
import 'package:Everbound/providers/reader_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import '../providers/my_books_providers.dart';
import '../models/book_model.dart';
import '../services/book_import_service.dart';
import '../services/book_import_exceptions.dart';
import '../services/logger_service.dart';
import 'book_detail_screen.dart';
import 'reader_screen.dart';
import 'file_sources_screen.dart';
import 'test_epub_viewer.dart';

const String _tag = 'MyBooksScreen';

class MyBooksScreen extends ConsumerStatefulWidget {
  const MyBooksScreen({super.key});

  @override
  ConsumerState<MyBooksScreen> createState() => _MyBooksScreenState();
}

class _MyBooksScreenState extends ConsumerState<MyBooksScreen> {
  final TextEditingController _searchController = TextEditingController();
  final MenuController _filterMenuController = MenuController();
  final MenuController _optionsMenuController = MenuController();
  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _importBook() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['epub'],
      );

      if (result != null && result.files.single.path != null) {
        final filePath = result.files.single.path!;

        // Show loading dialog
        if (!mounted) return;
        final navigator = Navigator.of(context);
        final scaffoldMessenger = ScaffoldMessenger.of(context);
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => const Center(
            child: Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Importing book...'),
                  ],
                ),
              ),
            ),
          ),
        );

        try {
          // Import the book
          final importService = BookImportService.instance;
          await importService.importEpubFile(filePath);

          // Refresh the books list from database
          ref.read(booksRefreshProvider.notifier).state++;

          // Close loading dialog
          if (mounted && navigator.canPop()) {
            navigator.pop();
          }

          // Show success message
          if (mounted) {
            scaffoldMessenger.showSnackBar(
              const SnackBar(
                content: Text('Successfully imported book'),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 2),
              ),
            );
          }
        } catch (e) {
          // Close loading dialog
          if (mounted && navigator.canPop()) {
            navigator.pop();
          }

          // Show error as alert dialog with friendly message
          if (mounted) {
            String title = 'Import Error';
            String message = 'Unable to import book';

            if (e is DuplicateBookException) {
              title = 'Already in Library';
              message = e.toString();
            } else if (e is BookFileNotFoundException) {
              title = 'File Not Found';
              message = e.toString();
            } else if (e is InvalidEpubException) {
              title = 'Invalid File';
              message = e.toString();
            } else if (e is MetadataExtractionException) {
              title = 'Read Error';
              message = e.toString();
            } else if (e is BookImportException) {
              title = 'Import Failed';
              message = e.toString();
            } else {
              // Fallback for unexpected errors
              message = 'An unexpected error occurred. Please try again.';
            }

            showDialog(
              context: context,
              builder: (dialogContext) => AlertDialog(
                title: Text(title),
                content: Text(message),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('OK'),
                  ),
                ],
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        final scaffoldMessenger = ScaffoldMessenger.of(context);
        scaffoldMessenger.showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final books = ref.watch(filteredMyBooksProvider);
    final searchQuery = ref.watch(searchQueryProvider);
    final viewMode = ref.watch(viewModeProvider);

    final readingSettings = ref.watch(readingSettingsProvider);
    final selectedTheme = AppThemes.getThemeByName(
      readingSettings.selectedThemeName,
    );
    final variant = selectedTheme.getVariant(readingSettings.isDarkMode);

    return Scaffold(
      // floatingActionButton: FloatingActionButton(
      //   onPressed: () {
      //     // Test button - navigate to test viewer with Project Gutenberg EPUB
      //     Navigator.of(context).push(MaterialPageRoute(builder: (context) => const TestEpubViewerPage()));
      //   },
      //   child: const Icon(Icons.bug_report),
      //   tooltip: 'Test EPUB Viewer',
      // ),
      appBar: AppBar(
        toolbarHeight: 80,
        surfaceTintColor:
            Colors.transparent, // Material 3: removes tint overlay
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Text(
          'My Books',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: variant.secondaryTextColor,
          ),
        ),
        actions: [
          MenuAnchor(
            controller: _filterMenuController,
            alignmentOffset: const Offset(-100, 24),
            style: MenuStyle(
              alignment: Alignment.bottomCenter,
              shape: WidgetStateProperty.all(
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              padding: WidgetStateProperty.all(
                EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
            ),
            builder:
                (
                  BuildContext context,
                  MenuController controller,
                  Widget? child,
                ) {
                  return IconButton(
                    icon: Icon(
                      Icons.filter_list,
                      color: variant.secondaryTextColor,
                    ),
                    onPressed: () {
                      if (controller.isOpen) {
                        controller.close();
                      } else {
                        controller.open();
                      }
                    },
                    tooltip: 'Filter & Sort',
                  );
                },
            menuChildren: [
              // View Mode Section
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Text(
                  'View',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: variant.secondaryTextColor.withValues(alpha: 0.6),
                  ),
                ),
              ),
              MenuItemButton(
                leadingIcon: ref.watch(viewModeProvider) == ViewMode.list
                    ? Icon(Icons.check, size: 20, color: variant.primaryColor)
                    : const SizedBox(width: 20),
                onPressed: () {
                  ref
                      .read(viewModeProvider.notifier)
                      .setViewMode(ViewMode.list);
                },
                child: Text(
                  'List',
                  style: TextStyle(color: variant.secondaryTextColor),
                ),
              ),
              MenuItemButton(
                leadingIcon: ref.watch(viewModeProvider) == ViewMode.grid
                    ? Icon(Icons.check, size: 20, color: variant.primaryColor)
                    : const SizedBox(width: 20),
                onPressed: () {
                  ref
                      .read(viewModeProvider.notifier)
                      .setViewMode(ViewMode.grid);
                },
                child: Text(
                  'Grid',
                  style: TextStyle(color: variant.secondaryTextColor),
                ),
              ),
              Divider(color: variant.secondaryTextColor.withValues(alpha: 0.2)),
              // Sort By Section
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Text(
                  'Sort by',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: variant.secondaryTextColor.withValues(alpha: 0.6),
                  ),
                ),
              ),
              MenuItemButton(
                leadingIcon: ref.watch(sortByProvider) == SortBy.title
                    ? Icon(Icons.check, size: 20, color: variant.primaryColor)
                    : const SizedBox(width: 20),
                onPressed: () {
                  ref.read(sortByProvider.notifier).setSortBy(SortBy.title);
                },
                child: Text(
                  'Title',
                  style: TextStyle(color: variant.secondaryTextColor),
                ),
              ),
              MenuItemButton(
                leadingIcon: ref.watch(sortByProvider) == SortBy.author
                    ? Icon(Icons.check, size: 20, color: variant.primaryColor)
                    : const SizedBox(width: 20),
                onPressed: () {
                  ref.read(sortByProvider.notifier).setSortBy(SortBy.author);
                },
                child: Text(
                  'Author',
                  style: TextStyle(color: variant.secondaryTextColor),
                ),
              ),
              MenuItemButton(
                leadingIcon: ref.watch(sortByProvider) == SortBy.dateRead
                    ? Icon(Icons.check, size: 20, color: variant.primaryColor)
                    : const SizedBox(width: 20),
                onPressed: () {
                  ref.read(sortByProvider.notifier).setSortBy(SortBy.dateRead);
                },
                child: Text(
                  'Date Read',
                  style: TextStyle(color: variant.secondaryTextColor),
                ),
              ),
              MenuItemButton(
                leadingIcon: ref.watch(sortByProvider) == SortBy.dateAdded
                    ? Icon(Icons.check, size: 20, color: variant.primaryColor)
                    : const SizedBox(width: 20),
                onPressed: () {
                  ref.read(sortByProvider.notifier).setSortBy(SortBy.dateAdded);
                },
                child: Text(
                  'Date Added',
                  style: TextStyle(color: variant.secondaryTextColor),
                ),
              ),
              Divider(color: variant.secondaryTextColor.withValues(alpha: 0.2)),
              // Sort Order
              MenuItemButton(
                leadingIcon: ref.watch(sortOrderProvider) == SortOrder.ascending
                    ? Icon(Icons.check, size: 20, color: variant.primaryColor)
                    : const SizedBox(width: 20),
                onPressed: () {
                  ref
                      .read(sortOrderProvider.notifier)
                      .setSortOrder(SortOrder.ascending);
                },
                child: Text(
                  'Ascending',
                  style: TextStyle(color: variant.secondaryTextColor),
                ),
              ),
              MenuItemButton(
                leadingIcon:
                    ref.watch(sortOrderProvider) == SortOrder.descending
                    ? Icon(Icons.check, size: 20, color: variant.primaryColor)
                    : const SizedBox(width: 20),
                onPressed: () {
                  ref
                      .read(sortOrderProvider.notifier)
                      .setSortOrder(SortOrder.descending);
                },
                child: Text(
                  'Descending',
                  style: TextStyle(color: variant.secondaryTextColor),
                ),
              ),
            ],
          ),

          MenuAnchor(
            controller: _optionsMenuController,
            alignmentOffset: const Offset(-155, 24),
            builder:
                (
                  BuildContext context,
                  MenuController controller,
                  Widget? child,
                ) {
                  return IconButton(
                    icon: Icon(
                      Icons.more_vert,
                      color: variant.secondaryTextColor,
                    ),
                    onPressed: () {
                      if (controller.isOpen) {
                        controller.close();
                      } else {
                        controller.open();
                      }
                    },
                    tooltip: 'Options',
                  );
                },
            style: MenuStyle(
              alignment: Alignment.bottomCenter,
              shape: WidgetStateProperty.all(
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              padding: WidgetStateProperty.all(
                EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
            ),
            menuChildren: [
              MenuItemButton(
                leadingIcon: Icon(
                  Icons.add_circle_outline,
                  color: variant.secondaryTextColor,
                ),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const FileSourcesScreen(),
                    ),
                  );
                },
                child: Text(
                  'File Sources',
                  style: TextStyle(color: variant.secondaryTextColor),
                ),
              ),
              MenuItemButton(
                leadingIcon: Icon(
                  Icons.file_upload_outlined,
                  color: variant.secondaryTextColor,
                ),
                onPressed: () {
                  _importBook();
                },
                child: Text(
                  'Add File',
                  style: TextStyle(color: variant.secondaryTextColor),
                ),
              ),
            ],
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Search Bar
            Padding(
              padding: const EdgeInsets.only(
                left: 20,
                right: 20,
                bottom: 16,
                top: 16,
              ),
              child: _buildSearchBar(context, ref, searchQuery),
            ),
            // Reading Progress Section (moved from home screen)
            _buildReadingProgressSection(context, ref),
            const SizedBox(height: 8),
            // My Books Section (collapsible)
            _buildMyBooksSection(context, ref, books, viewMode, variant),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar(BuildContext context, WidgetRef ref, String query) {
    final readingSettings = ref.watch(readingSettingsProvider);
    final selectedTheme = AppThemes.getThemeByName(
      readingSettings.selectedThemeName,
    );
    final variant = selectedTheme.getVariant(readingSettings.isDarkMode);

    return Container(
      decoration: BoxDecoration(
        color: variant.cardColor.withValues(alpha: 1.0),
        borderRadius: BorderRadius.circular(12),
      ),
      child: TextField(
        controller: _searchController,
        onChanged: (value) {
          ref.read(searchQueryProvider.notifier).state = value;
        },
        decoration: InputDecoration(
          hintText: 'Search by title or author',
          hintStyle: TextStyle(
            color: variant.secondaryTextColor.withValues(alpha: 0.8),
          ),
          prefixIcon: Icon(Icons.search, color: variant.secondaryTextColor),
          suffixIcon: query.isNotEmpty
              ? IconButton(
                  icon: Icon(Icons.clear, color: variant.secondaryTextColor),
                  onPressed: () {
                    _searchController.clear();
                    ref.read(searchQueryProvider.notifier).state = '';
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
        ),
      ),
    );
  }

  Widget _buildBookItem(
    BuildContext context,
    BookModel book,
    int index,
    ThemeVariant variant,
  ) {
    final readingSettings = ref.watch(readingSettingsProvider);
    final selectedTheme = AppThemes.getThemeByName(
      readingSettings.selectedThemeName,
    );
    final variant = selectedTheme.getVariant(readingSettings.isDarkMode);

    final progress = book.progressPercentage ?? 0.0;
    final percentage = (progress * 100).toInt();
    final bookId = int.tryParse(book.id);

    return Container(
      height: 160,
      padding: const EdgeInsets.only(bottom: 16),
      child: Slidable(
        key: ValueKey(book.id),
        endActionPane: ActionPane(
          motion: const BehindMotion(),
          extentRatio: 0.4,
          children: [
            //Edit book
            SlidableAction(
              borderRadius: BorderRadius.circular(8),
              onPressed: (context) => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => BookDetailScreen(book: book),
                ),
              ),
              backgroundColor: variant.primaryColor,
              foregroundColor: Colors.white,
              icon: Icons.visibility,
              label: 'View',
            ),
            SlidableAction(
              borderRadius: BorderRadius.circular(8),
              onPressed: (context) => _deleteBook(context, book, bookId),
              backgroundColor: const Color(0xFFFE4A49),
              foregroundColor: Colors.white,
              icon: Icons.delete,
              label: 'Delete',
            ),
          ],
        ),
        child: GestureDetector(
          onTap: () {
            // If book has EPUB file path, go directly to reader, otherwise show details
            if (book.epubFilePath != null) {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => ReaderScreen(book: book),
                ),
              );
            } else {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => BookDetailScreen(book: book),
                ),
              );
            }
          },
          child: Container(
            decoration: BoxDecoration(
              color: variant.cardColor,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Book Cover
                  Container(
                    width: 80,
                    height: 120,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child:
                        book.coverImageUrl != null &&
                            File(book.coverImageUrl!).existsSync()
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.file(
                              File(book.coverImageUrl!),
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return Icon(
                                  Icons.book,
                                  size: 40,
                                  color: Colors.grey[600],
                                );
                              },
                            ),
                          )
                        : Icon(Icons.book, size: 40, color: Colors.grey[600]),
                  ),
                  const SizedBox(width: 16),
                  // Book Details
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Title
                        RichText(
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          text: TextSpan(
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: variant.secondaryTextColor,
                            ),
                            children: [
                              TextSpan(text: book.title),
                              if (book.series != null)
                                TextSpan(
                                  text: ' (${book.series})',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.normal,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 4),
                        // Author
                        Text(
                          'By ${book.author}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            color: variant.secondaryTextColor.withValues(
                              alpha: 0.7,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Progress Bar
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: progress,
                                minHeight: 6,
                                backgroundColor: variant.backgroundColor
                                    .withValues(alpha: 0.3),
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  variant.primaryColor,
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            // Percentage and Status
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '$percentage%',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: variant.secondaryTextColor,
                                  ),
                                ),
                                if (book.lastReadStatus != null)
                                  Flexible(
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.access_time,
                                          size: 14,
                                          color: Colors.grey[600],
                                        ),
                                        const SizedBox(width: 4),
                                        Flexible(
                                          child: Text(
                                            book.lastReadStatus!,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey[600],
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGridBookItem(
    BuildContext context,
    BookModel book,
    ThemeVariant variant,
  ) {
    final bookId = int.tryParse(book.id);

    return GestureDetector(
      onTap: () {
        // If book has EPUB file path, go directly to reader, otherwise show details
        if (book.epubFilePath != null) {
          logger.info(_tag, 'Opening book: ${book.title} (ID: ${book.id})');
          Navigator.of(context).push(
            MaterialPageRoute(builder: (context) => ReaderScreen(book: book)),
          );
        } else {
          logger.info(_tag, 'Opening book details: ${book.title} (ID: ${book.id})');
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => BookDetailScreen(book: book),
            ),
          );
        }
      },
      onLongPress: () {
        _showGridBookMenu(context, book, bookId, variant);
      },
      child: Container(
        decoration: BoxDecoration(
          color: variant.cardColor,
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Book Cover
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(8),
                    topRight: Radius.circular(8),
                  ),
                ),
                child:
                    book.coverImageUrl != null &&
                        File(book.coverImageUrl!).existsSync()
                    ? ClipRRect(
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(8),
                          topRight: Radius.circular(8),
                        ),
                        child: Image.file(
                          File(book.coverImageUrl!),
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Icon(
                              Icons.book,
                              size: 40,
                              color: Colors.grey[600],
                            );
                          },
                        ),
                      )
                    : Icon(Icons.book, size: 40, color: Colors.grey[600]),
              ),
            ),
            // Book Details
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title
                  Text(
                    book.title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: variant.secondaryTextColor,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  // Author
                  Text(
                    book.author,
                    style: TextStyle(
                      fontSize: 11,
                      color: variant.secondaryTextColor.withValues(alpha: 0.7),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showGridBookMenu(
    BuildContext context,
    BookModel book,
    int? bookId,
    ThemeVariant variant,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.3),
      builder: (bottomSheetContext) {
        return Container(
          margin: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Action buttons container
              Container(
                decoration: BoxDecoration(
                  color: variant.cardColor,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildBottomSheetAction(
                      iconColor: variant.secondaryTextColor,
                      icon: Icons.open_in_new_rounded,
                      label: 'Open',
                      onTap: () {
                        Navigator.pop(bottomSheetContext);
                        if (book.epubFilePath != null) {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => ReaderScreen(book: book),
                            ),
                          );
                        }
                      },
                    ),
                    // _buildBottomSheetAction(
                    //   iconColor: variant.secondaryTextColor,
                    //   icon: Icons.folder_open_rounded,
                    //   label: 'Group',
                    //   onTap: () {
                    //     Navigator.pop(bottomSheetContext);
                    //     // TODO: Implement group functionality
                    //   },
                    // ),
                    _buildBottomSheetAction(
                      iconColor: variant.secondaryTextColor,
                      icon: Icons.info_outline_rounded,
                      label: 'Details',
                      onTap: () {
                        Navigator.pop(bottomSheetContext);
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => BookDetailScreen(book: book),
                          ),
                        );
                      },
                    ),
                    _buildBottomSheetAction(
                      iconColor: variant.secondaryTextColor,
                      icon: Icons.delete_outline_rounded,
                      label: 'Delete',
                      isDestructive: true,
                      onTap: () {
                        Navigator.pop(bottomSheetContext);
                        _deleteBook(context, book, bookId);
                      },
                    ),
                    _buildBottomSheetAction(
                      iconColor: variant.secondaryTextColor,
                      icon: Icons.close_rounded,
                      label: 'Cancel',
                      onTap: () {
                        Navigator.pop(bottomSheetContext);
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBottomSheetAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool isDestructive = false,
    Color iconColor = Colors.white,
  }) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          splashColor: (isDestructive ? Colors.red : iconColor).withOpacity(
            0.1,
          ),
          highlightColor: (isDestructive ? Colors.red : iconColor).withOpacity(
            0.05,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  color: isDestructive ? Colors.red : iconColor,
                  size: 24,
                ),
                const SizedBox(height: 8),
                Text(
                  label,
                  style: TextStyle(
                    color: isDestructive ? Colors.red : iconColor,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReadingProgressSection(BuildContext context, WidgetRef ref) {
    final readingSettings = ref.watch(readingSettingsProvider);
    final selectedTheme = AppThemes.getThemeByName(
      readingSettings.selectedThemeName,
    );
    final variant = selectedTheme.getVariant(readingSettings.isDarkMode);
    final expandedSection = ref.watch(expandedSectionProvider);
    final isCollapsed = expandedSection != ExpandedSection.continueReading;
    final searchQuery = ref.watch(searchQueryProvider);

    // Get books with reading progress and filter by search query
    final booksAsync = ref.watch(myBooksProvider);
    final readingProgressBooks = booksAsync.when(
      data: (books) {
        var filteredBooks = books
            .where((book) => (book.progressPercentage ?? 0.0) > 0.0)
            .toList();

        // Apply search filter if query is not empty
        if (searchQuery.isNotEmpty) {
          final lowerQuery = searchQuery.toLowerCase();
          filteredBooks = filteredBooks.where((book) {
            return book.title.toLowerCase().contains(lowerQuery) ||
                book.author.toLowerCase().contains(lowerQuery);
          }).toList();
        }

        return filteredBooks;
      },
      loading: () => <BookModel>[],
      error: (_, __) => <BookModel>[],
    );

    if (readingProgressBooks.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: InkWell(
            splashColor: variant.backgroundColor,
            highlightColor: variant.backgroundColor,
            onTap: () {
              ref.read(expandedSectionProvider.notifier).state = isCollapsed
                  ? ExpandedSection.continueReading
                  : ExpandedSection.none;
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Continue Reading',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: variant.secondaryTextColor,
                    ),
                  ),
                  Icon(
                    isCollapsed ? Icons.expand_more : Icons.expand_less,
                    color: variant.secondaryTextColor,
                  ),
                ],
              ),
            ),
          ),
        ),
        ClipRect(
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeInOut,
            heightFactor: isCollapsed ? 0.0 : 1.0,
            alignment: Alignment.topCenter,
            child: Column(
              children: [
                const SizedBox(height: 16),
                SizedBox(
                  height: 180,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: readingProgressBooks.length,
                    itemBuilder: (context, index) {
                      return _buildBookCard(
                        context,
                        readingProgressBooks[index],
                        variant,
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMyBooksSection(
    BuildContext context,
    WidgetRef ref,
    List<BookModel> books,
    ViewMode viewMode,
    ThemeVariant variant,
  ) {
    final expandedSection = ref.watch(expandedSectionProvider);
    final isCollapsed = expandedSection != ExpandedSection.myBooks;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: InkWell(
            splashColor: variant.backgroundColor,
            highlightColor: variant.backgroundColor,
            onTap: () {
              ref.read(expandedSectionProvider.notifier).state = isCollapsed
                  ? ExpandedSection.myBooks
                  : ExpandedSection.none;
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'My Books',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: variant.secondaryTextColor,
                    ),
                  ),
                  Icon(
                    isCollapsed ? Icons.expand_more : Icons.expand_less,
                    color: variant.secondaryTextColor,
                  ),
                ],
              ),
            ),
          ),
        ),
        ClipRect(
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeInOut,
            heightFactor: isCollapsed ? 0.0 : 1.0,
            alignment: Alignment.topCenter,
            child: Column(
              children: [
                const SizedBox(height: 8),
                books.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(40),
                        child: Text(
                          'No books found',
                          style: TextStyle(
                            color: variant.secondaryTextColor.withValues(
                              alpha: 0.6,
                            ),
                          ),
                        ),
                      )
                    : viewMode == ViewMode.list
                    ? Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: books.length,
                          itemBuilder: (context, index) {
                            return _buildBookItem(
                              context,
                              books[index],
                              index,
                              variant,
                            );
                          },
                        ),
                      )
                    : Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                childAspectRatio: 0.55,
                                crossAxisSpacing: 16,
                                mainAxisSpacing: 16,
                              ),
                          itemCount: books.length,
                          itemBuilder: (context, index) {
                            return _buildGridBookItem(
                              context,
                              books[index],
                              variant,
                            );
                          },
                        ),
                      ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBookCard(
    BuildContext context,
    BookModel book,
    ThemeVariant variant,
  ) {
    final bookId = int.tryParse(book.id);

    return GestureDetector(
      onTap: () {
        if (book.epubFilePath != null) {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (context) => ReaderScreen(book: book)),
          );
        } else {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => BookDetailScreen(book: book),
            ),
          );
        }
      },
      child: Container(
        width: 120,
        margin: const EdgeInsets.only(right: 16),
        decoration: BoxDecoration(
          color: variant.cardColor,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Book cover
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child:
                      book.coverImageUrl != null &&
                          File(book.coverImageUrl!).existsSync()
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(
                            File(book.coverImageUrl!),
                            width: double.infinity,
                            height: double.infinity,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Center(
                                child: Icon(
                                  Icons.book,
                                  size: 48,
                                  color: Colors.grey[600],
                                ),
                              );
                            },
                          ),
                        )
                      : Center(
                          child: Icon(
                            Icons.book,
                            size: 48,
                            color: Colors.grey[600],
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 8),
              // Progress bar with percentage
              Row(
                children: [
                  Text(
                    '${((book.progressPercentage ?? 0.0) * 100).toInt()}%',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: variant.secondaryTextColor,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: book.progressPercentage ?? 0.0,
                        minHeight: 4,
                        backgroundColor: variant.backgroundColor.withValues(
                          alpha: 0.3,
                        ),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          variant.primaryColor,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // // Book title
              // Text(
              //   book.title,
              //   style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: variant.secondaryTextColor),
              //   maxLines: 1,
              //   overflow: TextOverflow.ellipsis,
              // ),
              // const SizedBox(height: 4),
              // // Author
              // Text(
              //   book.author,
              //   style: TextStyle(fontSize: 11, color: variant.secondaryTextColor.withValues(alpha: 0.7)),
              //   maxLines: 1,
              //   overflow: TextOverflow.ellipsis,
              // ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _deleteBook(
    BuildContext context,
    BookModel book,
    int? bookId,
  ) async {
    // Capture ScaffoldMessenger before any async operations
    if (!mounted) return;
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    if (bookId == null) {
      scaffoldMessenger.showSnackBar(
        const SnackBar(
          content: Text('Cannot delete book: Invalid book ID'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Book'),
        content: Text(
          'Are you sure you want to delete "${book.title}"? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        final importService = BookImportService.instance;
        await importService.deleteImportedBook(bookId);

        // Refresh the books list
        ref.read(booksRefreshProvider.notifier).state++;

        if (mounted) {
          scaffoldMessenger.showSnackBar(
            SnackBar(
              content: Text('"${book.title}" has been deleted'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          scaffoldMessenger.showSnackBar(
            SnackBar(
              content: Text('Error deleting book: $e'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    }
  }
}
