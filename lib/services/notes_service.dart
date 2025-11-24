import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import '../models/note_model.dart';

/// Service for managing notes persistence in JSON files
class NotesService {
  static final NotesService _instance = NotesService._internal();
  factory NotesService() => _instance;
  NotesService._internal();

  /// Get the cache directory for storing note files
  Future<Directory> _getCacheDirectory() async {
    try {
      final cacheDir = await getApplicationCacheDirectory();
      final notesDir = Directory(path.join(cacheDir.path, 'notes'));
      if (!await notesDir.exists()) {
        await notesDir.create(recursive: true);
      }
      return notesDir;
    } catch (e) {
      // Fallback to temporary directory if cache directory fails
      final tempDir = Directory.systemTemp;
      final notesDir = Directory(path.join(tempDir.path, 'notes'));
      if (!await notesDir.exists()) {
        await notesDir.create(recursive: true);
      }
      return notesDir;
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

  /// Get the file path for a book's notes
  Future<File> _getNotesFile(String? bookId, String epubFilePath) async {
    final cacheDir = await _getCacheDirectory();
    final fileName = _getBookIdentifier(bookId, epubFilePath);
    return File(path.join(cacheDir.path, fileName));
  }

  /// Save notes for a book
  Future<void> saveNotes(String? bookId, String epubFilePath, List<NoteModel> notes) async {
    try {
      final file = await _getNotesFile(bookId, epubFilePath);
      final jsonData = notes.map((n) => n.toJson()).toList();
      await file.writeAsString(jsonEncode(jsonData));
      print('Saved ${notes.length} notes for book ${bookId ?? epubFilePath}');
    } catch (e) {
      print('Error saving notes: $e');
    }
  }

  /// Load notes for a book
  Future<List<NoteModel>> loadNotes(String? bookId, String epubFilePath) async {
    try {
      final file = await _getNotesFile(bookId, epubFilePath);
      if (!await file.exists()) {
        return [];
      }

      final jsonString = await file.readAsString();
      final jsonData = jsonDecode(jsonString) as List<dynamic>;
      final notes = jsonData.map((json) => NoteModel.fromJson(json as Map<String, dynamic>)).toList();
      print('Loaded ${notes.length} notes for book ${bookId ?? epubFilePath}');
      return notes;
    } catch (e) {
      print('Error loading notes: $e');
      return [];
    }
  }

  /// Add a single note
  Future<void> addNote(String? bookId, String epubFilePath, NoteModel note) async {
    final existing = await loadNotes(bookId, epubFilePath);
    existing.add(note);
    await saveNotes(bookId, epubFilePath, existing);
  }

  /// Update an existing note
  Future<void> updateNote(String? bookId, String epubFilePath, NoteModel note) async {
    final existing = await loadNotes(bookId, epubFilePath);
    final index = existing.indexWhere((n) => n.id == note.id);
    if (index != -1) {
      existing[index] = note;
      await saveNotes(bookId, epubFilePath, existing);
    }
  }

  /// Remove a note by ID
  Future<void> removeNote(String? bookId, String epubFilePath, String noteId) async {
    final existing = await loadNotes(bookId, epubFilePath);
    final updated = existing.where((n) => n.id != noteId).toList();
    await saveNotes(bookId, epubFilePath, updated);
  }

  /// Clear all notes for a book
  Future<void> clearNotes(String? bookId, String epubFilePath) async {
    await saveNotes(bookId, epubFilePath, []);
  }

  /// Delete the notes file for a book
  Future<void> deleteNotesFile(String? bookId, String epubFilePath) async {
    try {
      final file = await _getNotesFile(bookId, epubFilePath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      print('Error deleting notes file: $e');
    }
  }
}



