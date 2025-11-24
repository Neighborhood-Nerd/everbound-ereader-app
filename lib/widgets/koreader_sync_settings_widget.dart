import 'dart:io' as io;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/reader_providers.dart';
import '../providers/sync_providers.dart';
import '../providers/my_books_providers.dart';
import '../services/local_database_service.dart';
import '../services/sync_manager_service.dart';
import '../services/koreader_sync_service.dart';
import '../models/sync_server_model.dart';

class KoreaderSyncSettingsWidget extends ConsumerStatefulWidget {
  final int? bookId;
  final bool showBookSyncToggle;
  final VoidCallback? onClose;

  const KoreaderSyncSettingsWidget({super.key, this.bookId, this.showBookSyncToggle = false, this.onClose});

  @override
  ConsumerState<KoreaderSyncSettingsWidget> createState() => _KoreaderSyncSettingsWidgetState();
}

class _KoreaderSyncSettingsWidgetState extends ConsumerState<KoreaderSyncSettingsWidget> {
  late TextEditingController urlController;
  late TextEditingController usernameController;
  late TextEditingController passwordController;
  late TextEditingController deviceNameController;
  bool _isConnectButtonEnabled = false;

  @override
  void initState() {
    super.initState();
    urlController = TextEditingController(text: 'https://sync.koreader.rocks/');
    usernameController = TextEditingController();
    passwordController = TextEditingController();
    deviceNameController = TextEditingController();

    // Add listeners to track text changes
    urlController.addListener(_updateConnectButtonState);
    usernameController.addListener(_updateConnectButtonState);
    passwordController.addListener(_updateConnectButtonState);

    // Initial state check
    _updateConnectButtonState();
    _loadInitialData();
  }

  void _updateConnectButtonState() {
    final isEnabled =
        urlController.text.isNotEmpty && usernameController.text.isNotEmpty && passwordController.text.isNotEmpty;

    if (_isConnectButtonEnabled != isEnabled) {
      setState(() {
        _isConnectButtonEnabled = isEnabled;
      });
    }
  }

  Future<void> _loadInitialData() async {
    final activeServer = await ref.read(activeSyncServerProvider.future);
    if (activeServer != null && mounted) {
      deviceNameController.text = activeServer.deviceName ?? 'Flutter eReader';
    }
  }

  @override
  void dispose() {
    urlController.removeListener(_updateConnectButtonState);
    usernameController.removeListener(_updateConnectButtonState);
    passwordController.removeListener(_updateConnectButtonState);
    urlController.dispose();
    usernameController.dispose();
    passwordController.dispose();
    deviceNameController.dispose();
    super.dispose();
  }

