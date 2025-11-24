import 'dart:io' as io;
import 'dart:convert';
import 'package:path/path.dart' as path;
import 'package:epub_plus/epub_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'local_database_service.dart';
import '../utils/md5_utils.dart';
import 'book_import_exceptions.dart';

class BookImportService {
  static final BookImportService instance = BookImportService._internal();
  factory BookImportService() => instance;
  BookImportService._internal();

  /// Get cache directory for storing imported books
  Future<io.Directory> getCacheDirectory() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final booksCacheDir = io.Directory(
        path.join(appDir.path, 'Everbound', 'books'),
      );

      if (!await booksCacheDir.exists()) {
        await booksCacheDir.create(recursive: true);
      }

      return booksCacheDir;
    } catch (e) {
      // Fallback to temporary directory if path_provider fails
      print('Error getting application documents directory, using temp: $e');
      final tempDir = io.Directory.systemTemp;
      final booksCacheDir = io.Directory(
        path.join(tempDir.path, 'Everbound', 'books'),
      );

      if (!await booksCacheDir.exists()) {
        await booksCacheDir.create(recursive: true);
      }

      return booksCacheDir;
    }
  }

  /// Resolve relative path to absolute path using current cache directory
  /// This handles iOS container ID changes by always using the current cache directory
  Future<String> resolvePath(String relativePath) async {
    final cacheDir = await getCacheDirectory();
    return path.join(cacheDir.path, relativePath);
  }

  /// Import an EPUB file to cache and extract metadata
  Future<LocalBook> importEpubFile(String sourcePath) async {
    try {
      final sourceFile = io.File(sourcePath);
      if (!await sourceFile.exists()) {
        throw BookFileNotFoundException(sourcePath);
      }

      // Calculate partial MD5 checksum FIRST to check for duplicates before copying
      String? partialMd5Checksum;
      try {
        partialMd5Checksum = computePartialMD5(sourcePath);
        print('Calculated partial MD5 checksum: $partialMd5Checksum');

        // Check if book with same MD5 already exists
        final dbService = LocalDatabaseService.instance;
        await dbService.initialize();
        final existingBook = dbService.getBookByPartialMd5(partialMd5Checksum);

        if (existingBook != null) {
          throw DuplicateBookException(existingBook.title, existingBook.author);
        }
      } catch (e) {
        // If it's our custom exception, rethrow it
        if (e is DuplicateBookException) {
          rethrow;
        }
        print('Error calculating partial MD5 checksum: $e');
        // Continue without MD5 check if calculation fails
        partialMd5Checksum = null;
      }

      // Get cache directory
      final cacheDir = await getCacheDirectory();

      // Generate unique directory name for this book
      final fileName = path.basename(sourcePath);
      final fileExtension = path.extension(fileName);
      final baseName = path.basenameWithoutExtension(fileName);
      final timestamp = DateTime.now().millisecondsSinceEpoch;

      // Create a sanitized directory name (remove invalid characters)
      final sanitizedBaseName = baseName.replaceAll(
        RegExp(r'[<>:"/\\|?*]'),
        '_',
      );
      final bookDirName = '${sanitizedBaseName}_$timestamp';
      final bookDir = io.Directory(path.join(cacheDir.path, bookDirName));

      // Create the book directory
      if (!await bookDir.exists()) {
        await bookDir.create(recursive: true);
      }

      // Copy EPUB file to book directory
      final epubFileName = 'book$fileExtension';
      final epubPath = path.join(bookDir.path, epubFileName);
      await sourceFile.copy(epubPath);

      // Extract metadata and cover image from EPUB
      final metadata = await _extractMetadata(epubPath, bookDir);

      // Extract and save cover image
      String? coverImagePath;
      try {
        coverImagePath = await _extractCoverImage(epubPath, bookDir, timestamp);
      } catch (e) {
        print('Error extracting cover image: $e');
        // Continue without cover image
      }

      // Note: partialMd5Checksum was already calculated earlier for duplicate detection

      // Convert to relative path for storage (handles iOS container ID changes)
      final relativePath = path.relative(epubPath, from: cacheDir.path);
      final relativeCoverPath = coverImagePath != null
          ? path.relative(coverImagePath, from: cacheDir.path)
          : null;

      // Create LocalBook object with relative paths and all metadata
      final book = LocalBook(
        title: metadata['title'] ?? baseName,
        author: metadata['author'] ?? 'Unknown Author',
        filePath: relativePath, // Store relative path
        originalFileName: fileName,
        coverImagePath: relativeCoverPath, // Store relative path
        importedAt: DateTime.now(),
        partialMd5Checksum: partialMd5Checksum,
        publisher: metadata['publisher'],
        publishedDate: metadata['publishedDate'],
        genre: metadata['genre'],
        isbn: metadata['isbn'],
        pageCount: metadata['pageCount'],
        language: metadata['language'],
        description: metadata['description'],
        rating: metadata['rating'],
        ratingsCount: metadata['ratingsCount'],
      );

      // Save to database
      final dbService = LocalDatabaseService.instance;
      await dbService.initialize();
      final bookId = dbService.insertBook(book);

      // Return book with ID and all metadata
      return LocalBook(
        id: bookId,
        title: book.title,
        author: book.author,
        filePath: book.filePath,
        originalFileName: book.originalFileName,
        coverImagePath: book.coverImagePath,
        importedAt: book.importedAt,
        progressPercentage: book.progressPercentage,
        lastReadStatus: book.lastReadStatus,
        partialMd5Checksum: book.partialMd5Checksum,
        publisher: book.publisher,
        publishedDate: book.publishedDate,
        genre: book.genre,
        isbn: book.isbn,
        pageCount: book.pageCount,
        language: book.language,
        description: book.description,
        rating: book.rating,
        ratingsCount: book.ratingsCount,
      );
    } catch (e) {
      print('Error importing book: $e');

      // Rethrow custom exceptions as-is
      if (e is DuplicateBookException ||
          e is BookFileNotFoundException ||
          e is InvalidEpubException ||
          e is MetadataExtractionException ||
          e is BookImportException) {
        rethrow;
      }

      // Wrap other exceptions in a user-friendly message
      throw BookImportException(
        'Unable to import this book. Please make sure it\'s a valid EPUB file.',
      );
    }
  }

  /// Extract cover image from EPUB file
  Future<String?> _extractCoverImage(
    String epubPath,
    io.Directory bookDir,
    int timestamp,
  ) async {
    try {
      // Read the EPUB file into memory
      final file = io.File(epubPath);
      final bytes = await file.readAsBytes();

      // Parse the EPUB book using epub_plus
      final epubBook = await EpubReader.readBook(bytes);

      // Try to get cover image from content/images
      // epub_plus stores images in the content map
      final images = epubBook.content?.images;
      if (images != null && images.isNotEmpty) {
        // Use the first image as cover, or try to find a cover-specific image
        for (final imageEntry in images.entries) {
          final imageFile = imageEntry.value;
          final imageBytes = imageFile.content;
          if (imageBytes != null && imageBytes.isNotEmpty) {
            // Determine file extension from image file name or content type
            String extension = '.jpg';
            final fileName = imageEntry.key.toLowerCase();
            if (fileName.endsWith('.png')) {
              extension = '.png';
            } else if (fileName.endsWith('.gif')) {
              extension = '.gif';
            } else if (fileName.endsWith('.webp')) {
              extension = '.webp';
            } else if (fileName.endsWith('.jpeg') ||
                fileName.endsWith('.jpg')) {
              extension = '.jpg';
            }

            // Save cover image to book directory
            final coverFileName = 'cover$extension';
            final coverPath = path.join(bookDir.path, coverFileName);
            final coverFile = io.File(coverPath);
            await coverFile.writeAsBytes(imageBytes);
            return coverPath;
          }
        }
      }

      // If no image found in content, return null
      return null;
    } catch (e) {
      print('Error extracting cover image: $e');
      return null;
    }
  }

  /// Extract metadata from EPUB file using epub_plus
  Future<Map<String, String>> _extractMetadata(
    String epubPath,
    io.Directory bookDir,
  ) async {
    try {
      // Read the EPUB file into memory
      final file = io.File(epubPath);
      final bytes = await file.readAsBytes();

      // Parse the EPUB book using epub_plus
      final epubBook = await EpubReader.readBook(bytes);

      // Save page-map.xml to book directory if it exists
      if (epubBook.content?.allFiles.containsKey('page-map.xml') ?? false) {
        try {
          final pageMapEntry = epubBook.content!.allFiles['page-map.xml'];
          if (pageMapEntry != null && pageMapEntry is EpubByteContentFile) {
            final pageMapBytes = pageMapEntry.content;
            if (pageMapBytes != null && pageMapBytes.isNotEmpty) {
              final pageMapPath = path.join(bookDir.path, 'page-map.xml');
              final pageMapFileOutput = io.File(pageMapPath);
              await pageMapFileOutput.writeAsBytes(pageMapBytes);
            }
          }
        } catch (e) {
          print('Error saving page-map.xml: $e');
          // Continue without page-map.xml
        }
      }

      final Map<String, String> result = {};

      // Extract title from metadata
      if (epubBook.title != null && epubBook.title!.isNotEmpty) {
        result['title'] = epubBook.title!;
      }

      // Extract author from metadata
      // epub_plus provides both author (comma-separated string) and authors (list)
      if (epubBook.author != null && epubBook.author!.isNotEmpty) {
        result['author'] = epubBook.author!;
      } else if (epubBook.authors.isNotEmpty) {
        // Use first author if author string is not available
        final authors = epubBook.authors
            .where((a) => a != null && a.isNotEmpty)
            .map((a) => a!)
            .toList();
        if (authors.isNotEmpty) {
          result['author'] = authors.first;
        }
      }

      // Fallback to filename if title is not available
      if (result['title'] == null || result['title']!.isEmpty) {
        final fileName = path.basenameWithoutExtension(epubPath);
        result['title'] = fileName;
      }

      // Fallback to filename parsing if author is not available
      if (result['author'] == null || result['author']!.isEmpty) {
        final fileName = path.basenameWithoutExtension(epubPath);
        if (fileName.contains(' - ')) {
          final parts = fileName.split(' - ');
          if (parts.length > 1) {
            result['author'] = parts[1].trim();
          }
        }
        if (result['author'] == null || result['author']!.isEmpty) {
          result['author'] = 'Unknown Author';
        }
      }

      var additionalDetails = <String, String>{};

      // Search for additional book details using Google Books API
      try {
        additionalDetails = await _searchBookDetails(
          result['title'] ?? '',
          result['author'] ?? '',
        );
        if (additionalDetails.isNotEmpty) {
          result.addAll(additionalDetails);
        }
      } catch (e) {
        print('Error fetching additional book details from API: $e');
        // Continue without additional details if API call fails
      }

      // Fallback: Try to extract title from HTML content (xhtml/title.xhtml)
      // Only if API didn't return results and we still don't have a good title
      if (additionalDetails.isEmpty) {
        final titleFromHtml = await _extractTitleFromHtml(epubBook);
        if (titleFromHtml != null && titleFromHtml.isNotEmpty) {
          final oldTitle = result['title'];
          result['title'] = titleFromHtml;

          // If we found a title from HTML, try the API again with the new title
          if (oldTitle != titleFromHtml) {
            try {
              final additionalDetails = await _searchBookDetails(
                titleFromHtml,
                result['author'] ?? '',
              );
              if (additionalDetails.isNotEmpty) {
                result.addAll(additionalDetails);
              }
            } catch (e) {
              print(
                'Error fetching additional book details from API with HTML title: $e',
              );
              // Continue without additional details if API call fails
            }
          }
        }
      }

      return result;
    } catch (e) {
      print('Error extracting metadata: $e');
      // Fallback to filename-based extraction
      final fileName = path.basenameWithoutExtension(epubPath);
      final Map<String, String> result = {};

      if (fileName.contains(' - ')) {
        final parts = fileName.split(' - ');
        result['title'] = parts[0].trim();
        if (parts.length > 1) {
          result['author'] = parts[1].trim();
        }
      } else {
        result['title'] = fileName;
      }

      if (result['author'] == null || result['author']!.isEmpty) {
        result['author'] = 'Unknown Author';
      }

      // Search for additional book details using Google Books API
      try {
        final additionalDetails = await _searchBookDetails(
          result['title'] ?? '',
          result['author'] ?? '',
        );
        if (additionalDetails.isNotEmpty) {
          result.addAll(additionalDetails);
        }
      } catch (e) {
        print('Error fetching additional book details from API: $e');
        // Continue without additional details if API call fails
      }

      return result;
    }
  }

  /// Extract title from HTML content file (xhtml/title.xhtml)
  /// Returns the content of the <title> tag if found, null otherwise
  Future<String?> _extractTitleFromHtml(EpubBook epubBook) async {
    try {
      // Check if title.xhtml exists in the EPUB content
      final allFiles = epubBook.content?.allFiles;
      if (allFiles == null) {
        return null;
      }

      // Try the exact path first
      String? titleHtmlKey;
      if (allFiles.containsKey('xhtml/title.xhtml')) {
        titleHtmlKey = 'xhtml/title.xhtml';
      } else if (allFiles.containsKey('title.xhtml')) {
        titleHtmlKey = 'title.xhtml';
      } else {
        // Try to find any file with "title" in the name
        for (final key in allFiles.keys) {
          if (key.toLowerCase().contains('title') &&
              (key.toLowerCase().endsWith('.xhtml') ||
                  key.toLowerCase().endsWith('.html'))) {
            titleHtmlKey = key;
            break;
          }
        }
      }

      if (titleHtmlKey == null) {
        return null;
      }

      final titleFile = allFiles[titleHtmlKey];
      if (titleFile == null) {
        return null;
      }

      String? htmlContent;

      // Handle content file - get as bytes and decode
      if (titleFile is EpubTextContentFile) {
        htmlContent = titleFile.content;
      } else {
        // If not a byte content file, we can't extract the content
        return null;
      }

      if (htmlContent == null || htmlContent!.isEmpty) {
        return null;
      }

      // Extract title from HTML using regex
      // Look for <title>...</title> tag (case-insensitive)
      final titleRegex = RegExp(
        r'<title[^>]*>(.*?)</title>',
        caseSensitive: false,
        dotAll: true,
      );

      final match = titleRegex.firstMatch(htmlContent);
      if (match != null && match.groupCount >= 1) {
        final title = match.group(1);
        if (title != null && title.isNotEmpty) {
          // Decode HTML entities and clean up whitespace
          return title
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim()
              .replaceAll('&nbsp;', ' ')
              .replaceAll('&amp;', '&')
              .replaceAll('&lt;', '<')
              .replaceAll('&gt;', '>')
              .replaceAll('&quot;', '"')
              .replaceAll('&#39;', "'")
              .trim();
        }
      }

      return null;
    } catch (e) {
      print('Error extracting title from HTML: $e');
      return null;
    }
  }

  /// Search for book details using Google Books API (primary) and Open Library API (fallback)
  /// Returns a map with additional metadata like publisher, publishedDate, genre, ISBN, etc.
  Future<Map<String, String>> _searchBookDetails(
    String title,
    String author,
  ) async {
    if (title.isEmpty && author.isEmpty) {
      return {};
    }

    // Try Google Books API first
    final googleBooksDetails = await _searchGoogleBooks(title, author);
    if (googleBooksDetails.isNotEmpty) {
      return googleBooksDetails;
    }

    // Fallback to Open Library API if Google Books doesn't return results
    final openLibraryDetails = await _searchOpenLibrary(title, author);
    return openLibraryDetails;
  }

  /// Search Open Library API for book details (fallback)
  Future<Map<String, String>> _searchOpenLibrary(
    String title,
    String author,
  ) async {
    try {
      // Build search query
      final queryParams = <String, String>{};
      if (title.isNotEmpty) {
        queryParams['title'] = title.trim();
      }
      if (author.isNotEmpty) {
        // Extract first author name if multiple authors (comma-separated)
        final firstAuthor = author.split(',').first.trim();
        queryParams['author'] = firstAuthor;
      }

      if (queryParams.isEmpty) {
        return {};
      }

      final uri = Uri.https('openlibrary.org', '/search.json', queryParams);
      final url = uri.toString();

      final response = await http
          .get(Uri.parse(url))
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              throw Exception('Open Library API request timeout');
            },
          );

      if (response.statusCode != 200) {
        print('Open Library API returned status code: ${response.statusCode}');
        return {};
      }

      final jsonData = json.decode(response.body) as Map<String, dynamic>;
      final docs = jsonData['docs'] as List?;

      if (docs == null || docs.isEmpty) {
        return {};
      }

      // Get the first result (most relevant)
      final firstResult = docs.first as Map<String, dynamic>?;
      if (firstResult == null) {
        return {};
      }

      final Map<String, String> details = {};

      // Extract publisher
      if (firstResult['publisher'] != null) {
        final publishers = firstResult['publisher'] as List?;
        if (publishers != null && publishers.isNotEmpty) {
          details['publisher'] = publishers.first.toString();
        } else if (firstResult['publisher'] is String) {
          details['publisher'] = firstResult['publisher'].toString();
        }
      }

      // Extract published date
      if (firstResult['publish_date'] != null) {
        details['publishedDate'] = firstResult['publish_date'].toString();
      } else if (firstResult['first_publish_year'] != null) {
        details['publishedDate'] = firstResult['first_publish_year'].toString();
      }

      // Extract genres/subjects
      if (firstResult['subject'] != null) {
        final subjects = firstResult['subject'] as List?;
        if (subjects != null && subjects.isNotEmpty) {
          // Filter out common non-genre subjects and take first few
          final genreSubjects = subjects
              .where((s) => s.toString().toLowerCase() != 'fiction')
              .where((s) => s.toString().toLowerCase() != 'accessible book')
              .where((s) => s.toString().toLowerCase() != 'protected daisy')
              .take(5)
              .map((s) => s.toString())
              .toList();
          if (genreSubjects.isNotEmpty) {
            details['genre'] = genreSubjects.join(', ');
          }
        }
      }

      // Extract ISBN
      if (firstResult['isbn'] != null) {
        final isbns = firstResult['isbn'] as List?;
        if (isbns != null && isbns.isNotEmpty) {
          // Prefer ISBN-13 (13 digits), fallback to ISBN-10 (10 digits)
          String? isbn13;
          String? isbn10;
          for (final isbn in isbns) {
            final isbnStr = isbn
                .toString()
                .replaceAll('-', '')
                .replaceAll(' ', '');
            if (isbnStr.length == 13) {
              isbn13 = isbnStr;
            } else if (isbnStr.length == 10 && isbn10 == null) {
              isbn10 = isbnStr;
            }
          }
          details['isbn'] = isbn13 ?? isbn10 ?? isbns.first.toString();
        }
      }

      // Extract page count
      if (firstResult['number_of_pages_median'] != null) {
        details['pageCount'] = firstResult['number_of_pages_median'].toString();
      } else if (firstResult['number_of_pages'] != null) {
        final pages = firstResult['number_of_pages'];
        if (pages is List && pages.isNotEmpty) {
          details['pageCount'] = pages.first.toString();
        } else {
          details['pageCount'] = pages.toString();
        }
      }

      // Extract language
      if (firstResult['language'] != null) {
        final languages = firstResult['language'] as List?;
        if (languages != null && languages.isNotEmpty) {
          // Language codes like ['eng', 'fre'] - convert to readable names
          final langCode = languages.first.toString();
          final langMap = {
            'eng': 'English',
            'fre': 'French',
            'spa': 'Spanish',
            'ger': 'German',
            'ita': 'Italian',
            'por': 'Portuguese',
            'rus': 'Russian',
            'chi': 'Chinese',
            'jpn': 'Japanese',
            'kor': 'Korean',
          };
          details['language'] = langMap[langCode.toLowerCase()] ?? langCode;
        }
      }

      // Extract description (requires another API call to get full work details)
      // We can get the work key and fetch details, but for now we'll skip to keep it fast

      return details;
    } catch (e) {
      print('Error searching Open Library: $e');
      return {};
    }
  }

  /// Search Google Books API for book details (primary)
  Future<Map<String, String>> _searchGoogleBooks(
    String title,
    String author,
  ) async {
    try {
      // Build search query using title and author
      final queryParts = <String>[];
      if (title.isNotEmpty) {
        queryParts.add('intitle:"${title.trim()}"');
      }
      if (author.isNotEmpty) {
        // Extract first author name if multiple authors (comma-separated)
        final firstAuthor = author.split(',').first.trim();
        queryParts.add('inauthor:"${firstAuthor}"');
      }

      if (queryParts.isEmpty) {
        return {};
      }

      final query = queryParts.join('+');
      final encodedQuery = Uri.encodeComponent(query);
      final url =
          'https://www.googleapis.com/books/v1/volumes?q=$encodedQuery&maxResults=1';

      final response = await http
          .get(Uri.parse(url))
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              throw Exception('Google Books API request timeout');
            },
          );

      if (response.statusCode != 200) {
        print('Google Books API returned status code: ${response.statusCode}');
        return {};
      }

      final jsonData = json.decode(response.body) as Map<String, dynamic>;
      final items = jsonData['items'] as List?;

      if (items == null || items.isEmpty) {
        return {};
      }

      final volumeInfo = items.first['volumeInfo'] as Map<String, dynamic>?;
      if (volumeInfo == null) {
        return {};
      }

      final Map<String, String> details = {};

      // Extract publisher
      if (volumeInfo['publisher'] != null) {
        details['publisher'] = volumeInfo['publisher'].toString();
      }

      // Extract published date
      if (volumeInfo['publishedDate'] != null) {
        details['publishedDate'] = volumeInfo['publishedDate'].toString();
      }

      // Extract genres/categories
      if (volumeInfo['categories'] != null) {
        final categories = volumeInfo['categories'] as List?;
        if (categories != null && categories.isNotEmpty) {
          details['genre'] = categories.join(', ');
        }
      }

      // Extract ISBN
      if (volumeInfo['industryIdentifiers'] != null) {
        final identifiers = volumeInfo['industryIdentifiers'] as List?;
        if (identifiers != null) {
          for (final identifier in identifiers) {
            final type = identifier['type']?.toString().toUpperCase();
            final identifierValue = identifier['identifier']?.toString();
            if (type == 'ISBN_13' && identifierValue != null) {
              details['isbn'] = identifierValue;
              break;
            } else if (type == 'ISBN_10' &&
                identifierValue != null &&
                details['isbn'] == null) {
              details['isbn'] = identifierValue;
            }
          }
        }
      }

      // Extract page count
      if (volumeInfo['pageCount'] != null) {
        details['pageCount'] = volumeInfo['pageCount'].toString();
      }

      // Extract language
      if (volumeInfo['language'] != null) {
        details['language'] = volumeInfo['language'].toString();
      }

      // Extract description
      if (volumeInfo['description'] != null) {
        details['description'] = volumeInfo['description'].toString();
      }

      // Extract average rating
      if (volumeInfo['averageRating'] != null) {
        details['rating'] = volumeInfo['averageRating'].toString();
      }

      // Extract ratings count
      if (volumeInfo['ratingsCount'] != null) {
        details['ratingsCount'] = volumeInfo['ratingsCount'].toString();
      }

      return details;
    } catch (e) {
      print('Error searching Google Books: $e');
      return {};
    }
  }

  /// Delete imported book from cache and database
  Future<void> deleteImportedBook(int bookId) async {
    try {
      final dbService = LocalDatabaseService.instance;
      await dbService.initialize();

      final book = dbService.getBookById(bookId);
      if (book == null) return;

      // Get the book directory (parent of EPUB file)
      final epubFile = io.File(book.filePath);
      final bookDir = epubFile.parent;

      // Delete the entire book directory (which contains EPUB, cover, and other files)
      if (await bookDir.exists()) {
        await bookDir.delete(recursive: true);
      }

      // Delete from database
      dbService.deleteBook(bookId);
    } catch (e) {
      print('Error deleting book: $e');
    }
  }
}
