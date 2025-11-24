import 'dart:io';
import 'package:sqlite3/sqlite3.dart';

/// Model class for a book entry
class Book {
  final int? id;
  final String? title;
  final String? authors;
  final int? notes;
  final int? lastOpen;
  final int? highlights;
  final int? pages;
  final String? series;
  final String? language;
  final String? md5;
  final int? totalReadTime;
  final int? totalReadPages;

  Book({
    this.id,
    this.title,
    this.authors,
    this.notes,
    this.lastOpen,
    this.highlights,
    this.pages,
    this.series,
    this.language,
    this.md5,
    this.totalReadTime,
    this.totalReadPages,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'authors': authors,
      'notes': notes,
      'last_open': lastOpen,
      'highlights': highlights,
      'pages': pages,
      'series': series,
      'language': language,
      'md5': md5,
      'total_read_time': totalReadTime,
      'total_read_pages': totalReadPages,
    };
  }

  factory Book.fromMap(Map<String, dynamic> map) {
    return Book(
      id: map['id'] as int?,
      title: map['title'] as String?,
      authors: map['authors'] as String?,
      notes: map['notes'] as int?,
      lastOpen: map['last_open'] as int?,
      highlights: map['highlights'] as int?,
      pages: map['pages'] as int?,
      series: map['series'] as String?,
      language: map['language'] as String?,
      md5: map['md5'] as String?,
      totalReadTime: map['total_read_time'] as int?,
      totalReadPages: map['total_read_pages'] as int?,
    );
  }

  factory Book.fromRow(Row row, List<String> columnNames) {
    int getIndex(String name) => columnNames.indexOf(name);
    return Book(
      id: row[getIndex('id')] as int?,
      title: row[getIndex('title')] as String?,
      authors: row[getIndex('authors')] as String?,
      notes: row[getIndex('notes')] as int?,
      lastOpen: row[getIndex('last_open')] as int?,
      highlights: row[getIndex('highlights')] as int?,
      pages: row[getIndex('pages')] as int?,
      series: row[getIndex('series')] as String?,
      language: row[getIndex('language')] as String?,
      md5: row[getIndex('md5')] as String?,
      totalReadTime: row[getIndex('total_read_time')] as int?,
      totalReadPages: row[getIndex('total_read_pages')] as int?,
    );
  }
}

/// Model class for page statistics
class PageStatData {
  final int? idBook;
  final int page;
  final int startTime;
  final int duration;
  final int totalPages;

  PageStatData({
    this.idBook,
    required this.page,
    required this.startTime,
    required this.duration,
    required this.totalPages,
  });

  Map<String, dynamic> toMap() {
    return {
      'id_book': idBook,
      'page': page,
      'start_time': startTime,
      'duration': duration,
      'total_pages': totalPages,
    };
  }

  factory PageStatData.fromMap(Map<String, dynamic> map) {
    return PageStatData(
      idBook: map['id_book'] as int?,
      page: map['page'] as int,
      startTime: map['start_time'] as int,
      duration: map['duration'] as int,
      totalPages: map['total_pages'] as int,
    );
  }

  factory PageStatData.fromRow(Row row, List<String> columnNames) {
    int getIndex(String name) => columnNames.indexOf(name);
    return PageStatData(
      idBook: row[getIndex('id_book')] as int?,
      page: row[getIndex('page')] as int,
      startTime: row[getIndex('start_time')] as int,
      duration: row[getIndex('duration')] as int,
      totalPages: row[getIndex('total_pages')] as int,
    );
  }
}

/// Service class for interacting with KoReader statistics database
class KoReaderDatabaseService {
  static Database? _database;
  static final KoReaderDatabaseService instance = KoReaderDatabaseService._internal();
  factory KoReaderDatabaseService() => instance;
  KoReaderDatabaseService._internal();

  String? _databasePath;

  /// Initialize the database with a file path
  Future<void> initialize(String databasePath) async {
    if (!File(databasePath).existsSync()) {
      throw Exception('Database file does not exist: $databasePath');
    }
    _databasePath = databasePath;
    _database = _openDatabase();
  }

  /// Open the database connection
  Database _openDatabase() {
    if (_databasePath == null) {
      throw Exception('Database path not initialized. Call initialize() first.');
    }

    return sqlite3.open(_databasePath!);
  }

  /// Get the database instance
  Database get database {
    if (_database == null) {
      _database = _openDatabase();
    }
    return _database!;
  }

  /// Close the database connection
  void close() {
    _database?.dispose();
    _database = null;
  }

