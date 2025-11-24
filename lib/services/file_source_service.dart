import 'dart:io' as io;
import 'package:path/path.dart' as path;
import 'package:webdav_client/webdav_client.dart';
import '../models/file_source_model.dart';
import '../services/local_database_service.dart';
import '../services/book_import_service.dart';

class FileSourceService {
  static final FileSourceService instance = FileSourceService._internal();
  factory FileSourceService() => instance;
  FileSourceService._internal();

  /// Scan all configured file sources for EPUB books
  Future<ScanResult> scanAllSources({
    Function(String)? onProgress,
    Function(int sourceId, int booksFound, int booksImported)? onSourceProgress,
  }) async {
    final dbService = LocalDatabaseService.instance;
    await dbService.initialize();

    final sources = dbService.getAllFileSources();
    if (sources.isEmpty) {
      return ScanResult(scanned: 0, imported: 0, errors: []);
    }

    int totalScanned = 0;
    int totalImported = 0;
    final List<String> errors = [];

    for (final source in sources) {
      try {
        onProgress?.call('Scanning ${source.name}...');
        final result = await scanSource(
          source.id!,
          onProgress: (booksFound, booksImported) {
            onSourceProgress?.call(source.id!, booksFound, booksImported);
          },
        );
        totalScanned += result.scanned;
        totalImported += result.imported;
        errors.addAll(result.errors);

        // Update last scanned timestamp
        dbService.updateFileSourceLastScanned(source.id!, DateTime.now());
      } catch (e) {
        errors.add('Error scanning ${source.name}: $e');
      }
    }

    return ScanResult(scanned: totalScanned, imported: totalImported, errors: errors);
  }

  /// Scan a specific file source
  Future<ScanResult> scanSource(
    int sourceId, {
    Function(int booksFound, int booksImported)? onProgress,
  }) async {
    final dbService = LocalDatabaseService.instance;
    await dbService.initialize();

    final source = dbService.getFileSourceById(sourceId);
    if (source == null) {
      throw Exception('File source not found');
    }

    switch (source.type) {
      case FileSourceType.local:
        return await _scanLocalSource(source, onProgress: onProgress);
      case FileSourceType.webdav:
        return await _scanWebDavSource(source, onProgress: onProgress);
    }
  }

  /// Scan local folder recursively for EPUB files
  Future<ScanResult> _scanLocalSource(
    FileSource source, {
    Function(int booksFound, int booksImported)? onProgress,
  }) async {
    if (source.localPath == null || source.localPath!.isEmpty) {
      return ScanResult(scanned: 0, imported: 0, errors: ['Local path not configured']);
    }

    final directory = io.Directory(source.localPath!);
    if (!await directory.exists()) {
      return ScanResult(scanned: 0, imported: 0, errors: ['Directory does not exist: ${source.localPath}']);
    }

    final epubFiles = <String>[];
    await _findEpubFiles(directory, epubFiles);

    // Report books found
    onProgress?.call(epubFiles.length, 0);

    return await _importFiles(epubFiles, source.name, onProgress: onProgress);
  }

  /// Scan WebDAV folder recursively for EPUB files
  Future<ScanResult> _scanWebDavSource(
    FileSource source, {
    Function(int booksFound, int booksImported)? onProgress,
  }) async {
    if (source.url == null || source.url!.isEmpty) {
      return ScanResult(scanned: 0, imported: 0, errors: ['WebDAV URL not configured']);
    }

    if (source.selectedPath == null || source.selectedPath!.isEmpty) {
      return ScanResult(scanned: 0, imported: 0, errors: ['WebDAV folder not selected']);
    }

    try {
      final client = newClient(source.url!, user: source.username ?? '', password: source.password ?? '');
      final epubFiles = <String>[];
      await _findEpubFilesWebDav(client, source.selectedPath!, epubFiles, source);

      // Report books found
      onProgress?.call(epubFiles.length, 0);

      return await _importFilesWebDav(client, epubFiles, source, onProgress: onProgress);
    } catch (e) {
      return ScanResult(scanned: 0, imported: 0, errors: ['Error connecting to WebDAV: $e']);
    }
  }

  /// Recursively find EPUB files in local directory
  /// This method scans all subdirectories recursively to find EPUB files
  Future<void> _findEpubFiles(io.Directory directory, List<String> epubFiles) async {
    try {
      // Use recursive: true to scan all subdirectories
      await for (final entity in directory.list(recursive: true)) {
        if (entity is io.File) {
          final fileName = entity.path.toLowerCase();
          if (fileName.endsWith('.epub')) {
            epubFiles.add(entity.path);
          }
        }
      }
    } catch (e) {
      print('Error scanning directory ${directory.path}: $e');
      // Continue even if there's an error in one directory
      // The recursive scan will continue in other directories
    }
  }

