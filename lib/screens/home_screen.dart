import 'dart:io';
import 'package:Everbound/colors.dart';
import 'package:Everbound/models/app_theme_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/home_providers.dart';
import '../models/book_model.dart';
import '../providers/reader_providers.dart';
import '../services/logger_service.dart';
import 'book_detail_screen.dart';
import 'reader_screen.dart';

const String _tag = 'HomeScreen';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userName = ref.watch(userNameProvider);
    final readingProgressBooks = ref.watch(readingProgressBooksProvider);
    final readerChoiceBooks = ref.watch(readerChoiceBooksProvider);
    final recommendedBooks = ref.watch(recommendedBooksProvider);
    final selectedCategory = ref.watch(selectedCategoryProvider);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Content
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 20),
                    // Reading Progress Section
                    _buildReadingProgressSection(context, readingProgressBooks, ref),
                    const SizedBox(height: 32),
                    // Reader Choice Section
                    _buildReaderChoiceSection(context, readerChoiceBooks, selectedCategory, ref),
                    const SizedBox(height: 32),
                    // Recommended Section
                    _buildRecommendedSection(context, recommendedBooks),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReadingProgressSection(BuildContext context, List<BookModel> books, WidgetRef ref) {
    final readingSettings = ref.watch(readingSettingsProvider);
    final selectedTheme = AppThemes.getThemeByName(readingSettings.selectedThemeName);
    final variant = selectedTheme.getVariant(readingSettings.isDarkMode);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Continue Reading', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              TextButton(
                onPressed: () {},
                child: Text('See All', style: TextStyle(color: variant.primaryColor, fontSize: 14)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 180,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: books.length,
            itemBuilder: (context, index) {
              return _buildBookCard(context, books[index], showRating: false, goToReader: true);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildReaderChoiceSection(
    BuildContext context,
    List<BookModel> books,
    String selectedCategory,
    WidgetRef ref,
  ) {
    final categories = ['Reader Choice', 'Classic', 'Thriller', 'Romance'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              const Text('Reader Choice', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(width: 16),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: categories.map((category) {
                      final isSelected = category == selectedCategory;
                      return Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: GestureDetector(
                          onTap: () {
                            ref.read(selectedCategoryProvider.notifier).state = category;
                          },
                          child: Text(
                            category,
                            style: TextStyle(
                              fontSize: 14,
                              color: isSelected ? Colors.black : Colors.grey[600],
                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 220,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: books.length,
            itemBuilder: (context, index) {
              return _buildBookCard(context, books[index], showRating: true);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildRecommendedSection(BuildContext context, List<BookModel> books) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: const Text('Recommended', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 180,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: books.length,
            itemBuilder: (context, index) {
              return _buildBookCard(context, books[index], showRating: false);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildBookCard(BuildContext context, BookModel book, {required bool showRating, bool goToReader = false}) {
    return GestureDetector(
      onTap: () {
        // If goToReader is true and book has EPUB file path, go directly to reader
        if (goToReader && book.epubFilePath != null) {
          logger.info(_tag, 'Opening book: ${book.title} (ID: ${book.id})');
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) =>
                  ReaderScreen(book: book),
            ),
          );
        } else {
          logger.info(_tag, 'Opening book details: ${book.title} (ID: ${book.id})');
          Navigator.of(context).push(MaterialPageRoute(builder: (context) => BookDetailScreen(book: book)));
        }
      },
      child: Container(
        width: 100,
        margin: const EdgeInsets.only(right: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Book cover
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4, offset: const Offset(0, 2)),
                  ],
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
                              fit: BoxFit.fitWidth,
                              errorBuilder: (context, error, stackTrace) {
                                return Center(child: Icon(Icons.book, size: 48, color: Colors.grey[600]));
                              },
                            ),
                          )
                        : Center(child: Icon(Icons.book, size: 48, color: Colors.grey[600])),
                    // Rating badge
                    if (showRating && book.rating != null)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                          decoration: BoxDecoration(color: primaryColor, borderRadius: BorderRadius.circular(4)),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.star, color: Colors.white, size: 12),
                              const SizedBox(width: 2),
                              Text(
                                book.rating!.toStringAsFixed(1),
                                style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Book title
            Text(
              book.title,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            // Author
            Text(
              book.author,
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
