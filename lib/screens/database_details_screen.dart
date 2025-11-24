import 'package:flutter/material.dart';
import '../colors.dart';
import '../services/koreader_database_service.dart';

class DatabaseDetailsScreen extends StatefulWidget {
  final String filePath;
  final String fileName;

  const DatabaseDetailsScreen({super.key, required this.filePath, required this.fileName});

  @override
  State<DatabaseDetailsScreen> createState() => _DatabaseDetailsScreenState();
}

class _DatabaseDetailsScreenState extends State<DatabaseDetailsScreen> {
  final _dbService = KoReaderDatabaseService.instance;
  bool _isLoading = true;
  String? _error;
  List<Book> _books = [];
  Map<String, int> _statistics = {};

  @override
  void initState() {
    super.initState();
    _loadDatabaseInfo();
  }

  Future<void> _loadDatabaseInfo() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Initialize database service
      await _dbService.initialize(widget.filePath);

      // Load books
      final books = _dbService.getAllBooks();

      // Calculate statistics
      int totalBooks = books.length;
      int totalPages = 0;
      int totalReadTime = 0;
      int booksWithStats = 0;

      for (var book in books) {
        if (book.pages != null) totalPages += book.pages!;
        if (book.totalReadTime != null) totalReadTime += book.totalReadTime!;
        if (book.totalReadPages != null && book.totalReadPages! > 0) {
          booksWithStats++;
        }
      }

      setState(() {
        _books = books;
        _statistics = {
          'total_books': totalBooks,
          'total_pages': totalPages,
          'total_read_time': totalReadTime,
          'books_with_stats': booksWithStats,
        };
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  String _formatReadTime(int seconds) {
    if (seconds < 60) return '$seconds seconds';
    if (seconds < 3600) return '${(seconds / 60).toStringAsFixed(1)} minutes';
    return '${(seconds / 3600).toStringAsFixed(1)} hours';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.fileName)),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 64, color: primaryColor),
                  const SizedBox(height: 16),
                  Text('Error loading database', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: primaryColor),
                    ),
                  ),
                ],
              ),
            )
          : SingleChildScrollView(
              child: Column(
                children: [
                  // Statistics card
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.all(16.0),
                    padding: const EdgeInsets.all(16.0),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue[200]!),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Database Statistics', style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 16),
                        _buildStatRow('Total Books', '${_statistics['total_books'] ?? 0}'),
                        _buildStatRow('Total Pages', '${_statistics['total_pages'] ?? 0}'),
                        _buildStatRow('Books with Reading Data', '${_statistics['books_with_stats'] ?? 0}'),
                        _buildStatRow('Total Reading Time', _formatReadTime(_statistics['total_read_time'] ?? 0)),
                      ],
                    ),
                  ),
                  // Books list header
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Row(
                      children: [Text('Books (${_books.length})', style: Theme.of(context).textTheme.titleMedium)],
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Books list
                  _books.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Center(
                            child: Text('No books found', style: TextStyle(color: Colors.grey[600])),
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          padding: const EdgeInsets.symmetric(horizontal: 16.0),
                          itemCount: _books.length,
                          itemBuilder: (context, index) {
                            final book = _books[index];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8.0),
                              child: ListTile(
                                title: Text(book.title ?? 'Unknown Title'),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (book.authors != null) Text('Author: ${book.authors}'),
                                    if (book.pages != null) Text('Pages: ${book.pages}'),
                                    if (book.md5 != null)
                                      Text(
                                        'MD5: ${book.md5}',
                                        style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: Colors.grey[700]),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    if (book.totalReadPages != null && book.totalReadPages! > 0)
                                      Text(
                                        'Read: ${book.totalReadPages}/${book.pages ?? 0} pages',
                                        style: TextStyle(color: Colors.green[700]),
                                      ),
                                    if (book.totalReadTime != null && book.totalReadTime! > 0)
                                      Text(
                                        'Reading Time: ${_formatReadTime(book.totalReadTime!)}',
                                        style: TextStyle(color: Colors.blue[700]),
                                      ),
                                  ],
                                ),
                                trailing: book.lastOpen != null
                                    ? Text(_formatDate(book.lastOpen!), style: const TextStyle(fontSize: 12))
                                    : null,
                              ),
                            );
                          },
                        ),
                ],
              ),
            ),
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  String _formatDate(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}
