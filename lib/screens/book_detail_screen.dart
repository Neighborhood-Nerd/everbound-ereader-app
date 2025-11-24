import 'dart:io';
import 'package:Everbound/services/local_database_service.dart';
import 'package:Everbound/services/book_import_service.dart';
import 'package:Everbound/services/book_metadata_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/book_model.dart';
import '../models/app_theme_model.dart';
import '../providers/my_books_providers.dart';
import '../providers/reader_providers.dart';
import '../services/logger_service.dart';
import 'reader_screen.dart';

const String _tag = 'BookDetailScreen';

class BookDetailScreen extends ConsumerStatefulWidget {
  final BookModel book;

  const BookDetailScreen({super.key, required this.book});

  @override
  ConsumerState<BookDetailScreen> createState() => _BookDetailScreenState();
}

class _BookDetailScreenState extends ConsumerState<BookDetailScreen> {
  bool _isDescriptionExpanded = false;
  LocalBook? _localBook;
  String _fileSize = 'N/A';
  bool _isLoadingMetadata = false;

  @override
  void initState() {
    super.initState();
    _loadLocalBook();
  }

  Future<void> _loadLocalBook() async {
    try {
      final dbService = LocalDatabaseService.instance;
      await dbService.initialize();
      final bookId = int.tryParse(widget.book.id);
      if (bookId != null) {
        final localBook = dbService.getBookById(bookId);
        if (mounted) {
          setState(() {
            _localBook = localBook;
          });
          // Load file size after setting local book
          _loadFileSize();
          // Fetch metadata if missing
          _fetchMetadataIfNeeded();
        }
      }
    } catch (e) {
      // Ignore errors
    }
  }

  Future<void> _fetchMetadataIfNeeded() async {
    if (_localBook == null) return;

    // Check if we need to fetch metadata (missing key fields like ISBN, description, etc.)
    final needsMetadata =
        _localBook!.isbn == null ||
        _localBook!.description == null ||
        _localBook!.publisher == null ||
        _localBook!.publishedDate == null;

    if (needsMetadata && !_isLoadingMetadata) {
      setState(() {
        _isLoadingMetadata = true;
      });

      try {
        final metadataService = BookMetadataService.instance;
        final metadata = await metadataService.fetchBookMetadata(_localBook!.title, _localBook!.author);

        if (metadata.isNotEmpty && mounted) {
          // Update the book in database with fetched metadata
          final dbService = LocalDatabaseService.instance;
          await dbService.initialize();

          final updatedBook = _localBook!.copyWith(
            publisher: metadata['publisher'] ?? _localBook!.publisher,
            publishedDate: metadata['publishedDate'] ?? _localBook!.publishedDate,
            genre: metadata['genre'] ?? _localBook!.genre,
            isbn: metadata['isbn'] ?? _localBook!.isbn,
            pageCount: metadata['pageCount'] ?? _localBook!.pageCount,
            language: metadata['language'] ?? _localBook!.language,
            description: metadata['description'] ?? _localBook!.description,
            rating: metadata['rating'] ?? _localBook!.rating,
            ratingsCount: metadata['ratingsCount'] ?? _localBook!.ratingsCount,
          );

          dbService.updateBook(updatedBook);

          if (mounted) {
            setState(() {
              _localBook = updatedBook;
              _isLoadingMetadata = false;
            });
          }
        } else if (mounted) {
          setState(() {
            _isLoadingMetadata = false;
          });
        }
      } catch (e) {
        print('Error fetching metadata: $e');
        if (mounted) {
          setState(() {
            _isLoadingMetadata = false;
          });
        }
      }
    }
  }