  /// Recursively find EPUB files in WebDAV
  Future<void> _findEpubFilesWebDav(
    Client client,
    String currentPath,
    List<String> epubFiles,
    FileSource source,
  ) async {
    try {
      final items = await client.readDir(currentPath.isEmpty ? '' : currentPath);
      for (final item in items) {
        if (item.name == null) continue;

        // Build the full path for this item
        final itemPath = currentPath.isEmpty
            ? item.name!
            : currentPath.endsWith('/')
            ? '$currentPath${item.name}'
            : '$currentPath/${item.name}';

        if (item.isDir == true) {
          // Recursively scan subdirectories
          await _findEpubFilesWebDav(client, itemPath, epubFiles, source);
        } else if (item.isDir == false) {
          // Check if it's an EPUB file
          final fileName = item.name!.toLowerCase();
          if (fileName.endsWith('.epub')) {
            epubFiles.add(itemPath);
          }
        }
      }
    } catch (e) {
      print('Error scanning WebDAV path $currentPath: $e');
      // Continue scanning other directories even if one fails
    }
  }

  /// Import EPUB files from local source
  Future<ScanResult> _importFiles(
    List<String> epubFiles,
    String sourceName, {
    Function(int booksFound, int booksImported)? onProgress,
  }) async {
    final dbService = LocalDatabaseService.instance;
    await dbService.initialize();
    final importService = BookImportService.instance;

    int imported = 0;
    final List<String> errors = [];

    for (int i = 0; i < epubFiles.length; i++) {
      final filePath = epubFiles[i];
      try {
        // Check if book already exists (by checking if file path is already imported)
        // Note: For local files, we check the original file path
        final existingBook = dbService.getBookByFilePath(filePath);
        if (existingBook != null) {
          // Still report progress even if skipped
          onProgress?.call(epubFiles.length, imported);
          continue; // Skip if already imported
        }

        // Import the book
        await importService.importEpubFile(filePath);
        imported++;
        
        // Report progress after each import
        onProgress?.call(epubFiles.length, imported);
      } catch (e) {
        errors.add('Error importing $filePath: $e');
        // Report progress even on error
        onProgress?.call(epubFiles.length, imported);
      }
    }

    return ScanResult(scanned: epubFiles.length, imported: imported, errors: errors);
  }

  /// Import EPUB files from WebDAV source
  Future<ScanResult> _importFilesWebDav(
    Client client,
    List<String> epubFilePaths,
    FileSource source, {
    Function(int booksFound, int booksImported)? onProgress,
  }) async {
    final dbService = LocalDatabaseService.instance;
    await dbService.initialize();
    final importService = BookImportService.instance;

    int imported = 0;
    final List<String> errors = [];

    // Create a temporary directory for downloads
    final tempDir = io.Directory.systemTemp;
    final downloadDir = io.Directory(path.join(tempDir.path, 'Everbound', 'webdav_downloads'));
    if (!await downloadDir.exists()) {
      await downloadDir.create(recursive: true);
    }

    for (int i = 0; i < epubFilePaths.length; i++) {
      final filePath = epubFilePaths[i];
      try {
        // Check if book already exists by checking original file name
        // We'll need to download and check, or store WebDAV paths separately
        // For now, we'll download and check file path
        final fileName = path.basename(filePath);
        final localFilePath = path.join(downloadDir.path, fileName);

        // Download file from WebDAV
        final fileData = await client.read(filePath);
        final localFile = io.File(localFilePath);
        await localFile.writeAsBytes(fileData);

        // Check if already imported by checking the original file name pattern
        // This is a simple check - we could improve this by storing source info
        final existingBooks = dbService.getAllBooks();
        final alreadyImported = existingBooks.any(
          (book) =>
              book.originalFileName == fileName ||
              (book.filePath.contains(fileName) && book.originalFileName == fileName),
        );

        if (alreadyImported) {
          // Clean up downloaded file
          if (await localFile.exists()) {
            await localFile.delete();
          }
          // Still report progress even if skipped
          onProgress?.call(epubFilePaths.length, imported);
          continue;
        }

        // Import the book
        await importService.importEpubFile(localFilePath);

        // Clean up downloaded file after import (it's been copied to cache)
        if (await localFile.exists()) {
          await localFile.delete();
        }

        imported++;
        
        // Report progress after each import
        onProgress?.call(epubFilePaths.length, imported);
      } catch (e) {
        errors.add('Error importing $filePath: $e');
        // Report progress even on error
        onProgress?.call(epubFilePaths.length, imported);
      }
    }

    // Clean up download directory
    try {
      if (await downloadDir.exists()) {
        await downloadDir.delete(recursive: true);
      }
    } catch (e) {
      print('Error cleaning up download directory: $e');
    }

    return ScanResult(scanned: epubFilePaths.length, imported: imported, errors: errors);
  }
}

/// Result of a scan operation
class ScanResult {
  final int scanned;
  final int imported;
  final List<String> errors;

  ScanResult({required this.scanned, required this.imported, required this.errors});
}
