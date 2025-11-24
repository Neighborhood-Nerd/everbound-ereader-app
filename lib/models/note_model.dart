/// Model representing a standalone note in an EPUB book
class NoteModel {
  /// Unique identifier for the note
  final String id;

  /// Canonical Fragment Identifier (CFI) for the note location
  final String cfi;

  /// The note text content
  final String text;

  /// Optional selected text at the time of note creation
  final String? selectedText;

  /// Timestamp when the note was created
  final DateTime createdAt;

  /// Timestamp when the note was last updated
  final DateTime updatedAt;

  NoteModel({
    required this.id,
    required this.cfi,
    required this.text,
    this.selectedText,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Convert to JSON for storage
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'cfi': cfi,
      'text': text,
      'selectedText': selectedText,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  /// Create from JSON
  factory NoteModel.fromJson(Map<String, dynamic> json) {
    return NoteModel(
      id: json['id'] as String,
      cfi: json['cfi'] as String,
      text: json['text'] as String,
      selectedText: json['selectedText'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  /// Create a copy with updated fields
  NoteModel copyWith({
    String? id,
    String? cfi,
    String? text,
    String? selectedText,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return NoteModel(
      id: id ?? this.id,
      cfi: cfi ?? this.cfi,
      text: text ?? this.text,
      selectedText: selectedText ?? this.selectedText,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}



