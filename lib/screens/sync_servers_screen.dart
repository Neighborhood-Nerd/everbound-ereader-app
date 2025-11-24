import 'package:Everbound/models/app_theme_model.dart';
import 'package:Everbound/providers/reader_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:io';
import '../models/sync_server_model.dart';
import '../services/local_database_service.dart';
import '../providers/sync_providers.dart';
import '../services/sync_manager_service.dart';
import '../services/koreader_sync_service.dart';

class SyncServersScreen extends ConsumerStatefulWidget {
  const SyncServersScreen({super.key});

  @override
  ConsumerState<SyncServersScreen> createState() => _SyncServersScreenState();
}

class _SyncServersScreenState extends ConsumerState<SyncServersScreen> {
  Future<void> _addServer({
    String? initialName,
    String? initialUrl,
    String? initialUsername,
    String? initialPassword,
    String? initialDeviceName,
  }) async {
    final nameController = TextEditingController(text: initialName ?? '');
    final urlController = TextEditingController(text: initialUrl ?? '');
    final usernameController = TextEditingController(text: initialUsername ?? '');
    final passwordController = TextEditingController(text: initialPassword ?? '');
    final deviceNameController = TextEditingController();

    // Get default device name
    String defaultDeviceName = 'Everbound App';
    if (Platform.isAndroid) {
      defaultDeviceName = 'Everbound (Android)';
    } else if (Platform.isIOS) {
      defaultDeviceName = 'Everbound (iOS)';
    } else if (Platform.isMacOS) {
      defaultDeviceName = 'Everbound (macOS)';
    } else if (Platform.isWindows) {
      defaultDeviceName = 'Everbound (Windows)';
    } else if (Platform.isLinux) {
      defaultDeviceName = 'Everbound (Linux)';
    }
    deviceNameController.text = initialDeviceName ?? defaultDeviceName;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Sync Server'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Server Name', hintText: 'Enter a name for this server'),
                autofocus: true,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: urlController,
                decoration: const InputDecoration(labelText: 'Server URL', hintText: 'https://example.com/sync'),
                keyboardType: TextInputType.url,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: usernameController,
                decoration: const InputDecoration(labelText: 'Username'),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: passwordController,
                decoration: const InputDecoration(labelText: 'Password'),
                obscureText: true,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: deviceNameController,
                decoration: const InputDecoration(labelText: 'Device Name', hintText: 'Name for this device'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Add')),
        ],
      ),
    );

    if (confirmed == true &&
        nameController.text.isNotEmpty &&
        urlController.text.isNotEmpty &&
        usernameController.text.isNotEmpty &&
        passwordController.text.isNotEmpty) {
      // Test connection before saving
      await _testAndAddServer(
        nameController.text,
        urlController.text,
        usernameController.text,
        passwordController.text,
        deviceNameController.text.isNotEmpty ? deviceNameController.text : defaultDeviceName,
      );
    }
  }

  Future<void> _testAndAddServer(String name, String url, String username, String password, String deviceName) async {
    // Show loading dialog while testing connection
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(children: [CircularProgressIndicator(), SizedBox(width: 16), Text('Testing connection...')]),
      ),
    );

    try {
      final dbService = LocalDatabaseService.instance;
      await dbService.initialize();

      // Generate device ID (simple UUID-like string)
      final deviceId = _generateDeviceId();

      // Create temporary server for testing
      final testServer = SyncServer(
        name: name,
        url: url,
        username: username,
        password: password,
        deviceId: deviceId,
        deviceName: deviceName,
        createdAt: DateTime.now(),
        isActive: false,
      );

      // Test connection
      final syncService = KOSyncService(server: testServer);
      bool connectionSuccessful = false;
      try {
        connectionSuccessful = await syncService.testConnection();
      } catch (e) {
        // Close loading dialog on error
        if (mounted) {
          Navigator.of(context).pop();
        }
        // Re-throw to be handled by outer catch block
        rethrow;
      }

      // Close loading dialog
      if (mounted) {
        Navigator.of(context).pop();
      }

      if (!connectionSuccessful) {
        // Authentication failed - show error and allow retry
        if (mounted) {
          final retry = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Authentication Failed'),
              content: const Text(
                'The login credentials are incorrect. Please check your username and password and try again.',
              ),
              actions: [
                TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
                TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Retry')),
              ],
            ),
          );

          if (retry == true) {
            // Retry by showing the add server dialog again with previous values
            _addServer(
              initialName: name,
              initialUrl: url,
              initialUsername: username,
              initialPassword: password,
              initialDeviceName: deviceName,
            );
          }
        }
        return;
      }

      // Connection successful - save the server
      // Check if there's already an active server
      final existingActiveServer = dbService.getActiveSyncServer();
      final shouldBeActive = existingActiveServer == null; // Auto-activate if no active server exists

      final server = SyncServer(
        name: name,
        url: url,
        username: username,
        password: password,
        deviceId: deviceId,
        deviceName: deviceName,
        createdAt: DateTime.now(),
        isActive: shouldBeActive, // Auto-activate if it's the first server
      );

      final serverId = dbService.insertSyncServer(server);

      // If this should be active, set it as active
      if (shouldBeActive && serverId > 0) {
        dbService.setActiveSyncServer(serverId);
        // Update sync manager with the new active server
        final insertedServer = dbService.getSyncServerById(serverId);
        if (insertedServer != null) {
          SyncManagerService.instance.setActiveServer(insertedServer);
        }
      }

      // Refresh providers to update the UI
      ref.read(syncServersRefreshProvider.notifier).state++;
      // Explicitly invalidate the active server provider to ensure it refreshes
      ref.invalidate(activeSyncServerProvider);

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Sync server added successfully'), backgroundColor: Colors.green));
      }
    } catch (e) {
      // Close loading dialog if still open
      if (mounted) {
        Navigator.of(context).pop(); // Close loading dialog
      }

      // Show error dialog
      if (mounted) {
        final errorMessage = e.toString().replaceFirst('Exception: ', '');
        final retry = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Connection Error'),
            content: Text(
              'Failed to connect to the server:\n\n$errorMessage\n\nPlease check the server URL and try again.',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
              TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Retry')),
            ],
          ),
        );

        if (retry == true) {
          // Retry by showing the add server dialog again with previous values
          _addServer(
            initialName: name,
            initialUrl: url,
            initialUsername: username,
            initialPassword: password,
            initialDeviceName: deviceName,
          );
        }
      }
    }
  }

  String _generateDeviceId() {
    // Simple device ID generation (could use uuid package for better uniqueness)
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = (timestamp % 1000000).toString().padLeft(6, '0');
    return 'device_$random';
  }

  Future<void> _editServer(SyncServer server) async {
    final nameController = TextEditingController(text: server.name);
    final urlController = TextEditingController(text: server.url);
    final usernameController = TextEditingController(text: server.username);
    final passwordController = TextEditingController(text: server.password);
    final deviceNameController = TextEditingController(text: server.deviceName ?? '');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Sync Server'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Server Name'),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: urlController,
                decoration: const InputDecoration(labelText: 'Server URL'),
                keyboardType: TextInputType.url,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: usernameController,
                decoration: const InputDecoration(labelText: 'Username'),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: passwordController,
                decoration: const InputDecoration(labelText: 'Password'),
                obscureText: true,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: deviceNameController,
                decoration: const InputDecoration(labelText: 'Device Name'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Save')),
        ],
      ),
    );

    if (confirmed == true &&
        nameController.text.isNotEmpty &&
        urlController.text.isNotEmpty &&
        usernameController.text.isNotEmpty &&
        passwordController.text.isNotEmpty &&
        server.id != null) {
      try {
        final dbService = LocalDatabaseService.instance;
        await dbService.initialize();

        final updatedServer = server.copyWith(
          name: nameController.text,
          url: urlController.text,
          username: usernameController.text,
          password: passwordController.text,
          deviceName: deviceNameController.text.isNotEmpty ? deviceNameController.text : server.deviceName,
        );

        dbService.updateSyncServer(updatedServer);
        ref.read(syncServersRefreshProvider.notifier).state++;

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Sync server updated successfully'), backgroundColor: Colors.green),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error updating sync server: $e'), backgroundColor: Colors.red));
        }
      }
    }
  }

  Future<void> _deleteServer(SyncServer server) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Sync Server'),
        content: Text('Are you sure you want to delete "${server.name}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && server.id != null) {
      try {
        final dbService = LocalDatabaseService.instance;
        await dbService.initialize();

        dbService.deleteSyncServer(server.id!);
        ref.read(syncServersRefreshProvider.notifier).state++;

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Sync server deleted successfully'), backgroundColor: Colors.green),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error deleting sync server: $e'), backgroundColor: Colors.red));
        }
      }
    }
  }

  Future<void> _setActiveServer(SyncServer server) async {
    if (server.id == null) return;

    try {
      final dbService = LocalDatabaseService.instance;
      await dbService.initialize();

      dbService.setActiveSyncServer(server.id!);
      ref.read(syncServersRefreshProvider.notifier).state++;
      // Explicitly invalidate the active server provider to ensure it refreshes
      ref.invalidate(activeSyncServerProvider);

      // Update sync manager
      SyncManagerService.instance.setActiveServer(server);

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('${server.name} is now active'), backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error setting active server: $e'), backgroundColor: Colors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final serversAsync = ref.watch(syncServersProvider);
    final readingSettings = ref.watch(readingSettingsProvider);
    final selectedTheme = AppThemes.getThemeByName(readingSettings.selectedThemeName);
    final variant = selectedTheme.getVariant(readingSettings.isDarkMode);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sync Servers'),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, size: 20, color: variant.textColor), // Custom icon
          onPressed: () {
            Navigator.pop(context); // Custom back action
          },
        ),
      ),
      body: serversAsync.when(
        data: (servers) {
          if (servers.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.cloud_sync, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text('No sync servers configured', style: TextStyle(fontSize: 18, color: Colors.grey[600])),
                  const SizedBox(height: 8),
                  Text('Add a server to sync reading progress', style: TextStyle(color: Colors.grey[500])),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: servers.length,
            itemBuilder: (context, index) {
              final server = servers[index];
              return _buildServerCard(context, server);
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error, color: Colors.red, size: 48),
              const SizedBox(height: 16),
              Text('Error loading sync servers: $error'),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addServer,
        backgroundColor: variant.primaryColor.withValues(alpha: 0.8),
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildServerCard(BuildContext context, SyncServer server) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Icon(
          server.isActive ? Icons.cloud_done : Icons.cloud,
          color: server.isActive ? Colors.green : Colors.grey,
        ),
        title: Row(
          children: [
            Expanded(child: Text(server.name)),
            if (server.isActive)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: Colors.green, borderRadius: BorderRadius.circular(12)),
                child: const Text('Active', style: TextStyle(color: Colors.white, fontSize: 12)),
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              server.url,
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (server.deviceName != null)
              Text('Device: ${server.deviceName}', style: TextStyle(fontSize: 11, color: Colors.grey[500])),
            Text(
              'Created: ${_formatDateTime(server.createdAt)}',
              style: TextStyle(fontSize: 11, color: Colors.grey[500]),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!server.isActive)
              IconButton(
                icon: const Icon(Icons.check_circle),
                onPressed: () => _setActiveServer(server),
                tooltip: 'Set as Active',
                color: Colors.green,
              ),
            IconButton(icon: const Icon(Icons.edit), onPressed: () => _editServer(server), tooltip: 'Edit'),
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: () => _deleteServer(server),
              tooltip: 'Delete',
            ),
          ],
        ),
      ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 0) {
      return '${difference.inDays} day(s) ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} hour(s) ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} minute(s) ago';
    } else {
      return 'Just now';
    }
  }
}