  // ==================== Book Operations ====================

  /// Get all books
  List<Book> getAllBooks() {
    final stmt = database.prepare('SELECT * FROM book ORDER BY last_open DESC');
    try {
      final result = stmt.select();
      final columnNames = result.columnNames;
      return result.map((row) => Book.fromRow(row, columnNames)).toList();
    } finally {
      stmt.dispose();
    }
  }

  /// Get a book by ID
  Book? getBookById(int id) {
    final stmt = database.prepare('SELECT * FROM book WHERE id = ? LIMIT 1');
    try {
      stmt.execute([id]);
      final result = stmt.select();
      if (result.isEmpty) return null;
      final columnNames = result.columnNames;
      return Book.fromRow(result.first, columnNames);
    } finally {
      stmt.dispose();
    }
  }

  /// Get a book by title, authors, and MD5
  Book? getBookByTitleAuthorsMd5(String title, String authors, String md5) {
    final stmt = database.prepare('SELECT * FROM book WHERE title = ? AND authors = ? AND md5 = ? LIMIT 1');
    try {
      stmt.execute([title, authors, md5]);
      final result = stmt.select();
      if (result.isEmpty) return null;
      final columnNames = result.columnNames;
      return Book.fromRow(result.first, columnNames);
    } finally {
      stmt.dispose();
    }
  }

  /// Get all books with their MD5 values (for debugging)
  List<Map<String, dynamic>> getAllBooksWithMD5() {
    final stmt = database.prepare('SELECT id, title, authors, md5 FROM book WHERE md5 IS NOT NULL ORDER BY title');
    try {
      final result = stmt.select();
      final columnNames = result.columnNames;
      return result.map((row) {
        final map = <String, dynamic>{};
        for (var i = 0; i < columnNames.length; i++) {
          map[columnNames[i]] = row[i];
        }
        return map;
      }).toList();
    } finally {
      stmt.dispose();
    }
  }

  /// Insert a new book
  int insertBook(Book book) {
    final stmt = database.prepare('''
      INSERT OR REPLACE INTO book 
      (id, title, authors, notes, last_open, highlights, pages, series, language, md5, total_read_time, total_read_pages)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ''');
    try {
      stmt.execute([
        book.id,
        book.title,
        book.authors,
        book.notes,
        book.lastOpen,
        book.highlights,
        book.pages,
        book.series,
        book.language,
        book.md5,
        book.totalReadTime,
        book.totalReadPages,
      ]);
      return database.lastInsertRowId;
    } finally {
      stmt.dispose();
    }
  }

  /// Update an existing book
  int updateBook(Book book) {
    if (book.id == null) {
      throw Exception('Cannot update book without an ID');
    }
    final stmt = database.prepare('''
      UPDATE book SET
        title = ?, authors = ?, notes = ?, last_open = ?, highlights = ?,
        pages = ?, series = ?, language = ?, md5 = ?, total_read_time = ?, total_read_pages = ?
      WHERE id = ?
    ''');
    try {
      stmt.execute([
        book.title,
        book.authors,
        book.notes,
        book.lastOpen,
        book.highlights,
        book.pages,
        book.series,
        book.language,
        book.md5,
        book.totalReadTime,
        book.totalReadPages,
        book.id,
      ]);
      return database.lastInsertRowId;
    } finally {
      stmt.dispose();
    }
  }

  /// Delete a book by ID
  int deleteBook(int id) {
    final stmt = database.prepare('DELETE FROM book WHERE id = ?');
    try {
      stmt.execute([id]);
      return database.lastInsertRowId;
    } finally {
      stmt.dispose();
    }
  }

  /// Upsert a book (insert or update if exists)
  int upsertBook(Book book) {
    if (book.title == null || book.authors == null || book.md5 == null) {
      throw Exception('Title, authors, and MD5 are required for upsert');
    }

    final existing = getBookByTitleAuthorsMd5(book.title!, book.authors!, book.md5!);
    if (existing != null) {
      // Update existing book, preserving the ID
      return updateBook(Book(
        id: existing.id,
        title: book.title ?? existing.title,
        authors: book.authors ?? existing.authors,
        notes: book.notes ?? existing.notes,
        lastOpen: book.lastOpen ?? existing.lastOpen,
        highlights: book.highlights ?? existing.highlights,
        pages: book.pages ?? existing.pages,
        series: book.series ?? existing.series,
        language: book.language ?? existing.language,
        md5: book.md5 ?? existing.md5,
        totalReadTime: book.totalReadTime ?? existing.totalReadTime,
        totalReadPages: book.totalReadPages ?? existing.totalReadPages,
      ));
    } else {
      // Insert new book
      return insertBook(book);
    }
  }

