import 'dart:io' as io;
import 'package:Everbound/models/app_theme_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webdav_client/webdav_client.dart';
import 'package:path/path.dart' as path;
import 'colors.dart';
import 'screens/database_details_screen.dart';
import 'screens/home_screen.dart';
import 'screens/my_books_screen.dart';
import 'screens/settings_screen.dart';
import 'providers/file_source_providers.dart';
import 'providers/sync_providers.dart';
import 'providers/reader_providers.dart';
import 'providers/home_providers.dart';
import 'providers/logging_providers.dart';
import 'services/logger_service.dart';
import 'widgets/foliate_webview.dart';

const String _tag = 'Main';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set preferred orientations
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Set up error handling
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    logger.error(
      _tag,
      'Flutter Error: ${details.exception}',
      details.exception,
      details.stack,
    );
  };

  // Start the foliate server early so it's ready when user opens a book
  // This prevents the 10-second delay when opening books
  FoliateWebView.initializeServerEarly().catchError((e) {
    logger.error(_tag, 'Error initializing foliate server early: $e', e);
  });

  runApp(ProviderScope(child: const MainApp()));
}

// Provider for current tab index
final currentTabIndexProvider = StateProvider<int>((ref) => 0);

class MainApp extends ConsumerWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Sync strategy is automatically loaded when the provider is first accessed
    // (happens in the constructor of SyncStrategyNotifier)
    ref.read(syncStrategyProvider); // Ensure provider is initialized

    // Initialize logging provider (always starts disabled)
    // Logging must be manually enabled each session to prevent accidental performance issues
    ref.read(loggingEnabledProvider);

    // Initialize background scanning on app start
    WidgetsBinding.instance.addPostFrameCallback((_) {
      initializeBackgroundScanning(ref);
    });

    // Watch the app theme provider to apply theme changes
    final appTheme = ref.watch(appThemeProvider);
    final readingSettings = ref.watch(readingSettingsProvider);

    // Build both light and dark themes
    final lightTheme = appTheme.copyWith(brightness: Brightness.light);
    final darkTheme = appTheme.copyWith(brightness: Brightness.dark);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Everbound',
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: readingSettings.isDarkMode ? ThemeMode.dark : ThemeMode.light,
      home: const _MainNavigationScreen(),
      // Keep WebDAV browser as a separate route for now
      routes: {'/browser': (context) => const WebDavBrowser()},
    );
  }
}

class _MainNavigationScreen extends ConsumerWidget {
  const _MainNavigationScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentIndex = ref.watch(currentTabIndexProvider);

