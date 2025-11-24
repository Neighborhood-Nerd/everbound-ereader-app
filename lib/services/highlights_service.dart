import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import '../models/highlight_model.dart';
import 'notes_service.dart';
import '../models/note_model.dart';

/// Service for managing highlights persistence in JSON files
class HighlightsService {
  static final HighlightsService _instance = HighlightsService._internal();
  factory HighlightsService() => _instance;
  HighlightsService._internal();

  /// Get the cache directory for storing highlight files
  Future<Directory> _getCacheDirectory() async {
    try {
      final cacheDir = await getApplicationCacheDirectory();
      final highlightsDir = Directory(path.join(cacheDir.path, 'highlights'));
      if (!await highlightsDir.exists()) {
        await highlightsDir.create(recursive: true);
      }
      return highlightsDir;
    } catch (e) {
      // Fallback to temporary directory if cache directory fails
      final tempDir = Directory.systemTemp;
      final highlightsDir = Directory(path.join(tempDir.path, 'highlights'));
      if (!await highlightsDir.exists()) {
        await highlightsDir.create(recursive: true);
      }
      return highlightsDir;
    }
  }

  /// Generate a unique file identifier from book path or ID
  String _getBookIdentifier(String? bookId, String epubFilePath) {
    if (bookId != null) {
      return 'book_$bookId.json';
    }
    // Use a hash of the file path as identifier
    // Remove any problematic characters from the path
    final safePath = epubFilePath.replaceAll(RegExp(r'[^\w\-_\.]'), '_');
    // Use last 100 characters to avoid overly long filenames
    final shortPath = safePath.length > 100 ? safePath.substring(safePath.length - 100) : safePath;
    return '${shortPath.hashCode.abs()}.json';
  }

  /// Get the file path for a book's highlights
  Future<File> _getHighlightFile(String? bookId, String epubFilePath) async {
    final cacheDir = await _getCacheDirectory();
    final fileName = _getBookIdentifier(bookId, epubFilePath);
    return File(path.join(cacheDir.path, fileName));
  }

  /// Save highlights for a book
  Future<void> saveHighlights(String? bookId, String epubFilePath, List<HighlightModel> highlights) async {
    try {
      final file = await _getHighlightFile(bookId, epubFilePath);
      final jsonData = highlights.map((h) => h.toJson()).toList();
      await file.writeAsString(jsonEncode(jsonData));
      print('Saved ${highlights.length} highlights for book ${bookId ?? epubFilePath}');
    } catch (e) {
      print('Error saving highlights: $e');
    }
  }

  /// Load highlights for a book (includes both highlights and notes)
  Future<List<HighlightModel>> loadHighlights(String? bookId, String epubFilePath) async {
    try {
      final file = await _getHighlightFile(bookId, epubFilePath);
      List<HighlightModel> highlights = [];
      
      if (await file.exists()) {
        final jsonString = await file.readAsString();
        final jsonData = jsonDecode(jsonString) as List<dynamic>;
        highlights = jsonData.map((json) => HighlightModel.fromJson(json as Map<String, dynamic>)).toList();
      }
      
      // Try to migrate notes from old notes service (one-time migration)
      final migrated = await _migrateNotesFromOldService(bookId, epubFilePath, highlights);
      if (migrated.isNotEmpty) {
        highlights = [...highlights, ...migrated];
        await saveHighlights(bookId, epubFilePath, highlights);
      }
      
      print('Loaded ${highlights.length} annotations (${highlights.where((h) => h.isHighlight).length} highlights, ${highlights.where((h) => h.isNote).length} notes) for book ${bookId ?? epubFilePath}');
      
      return highlights;
    } catch (e) {
      print('Error loading highlights: $e');
      return [];
    }
  }

  /// Migrate notes from the old NotesService to unified HighlightsService
  Future<List<HighlightModel>> _migrateNotesFromOldService(String? bookId, String epubFilePath, List<HighlightModel> existingHighlights) async {
    try {
      final notesService = NotesService();
      final notes = await notesService.loadNotes(bookId, epubFilePath);
      if (notes.isEmpty) return [];

      print('Migrating ${notes.length} notes from old service to unified highlights...');
      
      final existingNoteIds = existingHighlights.where((h) => h.isNote).map((h) => h.id).toSet();
      
      // Convert notes to highlights with note text filled
      final migratedHighlights = notes.map((note) {
        // Skip if already migrated
        if (existingNoteIds.contains(note.id)) return null;
        
        return HighlightModel(
          id: note.id,
          cfi: note.cfi,
          colorHex: '#FFEB3B', // Default yellow for notes
          opacity: 0.4,
          createdAt: note.createdAt,
          updatedAt: note.updatedAt,
          note: note.text, // Fill note text to mark as note
          selectedText: note.selectedText,
          type: 'highlight',
        );
      }).whereType<HighlightModel>().toList();
      
      if (migratedHighlights.isNotEmpty) {
        print('Migrated ${migratedHighlights.length} notes successfully');
      }
      
      return migratedHighlights;
    } catch (e) {
      print('Error migrating notes: $e');
      return [];
    }
  }

  /// Add a single highlight or note
  Future<void> addHighlight(String? bookId, String epubFilePath, HighlightModel highlight) async {
    final existing = await loadHighlights(bookId, epubFilePath);
    // Check if annotation with same ID already exists (for notes) or same CFI (for highlights)
    final updated = highlight.isNote
        ? existing.where((h) => h.id != highlight.id).toList()
        : existing.where((h) => h.cfi != highlight.cfi || h.isNote).toList();
    updated.add(highlight);
    await saveHighlights(bookId, epubFilePath, updated);
  }

  /// Remove a highlight by CFI or note by ID
  Future<void> removeHighlight(String? bookId, String epubFilePath, String cfi) async {
    final existing = await loadHighlights(bookId, epubFilePath);
    final updated = existing.where((h) => h.cfi != cfi && h.id != cfi).toList();
    await saveHighlights(bookId, epubFilePath, updated);
  }

  /// Remove a note by ID
  Future<void> removeNote(String? bookId, String epubFilePath, String noteId) async {
    final existing = await loadHighlights(bookId, epubFilePath);
    final updated = existing.where((h) => h.id != noteId).toList();
    await saveHighlights(bookId, epubFilePath, updated);
  }

  /// Update an existing annotation (highlight or note)
  /// Updates the annotation with the given ID in the unified storage
  Future<void> updateAnnotation(String? bookId, String epubFilePath, HighlightModel annotation) async {
    final existing = await loadHighlights(bookId, epubFilePath);
    final index = existing.indexWhere((h) => h.id == annotation.id);
    if (index != -1) {
      existing[index] = annotation.copyWith(updatedAt: DateTime.now());
      await saveHighlights(bookId, epubFilePath, existing);
    }
  }

  /// Clear all highlights for a book
  Future<void> clearHighlights(String? bookId, String epubFilePath) async {
    await saveHighlights(bookId, epubFilePath, []);
  }

  /// Delete the highlights file for a book
  Future<void> deleteHighlightsFile(String? bookId, String epubFilePath) async {
    try {
      final file = await _getHighlightFile(bookId, epubFilePath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      print('Error deleting highlights file: $e');
    }
  }
}

