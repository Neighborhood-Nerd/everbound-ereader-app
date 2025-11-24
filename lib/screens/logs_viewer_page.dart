import 'dart:io';
import 'package:Everbound/models/app_theme_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:share_plus/share_plus.dart';
import '../models/log_entry.dart';
import '../providers/reader_providers.dart';
import '../services/log_cache.dart';

class LogsViewerPage extends ConsumerStatefulWidget {
  const LogsViewerPage({super.key});

  @override
  ConsumerState<LogsViewerPage> createState() => _LogsViewerPageState();
}

class _LogsViewerPageState extends ConsumerState<LogsViewerPage> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isAutoScrolling = true;
  bool _userManuallyScrolled = false;
  LogLevel? _selectedLogLevel;
  bool _isScrollingProgrammatically = false;
  List<LogEntry> _filteredLogs = [];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _scrollController.addListener(_onScrollChanged);
    _updateFilteredLogs();
    
    // Listen to log stream for real-time updates
    logCache.logStream.listen((_) {
      if (mounted) {
        _updateFilteredLogs();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _updateFilteredLogs() {
    setState(() {
      _filteredLogs = _filterLogs(
        logCache.logs,
        _searchController.text,
        _selectedLogLevel,
      );
    });
    
    // Auto-scroll if enabled
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_isAutoScrolling && !_userManuallyScrolled) {
        _scrollToBottom();
      }
    });
  }

  void _onSearchChanged() {
    _updateFilteredLogs();
  }

  void _onLogLevelChanged(LogLevel? level) {
    setState(() {
      _selectedLogLevel = level;
    });
    _updateFilteredLogs();
  }

  void _onScrollChanged() {
    if (_scrollController.hasClients && !_isScrollingProgrammatically) {
      final isAtBottom = _scrollController.offset >=
          _scrollController.position.maxScrollExtent - 100;

      if (isAtBottom) {
        _userManuallyScrolled = false;
      } else {
        _userManuallyScrolled = true;
      }
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _isScrollingProgrammatically = true;
      _scrollController
          .animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
      )
          .then((_) {
        _isScrollingProgrammatically = false;
      });
    }
  }

  void _shareLogs() async {
    try {
      final logsText = logCache.getLogsAsText();

      if (logsText.isEmpty) {
        _showSnackBar('No logs to share', isError: true);
        return;
      }

      // Get app version
      final packageInfo = await PackageInfo.fromPlatform();
      final version = packageInfo.version;

      // Create a temporary file to share
      final tempDir = Directory.systemTemp;
      final now = DateTime.now();
      final dateTimeStr = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
      final fileName = 'everbound_logs_${dateTimeStr}_$version.log';
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsString(logsText);

      // Share the file
      final xFile = XFile(
        file.path,
        name: fileName,
        mimeType: 'text/plain',
      );
      await Share.shareXFiles([xFile],
          subject: 'App Logs - ${DateTime.now().toString()}');
    } catch (e) {
      // Fallback to clipboard if sharing fails
      if (e.toString().contains('MissingPluginException') ||
          e.toString().contains('PlatformException')) {
        _showSnackBar('Sharing not available, copying to clipboard instead');
        _copyLogs();
      } else {
        _showSnackBar('Failed to share logs: $e', isError: true);
      }
    }
  }

  void _copyLogs() async {
    try {
      final logsText = logCache.getLogsAsText();

      if (logsText.isEmpty) {
        _showSnackBar('No logs to copy', isError: true);
        return;
      }

      // Copy logs to clipboard
      await Clipboard.setData(ClipboardData(text: logsText));
      _showSnackBar('Logs copied to clipboard');
    } catch (e) {
      _showSnackBar('Failed to copy logs: $e', isError: true);
    }
  }

  void _clearLogs() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Logs'),
        content: const Text(
            'Are you sure you want to clear all logs? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clear', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      logCache.clearLogs();
      _updateFilteredLogs();
      _showSnackBar('Logs cleared');
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  List<LogEntry> _filterLogs(
      List<LogEntry> logs, String query, LogLevel? levelFilter) {
    var filteredLogs = logs;

    // Filter by log level
    if (levelFilter != null) {
      filteredLogs =
          filteredLogs.where((log) => log.level == levelFilter).toList();
    }

    // Filter by search query
    if (query.isNotEmpty) {
      filteredLogs =
          filteredLogs.where((log) => log.matchesSearch(query)).toList();
    }

    return filteredLogs;
  }

  @override
  Widget build(BuildContext context) {
    final readingSettings = ref.watch(readingSettingsProvider);
    final selectedTheme = AppThemes.getThemeByName(
      readingSettings.selectedThemeName,
    );
    final variant = selectedTheme.getVariant(readingSettings.isDarkMode);
    final isDark = readingSettings.isDarkMode;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'App Logs',
          style: TextStyle(color: variant.secondaryTextColor),
        ),
        toolbarHeight: 80,
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'share':
                  _shareLogs();
                  break;
                case 'copy':
                  _copyLogs();
                  break;
                case 'clear':
                  _clearLogs();
                  break;
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'share',
                child: Row(
                  children: [
                    Icon(Icons.share, size: 20),
                    SizedBox(width: 8),
                    const Text('Share Logs'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'copy',
                child: Row(
                  children: [
                    Icon(Icons.copy, size: 20),
                    SizedBox(width: 8),
                    const Text('Copy Logs'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'clear',
                child: Row(
                  children: [
                    Icon(Icons.clear_all, size: 20, color: Colors.red),
                    SizedBox(width: 8),
                    const Text('Clear Logs',
                        style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ],
            icon: Icon(
              Icons.more_vert,
              color: variant.secondaryTextColor,
            ),
          ),
        ],
      ),
      body: SafeArea(
        bottom: true,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            children: [
              // Search bar
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search logs...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          onPressed: () {
                            _searchController.clear();
                          },
                          icon: const Icon(Icons.clear),
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: isDark ? Colors.grey[800] : Colors.grey[100],
                ),
              ),
              SizedBox(height: 16),

              // Log level filter
              Row(
                children: [
                  Text(
                    'Filter by level:',
                    style: TextStyle(color: variant.textColor),
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<LogLevel?>(
                      value: _selectedLogLevel,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        filled: true,
                        fillColor: isDark ? Colors.grey[800] : Colors.grey[100],
                      ),
                      hint: const Text('All levels'),
                      items: [
                        const DropdownMenuItem<LogLevel?>(
                          value: null,
                          child: Text('All levels'),
                        ),
                        DropdownMenuItem<LogLevel?>(
                          value: LogLevel.verbose,
                          child: Row(
                            children: [
                              Container(
                                width: 12,
                                height: 12,
                                decoration: const BoxDecoration(
                                  color: Colors.grey,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              SizedBox(width: 8),
                              const Text('Verbose'),
                            ],
                          ),
                        ),
                        DropdownMenuItem<LogLevel?>(
                          value: LogLevel.debug,
                          child: Row(
                            children: [
                              Container(
                                width: 12,
                                height: 12,
                                decoration: const BoxDecoration(
                                  color: Colors.blueGrey,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              SizedBox(width: 8),
                              const Text('Debug'),
                            ],
                          ),
                        ),
                        DropdownMenuItem<LogLevel?>(
                          value: LogLevel.info,
                          child: Row(
                            children: [
                              Container(
                                width: 12,
                                height: 12,
                                decoration: const BoxDecoration(
                                  color: Colors.green,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              SizedBox(width: 8),
                              const Text('Info'),
                            ],
                          ),
                        ),
                        DropdownMenuItem<LogLevel?>(
                          value: LogLevel.warning,
                          child: Row(
                            children: [
                              Container(
                                width: 12,
                                height: 12,
                                decoration: const BoxDecoration(
                                  color: Colors.orange,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              SizedBox(width: 8),
                              const Text('Warning'),
                            ],
                          ),
                        ),
                        DropdownMenuItem<LogLevel?>(
                          value: LogLevel.error,
                          child: Row(
                            children: [
                              Container(
                                width: 12,
                                height: 12,
                                decoration: const BoxDecoration(
                                  color: Colors.red,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              SizedBox(width: 8),
                              const Text('Error'),
                            ],
                          ),
                        ),
                      ],
                      onChanged: _onLogLevelChanged,
                    ),
                  ),
                ],
              ),

              // Log count and auto-scroll toggle
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Text(
                      '${_filteredLogs.length} log${_filteredLogs.length != 1 ? 's' : ''}',
                      style: TextStyle(color: variant.textColor),
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        Text(
                          'Auto-scroll',
                          style: TextStyle(color: variant.textColor),
                        ),
                        Switch(
                          value: _isAutoScrolling,
                          onChanged: (value) {
                            setState(() {
                              _isAutoScrolling = value;
                              if (value) {
                                _userManuallyScrolled = false;
                              }
                            });
                            if (value) {
                              _scrollToBottom();
                            }
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Logs list
              Expanded(
                child: _filteredLogs.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.article_outlined,
                              size: 64,
                              color: isDark ? Colors.white38 : Colors.black38,
                            ),
                            SizedBox(height: 16),
                            Text(
                              _searchController.text.isNotEmpty
                                  ? 'No logs match your search'
                                  : 'No logs available',
                              style: TextStyle(
                                color: isDark ? Colors.white54 : Colors.black54,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        itemCount: _filteredLogs.length,
                        itemBuilder: (context, index) {
                          final log = _filteredLogs[index];
                          return _buildLogEntry(log, isDark, variant);
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLogEntry(LogEntry log, bool isDark, ThemeVariant variant) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[800] : Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: log.color.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Log level indicator
          Container(
            width: 4,
            height: 20,
            decoration: BoxDecoration(
              color: log.color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          SizedBox(width: 8),

          // Log content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header with timestamp and level
                Row(
                  children: [
                    Text(
                      log.formattedTime,
                      style: TextStyle(
                        color: isDark ? Colors.white70 : Colors.black54,
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                    SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: log.color.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        log.level.displayName,
                        style: TextStyle(
                          color: log.color,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    SizedBox(width: 8),
                    Text(
                      log.tag,
                      style: TextStyle(
                        color: isDark ? Colors.white70 : Colors.black54,
                        fontWeight: FontWeight.w500,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 4),

                // Log message
                SelectableText(
                  log.message,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    height: 1.3,
                    color: variant.textColor,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

