import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';
import '../models/file_source_model.dart';
import '../models/sync_server_model.dart';

/// Model for imported book stored in local database
class LocalBook {
  final int? id;
  final String title;
  final String author;
  final String filePath;
  final String originalFileName;
  final String? coverImagePath;
  final DateTime importedAt;
  final double? progressPercentage;
  final String? lastReadStatus;
  final String? lastReadCfi; // CFI (Canonical Fragment Identifier) for resuming reading
  final String? lastReadXPath; // XPath for resuming reading (from KOReader/Kindle sync)
  final DateTime? lastReadAt; // Timestamp of when the book was last read
  final String? partialMd5Checksum; // Partial MD5 checksum for KOReader sync (computed on import)
  // Additional metadata from API
  final String? publisher;
  final String? publishedDate;
  final String? genre;
  final String? isbn;
  final String? pageCount;
  final String? language;
  final String? description;
  final String? rating;
  final String? ratingsCount;
  final bool? syncEnabled; // Whether sync is enabled for this book (null = true by default for existing books)

  LocalBook({
    this.id,
    required this.title,
    required this.author,
    required this.filePath,
    required this.originalFileName,
    this.coverImagePath,
    required this.importedAt,
    this.progressPercentage,
    this.lastReadStatus,
    this.lastReadCfi,
    this.lastReadXPath,
    this.lastReadAt,
    this.partialMd5Checksum,
    this.publisher,
    this.publishedDate,
    this.genre,
    this.isbn,
    this.pageCount,
    this.language,
    this.description,
      this.rating,
      this.ratingsCount,
      this.syncEnabled,
    });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'author': author,
      'file_path': filePath,
      'original_file_name': originalFileName,
      'cover_image_path': coverImagePath,
      'imported_at': importedAt.millisecondsSinceEpoch,
      'progress_percentage': progressPercentage,
      'last_read_status': lastReadStatus,
      'last_read_cfi': lastReadCfi,
      'last_read_xpath': lastReadXPath,
      'last_read_at': lastReadAt?.millisecondsSinceEpoch,
      'partial_md5_checksum': partialMd5Checksum,
      'publisher': publisher,
      'published_date': publishedDate,
      'genre': genre,
      'isbn': isbn,
      'page_count': pageCount,
      'language': language,
      'description': description,
      'rating': rating,
      'ratings_count': ratingsCount,
      'sync_enabled': syncEnabled != null ? (syncEnabled! ? 1 : 0) : null,
    };
  }

  factory LocalBook.fromMap(Map<String, dynamic> map) {
    return LocalBook(
      id: map['id'] as int?,
      title: map['title'] as String,
      author: map['author'] as String,
      filePath: map['file_path'] as String,
      originalFileName: map['original_file_name'] as String,
      coverImagePath: map['cover_image_path'] as String?,
      importedAt: DateTime.fromMillisecondsSinceEpoch(map['imported_at'] as int),
      progressPercentage: map['progress_percentage'] != null ? (map['progress_percentage'] as num).toDouble() : null,
      lastReadStatus: map['last_read_status'] as String?,
      lastReadCfi: map['last_read_cfi'] as String?,
      lastReadXPath: map['last_read_xpath'] as String?,
      lastReadAt: map['last_read_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['last_read_at'] as int)
          : null,
      partialMd5Checksum: map['partial_md5_checksum'] as String?,
      publisher: map['publisher'] as String?,
      publishedDate: map['published_date'] as String?,
      genre: map['genre'] as String?,
      isbn: map['isbn'] as String?,
      pageCount: map['page_count'] as String?,
      language: map['language'] as String?,
      description: map['description'] as String?,
      rating: map['rating'] as String?,
      ratingsCount: map['ratings_count'] as String?,
      syncEnabled: map['sync_enabled'] != null ? (map['sync_enabled'] as int) != 0 : null,
    );
  }

  factory LocalBook.fromRow(Row row, List<String> columnNames) {
    int getIndex(String name) => columnNames.indexOf(name);
    int? getIndexOrNull(String name) {
      final idx = columnNames.indexOf(name);
      return idx >= 0 ? idx : null;
    }

    return LocalBook(
      id: row[getIndex('id')] as int?,
      title: row[getIndex('title')] as String,
      author: row[getIndex('author')] as String,
      filePath: row[getIndex('file_path')] as String,
      originalFileName: row[getIndex('original_file_name')] as String,
      coverImagePath: getIndexOrNull('cover_image_path') != null
          ? row[getIndexOrNull('cover_image_path')!] as String?
          : null,
      importedAt: DateTime.fromMillisecondsSinceEpoch(row[getIndex('imported_at')] as int),
      progressPercentage:
          getIndexOrNull('progress_percentage') != null && row[getIndexOrNull('progress_percentage')!] != null
          ? (row[getIndexOrNull('progress_percentage')!] as num).toDouble()
          : null,
      lastReadStatus: getIndexOrNull('last_read_status') != null
          ? row[getIndexOrNull('last_read_status')!] as String?
          : null,
      lastReadCfi: getIndexOrNull('last_read_cfi') != null ? row[getIndexOrNull('last_read_cfi')!] as String? : null,
      lastReadXPath: getIndexOrNull('last_read_xpath') != null
          ? row[getIndexOrNull('last_read_xpath')!] as String?
          : null,
      lastReadAt: getIndexOrNull('last_read_at') != null && row[getIndexOrNull('last_read_at')!] != null
          ? DateTime.fromMillisecondsSinceEpoch(row[getIndexOrNull('last_read_at')!] as int)
          : null,
      partialMd5Checksum: getIndexOrNull('partial_md5_checksum') != null
          ? row[getIndexOrNull('partial_md5_checksum')!] as String?
          : null,
      publisher: getIndexOrNull('publisher') != null ? row[getIndexOrNull('publisher')!] as String? : null,
      publishedDate: getIndexOrNull('published_date') != null
          ? row[getIndexOrNull('published_date')!] as String?
          : null,
      genre: getIndexOrNull('genre') != null ? row[getIndexOrNull('genre')!] as String? : null,
      isbn: getIndexOrNull('isbn') != null ? row[getIndexOrNull('isbn')!] as String? : null,
      pageCount: getIndexOrNull('page_count') != null ? row[getIndexOrNull('page_count')!] as String? : null,
      language: getIndexOrNull('language') != null ? row[getIndexOrNull('language')!] as String? : null,
      description: getIndexOrNull('description') != null ? row[getIndexOrNull('description')!] as String? : null,
      rating: getIndexOrNull('rating') != null ? row[getIndexOrNull('rating')!] as String? : null,
      ratingsCount: getIndexOrNull('ratings_count') != null ? row[getIndexOrNull('ratings_count')!] as String? : null,
      syncEnabled: getIndexOrNull('sync_enabled') != null && row[getIndexOrNull('sync_enabled')!] != null
          ? (row[getIndexOrNull('sync_enabled')!] as int) != 0
          : null,
    );
  }

  /// Create a copy with updated fields
  LocalBook copyWith({
    int? id,
    String? title,
    String? author,
    String? filePath,
    String? originalFileName,
    String? coverImagePath,
    DateTime? importedAt,
    double? progressPercentage,
    String? lastReadStatus,
    String? lastReadCfi,
    String? lastReadXPath,
    DateTime? lastReadAt,
    String? publisher,
    String? publishedDate,
    String? genre,
    String? isbn,
    String? pageCount,
    String? language,
    String? description,
    String? rating,
    String? ratingsCount,
    bool? syncEnabled,
  }) {
    return LocalBook(
      id: id ?? this.id,
      title: title ?? this.title,
      author: author ?? this.author,
      filePath: filePath ?? this.filePath,
      originalFileName: originalFileName ?? this.originalFileName,
      coverImagePath: coverImagePath ?? this.coverImagePath,
      importedAt: importedAt ?? this.importedAt,
      progressPercentage: progressPercentage ?? this.progressPercentage,
      lastReadStatus: lastReadStatus ?? this.lastReadStatus,
      lastReadCfi: lastReadCfi ?? this.lastReadCfi,
      lastReadXPath: lastReadXPath ?? this.lastReadXPath,
      lastReadAt: lastReadAt ?? this.lastReadAt,
      publisher: publisher ?? this.publisher,
      publishedDate: publishedDate ?? this.publishedDate,
      genre: genre ?? this.genre,
      isbn: isbn ?? this.isbn,
      pageCount: pageCount ?? this.pageCount,
      language: language ?? this.language,
      description: description ?? this.description,
      rating: rating ?? this.rating,
      ratingsCount: ratingsCount ?? this.ratingsCount,
      syncEnabled: syncEnabled ?? this.syncEnabled,
    );
  }
}

