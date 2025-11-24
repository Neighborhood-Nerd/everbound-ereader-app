/// Model representing a highlight, underline, or note in an EPUB book
/// Unified pattern: highlights have empty note string, notes have filled note string
class HighlightModel {
  /// Unique identifier for the annotation
  final String id;

  /// Canonical Fragment Identifier (CFI) range for the highlight location
  final String cfi;

  /// Color of the highlight in hex format (e.g., "#FFFF00")
  final String colorHex;

  /// Opacity of the highlight (0.0 to 1.0)
  final double opacity;

  /// Timestamp when the highlight was created
  final DateTime createdAt;

  /// Timestamp when the highlight was last updated
  final DateTime updatedAt;

  /// Note text - empty string for highlights, filled for notes
  final String note;

  /// Optional selected text at the time of highlighting
  final String? selectedText;

  /// Type of annotation: 'highlight' or 'underline'
  final String type;

  HighlightModel({
    required this.id,
    required this.cfi,
    required this.colorHex,
    required this.opacity,
    required this.createdAt,
    required this.updatedAt,
    this.note = '',
    this.selectedText,
    this.type = 'highlight',
  });

  /// Check if this is a note (has non-empty note text)
  bool get isNote => note.isNotEmpty;

  /// Check if this is a highlight (has empty note text)
  bool get isHighlight => note.isEmpty;

  /// Convert to JSON for storage
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'cfi': cfi,
      'colorHex': colorHex,
      'opacity': opacity,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'note': note,
      'selectedText': selectedText,
      'type': type,
    };
  }

  /// Create from JSON
  factory HighlightModel.fromJson(Map<String, dynamic> json) {
    // Handle migration: if id is missing, generate one from CFI
    final id = json['id'] as String? ?? 'highlight_${json['cfi'] as String}';
    // Handle migration: if updatedAt is missing, use createdAt
    final updatedAt = json['updatedAt'] != null
        ? DateTime.parse(json['updatedAt'] as String)
        : DateTime.parse(json['createdAt'] as String);
    // Handle migration: note might be null, default to empty string
    final note = json['note'] as String? ?? '';

    return HighlightModel(
      id: id,
      cfi: json['cfi'] as String,
      colorHex: json['colorHex'] as String,
      opacity: (json['opacity'] as num).toDouble(),
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: updatedAt,
      note: note,
      selectedText: json['selectedText'] as String?,
      type: json['type'] as String? ?? 'highlight',
    );
  }

  /// Create a copy with updated fields
  HighlightModel copyWith({
    String? id,
    String? cfi,
    String? colorHex,
    double? opacity,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? note,
    String? selectedText,
    String? type,
  }) {
    return HighlightModel(
      id: id ?? this.id,
      cfi: cfi ?? this.cfi,
      colorHex: colorHex ?? this.colorHex,
      opacity: opacity ?? this.opacity,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      note: note ?? this.note,
      selectedText: selectedText ?? this.selectedText,
      type: type ?? this.type,
    );
  }
}
