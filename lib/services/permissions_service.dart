import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io' as io;
import 'logger_service.dart';

const String _permissionsTag = 'PermissionsService';

class PermissionsService {
  static final PermissionsService instance = PermissionsService._internal();
  factory PermissionsService() => instance;
  PermissionsService._internal();

  static const MethodChannel _permissionsChannel = MethodChannel(
    'com.neighborhoodnerd.everbound/permissions',
  );

  /// Open Android permission settings page directly
  Future<void> openStoragePermissionSettings() async {
    if (!io.Platform.isAndroid) {
      await openAppSettings();
      return;
    }

    try {
      await _permissionsChannel.invokeMethod('openStoragePermissionSettings');
    } catch (e) {
      // Fallback to general app settings if platform channel fails
      await openAppSettings();
    }
  }

  /// Check and request storage permissions before allowing folder selection
  /// Returns true if permission is granted, false otherwise
  Future<bool> checkAndRequestStoragePermissions(BuildContext context) async {
    logger.info(_permissionsTag, 'Checking storage permissions...');
    
    if (!io.Platform.isAndroid) {
      logger.info(_permissionsTag, 'Not Android platform, skipping permission check');
      return true;
    }

    try {
      // For Android 11+ (API 30+), check MANAGE_EXTERNAL_STORAGE first
      try {
        logger.info(_permissionsTag, 'Checking MANAGE_EXTERNAL_STORAGE permission...');
        final manageStorageStatus =
            await Permission.manageExternalStorage.status;
        
        logger.info(_permissionsTag, 'MANAGE_EXTERNAL_STORAGE status: ${manageStorageStatus.toString()}');

        if (!manageStorageStatus.isGranted) {
          logger.warning(_permissionsTag, 'MANAGE_EXTERNAL_STORAGE not granted, showing dialog');
          final shouldOpenSettings = await _showAndroid11PermissionDialog(
            context,
          );

          if (shouldOpenSettings != true) {
            return false;
          }

          // Open settings
          logger.info(_permissionsTag, 'Opening storage permission settings...');
          await openStoragePermissionSettings();
          
          // Wait for user to return from settings and re-check permission
          // Poll for permission status with a reasonable timeout
          logger.info(_permissionsTag, 'Waiting for user to return from settings and grant permission...');
          bool permissionGranted = false;
          const maxWaitTime = Duration(seconds: 30);
          const checkInterval = Duration(milliseconds: 500);
          final startTime = DateTime.now();
          int checkCount = 0;
          
          while (DateTime.now().difference(startTime) < maxWaitTime) {
            await Future.delayed(checkInterval);
            checkCount++;
            final newStatus = await Permission.manageExternalStorage.status;
            logger.debug(_permissionsTag, 'Permission check #$checkCount: ${newStatus.toString()}');
            if (newStatus.isGranted) {
              logger.info(_permissionsTag, 'MANAGE_EXTERNAL_STORAGE granted after $checkCount checks!');
              permissionGranted = true;
              break;
            }
          }

          if (!permissionGranted) {
            logger.warning(_permissionsTag, 'MANAGE_EXTERNAL_STORAGE still not granted after $checkCount checks');
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Please grant "All files access" in Settings, then tap refresh again.',
                  ),
                  backgroundColor: Colors.orange,
                  duration: Duration(seconds: 4),
                ),
              );
            }
            return false;
          }
        }

        logger.info(_permissionsTag, 'Storage permissions granted successfully');
        return true;
      } catch (e) {
        // If manageExternalStorage is not available, we're on Android 10 or below
        logger.info(_permissionsTag, 'MANAGE_EXTERNAL_STORAGE not available (Android 10 or below), checking READ_EXTERNAL_STORAGE');
        // Fall through to check READ_EXTERNAL_STORAGE
      }

      // For Android 10 and below, check READ_EXTERNAL_STORAGE
      logger.info(_permissionsTag, 'Checking READ_EXTERNAL_STORAGE permission...');
      final readStorageStatus = await Permission.storage.status;
      logger.info(_permissionsTag, 'READ_EXTERNAL_STORAGE status: ${readStorageStatus.toString()}');

      if (!readStorageStatus.isGranted) {
        final readResult = await Permission.storage.request();

        if (!readResult.isGranted) {
          final action = await _showAndroid10PermissionDialog(context);

          if (action == 'cancel') {
            return false;
          } else if (action == 'settings') {
            await Future.delayed(const Duration(milliseconds: 500));
            final newStatus = await Permission.storage.status;
            if (!newStatus.isGranted) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Please grant storage permission in Settings, then try again.',
                    ),
                    backgroundColor: Colors.orange,
                    duration: Duration(seconds: 3),
                  ),
                );
              }
              return false;
            }
          } else if (action == 'retry') {
            final retryResult = await Permission.storage.request();
            if (!retryResult.isGranted) {
              return false;
            }
          } else {
            return false;
          }
        }
      }

      return true;
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error checking permissions: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return false;
    }
  }

  /// Show permission dialog for Android 11+
  Future<bool?> _showAndroid11PermissionDialog(BuildContext context) async {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Permission Required'),
        content: const Text(
          'On Android 11+, you need to grant "All files access" permission to scan folders.\n\n'
          'Tap "Open Settings" to grant the permission, then return to the app.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton.icon(
            onPressed: () async {
              Navigator.of(context).pop(true);
              await openStoragePermissionSettings();
            },
            icon: const Icon(Icons.settings),
            label: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  /// Show permission dialog for Android 10 and below
  Future<String?> _showAndroid10PermissionDialog(BuildContext context) async {
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Permission Required'),
        content: const Text(
          'Storage permission is required to scan for books in your selected folder.\n\n'
          'Please grant the permission to continue.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop('cancel'),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop('retry'),
            child: const Text('Try Again'),
          ),
          TextButton.icon(
            onPressed: () async {
              Navigator.of(context).pop('settings');
              await openStoragePermissionSettings();
            },
            icon: const Icon(Icons.settings, size: 18),
            label: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  /// Request storage permission (used in error dialogs)
  Future<void> requestStoragePermission(BuildContext context) async {
    if (!io.Platform.isAndroid) {
      return;
    }

    try {
      final readStorageStatus = await Permission.storage.status;

      if (!readStorageStatus.isGranted) {
        final readResult = await Permission.storage.request();

        if (readResult.isGranted && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Permission granted! You can now scan for books.'),
              backgroundColor: Colors.green,
            ),
          );
          return;
        }
      }

      final manageStorageStatus = await Permission.manageExternalStorage.status;

      if (manageStorageStatus.isGranted) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Storage permission already granted'),
              backgroundColor: Colors.green,
            ),
          );
        }
        return;
      }

      final result = await Permission.manageExternalStorage.request();

      if (result.isGranted) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Permission granted! You can now scan for books.'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else if (result.isPermanentlyDenied) {
        if (context.mounted) {
          final shouldOpenSettings = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Permission Denied'),
              content: const Text(
                'Storage permission was denied. Please grant "All files access" '
                'in Android Settings to scan for books.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Open Settings'),
                ),
              ],
            ),
          );

          if (shouldOpenSettings == true) {
            await openStoragePermissionSettings();
          }
        }
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Permission request cancelled'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error requesting permission: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