/// Service for managing local SQLite database of imported books
class LocalDatabaseService {
  static Database? _database;
  static final LocalDatabaseService instance = LocalDatabaseService._internal();
  factory LocalDatabaseService() => instance;
  LocalDatabaseService._internal();

  String? _databasePath;
  bool _initialized = false;

  /// Initialize the database
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      final appDir = await getApplicationDocumentsDirectory();
      final dbDir = Directory(path.join(appDir.path, 'Everbound'));
      if (!await dbDir.exists()) {
        await dbDir.create(recursive: true);
      }

      _databasePath = path.join(dbDir.path, 'imported_books.db');
    } catch (e) {
      // Fallback to temporary directory if path_provider fails
      print('Error getting application documents directory, using temp: $e');
      final tempDir = Directory.systemTemp;
      final dbDir = Directory(path.join(tempDir.path, 'Everbound'));
      if (!await dbDir.exists()) {
        await dbDir.create(recursive: true);
      }

      _databasePath = path.join(dbDir.path, 'imported_books.db');
    }

    _database = _openDatabase();
    _createTables();
    _initialized = true;
  }

  /// Open the database connection
  Database _openDatabase() {
    if (_databasePath == null) {
      throw Exception('Database path not initialized. Call initialize() first.');
    }
    return sqlite3.open(_databasePath!);
  }

  /// Create database tables
  void _createTables() {
    final db = database;
    db.execute('''
      CREATE TABLE IF NOT EXISTS imported_books (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        author TEXT NOT NULL,
        file_path TEXT NOT NULL UNIQUE,
        original_file_name TEXT NOT NULL,
        cover_image_path TEXT,
        imported_at INTEGER NOT NULL,
        progress_percentage REAL,
        last_read_status TEXT,
        last_read_cfi TEXT,
        last_read_xpath TEXT
      )
    ''');

    // Migration: Add missing columns if they don't exist (for existing databases)
    try {
      final stmt = db.prepare('PRAGMA table_info(imported_books)');
      try {
        final result = stmt.select();
        final columnNames = result.map((row) => row['name'] as String).toList();

        final columnsToAdd = [
          'last_read_cfi',
          'last_read_xpath',
          'last_read_at',
          'partial_md5_checksum',
          'publisher',
          'published_date',
          'genre',
          'isbn',
          'page_count',
          'language',
          'description',
          'rating',
          'ratings_count',
          'sync_enabled',
        ];

        for (final columnName in columnsToAdd) {
          if (!columnNames.contains(columnName)) {
            print('Adding $columnName column to imported_books table');
            // sync_enabled and last_read_at are INTEGER, all others are TEXT
            final columnType = (columnName == 'sync_enabled' || columnName == 'last_read_at') ? 'INTEGER' : 'TEXT';
            db.execute('ALTER TABLE imported_books ADD COLUMN $columnName $columnType');
          }
        }
      } finally {
        stmt.dispose();
      }
    } catch (e) {
      print('Error checking/adding columns: $e');
    }

    // Create index for faster queries
    db.execute('''
      CREATE INDEX IF NOT EXISTS idx_imported_at ON imported_books(imported_at DESC)
    ''');

    // Create file_sources table
    db.execute('''
      CREATE TABLE IF NOT EXISTS file_sources (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        type TEXT NOT NULL,
        local_path TEXT,
        url TEXT,
        username TEXT,
        password TEXT,
        selected_path TEXT,
        created_at INTEGER NOT NULL,
        last_scanned_at INTEGER
      )
    ''');

    // Create index for file_sources
    db.execute('''
      CREATE INDEX IF NOT EXISTS idx_file_sources_created_at ON file_sources(created_at DESC)
    ''');

    // Create sync_servers table
    db.execute('''
      CREATE TABLE IF NOT EXISTS sync_servers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        url TEXT NOT NULL,
        username TEXT NOT NULL,
        password TEXT NOT NULL,
        device_id TEXT,
        device_name TEXT,
        created_at INTEGER NOT NULL,
        is_active INTEGER DEFAULT 0
      )
    ''');

    // Create index for sync_servers
    db.execute('''
      CREATE INDEX IF NOT EXISTS idx_sync_servers_created_at ON sync_servers(created_at DESC)
    ''');

    // Create app_settings table for app-wide settings
    db.execute('''
      CREATE TABLE IF NOT EXISTS app_settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    // Migration: Add missing columns if they don't exist (for existing databases)
    try {
      final stmt = db.prepare('PRAGMA table_info(sync_servers)');
      try {
        final result = stmt.select();
        final columnNames = result.map((row) => row['name'] as String).toList();

        final columnsToAdd = ['device_id', 'device_name', 'is_active'];

        for (final columnName in columnsToAdd) {
          if (!columnNames.contains(columnName)) {
            print('Adding $columnName column to sync_servers table');
            if (columnName == 'is_active') {
              db.execute('ALTER TABLE sync_servers ADD COLUMN $columnName INTEGER DEFAULT 0');
            } else {
              db.execute('ALTER TABLE sync_servers ADD COLUMN $columnName TEXT');
            }
          }
        }
      } finally {
        stmt.dispose();
      }
    } catch (e) {
      print('Error checking/adding columns to sync_servers: $e');
    }
  }

  /// Get the database instance
  Database get database {
    if (_database == null) {
      if (_databasePath == null) {
        throw Exception('Database not initialized. Call initialize() first.');
      }
      _database = _openDatabase();
    }
    return _database!;
  }

  /// Close the database connection
  void close() {
    _database?.dispose();
    _database = null;
    _initialized = false;
  }

  // ==================== Book Operations ====================

  /// Get all imported books
  List<LocalBook> getAllBooks() {
    final stmt = database.prepare('SELECT * FROM imported_books ORDER BY imported_at DESC');
    try {
      final result = stmt.select();
      final columnNames = result.columnNames;
      return result.map((row) => LocalBook.fromRow(row, columnNames)).toList();
    } finally {
      stmt.dispose();
    }
  }

  /// Get a book by ID
  LocalBook? getBookById(int id) {
    final stmt = database.prepare('SELECT * FROM imported_books WHERE id = ? LIMIT 1');
    try {
      // For SELECT queries, pass parameters directly to select()
      final result = stmt.select([id]);
      if (result.isEmpty) return null;
      final columnNames = result.columnNames;
      return LocalBook.fromRow(result.first, columnNames);
    } finally {
      stmt.dispose();
    }
  }

  /// Find book by partial MD5 checksum
  LocalBook? getBookByPartialMd5(String partialMd5Checksum) {
    final stmt = database.prepare('SELECT * FROM imported_books WHERE partial_md5_checksum = ? LIMIT 1');
    try {
      final result = stmt.select([partialMd5Checksum]);
      if (result.isEmpty) return null;
      final columnNames = result.columnNames;
      return LocalBook.fromRow(result.first, columnNames);
    } finally {
      stmt.dispose();
    }
  }

  /// Get a book by file path (relative path)
  LocalBook? getBookByFilePath(String filePath) {
    final stmt = database.prepare('SELECT * FROM imported_books WHERE file_path = ? LIMIT 1');
    try {
      final result = stmt.select([filePath]);
      if (result.isEmpty) return null;
      final columnNames = result.columnNames;
      return LocalBook.fromRow(result.first, columnNames);
    } finally {
      stmt.dispose();
    }
  }

  /// Insert a new book
  int insertBook(LocalBook book) {
    final stmt = database.prepare('''
      INSERT INTO imported_books 
      (title, author, file_path, original_file_name, cover_image_path, imported_at, progress_percentage, last_read_status, last_read_cfi, last_read_xpath, last_read_at,
       partial_md5_checksum, publisher, published_date, genre, isbn, page_count, language, description, rating, ratings_count, sync_enabled)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ''');
    try {
      stmt.execute([
        book.title,
        book.author,
        book.filePath,
        book.originalFileName,
        book.coverImagePath,
        book.importedAt.millisecondsSinceEpoch,
        book.progressPercentage,
        book.lastReadStatus,
        book.lastReadCfi,
        book.lastReadXPath,
        book.lastReadAt?.millisecondsSinceEpoch,
        book.partialMd5Checksum,
        book.publisher,
        book.publishedDate,
        book.genre,
        book.isbn,
        book.pageCount,
        book.language,
        book.description,
        book.rating,
        book.ratingsCount,
        book.syncEnabled != null ? (book.syncEnabled! ? 1 : 0) : null,
      ]);
      return database.lastInsertRowId;
    } finally {
      stmt.dispose();
    }
  }

  /// Update an existing book
  int updateBook(LocalBook book) {
    if (book.id == null) {
      throw Exception('Cannot update book without an ID');
    }
    final stmt = database.prepare('''
      UPDATE imported_books SET
        title = ?, author = ?, file_path = ?, original_file_name = ?,
        cover_image_path = ?, imported_at = ?, progress_percentage = ?, last_read_status = ?,
        last_read_cfi = ?, last_read_xpath = ?, last_read_at = ?, partial_md5_checksum = ?,
        publisher = ?, published_date = ?, genre = ?, isbn = ?, page_count = ?, 
        language = ?, description = ?, rating = ?, ratings_count = ?, sync_enabled = ?
      WHERE id = ?
    ''');
    try {
      stmt.execute([
        book.title,
        book.author,
        book.filePath,
        book.originalFileName,
        book.coverImagePath,
        book.importedAt.millisecondsSinceEpoch,
        book.progressPercentage,
        book.lastReadStatus,
        book.lastReadCfi,
        book.lastReadXPath,
        book.lastReadAt?.millisecondsSinceEpoch,
        book.partialMd5Checksum,
        book.publisher,
        book.publishedDate,
        book.genre,
        book.isbn,
        book.pageCount,
        book.language,
        book.description,
        book.rating,
        book.ratingsCount,
        book.syncEnabled != null ? (book.syncEnabled! ? 1 : 0) : null,
        book.id,
      ]);
      return 1; // Return 1 to indicate success
    } finally {
      stmt.dispose();
    }
  }

  /// Update reading progress for a book
  int updateProgress(
    int bookId,
    double progressPercentage,
    String? lastReadStatus, {
    String? lastReadCfi,
    String? lastReadXPath,
  }) {
    try {
      // Escape the lastReadStatus, lastReadCfi, and lastReadXPath strings for SQL if they're not null
      final statusValue = lastReadStatus != null ? "'${lastReadStatus.replaceAll("'", "''")}'" : 'NULL';
      final cfiValue = lastReadCfi != null ? "'${lastReadCfi.replaceAll("'", "''")}'" : 'NULL';
      final xpathValue = lastReadXPath != null ? "'${lastReadXPath.replaceAll("'", "''")}'" : 'NULL';

      // Use raw SQL execution to avoid parameter binding issues
      // Set last_read_at to current timestamp when progress is updated
      final now = DateTime.now().millisecondsSinceEpoch;
      final sql =
          '''
        UPDATE imported_books SET
          progress_percentage = $progressPercentage,
          last_read_status = $statusValue,
          last_read_cfi = $cfiValue,
          last_read_xpath = $xpathValue,
          last_read_at = $now
        WHERE id = $bookId
      ''';

      database.execute(sql);

      // Verify the update by checking if the book exists and progress was updated
      final updatedBook = getBookById(bookId);
      if (updatedBook != null) {
        // Check if progress matches (with small tolerance for floating point)
        final currentProgress = updatedBook.progressPercentage ?? 0.0;
        final progressMatches = (currentProgress - progressPercentage).abs() < 0.001;
        if (progressMatches) {
          return 1; // Success
        } else {
          print('Warning: Progress mismatch. Expected: $progressPercentage, Got: $currentProgress');
        }
      } else {
        print('Warning: Book with id $bookId not found after update');
      }
      return 0; // Update may have failed
    } catch (e, stackTrace) {
      print('Error in updateProgress: $e');
      print('Stack trace: $stackTrace');
      return 0;
    }
  }

  /// Update last read timestamp for a book (called when book is opened)
  int updateLastReadAt(int bookId) {
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final sql = '''
        UPDATE imported_books SET
          last_read_at = $now
        WHERE id = $bookId
      ''';
      database.execute(sql);
      return 1; // Success
    } catch (e, stackTrace) {
      print('Error in updateLastReadAt: $e');
      print('Stack trace: $stackTrace');
      return 0;
    }
  }

  /// Delete a book by ID
  int deleteBook(int id) {
    final stmt = database.prepare('DELETE FROM imported_books WHERE id = ?');
    try {
      stmt.execute([id]);
      return 1; // Return 1 to indicate success
    } finally {
      stmt.dispose();
    }
  }

  /// Update sync enabled state for a book
  int updateBookSyncEnabled(int bookId, bool enabled) {
    final stmt = database.prepare('UPDATE imported_books SET sync_enabled = ? WHERE id = ?');
    try {
      stmt.execute([enabled ? 1 : 0, bookId]);
      return 1; // Return 1 to indicate success
    } finally {
      stmt.dispose();
    }
  }

  /// Update device name for active sync server
  int updateActiveSyncServerDeviceName(String deviceName) {
    final stmt = database.prepare('UPDATE sync_servers SET device_name = ? WHERE is_active = 1');
    try {
      stmt.execute([deviceName]);
      return 1; // Return 1 to indicate success
    } finally {
      stmt.dispose();
    }
  }

  /// Delete a book by file path
  int deleteBookByFilePath(String filePath) {
    final stmt = database.prepare('DELETE FROM imported_books WHERE file_path = ?');
    try {
      stmt.execute([filePath]);
      return 1; // Return 1 to indicate success
    } finally {
      stmt.dispose();
    }
  }

  /// Delete all books (for testing/clearing data)
  int deleteAllBooks() {
    final stmt = database.prepare('DELETE FROM imported_books');
    try {
      stmt.execute();
      return 1; // Return 1 to indicate success
    } finally {
      stmt.dispose();
    }
  }

  // ==================== File Source Operations ====================

  /// Get all file sources
  List<FileSource> getAllFileSources() {
    final stmt = database.prepare('SELECT * FROM file_sources ORDER BY created_at DESC');
    try {
      final result = stmt.select();
      final columnNames = result.columnNames;
      return result.map((row) => FileSource.fromRow(row, columnNames)).toList();
    } finally {
      stmt.dispose();
    }
  }

  /// Get a file source by ID
  FileSource? getFileSourceById(int id) {
    final stmt = database.prepare('SELECT * FROM file_sources WHERE id = ? LIMIT 1');
    try {
      final result = stmt.select([id]);
      if (result.isEmpty) return null;
      final columnNames = result.columnNames;
      return FileSource.fromRow(result.first, columnNames);
    } finally {
      stmt.dispose();
    }
  }

  /// Insert a new file source
  int insertFileSource(FileSource source) {
    final stmt = database.prepare('''
      INSERT INTO file_sources 
      (name, type, local_path, url, username, password, selected_path, created_at, last_scanned_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    ''');
    try {
      stmt.execute([
        source.name,
        source.type.name,
        source.localPath,
        source.url,
        source.username,
        source.password,
        source.selectedPath,
        source.createdAt.millisecondsSinceEpoch,
        source.lastScannedAt?.millisecondsSinceEpoch,
      ]);
      return database.lastInsertRowId;
    } finally {
      stmt.dispose();
    }
  }

  /// Update an existing file source
  int updateFileSource(FileSource source) {
    if (source.id == null) {
      throw Exception('Cannot update file source without an ID');
    }
    final stmt = database.prepare('''
      UPDATE file_sources SET
        name = ?, type = ?, local_path = ?, url = ?, username = ?, password = ?,
        selected_path = ?, created_at = ?, last_scanned_at = ?
      WHERE id = ?
    ''');
    try {
      stmt.execute([
        source.name,
        source.type.name,
        source.localPath,
        source.url,
        source.username,
        source.password,
        source.selectedPath,
        source.createdAt.millisecondsSinceEpoch,
        source.lastScannedAt?.millisecondsSinceEpoch,
        source.id,
      ]);
      return 1; // Return 1 to indicate success
    } finally {
      stmt.dispose();
    }
  }

  /// Update last scanned timestamp for a file source
  int updateFileSourceLastScanned(int id, DateTime lastScannedAt) {
    final stmt = database.prepare('UPDATE file_sources SET last_scanned_at = ? WHERE id = ?');
    try {
      stmt.execute([lastScannedAt.millisecondsSinceEpoch, id]);
      return 1; // Return 1 to indicate success
    } finally {
      stmt.dispose();
    }
  }

  /// Delete a file source by ID
  int deleteFileSource(int id) {
    final stmt = database.prepare('DELETE FROM file_sources WHERE id = ?');
    try {
      stmt.execute([id]);
      return 1; // Return 1 to indicate success
    } finally {
      stmt.dispose();
    }
  }

  // ==================== Sync Server Operations ====================

  /// Get all sync servers
  List<SyncServer> getAllSyncServers() {
    final stmt = database.prepare('SELECT * FROM sync_servers ORDER BY created_at DESC');
    try {
      final result = stmt.select();
      final columnNames = result.columnNames;
      return result.map((row) => SyncServer.fromRow(row, columnNames)).toList();
    } finally {
      stmt.dispose();
    }
  }

  /// Get the active sync server
  SyncServer? getActiveSyncServer() {
    final stmt = database.prepare('SELECT * FROM sync_servers WHERE is_active = 1 LIMIT 1');
    try {
      final result = stmt.select();
      if (result.isEmpty) return null;
      final columnNames = result.columnNames;
      return SyncServer.fromRow(result.first, columnNames);
    } finally {
      stmt.dispose();
    }
  }

  /// Get a sync server by ID
  SyncServer? getSyncServerById(int id) {
    final stmt = database.prepare('SELECT * FROM sync_servers WHERE id = ? LIMIT 1');
    try {
      final result = stmt.select([id]);
      if (result.isEmpty) return null;
      final columnNames = result.columnNames;
      return SyncServer.fromRow(result.first, columnNames);
    } finally {
      stmt.dispose();
    }
  }

  /// Insert a new sync server
  int insertSyncServer(SyncServer server) {
    final stmt = database.prepare('''
      INSERT INTO sync_servers 
      (name, url, username, password, device_id, device_name, created_at, is_active)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ''');
    try {
      stmt.execute([
        server.name,
        server.url,
        server.username,
        server.password,
        server.deviceId,
        server.deviceName,
        server.createdAt.millisecondsSinceEpoch,
        server.isActive ? 1 : 0,
      ]);
      return database.lastInsertRowId;
    } finally {
      stmt.dispose();
    }
  }

  /// Update an existing sync server
  int updateSyncServer(SyncServer server) {
    if (server.id == null) {
      throw Exception('Cannot update sync server without an ID');
    }
    final stmt = database.prepare('''
      UPDATE sync_servers SET
        name = ?, url = ?, username = ?, password = ?,
        device_id = ?, device_name = ?, created_at = ?, is_active = ?
      WHERE id = ?
    ''');
    try {
      stmt.execute([
        server.name,
        server.url,
        server.username,
        server.password,
        server.deviceId,
        server.deviceName,
        server.createdAt.millisecondsSinceEpoch,
        server.isActive ? 1 : 0,
        server.id,
      ]);
      return 1; // Return 1 to indicate success
    } finally {
      stmt.dispose();
    }
  }

  /// Set a sync server as active (deactivates all others)
  int setActiveSyncServer(int id) {
    final db = database;
    try {
      // First, deactivate all servers
      db.execute('UPDATE sync_servers SET is_active = 0');

      // Then activate the specified server
      final stmt = db.prepare('UPDATE sync_servers SET is_active = 1 WHERE id = ?');
      try {
        stmt.execute([id]);
        return 1;
      } finally {
        stmt.dispose();
      }
    } catch (e) {
      print('Error setting active sync server: $e');
      return 0;
    }
  }

  /// Delete a sync server by ID
  int deleteSyncServer(int id) {
    final stmt = database.prepare('DELETE FROM sync_servers WHERE id = ?');
    try {
      stmt.execute([id]);
      return 1; // Return 1 to indicate success
    } finally {
      stmt.dispose();
    }
  }

  // ==================== App Settings Operations ====================

  /// Get a setting value by key
  String? getSetting(String key) {
    final stmt = database.prepare('SELECT value FROM app_settings WHERE key = ?');
    try {
      final result = stmt.select([key]);
      if (result.isEmpty) return null;
      return result.first['value'] as String?;
    } finally {
      stmt.dispose();
    }
  }

  /// Set a setting value by key
  int setSetting(String key, String value) {
    final stmt = database.prepare('INSERT OR REPLACE INTO app_settings (key, value) VALUES (?, ?)');
    try {
      stmt.execute([key, value]);
      return 1; // Return 1 to indicate success
    } finally {
      stmt.dispose();
    }
  }

  /// Get sync strategy from settings
  String? getSyncStrategy() {
    return getSetting('sync_strategy');
  }

  /// Save sync strategy to settings
  int saveSyncStrategy(String strategy) {
    return setSetting('sync_strategy', strategy);
  }
}
