import 'dart:io';
import 'package:crypto/crypto.dart';

/// Compute partial MD5 hash of file (matches KOReader's util.partialMD5)
/// Samples chunks from specific positions in the file to create a faster hash
/// Used for book identification and KOReader sync server compatibility
///
/// Algorithm matches KOReader's util.partialMD5() in frontend/util.lua
String computePartialMD5(String filePath) {
  try {
    final file = File(filePath);
    if (!file.existsSync()) {
      throw Exception('File not found: $filePath');
    }

    final fileSize = file.lengthSync();
    const step = 1024;
    const size = 1024;

    final bytes = <int>[];

    // Sample chunks at positions matching KOReader's util.partialMD5 algorithm exactly
    // KOReader's lshift(step, -2) actually returns 0 (not 256), matching JavaScript behavior
    // This is verified by KOReader's metadata showing MD5 that matches position 0 for i=-1
    for (int i = -1; i <= 10; i++) {
      // Match KOReader's actual behavior: lshift(step, 2*i) where negative shift = 0
      // For i = -1: position 0 (verified to match KOReader metadata)
      // For i >= 0: lshift(step, 2*i) works normally
      final shiftAmount = 2 * i;
      final rawStart = shiftAmount < 0 ? 0 : (step << shiftAmount);
      // Match KOReader: file:seek("set", lshift(step, 2*i))
      final start = rawStart < fileSize ? rawStart : fileSize;
      // Calculate end position, ensuring we don't exceed file size
      final end = (start + size) < fileSize ? (start + size) : fileSize;

      // Skip if start position is beyond file size
      if (start >= fileSize) break;

      final randomAccessFile = file.openSync();
      try {
        randomAccessFile.setPositionSync(start);
        final chunk = randomAccessFile.readSync(end - start);
        bytes.addAll(chunk);
      } finally {
        randomAccessFile.closeSync();
      }
    }

    // Calculate MD5 from accumulated sampled bytes
    final digest = md5.convert(bytes);
    final result = digest.toString();

    print('computePartialMD5: file=$filePath, size=$fileSize, sampled=${bytes.length} bytes, MD5=$result');
    return result;
  } catch (e) {
    throw Exception('Error computing partial MD5: $e');
  }
}

/// Compute full MD5 hash of file content (for debugging/verification)
/// This matches KOReader's 'Binary' method when using full file content
String computeFileContentMD5(String filePath) {
  try {
    final file = File(filePath);
    if (file.existsSync()) {
      final fileBytes = file.readAsBytesSync();
      final digest = md5.convert(fileBytes);
      return digest.toString();
    } else {
      throw Exception('File not found: $filePath');
    }
  } catch (e) {
    throw Exception('Error computing MD5: $e');
  }
}
