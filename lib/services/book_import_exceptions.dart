/// Custom exceptions for book import operations

/// Exception thrown when attempting to import a duplicate book
class DuplicateBookException implements Exception {
  final String bookTitle;
  final String bookAuthor;

  DuplicateBookException(this.bookTitle, this.bookAuthor);

  @override
  String toString() => 'This book is already in your library:\n\n"$bookTitle"\nby $bookAuthor';
}

/// Exception thrown when the source file is not found or inaccessible
class BookFileNotFoundException implements Exception {
  final String filePath;

  BookFileNotFoundException(this.filePath);

  @override
  String toString() => 'Could not find the book file. Please make sure the file exists and try again.';
}

/// Exception thrown when EPUB file parsing fails
class InvalidEpubException implements Exception {
  InvalidEpubException();

  @override
  String toString() => 'This file appears to be corrupted or is not a valid EPUB file.';
}

/// Exception thrown when metadata extraction fails
class MetadataExtractionException implements Exception {
  MetadataExtractionException();

  @override
  String toString() => 'Unable to read book information. The file may be corrupted.';
}

/// Generic book import exception for unexpected errors
class BookImportException implements Exception {
  final String message;

  BookImportException(this.message);

  @override
  String toString() => message;
}











