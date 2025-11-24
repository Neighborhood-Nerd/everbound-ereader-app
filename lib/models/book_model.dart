class BookModel {
  final String id;
  final String title;
  final String author;
  final String? coverImageUrl;
  final double? rating;
  final String? category;
  final int? reviewsCount;
  final int? pages;
  final List<String>? genres;
  final String? description;
  final String? series;
  final double? progressPercentage; // 0.0 to 1.0
  final String? lastReadStatus; // e.g., "All pages finish", "Just read recently", "Read 2 weeks ago"
  final DateTime? lastReadAt; // Timestamp of when the book was last read
  final String? epubFilePath; // Path to EPUB file for reading

  BookModel({
    required this.id,
    required this.title,
    required this.author,
    this.coverImageUrl,
    this.rating,
    this.category,
    this.reviewsCount,
    this.pages,
    this.genres,
    this.description,
    this.series,
    this.progressPercentage,
    this.lastReadStatus,
    this.lastReadAt,
    this.epubFilePath,
  });
}