  Future<void> _loadFileSize() async {
    if (_localBook?.filePath != null) {
      try {
        final importService = BookImportService.instance;
        final absolutePath = await importService.resolvePath(_localBook!.filePath);
        final file = File(absolutePath);
        if (await file.exists()) {
          final sizeInBytes = await file.length();
          String sizeStr;
          if (sizeInBytes < 1024) {
            sizeStr = '${sizeInBytes}B';
          } else if (sizeInBytes < 1024 * 1024) {
            sizeStr = '${(sizeInBytes / 1024).toStringAsFixed(0)}KB';
          } else {
            sizeStr = '${(sizeInBytes / (1024 * 1024)).toStringAsFixed(1)}MB';
          }
          if (mounted) {
            setState(() {
              _fileSize = sizeStr;
            });
          }
        }
      } catch (e) {
        // Ignore errors
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final book = widget.book;
    final readingSettings = ref.watch(readingSettingsProvider);
    final selectedTheme = AppThemes.getThemeByName(readingSettings.selectedThemeName);
    final variant = selectedTheme.getVariant(readingSettings.isDarkMode);

    return Scaffold(
      backgroundColor: variant.backgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // Custom navigation bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back_ios, color: variant.secondaryTextColor),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  Expanded(
                    child: Text(
                      'Book Detail',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: variant.secondaryTextColor),
                    ),
                  ),
                  //edit button
                  IconButton(
                    icon: Icon(Icons.edit, color: variant.secondaryTextColor),
                    onPressed: () => _openEditBookDialog(context, book, variant),
                  ),
                  IconButton(
                    icon: Icon(Icons.share, color: variant.secondaryTextColor),
                    onPressed: () {
                      // Handle share action
                    },
                  ),
                ],
              ),
            ),
            // Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _buildBookCover(book),
                    const SizedBox(height: 24),
                    // Book Title and Author
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                        children: [
                          Text(
                            book.title,
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: variant.secondaryTextColor,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'By ${book.author}',
                            style: TextStyle(fontSize: 16, color: variant.secondaryTextColor.withValues(alpha: 0.7)),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 20),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Stats Row (Rating, Reviews, Pages)
                    _buildStatsRow(book, variant),
                    const SizedBox(height: 32),
                    // Metadata in two columns
                    _buildMetadataSection(book, variant),
                    const SizedBox(height: 32),
                    // Description Section
                    _buildDescriptionSection(book, variant),
                    const SizedBox(height: 100), // Space for bottom button
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _buildContinueReadingButton(context, variant),
    );
  }

  Widget _buildMetadataSection(BookModel book, ThemeVariant variant) {
    // Format date helper
    String formatDate(DateTime? date) {
      if (date == null) return 'N/A';
      final months = [
        'January',
        'February',
        'March',
        'April',
        'May',
        'June',
        'July',
        'August',
        'September',
        'October',
        'November',
        'December',
      ];
      return '${months[date.month - 1]} ${date.day}, ${date.year}';
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left column
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildMetadataItem('Publisher', _localBook?.publisher ?? 'N/A', variant),
              const SizedBox(height: 16),
              _buildMetadataItem('Updated', formatDate(_localBook?.importedAt), variant),
              const SizedBox(height: 16),
              _buildMetadataItem('Language', _localBook?.language ?? 'N/A', variant),
              const SizedBox(height: 16),
              _buildMetadataItem('Format', 'EPUB', variant),
            ],
          ),
        ),
        const SizedBox(width: 24),
        // Right column
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildMetadataItem('Published', _localBook?.publishedDate ?? 'N/A', variant),
              const SizedBox(height: 16),
              _buildMetadataItem('Added', formatDate(_localBook?.importedAt), variant),
              const SizedBox(height: 16),
              _buildMetadataItem(
                'Subjects',
                _localBook?.genre ?? (book.genres != null && book.genres!.isNotEmpty ? book.genres!.join(', ') : 'N/A'),
                variant,
              ),
              const SizedBox(height: 16),
              _buildMetadataItem('File Size', _fileSize, variant),
              const SizedBox(height: 16),
              _buildMetadataItem('ISBN', _localBook?.isbn ?? 'N/A', variant),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMetadataItem(String label, String value, ThemeVariant variant) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: variant.secondaryTextColor),
        ),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(fontSize: 14, color: variant.secondaryTextColor.withValues(alpha: 0.7))),
      ],
    );
  }

  Widget _buildDescriptionSection(BookModel book, ThemeVariant variant) {
    // Prefer description from LocalBook (from API), fallback to BookModel
    final description = _localBook?.description ?? book.description;
    if (description == null || description.isEmpty) {
      return const SizedBox.shrink();
    }

    final isLong = description.length > 150;
    final displayText = _isDescriptionExpanded || !isLong ? description : '${description.substring(0, 150)}...';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Description',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: variant.secondaryTextColor),
        ),
        const SizedBox(height: 12),
        Text(
          displayText,
          style: TextStyle(fontSize: 14, color: variant.secondaryTextColor.withValues(alpha: 0.7), height: 1.5),
        ),
        if (isLong)
          GestureDetector(
            onTap: () {
              setState(() {
                _isDescriptionExpanded = !_isDescriptionExpanded;
              });
            },
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _isDescriptionExpanded ? 'less' : 'more',
                style: TextStyle(fontSize: 14, color: variant.primaryColor, fontWeight: FontWeight.w600),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildStatsRow(BookModel book, ThemeVariant variant) {
    // Prefer metadata from LocalBook, fallback to BookModel
    final rating = _localBook?.rating != null ? double.tryParse(_localBook!.rating!) : book.rating;
    final reviewsCount = _localBook?.ratingsCount != null ? int.tryParse(_localBook!.ratingsCount!) : book.reviewsCount;
    final pages = _localBook?.pageCount != null ? int.tryParse(_localBook!.pageCount!) : book.pages;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Rating
        Row(
          children: [
            Icon(Icons.star, color: variant.primaryColor, size: 20),
            const SizedBox(width: 4),
            Text(
              rating?.toStringAsFixed(1) ?? 'N/A',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: variant.secondaryTextColor),
            ),
          ],
        ),
        const SizedBox(width: 24),
        // Reviews
        Row(
          children: [
            Icon(Icons.people, color: variant.primaryColor, size: 20),
            const SizedBox(width: 4),
            Text(
              '${reviewsCount ?? 0} Reviews',
              style: TextStyle(fontSize: 16, color: variant.secondaryTextColor.withValues(alpha: 0.7)),
            ),
          ],
        ),
        const SizedBox(width: 24),
        // Pages
        Row(
          children: [
            Icon(Icons.book, color: variant.primaryColor, size: 20),
            const SizedBox(width: 4),
            Text(
              '${pages ?? 0} Pages',
              style: TextStyle(fontSize: 16, color: variant.secondaryTextColor.withValues(alpha: 0.7)),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildContinueReadingButton(BuildContext context, ThemeVariant variant) {
    final book = widget.book;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: variant.cardColor,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -2))],
      ),
      child: SafeArea(
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () {
              // Navigate to reader screen
              logger.info(_tag, 'Opening book: ${book.title} (ID: ${book.id})');
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => ReaderScreen(book: book),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: variant.isDark ? variant.backgroundColor : variant.primaryColor,
              foregroundColor: variant.isDark ? variant.textColor : Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.book, size: 20),
                SizedBox(width: 8),
                Text('Continue Reading', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openEditBookDialog(BuildContext context, BookModel book, ThemeVariant variant) async {
    // Get current book from database to populate all fields
    final dbService = LocalDatabaseService.instance;
    await dbService.initialize();
    final bookId = int.tryParse(book.id);
    if (bookId == null) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: const Text('Error: Invalid book ID'), backgroundColor: variant.primaryColor));
      }
      return;
    }

    final databaseBook = dbService.getBookById(bookId);
    if (databaseBook == null) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Error: Book not found in database'), backgroundColor: Colors.red));
      }
      return;
    }

    // Create controllers for all editable fields
    final titleController = TextEditingController(text: databaseBook.title);
    final authorController = TextEditingController(text: databaseBook.author);
    final publisherController = TextEditingController(text: databaseBook.publisher ?? '');
    final publishedDateController = TextEditingController(text: databaseBook.publishedDate ?? '');
    final genreController = TextEditingController(text: databaseBook.genre ?? '');
    final languageController = TextEditingController(text: databaseBook.language ?? '');
    final descriptionController = TextEditingController(text: databaseBook.description ?? '');
    final isbnController = TextEditingController(text: databaseBook.isbn ?? '');
    final ratingController = TextEditingController(text: databaseBook.rating ?? '');
    final ratingsCountController = TextEditingController(text: databaseBook.ratingsCount ?? '');
    final pageCountController = TextEditingController(text: databaseBook.pageCount ?? '');

    // Show a dialog to allow the user to edit all book fields
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Book'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: const InputDecoration(labelText: 'Title'),
                autofocus: true,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: authorController,
                decoration: const InputDecoration(labelText: 'Author'),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: publisherController,
                decoration: const InputDecoration(labelText: 'Publisher'),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: publishedDateController,
                decoration: const InputDecoration(labelText: 'Published Date'),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: genreController,
                decoration: const InputDecoration(labelText: 'Genre/Subjects'),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: languageController,
                decoration: const InputDecoration(labelText: 'Language'),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: isbnController,
                decoration: const InputDecoration(labelText: 'ISBN'),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: ratingController,
                decoration: const InputDecoration(labelText: 'Rating'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: ratingsCountController,
                decoration: const InputDecoration(labelText: 'Reviews Count'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: pageCountController,
                decoration: const InputDecoration(labelText: 'Page Count'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: descriptionController,
                decoration: const InputDecoration(labelText: 'Description'),
                maxLines: 5,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Save')),
        ],
      ),
    );

    // Read controller values before disposing
    String? titleValue, authorValue, publisherValue, publishedDateValue, genreValue;
    String? languageValue, descriptionValue, isbnValue, ratingValue, ratingsCountValue, pageCountValue;

    if (confirmed == true) {
      titleValue = titleController.text.trim();
      authorValue = authorController.text.trim();
      publisherValue = publisherController.text.trim();
      publishedDateValue = publishedDateController.text.trim();
      genreValue = genreController.text.trim();
      languageValue = languageController.text.trim();
      descriptionValue = descriptionController.text.trim();
      isbnValue = isbnController.text.trim();
      ratingValue = ratingController.text.trim();
      ratingsCountValue = ratingsCountController.text.trim();
      pageCountValue = pageCountController.text.trim();
    }

    // Dispose controllers after dialog closes, using post-frame callback to avoid build scope issues
    WidgetsBinding.instance.addPostFrameCallback((_) {
      titleController.dispose();
      authorController.dispose();
      publisherController.dispose();
      publishedDateController.dispose();
      genreController.dispose();
      languageController.dispose();
      descriptionController.dispose();
      isbnController.dispose();
      ratingController.dispose();
      ratingsCountController.dispose();
      pageCountController.dispose();
    });

    if (confirmed == true && mounted) {
      try {
        // Parse numeric fields
        String? rating = ratingValue?.isEmpty ?? true ? null : ratingValue;
        String? ratingsCount = ratingsCountValue?.isEmpty ?? true ? null : ratingsCountValue;
        String? pageCount = pageCountValue?.isEmpty ?? true ? null : pageCountValue;

        // Create updated book with all fields
        final updatedBook = databaseBook.copyWith(
          title: titleValue ?? '',
          author: authorValue ?? '',
          publisher: publisherValue?.isEmpty ?? true ? null : publisherValue,
          publishedDate: publishedDateValue?.isEmpty ?? true ? null : publishedDateValue,
          genre: genreValue?.isEmpty ?? true ? null : genreValue,
          language: languageValue?.isEmpty ?? true ? null : languageValue,
          description: descriptionValue?.isEmpty ?? true ? null : descriptionValue,
          isbn: isbnValue?.isEmpty ?? true ? null : isbnValue,
          rating: rating,
          ratingsCount: ratingsCount,
          pageCount: pageCount,
        );

        // Update the book in the database
        dbService.updateBook(updatedBook);

        // Refresh the books list
        ref.read(booksRefreshProvider.notifier).state++;

        // Reload local book to refresh UI
        await _loadLocalBook();

        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Book updated successfully'), backgroundColor: Colors.green));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error updating book: $e'), backgroundColor: Colors.red));
        }
      }
    }
  }

  Widget _buildBookCover(BookModel book) {
    return Container(
      width: 150,
      height: 200,
      decoration: BoxDecoration(
        color: Colors.grey[300],
        borderRadius: BorderRadius.circular(8),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 8, offset: const Offset(0, 4))],
      ),
      child: Stack(
        children: [
          // Book cover image or placeholder
          book.coverImageUrl != null && File(book.coverImageUrl!).existsSync()
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(
                    File(book.coverImageUrl!),
                    width: double.infinity,
                    height: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Center(child: Icon(Icons.book, size: 80, color: Colors.grey[600]));
                    },
                  ),
                )
              : Center(child: Icon(Icons.book, size: 80, color: Colors.grey[600])),
          // Series banner at top
          if (book.series != null)
            Positioned(
              top: 8,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 4),
                decoration: BoxDecoration(color: Colors.brown[800]),
                child: Text(
                  book.series!.toUpperCase(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
