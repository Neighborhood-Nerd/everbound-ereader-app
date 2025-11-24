import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webdav_client/webdav_client.dart';

import '../providers/reader_providers.dart';

/// WebDAV browser widget for selecting a folder
class WebDavBrowserWidget extends ConsumerStatefulWidget {
  final String url;
  final String username;
  final String password;
  final String? initialPath;

  const WebDavBrowserWidget({
    super.key,
    required this.url,
    required this.username,
    required this.password,
    this.initialPath,
  });

  @override
  ConsumerState<WebDavBrowserWidget> createState() =>
      _WebDavBrowserWidgetState();
}

class _WebDavBrowserWidgetState extends ConsumerState<WebDavBrowserWidget> {
  Client? _client;
  String _status = 'Not connected';
  List<File> _items = [];
  String _currentPath = '';
  List<String> _pathHistory = [];
  bool _isLoading = false;
  String? _selectedPath;

  @override
  void initState() {
    super.initState();
    _currentPath = widget.initialPath ?? '';
    _selectedPath = widget.initialPath;
    _connect();
  }

  Future<void> _connect() async {
    setState(() {
      _isLoading = true;
      _status = 'Connecting...';
      _items = [];
    });

    try {
      _client = newClient(
        widget.url,
        user: widget.username,
        password: widget.password,
      );
      await _loadDirectory(_currentPath);
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

  void _selectCurrentFolder() {
    setState(() {
      _selectedPath = _currentPath;
    });
    Navigator.of(context).pop(_currentPath);
  }

  String _getCurrentDisplayPath() {
    if (_currentPath.isEmpty) return '/';
    return '/$_currentPath';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Folder'),
        leading: _currentPath.isNotEmpty || _pathHistory.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: _navigateBack,
                tooltip: 'Go back',
              )
            : null,
        actions: [
          if (_currentPath.isNotEmpty || _selectedPath != null)
            IconButton(
              icon: const Icon(Icons.check),
              onPressed: _selectCurrentFolder,
              tooltip: 'Select this folder',
            ),
        ],
      ),
      body: Column(
        children: [
          // Status bar with path
          Container(
            padding: const EdgeInsets.all(12.0),
            color: ref.read(themeVariantProvider).backgroundColor,
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
          // Selected path indicator
          if (_selectedPath != null && _selectedPath!.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(12.0),
              color: Colors.blue[50],
              child: Row(
                children: [
                  const Icon(Icons.folder, color: Colors.blue, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Selected: /$_selectedPath',
                      style: const TextStyle(fontSize: 12, color: Colors.blue),
                      overflow: TextOverflow.ellipsis,
                    ),
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

                      if (!isFolder) {
                        // Skip files, only show folders
                        return const SizedBox.shrink();
                      }

                      final isSelected = _currentPath.isEmpty
                          ? itemName == _selectedPath
                          : '$_currentPath/$itemName' == _selectedPath;

                      return ListTile(
                        leading: Icon(
                          Icons.folder,
                          color: isSelected ? Colors.blue : Colors.blue[300],
                        ),
                        title: Text(itemName),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isSelected)
                              const Icon(Icons.check, color: Colors.blue),
                            const SizedBox(width: 8),
                            const Icon(Icons.chevron_right, color: Colors.grey),
                          ],
                        ),
                        onTap: () => _navigateToFolder(itemName),
                        onLongPress: () {
                          // Select folder on long press
                          final folderPath = _currentPath.isEmpty
                              ? itemName
                              : '$_currentPath/$itemName';
                          setState(() {
                            _selectedPath = folderPath;
                          });
                          Navigator.of(context).pop(folderPath);
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: _currentPath.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: _selectCurrentFolder,
              icon: const Icon(Icons.check),
              label: const Text('Select Folder'),
              backgroundColor: ref.read(themeVariantProvider).primaryColor,
            )
          : null,
    );
  }
}
