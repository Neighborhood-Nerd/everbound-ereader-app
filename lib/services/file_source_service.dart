import 'dart:io' as io;
import 'dart:async';
import 'package:path/path.dart' as path;
import 'package:webdav_client/webdav_client.dart';
import 'package:security_scoped_resource/security_scoped_resource.dart';
import '../models/file_source_model.dart';
import '../services/local_database_service.dart';
import '../services/book_import_service.dart';
import '../services/ios_bookmark_service.dart';
import '../services/logger_service.dart';

const String _fileSourceTag = 'FileSourceService';

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

    ScanResult result;
    switch (source.type) {
      case FileSourceType.local:
        result = await _scanLocalSource(source, onProgress: onProgress);
        break;
      case FileSourceType.webdav:
        result = await _scanWebDavSource(source, onProgress: onProgress);
        break;
    }

    // Update last scanned timestamp
    dbService.updateFileSourceLastScanned(sourceId, DateTime.now());

    return result;
  }

  /// Scan local folder recursively for EPUB files
  Future<ScanResult> _scanLocalSource(
    FileSource source, {
    Function(int booksFound, int booksImported)? onProgress,
  }) async {
    logger.info(
      _fileSourceTag,
      'Starting scan of local source: ${source.name} (ID: ${source.id})',
    );
    logger.info(_fileSourceTag, 'Source path: ${source.localPath}');
    logger.info(_fileSourceTag, 'Platform: ${io.Platform.operatingSystem}');

    String? directoryPath = source.localPath;
    bool shouldStopAccessing = false;

    // On iOS, use bookmark to resolve path if available
    if (io.Platform.isIOS &&
        source.bookmarkData != null &&
        source.bookmarkData!.isNotEmpty) {
      logger.info(_fileSourceTag, 'iOS: Resolving bookmark...');
      final bookmarkService = IOSBookmarkService.instance;

      // Resolve bookmark to get path
      final resolvedPath = await bookmarkService.resolveBookmark(
        source.bookmarkData!,
      );
      if (resolvedPath != null) {
        logger.info(_fileSourceTag, 'iOS: Bookmark resolved to: $resolvedPath');
        directoryPath = resolvedPath;
      } else {
        logger.warning(_fileSourceTag, 'iOS: Failed to resolve bookmark');
      }
    }

    if (directoryPath == null || directoryPath.isEmpty) {
      logger.error(_fileSourceTag, 'Directory path is null or empty');
      return ScanResult(
        scanned: 0,
        imported: 0,
        errors: ['Local path not configured'],
      );
    }

    logger.info(_fileSourceTag, 'Using directory path: $directoryPath');
    final directory = io.Directory(directoryPath);

    // On iOS, start accessing security-scoped resource using the package
    if (io.Platform.isIOS) {
      final accessGranted = await SecurityScopedResource.instance
          .startAccessingSecurityScopedResource(directory);
      if (!accessGranted) {
        return ScanResult(
          scanned: 0,
          imported: 0,
          errors: ['Failed to access folder. Please reselect the folder.'],
        );
      }
      shouldStopAccessing = true;
    }

    // On iOS, be more lenient with directory access checks
    // Security-scoped resources may not be immediately accessible
    // Let the actual file scanning handle access errors
    if (!io.Platform.isIOS) {
      // On non-iOS platforms, do standard validation
      logger.info(_fileSourceTag, 'Checking if directory exists...');
      bool directoryExists = false;
      try {
        directoryExists = await directory.exists();
        logger.info(
          _fileSourceTag,
          'Directory exists check result: $directoryExists',
        );
      } catch (e, stackTrace) {
        logger.error(
          _fileSourceTag,
          'Error checking directory existence',
          e,
          stackTrace,
        );
        return ScanResult(
          scanned: 0,
          imported: 0,
          errors: ['Unable to check directory: ${source.localPath}'],
        );
      }

      if (!directoryExists) {
        logger.warning(
          _fileSourceTag,
          'Directory does not exist: ${source.localPath}',
        );
        String errorMsg = 'Directory does not exist: ${source.localPath}';
        if (source.localPath!.contains('com~apple~CloudDocs')) {
          errorMsg =
              'iCloud Drive folder not found. '
              'The folder may not be synced to this device. '
              'Please open the folder in the Files app to sync it, then try again.';
        }
        return ScanResult(scanned: 0, imported: 0, errors: [errorMsg]);
      }

      // On Android, check permissions before attempting to list
      if (io.Platform.isAndroid) {
        logger.info(
          _fileSourceTag,
          'Android: Checking permissions before listing directory...',
        );
        try {
          // Try to list the directory to verify access
          final testList = directory.listSync();
          logger.info(
            _fileSourceTag,
            'Android: Successfully listed directory, found ${testList.length} items',
          );
        } catch (e, stackTrace) {
          logger.error(
            _fileSourceTag,
            'Android: Failed to list directory - permission issue?',
            e,
            stackTrace,
          );
          // Continue anyway - the actual scan will handle the error
        }
      }
    }
    // On iOS, skip strict validation and let file scanning handle errors
    // This allows security-scoped resources to be accessed properly

    final epubFiles = <String>[];
    try {
      logger.info(
        _fileSourceTag,
        'Starting to find EPUB files in directory...',
      );
      await _findEpubFiles(directory, epubFiles);
      logger.info(_fileSourceTag, 'Found ${epubFiles.length} EPUB files');
    } catch (e, stackTrace) {
      logger.error(_fileSourceTag, 'Error finding EPUB files', e, stackTrace);
      String errorMessage = e.toString();
      logger.error(_fileSourceTag, 'Error message: $errorMessage');

      // iOS-specific: Handle security-scoped resource access issues
      if (io.Platform.isIOS &&
          (e.toString().contains('PathAccessException') ||
              e.toString().contains('Directory listing failed') ||
              e.toString().contains('Operation not permitted'))) {
        errorMessage =
            'iOS folder access expired. '
            'On iOS, folder access is temporary. Please edit this source and reselect the folder, '
            'then try scanning again. Alternatively, you can delete and re-add the folder source.';
      }
      // Android-specific: Handle scoped storage errors
      else if (e.toString().contains('scoped storage') ||
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

      // Stop accessing security-scoped resource on iOS even on error
      if (shouldStopAccessing) {
        await SecurityScopedResource.instance
            .stopAccessingSecurityScopedResource(directory);
      }

      return ScanResult(scanned: 0, imported: 0, errors: [errorMessage]);
    }

    // Report books found
    onProgress?.call(epubFiles.length, 0);

    if (epubFiles.isEmpty) {
      logger.info(
        _fileSourceTag,
        'No EPUB files found in directory. This is normal if the directory is empty or contains no .epub files.',
      );

      // Stop accessing security-scoped resource on iOS
      if (shouldStopAccessing) {
        await SecurityScopedResource.instance
            .stopAccessingSecurityScopedResource(directory);
      }

      // Return successful scan with 0 files - this is not an error
      return ScanResult(
        scanned: 0,
        imported: 0,
        errors: [], // No errors - directory is just empty
      );
    }

    try {
      final result = await _importFiles(
        epubFiles,
        source.name,
        fileSourceId: source.id,
        onProgress: onProgress,
      );

      // Stop accessing security-scoped resource on iOS
      if (shouldStopAccessing) {
        await SecurityScopedResource.instance
            .stopAccessingSecurityScopedResource(directory);
      }

      return result;
    } catch (e) {
      // Stop accessing security-scoped resource on iOS even on error
      if (shouldStopAccessing) {
        await SecurityScopedResource.instance
            .stopAccessingSecurityScopedResource(directory);
      }
      rethrow;
    }
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
    logger.info(
      _fileSourceTag,
      '_findEpubFiles: Starting scan of ${directory.path}',
    );

    try {
      logger.info(
        _fileSourceTag,
        '_findEpubFiles: Checking if directory exists...',
      );
      final exists = await directory.exists();
      logger.info(_fileSourceTag, '_findEpubFiles: Directory exists: $exists');

      if (!exists) {
        logger.error(
          _fileSourceTag,
          '_findEpubFiles: Directory does not exist: ${directory.path}',
        );
        throw Exception(
          'Directory does not exist or is not accessible: ${directory.path}',
        );
      }

      logger.info(
        _fileSourceTag,
        '_findEpubFiles: Attempting to list directory contents...',
      );
      final testList = directory.list();
      logger.info(
        _fileSourceTag,
        '_findEpubFiles: Got directory list stream, converting to list...',
      );

      List<io.FileSystemEntity> items;
      try {
        items = await testList.toList();
        logger.info(
          _fileSourceTag,
          '_findEpubFiles: Successfully listed directory, found ${items.length} items',
        );
      } catch (e, stackTrace) {
        logger.error(
          _fileSourceTag,
          '_findEpubFiles: Failed to list directory contents',
          e,
          stackTrace,
        );
        rethrow;
      }

      // If directory list is empty, it could be:
      // 1. Directory is actually empty (legitimate)
      // 2. Permission issue (can't see contents)
      // On Android with MANAGE_EXTERNAL_STORAGE, we should be able to list even if empty
      // So if we successfully listed (got 0 items), the directory is likely just empty
      // Only throw permission error if listing itself fails, not if it returns empty
      if (items.isEmpty) {
        logger.info(
          _fileSourceTag,
          '_findEpubFiles: Directory list is empty. This could mean the directory is empty or access is restricted.',
        );

        // On Android, try to verify by attempting recursive scan
        // If recursive scan fails with permission error, then we know it's a permission issue
        // Otherwise, the directory is likely just empty
        if (io.Platform.isAndroid) {
          logger.info(
            _fileSourceTag,
            '_findEpubFiles: Attempting recursive scan to verify access...',
          );
          // Don't throw error here - let the recursive scan below handle it
          // If recursive scan works (even if finds nothing), directory is just empty
          // If recursive scan fails with permission error, we'll catch it below
        } else {
          logger.info(
            _fileSourceTag,
            '_findEpubFiles: Directory appears to be empty (non-Android platform)',
          );
        }
      }

      logger.info(
        _fileSourceTag,
        '_findEpubFiles: Attempting recursive scan...',
      );
      try {
        int fileCount = 0;
        await for (final entity in directory.list(recursive: true)) {
          fileCount++;
          if (entity is io.File) {
            final fileName = entity.path.toLowerCase();
            if (fileName.endsWith('.epub')) {
              logger.debug(
                _fileSourceTag,
                '_findEpubFiles: Found EPUB: ${entity.path}',
              );
              epubFiles.add(entity.path);
            }
          }
        }
        logger.info(
          _fileSourceTag,
          '_findEpubFiles: Recursive scan complete, checked $fileCount files, found ${epubFiles.length} EPUBs',
        );
      } catch (e, stackTrace) {
        // Check if this is a permission error
        final errorStr = e.toString();
        if (errorStr.contains('Permission') ||
            errorStr.contains('permission') ||
            errorStr.contains('denied') ||
            errorStr.contains('scoped storage') ||
            errorStr.contains('Operation not permitted')) {
          logger.error(
            _fileSourceTag,
            '_findEpubFiles: Permission error during recursive scan',
            e,
            stackTrace,
          );
          // Re-throw permission errors
          rethrow;
        }

        // For other errors, try non-recursive scan as fallback
        logger.warning(
          _fileSourceTag,
          '_findEpubFiles: Recursive scan failed (non-permission error), trying non-recursive: $e',
        );
        try {
          await for (final entity in directory.list()) {
            if (entity is io.File) {
              final fileName = entity.path.toLowerCase();
              if (fileName.endsWith('.epub')) {
                logger.debug(
                  _fileSourceTag,
                  '_findEpubFiles: Found EPUB (non-recursive): ${entity.path}',
                );
                epubFiles.add(entity.path);
              }
            }
          }
          logger.info(
            _fileSourceTag,
            '_findEpubFiles: Non-recursive scan complete, found ${epubFiles.length} EPUBs',
          );
        } catch (e2, stackTrace2) {
          // If non-recursive also fails, check if it's a permission error
          final errorStr2 = e2.toString();
          if (errorStr2.contains('Permission') ||
              errorStr2.contains('permission') ||
              errorStr2.contains('denied') ||
              errorStr2.contains('scoped storage') ||
              errorStr2.contains('Operation not permitted')) {
            logger.error(
              _fileSourceTag,
              '_findEpubFiles: Permission error during non-recursive scan',
              e2,
              stackTrace2,
            );
            rethrow;
          }
          // Other errors - log and rethrow
          logger.error(
            _fileSourceTag,
            '_findEpubFiles: Non-recursive scan also failed',
            e2,
            stackTrace2,
          );
          rethrow;
        }
      }
    } catch (e, stackTrace) {
      logger.error(
        _fileSourceTag,
        '_findEpubFiles: Error during file search',
        e,
        stackTrace,
      );
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
    int? fileSourceId,
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

        await importService.importEpubFile(
          filePath,
          fileSourceId: fileSourceId,
        );
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
        await importService.importEpubFile(
          localFilePath,
          fileSourceId: source.id,
        );

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
