import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import '../models/sync_server_model.dart';
import '../utils/md5_utils.dart';
import 'local_database_service.dart';
import 'book_import_service.dart';

/// Response model for KOReader sync progress
class KoSyncProgress {
  final String? progress;
  final double? percentage;
  final int? timestamp;

  KoSyncProgress({this.progress, this.percentage, this.timestamp});

  factory KoSyncProgress.fromJson(Map<String, dynamic> json) {
    return KoSyncProgress(
      progress: json['progress'] as String?,
      percentage: json['percentage'] != null ? (json['percentage'] as num).toDouble() : null,
      timestamp: json['timestamp'] as int?,
    );
  }
}

/// Service for communicating with KOReader sync servers
class KOSyncService {
  final SyncServer server;
  final String checksumMethod; // 'binary' (file content), 'hash', or 'filename'

  KOSyncService({
    required this.server,
    this.checksumMethod = 'binary', // Default to 'binary' to match KOReader's 'Binary' method
  });

  /// Get the base URL for the sync server
  String get baseUrl {
    String url = server.url;
    if (!url.endsWith('/')) {
      url += '/';
    }
    return url;
  }

  /// Generate document digest based on checksum method
  ///
  /// Supports two methods:
  /// - If checksumMethod is 'filename': MD5 hash of filename without extension
  /// - Otherwise: MD5 hash of the actual file content (matches KOReader's 'Binary' method)
  ///
  /// Computes digest on-the-fly for consistency with KOReader sync protocol
  Future<String> getDocumentDigest(LocalBook book) async {
    // If filename method, use filename hash
    if (checksumMethod == 'filename') {
      final filename = book.originalFileName;
      final normalizedPath = filename.replaceAll('\\', '/');
      // Extract base name without extension for consistent hashing
      final nameWithoutExt = path.basenameWithoutExtension(normalizedPath);
      final bytes = utf8.encode(nameWithoutExt);
      final digest = md5.convert(bytes);
      final digestString = digest.toString();
      print('Computed filename digest for "${book.title}": $digestString (from: $nameWithoutExt)');
      return digestString;
    }

    // For 'binary' or any other method (default), use partial MD5
    // Use stored MD5 if available (computed on import), otherwise compute on-the-fly
    if (book.partialMd5Checksum != null && book.partialMd5Checksum!.isNotEmpty) {
      print('Using stored partial MD5 digest for "${book.title}": ${book.partialMd5Checksum}');
      return book.partialMd5Checksum!;
    }

    // Fallback to computing on-the-fly if not stored
    try {
      // Resolve path to handle relative paths and iOS container ID changes
      final resolvedPath = await BookImportService.instance.resolvePath(book.filePath);
      final file = File(resolvedPath);
      if (file.existsSync()) {
        final digestString = computePartialMD5(resolvedPath);
        print('Computed partial MD5 digest for "${book.title}": $digestString (file size: ${file.lengthSync()} bytes)');
        print('File path: $resolvedPath (original: ${book.filePath})');
        return digestString;
      } else {
        print('Warning: File not found for binary checksum: $resolvedPath (original: ${book.filePath})');
        // Fallback to filename method
        final filename = book.originalFileName;
        final normalizedPath = filename.replaceAll('\\', '/');
        final nameWithoutExt = path.basenameWithoutExtension(normalizedPath);
        final bytes = utf8.encode(nameWithoutExt);
        final digest = md5.convert(bytes);
        return digest.toString();
      }
    } catch (e) {
      print('Error computing partial MD5 checksum: $e');
      // Fallback to filename method
      final filename = book.originalFileName;
      final normalizedPath = filename.replaceAll('\\', '/');
      final nameWithoutExt = path.basenameWithoutExtension(normalizedPath);
      final bytes = utf8.encode(nameWithoutExt);
      final digest = md5.convert(bytes);
      return digest.toString();
    }
  }

