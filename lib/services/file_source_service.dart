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

        dbService.updateFileSourceLastScanned(source.id!, DateTime.now());
      } catch (e) {
        errors.add('Error scanning ${source.name}: $e');
      }
    }

    return ScanResult(
      scanned: totalScanned,
      imported: totalImported,
      errors: errors,
    );
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
      return ScanResult(
        scanned: 0,
        imported: 0,
        errors: ['Local path not configured'],
      );
    }

    final directory = io.Directory(source.localPath!);

    if (!await directory.exists()) {
      return ScanResult(
        scanned: 0,
        imported: 0,
        errors: ['Directory does not exist: ${source.localPath}'],
      );
    }

    final epubFiles = <String>[];
    try {
      await _findEpubFiles(directory, epubFiles);
    } catch (e) {
      String errorMessage = e.toString();

      // If the error contains our detailed scoped storage message, extract it
      if (e.toString().contains('scoped storage') ||
          e.toString().contains(
            'Cannot access directory contents due to Android',
          )) {
        // Extract the detailed message from the exception chain
        errorMessage = e.toString();

        // Try to extract just the helpful part (the detailed message)
        // Look for the part that starts with "Cannot access directory contents"
        final detailedStart = errorMessage.indexOf(
          'Cannot access directory contents',
        );
        if (detailedStart != -1) {
          errorMessage = errorMessage.substring(detailedStart);
          // Remove any trailing "Please check file permissions" or similar
          final checkIndex = errorMessage.indexOf(
            '. Please check file permissions',
          );
          if (checkIndex != -1) {
            errorMessage = errorMessage.substring(0, checkIndex);
          }
        } else {
          // Fallback: remove common prefixes
          errorMessage = errorMessage
              .replaceAll(RegExp(r'^Exception:\s*'), '')
              .replaceAll(RegExp(r'^Cannot read directory[^:]*:\s*'), '');
        }
      } else if (e.toString().contains('Permission') ||
          e.toString().contains('permission') ||
          e.toString().contains('access denied') ||
          e.toString().contains('Access denied')) {
        errorMessage =
            'Permission denied: Cannot read directory. Please grant storage permissions in app settings.';
      } else if (e.toString().contains('Cannot read directory')) {
        errorMessage = e.toString();
        // Remove the outer "Exception: " wrapper if present
        errorMessage = errorMessage
            .replaceAll(RegExp(r'^Exception:\s*'), '')
            .replaceAll(RegExp(r'^Cannot read directory[^:]*:\s*'), '');
      }
      return ScanResult(scanned: 0, imported: 0, errors: [errorMessage]);
    }

    // Report books found
    onProgress?.call(epubFiles.length, 0);

    if (epubFiles.isEmpty) {
      // Check if directory is actually readable by trying to list it
      try {
        final testList = directory.list();
        final hasItems = await testList.isEmpty;
        if (hasItems) {
          return ScanResult(
            scanned: 0,
            imported: 0,
            errors: [
              'No EPUB files found in directory. The directory appears to be empty or contains no .epub files.',
            ],
          );
        }
      } catch (e) {
        return ScanResult(
          scanned: 0,
          imported: 0,
          errors: [
            'Cannot access directory contents. Please check file permissions. Error: $e',
          ],
        );
      }
      return ScanResult(
        scanned: 0,
        imported: 0,
        errors: ['No EPUB files found in directory'],
      );
    }

    return await _importFiles(epubFiles, source.name, onProgress: onProgress);
  }

  /// Scan WebDAV folder recursively for EPUB files
  Future<ScanResult> _scanWebDavSource(
    FileSource source, {
    Function(int booksFound, int booksImported)? onProgress,
  }) async {
    if (source.url == null || source.url!.isEmpty) {
      return ScanResult(
        scanned: 0,
        imported: 0,
        errors: ['WebDAV URL not configured'],
      );
    }

    if (source.selectedPath == null || source.selectedPath!.isEmpty) {
      return ScanResult(
        scanned: 0,
        imported: 0,
        errors: ['WebDAV folder not selected'],
      );
    }

    try {
      final client = newClient(
        source.url!,
        user: source.username ?? '',
        password: source.password ?? '',
      );
      final epubFiles = <String>[];
      await _findEpubFilesWebDav(
        client,
        source.selectedPath!,
        epubFiles,
        source,
      );

      // Report books found
      onProgress?.call(epubFiles.length, 0);

      return await _importFilesWebDav(
        client,
        epubFiles,
        source,
        onProgress: onProgress,
      );
    } catch (e) {
      return ScanResult(
        scanned: 0,
        imported: 0,
        errors: ['Error connecting to WebDAV: $e'],
      );
    }
  }

  /// Recursively find EPUB files in local directory
  /// This method scans all subdirectories recursively to find EPUB files
  Future<void> _findEpubFiles(
    io.Directory directory,
    List<String> epubFiles,
  ) async {
    try {
      if (!await directory.exists()) {
        throw Exception(
          'Directory does not exist or is not accessible: ${directory.path}',
        );
      }

      final testList = directory.list();
      final items = await testList.toList();

      if (items.isEmpty) {
        try {
          final testPath = '${directory.path}/.test_access_check';
          final testFile = io.File(testPath);
          final parentExists = await testFile.parent.exists();

          if (parentExists) {
            throw Exception(
              'Cannot access directory contents due to Android scoped storage restrictions. '
              'Please try one of these solutions:\n'
              '1. Grant "All files access" permission in Android Settings > Apps > Everbound > Permissions\n'
              '2. Use a directory in the app\'s own storage (Android/data/com.neighborhoodnerd.everbound)\n'
              '3. Select the directory again using the file picker to refresh permissions',
            );
          }
        } catch (e) {
          if (e.toString().contains('scoped storage')) {
            rethrow;
          }
        }
      }

      try {
        await for (final entity in directory.list(recursive: true)) {
          if (entity is io.File) {
            final fileName = entity.path.toLowerCase();
            if (fileName.endsWith('.epub')) {
              epubFiles.add(entity.path);
            }
          }
        }
      } catch (e) {
        await for (final entity in directory.list()) {
          if (entity is io.File) {
            final fileName = entity.path.toLowerCase();
            if (fileName.endsWith('.epub')) {
              epubFiles.add(entity.path);
            }
          }
        }
      }
    } catch (e) {
      rethrow;
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
      final items = await client.readDir(
        currentPath.isEmpty ? '' : currentPath,
      );
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
        final file = io.File(filePath);
        if (!await file.exists()) {
          errors.add('File does not exist: $filePath');
          onProgress?.call(epubFiles.length, imported);
          continue;
        }

        final fileName = path.basename(filePath);
        final existingBooks = dbService.getAllBooks();
        final alreadyImported = existingBooks.any(
          (book) => book.originalFileName == fileName,
        );

        if (alreadyImported) {
          onProgress?.call(epubFiles.length, imported);
          continue;
        }

        await importService.importEpubFile(filePath);
        imported++;
        onProgress?.call(epubFiles.length, imported);
      } catch (e) {
        errors.add('Error importing $filePath: $e');
        onProgress?.call(epubFiles.length, imported);
      }
    }
    return ScanResult(
      scanned: epubFiles.length,
      imported: imported,
      errors: errors,
    );
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
    final downloadDir = io.Directory(
      path.join(tempDir.path, 'Everbound', 'webdav_downloads'),
    );
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
              (book.filePath.contains(fileName) &&
                  book.originalFileName == fileName),
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
      // Ignore cleanup errors
    }

    return ScanResult(
      scanned: epubFilePaths.length,
      imported: imported,
      errors: errors,
    );
  }
}

/// Result of a scan operation
class ScanResult {
  final int scanned;
  final int imported;
  final List<String> errors;

  ScanResult({
    required this.scanned,
    required this.imported,
    required this.errors,
  });
}