  // ==================== Page Statistics Operations ====================

  /// Get all page statistics for a book
  List<PageStatData> getPageStatsForBook(int idBook) {
    final stmt = database.prepare('SELECT * FROM page_stat_data WHERE id_book = ? ORDER BY page ASC, start_time ASC');
    try {
      stmt.execute([idBook]);
      final result = stmt.select();
      final columnNames = result.columnNames;
      return result.map((row) => PageStatData.fromRow(row, columnNames)).toList();
    } finally {
      stmt.dispose();
    }
  }

  /// Get page statistics for a specific page
  List<PageStatData> getPageStatsForPage(int idBook, int page) {
    final stmt = database.prepare('SELECT * FROM page_stat_data WHERE id_book = ? AND page = ? ORDER BY start_time ASC');
    try {
      stmt.execute([idBook, page]);
      final result = stmt.select();
      final columnNames = result.columnNames;
      return result.map((row) => PageStatData.fromRow(row, columnNames)).toList();
    } finally {
      stmt.dispose();
    }
  }

  /// Insert a page statistic
  int insertPageStat(PageStatData pageStat) {
    if (pageStat.idBook == null) {
      throw Exception('id_book is required for page statistics');
    }
    final stmt = database.prepare('''
      INSERT OR REPLACE INTO page_stat_data (id_book, page, start_time, duration, total_pages)
      VALUES (?, ?, ?, ?, ?)
    ''');
    try {
      stmt.execute([
        pageStat.idBook,
        pageStat.page,
        pageStat.startTime,
        pageStat.duration,
        pageStat.totalPages,
      ]);
      return database.lastInsertRowId;
    } finally {
      stmt.dispose();
    }
  }

  /// Insert multiple page statistics
  void insertPageStats(List<PageStatData> pageStats) {
    final stmt = database.prepare('''
      INSERT OR REPLACE INTO page_stat_data (id_book, page, start_time, duration, total_pages)
      VALUES (?, ?, ?, ?, ?)
    ''');
    try {
      database.execute('BEGIN TRANSACTION');
      for (var stat in pageStats) {
        if (stat.idBook == null) continue;
        stmt.execute([
          stat.idBook,
          stat.page,
          stat.startTime,
          stat.duration,
          stat.totalPages,
        ]);
      }
      database.execute('COMMIT');
    } catch (e) {
      database.execute('ROLLBACK');
      rethrow;
    } finally {
      stmt.dispose();
    }
  }

  /// Delete page statistics for a book
  int deletePageStatsForBook(int idBook) {
    final stmt = database.prepare('DELETE FROM page_stat_data WHERE id_book = ?');
    try {
      stmt.execute([idBook]);
      return database.lastInsertRowId;
    } finally {
      stmt.dispose();
    }
  }

  /// Delete a specific page statistic
  int deletePageStat(int idBook, int page, int startTime) {
    final stmt = database.prepare('DELETE FROM page_stat_data WHERE id_book = ? AND page = ? AND start_time = ?');
    try {
      stmt.execute([idBook, page, startTime]);
      return database.lastInsertRowId;
    } finally {
      stmt.dispose();
    }
  }

  /// Get reading statistics summary for a book
  Map<String, dynamic> getReadingSummary(int idBook) {
    final stmt = database.prepare('''
      SELECT 
        COUNT(DISTINCT page) as unique_pages_read,
        SUM(duration) as total_duration,
        MIN(start_time) as first_read,
        MAX(start_time) as last_read
      FROM page_stat_data
      WHERE id_book = ?
    ''');
    try {
      stmt.execute([idBook]);
      final result = stmt.select();
      final columnNames = result.columnNames;
      if (result.isEmpty) {
        return {
          'unique_pages_read': 0,
          'total_duration': 0,
          'first_read': null,
          'last_read': null,
        };
      }
      final row = result.first;
      int getIndex(String name) => columnNames.indexOf(name);
      return {
        'unique_pages_read': row[getIndex('unique_pages_read')] as int? ?? 0,
        'total_duration': row[getIndex('total_duration')] as int? ?? 0,
        'first_read': row[getIndex('first_read')] as int?,
        'last_read': row[getIndex('last_read')] as int?,
      };
    } finally {
      stmt.dispose();
    }
  }
}
