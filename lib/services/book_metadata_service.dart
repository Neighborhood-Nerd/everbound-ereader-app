import 'dart:io' as io;
import 'dart:convert';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';

/// Service for fetching and caching book metadata from APIs
class BookMetadataService {
  static final BookMetadataService instance = BookMetadataService._internal();
  factory BookMetadataService() => instance;
  BookMetadataService._internal();

  /// Get cache directory for storing metadata JSON files
  Future<io.Directory> getCacheDirectory() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final metadataCacheDir = io.Directory(path.join(appDir.path, 'Everbound', 'metadata_cache'));

      if (!await metadataCacheDir.exists()) {
        await metadataCacheDir.create(recursive: true);
      }

      return metadataCacheDir;
    } catch (e) {
      print('Error getting metadata cache directory: $e');
      final tempDir = io.Directory.systemTemp;
      final metadataCacheDir = io.Directory(path.join(tempDir.path, 'Everbound', 'metadata_cache'));

      if (!await metadataCacheDir.exists()) {
        await metadataCacheDir.create(recursive: true);
      }

      return metadataCacheDir;
    }
  }

  /// Generate cache file name from title and author
  String _getCacheFileName(String title, String author) {
    final sanitizedTitle = title.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_').toLowerCase();
    final sanitizedAuthor = author.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_').toLowerCase();
    final key = '$sanitizedTitle|$sanitizedAuthor';
    final bytes = utf8.encode(key);
    final hash = sha256.convert(bytes);
    return '${hash.toString().substring(0, 16)}.json';
  }

  /// Get cached metadata if available
  Future<Map<String, String>?> _getCachedMetadata(String title, String author) async {
    try {
      final cacheDir = await getCacheDirectory();
      final cacheFileName = _getCacheFileName(title, author);
      final cacheFile = io.File(path.join(cacheDir.path, cacheFileName));

      if (await cacheFile.exists()) {
        final content = await cacheFile.readAsString();
        final jsonData = json.decode(content) as Map<String, dynamic>;
        // Convert to Map<String, String>
        return jsonData.map((key, value) => MapEntry(key, value?.toString() ?? ''));
      }
    } catch (e) {
      print('Error reading cached metadata: $e');
    }
    return null;
  }

  /// Save metadata to cache
  Future<void> _saveMetadataToCache(String title, String author, Map<String, String> metadata) async {
    try {
      final cacheDir = await getCacheDirectory();
      final cacheFileName = _getCacheFileName(title, author);
      final cacheFile = io.File(path.join(cacheDir.path, cacheFileName));

      // Add timestamp
      final dataToSave = {
        ...metadata,
        'cachedAt': DateTime.now().toIso8601String(),
        'title': title,
        'author': author,
      };

      await cacheFile.writeAsString(json.encode(dataToSave));
    } catch (e) {
      print('Error saving metadata to cache: $e');
    }
  }

  /// Fetch book metadata from APIs (checks cache first)
  Future<Map<String, String>> fetchBookMetadata(String title, String author) async {
    if (title.isEmpty && author.isEmpty) {
      return {};
    }

    // Check cache first
    final cached = await _getCachedMetadata(title, author);
    if (cached != null) {
      // Remove cache-specific fields
      cached.remove('cachedAt');
      cached.remove('title');
      cached.remove('author');
      return cached;
    }

    // Try Google Books API first
    final googleBooksDetails = await _fetchFromGoogleBooks(title, author);
    if (googleBooksDetails.isNotEmpty) {
      await _saveMetadataToCache(title, author, googleBooksDetails);
      return googleBooksDetails;
    }

    // Fallback to Open Library API
    final openLibraryDetails = await _fetchFromOpenLibrary(title, author);
    if (openLibraryDetails.isNotEmpty) {
      await _saveMetadataToCache(title, author, openLibraryDetails);
      return openLibraryDetails;
    }

    return {};
  }

  /// Search Google Books API for book details (primary)
  Future<Map<String, String>> _fetchFromGoogleBooks(String title, String author) async {
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
      final url = 'https://www.googleapis.com/books/v1/volumes?q=$encodedQuery&maxResults=1';

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
            } else if (type == 'ISBN_10' && identifierValue != null && details['isbn'] == null) {
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

  /// Search Open Library API for book details (fallback)
  Future<Map<String, String>> _fetchFromOpenLibrary(String title, String author) async {
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
            final isbnStr = isbn.toString().replaceAll('-', '').replaceAll(' ', '');
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

      return details;
    } catch (e) {
      print('Error searching Open Library: $e');
      return {};
    }
  }
}