    return Scaffold(
      backgroundColor: Colors.white,
      body: IndexedStack(
        index: currentIndex,
        children: const [
          //HomeScreen(),
          MyBooksScreen(),
          //_PlaceholderScreen(title: 'Community'),
          //_PlaceholderScreen(title: 'Stats'),
          SettingsScreen(),
        ],
      ),
      bottomNavigationBar: _buildBottomNavigationBar(
        context,
        ref,
        currentIndex,
      ),
    );
  }

  Widget _buildBottomNavigationBar(
    BuildContext context,
    WidgetRef ref,
    int currentIndex,
  ) {
    final readingSettings = ref.watch(readingSettingsProvider);
    final selectedTheme = AppThemes.getThemeByName(
      readingSettings.selectedThemeName,
    );
    final variant = selectedTheme.getVariant(readingSettings.isDarkMode);

    return Container(
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: currentIndex,
        onTap: (index) {
          ref.read(currentTabIndexProvider.notifier).state = index;
        },
        selectedItemColor: variant.primaryColor,
        unselectedItemColor: variant.iconColor.withValues(alpha: 0.7),
        selectedLabelStyle: const TextStyle(fontSize: 12),
        unselectedLabelStyle: const TextStyle(fontSize: 12),
        items: [
          //const BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(
            icon: Stack(
              children: [
                const Icon(Icons.menu_book_rounded),
                if (currentIndex == 1)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      height: 2,
                      color: Colors.black,
                      margin: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                  ),
              ],
            ),
            label: 'My Books',
          ),
          //const BottomNavigationBarItem(icon: Icon(Icons.people), label: 'Community'),
          // const BottomNavigationBarItem(
          //   icon: Icon(Icons.search),
          //   label: 'Search',
          // ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

class _PlaceholderScreen extends ConsumerWidget {
  final String title;

  const _PlaceholderScreen({required this.title, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final readingSettings = ref.watch(readingSettingsProvider);
    final selectedTheme = AppThemes.getThemeByName(
      readingSettings.selectedThemeName,
    );
    final variant = selectedTheme.getVariant(readingSettings.isDarkMode);
    return Scaffold(
      appBar: AppBar(
        title: Text(title, style: TextStyle(color: variant.secondaryTextColor)),
      ),
      body: Center(
        child: Text(
          '$title Screen',
          style: TextStyle(fontSize: 24, color: variant.textColor),
        ),
      ),
    );
  }
}

class WebDavBrowser extends StatefulWidget {
  const WebDavBrowser({super.key});

  @override
  State<WebDavBrowser> createState() => _WebDavBrowserState();
}

class _WebDavBrowserState extends State<WebDavBrowser> {
  Client? _client;
  String _status = 'Not connected';
  List<File> _items = [];
  String _currentPath = '';
  List<String> _pathHistory = [];
  bool _isLoading = false;

  static const String url = '';
  static const String username = '';
  static const String password = '';

  @override
  void initState() {
    super.initState();
    _connect();
  }

  Future<void> _connect() async {
    setState(() {
      _isLoading = true;
      _status = 'Connecting...';
      _items = [];
    });

    try {
      _client = newClient(url, user: username, password: password);
      await _loadDirectory('');
    } catch (e) {
      setState(() {
        _status = 'Error: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _loadDirectory(String path) async {
    if (_client == null) return;

    setState(() {
      _isLoading = true;
      _status = 'Loading...';
      _currentPath = path;
    });

    try {
      final items = await _client!.readDir(path);

      // Sort: folders first, then files, both alphabetically
      items.sort((a, b) {
        final aIsDir = a.isDir ?? false;
        final bIsDir = b.isDir ?? false;
        if (aIsDir == bIsDir) {
          final aName = a.name ?? '';
          final bName = b.name ?? '';
          return aName.toLowerCase().compareTo(bName.toLowerCase());
        }
        return aIsDir ? -1 : 1;
      });

      setState(() {
        _items = items;
        _status = '${items.length} items';
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _status = 'Error: $e';
        _isLoading = false;
        _items = [];
      });
    }
  }

  void _navigateToFolder(String folderName) {
    final newPath = _currentPath.isEmpty
        ? folderName
        : '$_currentPath/$folderName';
    _pathHistory.add(_currentPath);
    _loadDirectory(newPath);
  }

  void _navigateBack() {
    if (_pathHistory.isNotEmpty) {
      final previousPath = _pathHistory.removeLast();
      _loadDirectory(previousPath);
    } else {
      _loadDirectory('');
    }
  }

  String _getCurrentDisplayPath() {
    if (_currentPath.isEmpty) return '/';
    return '/$_currentPath';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('WebDAV Browser'),
        leading: _currentPath.isNotEmpty || _pathHistory.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: _navigateBack,
                tooltip: 'Go back',
              )
            : null,
      ),
      body: Column(
        children: [
          // Status bar with path
          Container(
            padding: const EdgeInsets.all(12.0),
            color: Colors.grey[200],
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _getCurrentDisplayPath(),
                    style: const TextStyle(
                      fontSize: 14,
                      fontFamily: 'monospace',
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (_isLoading)
                  const Padding(
                    padding: EdgeInsets.only(left: 8.0),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else
                  Text(
                    _status,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
              ],
            ),
          ),
          // File list
          Expanded(
            child: _items.isEmpty && !_isLoading
                ? Center(
                    child: Text(
                      _client == null ? 'Not connected' : 'No items',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  )
                : ListView.builder(
                    itemCount: _items.length,
                    itemBuilder: (context, index) {
                      final item = _items[index];
                      final isFolder = item.isDir ?? false;
                      final itemName = item.name ?? 'Unknown';

                      return ListTile(
                        leading: Icon(
                          isFolder ? Icons.folder : Icons.insert_drive_file,
                          color: isFolder ? Colors.blue : Colors.grey,
                        ),
                        title: Text(itemName),
                        subtitle: isFolder
                            ? null
                            : Text(
                                item.size != null
                                    ? _formatFileSize(item.size!)
                                    : 'Unknown size',
                                style: const TextStyle(fontSize: 12),
                              ),
                        trailing: isFolder
                            ? const Icon(
                                Icons.chevron_right,
                                color: Colors.grey,
                              )
                            : null,
                        onTap: isFolder
                            ? () => _navigateToFolder(itemName)
                            : () => _handleFileTap(itemName, item),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleFileTap(String fileName, File file) async {
    // Check if it's a SQLite database file
    if (fileName.toLowerCase().endsWith('.sqlite3') ||
        fileName.toLowerCase().endsWith('.sqlite')) {
      await _openDatabaseDetails(fileName, file);
    } else {
      // Show snackbar for other files
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('File: $fileName'),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    }
  }

  Future<void> _openDatabaseDetails(String fileName, File file) async {
    if (_client == null) return;

    // Show loading dialog
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      // Get the full path to the file
      final filePath = _currentPath.isEmpty
          ? fileName
          : '$_currentPath/$fileName';

      // Download file to temporary directory
      // Use system temp directory directly
      final tempDir = io.Directory.systemTemp;
      final localFilePath = path.join(tempDir.path, fileName);

      // Read file from WebDAV
      // Use the read method which returns Uint8List
      final fileData = await _client!.read(filePath);

      // Write to local file
      final localFile = io.File(localFilePath);
      await localFile.writeAsBytes(fileData);

      // Close loading dialog
      if (mounted) Navigator.of(context).pop();

      // Navigate to details screen
      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => DatabaseDetailsScreen(
              filePath: localFilePath,
              fileName: fileName,
            ),
          ),
        );
      }
    } catch (e) {
      print('Error loading database: $e');
      // Close loading dialog
      if (mounted) Navigator.of(context).pop();

      // Show error
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading database: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}
