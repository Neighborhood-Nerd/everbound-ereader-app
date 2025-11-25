import 'dart:io' as io;
import 'package:flutter/services.dart';

class IOSBookmarkService {
  static final IOSBookmarkService instance = IOSBookmarkService._internal();
  factory IOSBookmarkService() => instance;
  IOSBookmarkService._internal();

  static const MethodChannel _channel = MethodChannel(
    'com.neighborhoodnerd.everbound/security_scoped_bookmark',
  );

  /// Create a security-scoped bookmark from a path
  /// Returns base64-encoded bookmark data
  Future<String?> createBookmark(String path) async {
    if (!io.Platform.isIOS) {
      return null; // Only needed on iOS
    }

    try {
      final result = await _channel.invokeMethod<String>('createBookmark', {
        'path': path,
      });
      return result;
    } catch (e) {
      // If bookmark creation fails, return null
      // The path can still be used (might be in app sandbox)
      return null;
    }
  }

  /// Resolve a bookmark to get the path
  /// Returns the path if successful, null otherwise
  Future<String?> resolveBookmark(String bookmarkData) async {
    if (!io.Platform.isIOS) {
      return null; // Only needed on iOS
    }

    try {
      final result = await _channel.invokeMethod<String>('resolveBookmark', {
        'bookmarkData': bookmarkData,
      });
      return result;
    } catch (e) {
      return null;
    }
  }

  /// Start accessing a security-scoped resource
  /// Returns true if successful, false otherwise
  Future<bool> startAccessing(String bookmarkData) async {
    if (!io.Platform.isIOS) {
      return true; // Not needed on other platforms
    }

    try {
      final result = await _channel.invokeMethod<bool>('startAccessing', {
        'bookmarkData': bookmarkData,
      });
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  /// Stop accessing a security-scoped resource
  Future<void> stopAccessing(String bookmarkData) async {
    if (!io.Platform.isIOS) {
      return; // Not needed on other platforms
    }

    try {
      await _channel.invokeMethod('stopAccessing', {
        'bookmarkData': bookmarkData,
      });
    } catch (e) {
      // Ignore errors when stopping access
    }
  }
}