  /// Get authentication headers (matches KOReader sync API format)
  /// KOReader uses X-Auth-User and X-Auth-Key headers, where userkey is MD5(password)
  Map<String, String> _getAuthHeaders() {
    // Compute userkey as MD5 of password per KOReader sync protocol
    final userkey = md5.convert(utf8.encode(server.password)).toString();
    return {'X-Auth-User': server.username, 'X-Auth-Key': userkey, 'Accept': 'application/vnd.koreader.v1+json'};
  }

  /// Test connection and authentication with the sync server
  /// Returns true if authentication succeeds, false otherwise
  /// Throws an exception if there's a connection error
  Future<bool> testConnection() async {
    try {
      // Test authentication by calling /users/auth endpoint per KOReader sync protocol
      final url = Uri.parse('${baseUrl}users/auth');
      
      final response = await http.get(url, headers: _getAuthHeaders()).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return true; // Authentication successful
      }

      if (response.statusCode == 401) {
        // Unauthorized - invalid credentials
        return false;
      }

      // Other error status codes
      throw Exception('Server returned status ${response.statusCode}: ${response.body}');
    } catch (e) {
      if (e is TimeoutException) {
        throw Exception('Connection timeout: Unable to reach the server');
      } else if (e is SocketException) {
        throw Exception('Connection error: Unable to connect to the server');
      } else if (e is FormatException) {
        throw Exception('Invalid server URL');
      }
      rethrow;
    }
  }

  /// Fetch reading progress from sync server
  Future<KoSyncProgress?> getProgress(LocalBook book) async {
    try {
      final digest = await getDocumentDigest(book);
      // KOReader sync servers use /syncs/progress/:document endpoint
      final url = Uri.parse('${baseUrl}syncs/progress/$digest');

      final response = await http.get(url, headers: _getAuthHeaders()).timeout(const Duration(seconds: 10));

      if (response.statusCode == 404) {
        // No progress found on server

        // Also compute and show the binary MD5 for verification
        try {
          final resolvedPath = await BookImportService.instance.resolvePath(book.filePath);
          final binaryMD5 = computeFileContentMD5(resolvedPath);
          print('Computed binary MD5: $binaryMD5');
        } catch (e) {
          print('Could not compute binary MD5: $e');
        }

        return null;
      }

      if (response.statusCode != 200) {
        throw Exception('Failed to fetch progress: ${response.statusCode} ${response.body}');
      }

      final contentType = response.headers['content-type'];
      if (contentType == null || !contentType.contains('application/json')) {
        throw Exception('Invalid sync server response: Unexpected Content-Type.');
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return KoSyncProgress.fromJson(json);
    } catch (e) {
      print('Error fetching progress from KOReader sync server: $e');
      rethrow;
    }
  }

  /// Round percentage to 4 decimal places (matching KOReader's Math.roundPercent)
  /// KOReader uses: math.floor(percent * 10000) / 10000
  double _roundPercent(double percent) {
    return (percent * 10000).floorToDouble() / 10000;
  }

  /// Update reading progress on sync server
  Future<void> updateProgress(LocalBook book, String progressStr, double? percentage) async {
    try {
      final digest = await getDocumentDigest(book);
      // KOReader sync servers use /syncs/progress endpoint for PUT
      final url = Uri.parse('${baseUrl}syncs/progress');

      // Round percentage to 4 decimal places to match KOReader's format
      // KOReader uses Math.roundPercent which rounds to 4 decimal places
      final roundedPercentage = percentage != null ? _roundPercent(percentage) : null;

      print('Updating progress to: $url');
      print('Using digest: $digest (method: $checksumMethod)');
      print('Progress: $progressStr, Percentage: $percentage -> Rounded: $roundedPercentage');

      // Payload format per KOReader sync protocol: includes 'document' field
      final body = <String, dynamic>{
        'document': digest,
        'progress': progressStr,
        'percentage': roundedPercentage,
        'device': server.deviceName ?? 'Flutter eReader',
        'device_id': server.deviceId ?? '',
      };

      final response = await http
          .put(url, headers: _getAuthHeaders(), body: jsonEncode(body))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200 && response.statusCode != 201) {
        throw Exception('Failed to update progress: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      print('Error updating progress to KOReader sync server: $e');
      rethrow;
    }
  }
}