  String _generateDeviceId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = (timestamp % 1000000).toString().padLeft(6, '0');
    return 'device_$random';
  }

  Future<void> _testAndConnect(String url, String username, String password) async {
    // Show loading dialog
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

      // Generate device ID
      final deviceId = _generateDeviceId();

      // Get default device name
      String defaultDeviceName = 'Everbound App';
      if (io.Platform.isAndroid) {
        defaultDeviceName = 'Everbound (Android)';
      } else if (io.Platform.isIOS) {
        defaultDeviceName = 'Everbound (iOS)';
      } else if (io.Platform.isMacOS) {
        defaultDeviceName = 'Everbound (macOS)';
      } else if (io.Platform.isWindows) {
        defaultDeviceName = 'Everbound (Windows)';
      } else if (io.Platform.isLinux) {
        defaultDeviceName = 'Everbound (Linux)';
      }

      // Create temporary server for testing
      final testServer = SyncServer(
        name: 'KOReader Sync',
        url: url,
        username: username,
        password: password,
        deviceId: deviceId,
        deviceName: defaultDeviceName,
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
            // Retry by calling this function again with same values
            await _testAndConnect(url, username, password);
          }
        }
        return;
      }

      // Connection successful - save the server and set as active
      final server = SyncServer(
        name: 'KOReader Sync',
        url: url,
        username: username,
        password: password,
        deviceId: deviceId,
        deviceName: defaultDeviceName,
        createdAt: DateTime.now(),
        isActive: true, // Set as active
      );

      // Delete any existing servers first (since we only support one)
      final existingServers = dbService.getAllSyncServers();
      for (final existingServer in existingServers) {
        if (existingServer.id != null) {
          dbService.deleteSyncServer(existingServer.id!);
        }
      }

      final serverId = dbService.insertSyncServer(server);

      // Set as active
      if (serverId > 0) {
        dbService.setActiveSyncServer(serverId);
        // Update sync manager with the new active server
        final insertedServer = dbService.getSyncServerById(serverId);
        if (insertedServer != null) {
          SyncManagerService.instance.setActiveServer(insertedServer);
        }
      }

      // Refresh providers to update the UI
      ref.read(syncServersRefreshProvider.notifier).state++;
      ref.invalidate(activeSyncServerProvider);

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Connected successfully'), backgroundColor: Colors.green));
        // Update device name controller
        final updatedServer = await ref.read(activeSyncServerProvider.future);
        if (updatedServer != null && mounted) {
          deviceNameController.text = updatedServer.deviceName ?? 'Flutter eReader';
        }
        setState(() {}); // Refresh UI to show logged in state
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
            content: Text(errorMessage),
            actions: [
              TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
              TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Retry')),
            ],
          ),
        );

        if (retry == true) {
          // Retry by calling this function again with same values
          await _testAndConnect(url, username, password);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeServerAsync = ref.watch(activeSyncServerProvider);
    final themeVariant = ref.watch(themeVariantProvider);

    final textColor = themeVariant.textColor;
    final hintColor = Colors.grey[600];
    final fieldBgColor = themeVariant.cardColor;

    return activeServerAsync.when(
      data: (activeServer) {
        final isLoggedIn = activeServer != null;
        SyncStrategy currentStrategy = ref.read(syncStrategyProvider).strategy;

        // Get book sync enabled state if bookId is provided
        bool bookSyncEnabled = true;
        if (widget.bookId != null) {
          final dbService = LocalDatabaseService.instance;
          final book = dbService.getBookById(widget.bookId!);
          bookSyncEnabled = book?.syncEnabled ?? true;
        }

        // Update device name controller if activeServer changes
        if (activeServer != null) {
          final currentDeviceName = activeServer.deviceName ?? 'Flutter eReader';
          if (deviceNameController.text != currentDeviceName) {
            deviceNameController.text = currentDeviceName;
          }
        }

        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isLoggedIn) ...[
                // Logged Out State - Login Form
                Text(
                  'Connect to your KOReader Sync server.',
                  style: TextStyle(fontSize: 14, color: textColor.withOpacity(0.7)),
                ),
                const SizedBox(height: 24),

                // Server URL
                Text(
                  'Server URL',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: textColor),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: urlController,
                  style: TextStyle(color: textColor),
                  decoration: InputDecoration(
                    hintText: 'https://sync.koreader.rocks/',
                    hintStyle: TextStyle(color: hintColor),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    filled: true,
                    fillColor: fieldBgColor,
                  ),
                  keyboardType: TextInputType.url,
                ),
                const SizedBox(height: 16),

                // Username
                Text(
                  'Username',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: textColor),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: usernameController,
                  style: TextStyle(color: textColor),
                  decoration: InputDecoration(
                    hintText: 'Enter username',
                    hintStyle: TextStyle(color: hintColor),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    filled: true,
                    fillColor: fieldBgColor,
                  ),
                ),
                const SizedBox(height: 16),

                // Password
                Text(
                  'Password',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: textColor),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: passwordController,
                  style: TextStyle(color: textColor),
                  obscureText: true,
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    hintText: 'Enter password',
                    hintStyle: TextStyle(color: hintColor),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    filled: true,
                    fillColor: fieldBgColor,
                  ),
                  onSubmitted: (value) async {
                    if (urlController.text.isEmpty ||
                        usernameController.text.isEmpty ||
                        passwordController.text.isEmpty) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(const SnackBar(content: Text('Please fill in all fields')));
                      return;
                    }

                    await _testAndConnect(urlController.text, usernameController.text, passwordController.text);
                  },
                ),
                const SizedBox(height: 24),

                // Connect Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isConnectButtonEnabled
                        ? () async {
                            await _testAndConnect(urlController.text, usernameController.text, passwordController.text);
                          }
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: themeVariant.primaryColor.withValues(alpha: 0.5),
                      foregroundColor: themeVariant.textColor,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('Connect'),
                  ),
                ),
              ] else ...[
                // Logged In State - Settings
                // Device Name
                Text(
                  'Device Name',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: textColor),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: deviceNameController,
                  style: TextStyle(color: textColor),
                  decoration: InputDecoration(
                    hintText: 'Enter device name',
                    hintStyle: TextStyle(color: hintColor),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    filled: true,
                    fillColor: fieldBgColor,
                  ),
                  onSubmitted: (value) async {
                    if (value.isNotEmpty && activeServer != null) {
                      final dbService = LocalDatabaseService.instance;
                      await dbService.initialize();
                      await dbService.updateActiveSyncServerDeviceName(value);
                      // Update sync manager
                      final updatedServer = dbService.getActiveSyncServer();
                      if (updatedServer != null) {
                        SyncManagerService.instance.setActiveServer(updatedServer);
                      }
                      // Refresh provider
                      ref.read(syncServersRefreshProvider.notifier).state++;
                    }
                  },
                ),

                const SizedBox(height: 24),

                // Sync Strategy
                Text(
                  'Sync Strategy',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: textColor),
                ),
                const SizedBox(height: 12),
                ...SyncStrategy.values.map((strategy) {
                  String label;
                  switch (strategy) {
                    case SyncStrategy.prompt:
                      label = 'Ask on Conflict';
                      break;
                    case SyncStrategy.silent:
                      label = 'Always Use Latest';
                      break;
                    case SyncStrategy.send:
                      label = 'Send Changes Only';
                      break;
                    case SyncStrategy.receive:
                      label = 'Receive Changes Only';
                      break;
                    case SyncStrategy.disabled:
                      label = 'Disabled';
                      break;
                  }

                  return RadioListTile<SyncStrategy>(
                    dense: true,
                    visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
                    contentPadding: EdgeInsets.zero,
                    title: Text(label, style: TextStyle(color: textColor)),
                    value: strategy,
                    groupValue: currentStrategy,
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          currentStrategy = value;
                        });
                        // Update provider (which will save to database and update service)
                        ref.read(syncStrategyProvider.notifier).setStrategy(value);
                      }
                    },
                  );
                }).toList(),

                if (widget.showBookSyncToggle && widget.bookId != null) ...[
                  const SizedBox(height: 24),
                  // Per-book sync toggle
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          'Enable Sync for This Book',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: textColor),
                        ),
                      ),
                      Switch(
                        value: bookSyncEnabled,
                        onChanged: (value) {
                          if (widget.bookId != null) {
                            final dbService = LocalDatabaseService.instance;
                            // Update database first
                            final result = dbService.updateBookSyncEnabled(widget.bookId!, value);
                            if (result > 0) {
                              // Trigger rebuild
                              setState(() {});
                              // Refresh books list
                              if (mounted) {
                                ref.read(booksRefreshProvider.notifier).state++;
                              }
                            }
                          }
                        },
                      ),
                    ],
                  ),
                ],

                const SizedBox(height: 24),

                // Log Out Button
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () async {
                      // Show confirmation dialog
                      final shouldLogout = await showDialog<bool>(
                        context: context,
                        builder: (BuildContext dialogContext) {
                          return AlertDialog(
                            title: const Text('Log Out'),
                            content: const Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Are you sure you want to log out of the koreader sync?'),
                                SizedBox(height: 12),
                                Text(
                                  'Note: reading progress will not be lost',
                                  style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                                ),
                              ],
                            ),
                            actions: [
                              TextButton(
                                onPressed: () {
                                  Navigator.of(dialogContext).pop(false);
                                },
                                child: const Text('Cancel'),
                              ),
                              TextButton(
                                onPressed: () {
                                  Navigator.of(dialogContext).pop(true);
                                },
                                style: TextButton.styleFrom(foregroundColor: Colors.red),
                                child: const Text('Log Out'),
                              ),
                            ],
                          );
                        },
                      );

                      // Only proceed if user confirmed
                      if (shouldLogout == true && mounted) {
                        if (activeServer != null && activeServer.id != null) {
                          final dbService = LocalDatabaseService.instance;
                          await dbService.initialize();
                          // Delete the server
                          dbService.deleteSyncServer(activeServer.id!);
                          // Clear active server in sync manager
                          SyncManagerService.instance.setActiveServer(null);
                          // Invalidate provider to refresh
                          ref.invalidate(activeSyncServerProvider);
                          ref.read(syncServersRefreshProvider.notifier).state++;
                          // Refresh UI
                          setState(() {});
                          // Call onClose if provided (for bottom sheet)
                          if (widget.onClose != null) {
                            widget.onClose!();
                          }
                        }
                      }
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.red,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: const Text('Log Out'),
                  ),
                ),
              ],
            ],
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
            const SizedBox(height: 16),
            Text('Error loading sync settings', style: TextStyle(color: Colors.red[700])),
            const SizedBox(height: 8),
            Text(error.toString(), style: TextStyle(color: Colors.grey[600])),
          ],
        ),
      ),
    );
  }
}
