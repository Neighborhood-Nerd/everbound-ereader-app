import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import '../colors.dart';
import '../models/file_source_model.dart';
import '../services/local_database_service.dart';
import '../providers/file_source_providers.dart';
import '../providers/my_books_providers.dart';
import '../widgets/webdav_browser_widget.dart';

class FileSourcesScreen extends ConsumerStatefulWidget {
  const FileSourcesScreen({super.key});

  @override
  ConsumerState<FileSourcesScreen> createState() => _FileSourcesScreenState();
}

class _FileSourcesScreenState extends ConsumerState<FileSourcesScreen> {
  Future<void> _addSource() async {
    // Show dialog to choose source type
    final sourceType = await showDialog<FileSourceType>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add File Source'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.folder),
              title: const Text('Local Folder'),
              onTap: () => Navigator.of(context).pop(FileSourceType.local),
            ),
            ListTile(
              leading: const Icon(Icons.cloud),
              title: const Text('WebDAV'),
              onTap: () => Navigator.of(context).pop(FileSourceType.webdav),
            ),
          ],
        ),
      ),
    );

    if (sourceType == null) return;

    if (sourceType == FileSourceType.local) {
      await _addLocalSource();
    } else if (sourceType == FileSourceType.webdav) {
      await _addWebDavSource();
    }
  }

  Future<void> _addLocalSource() async {
    try {
      final String? selectedDirectory = await FilePicker.platform
          .getDirectoryPath();
      if (selectedDirectory == null) return;

      // Show dialog to enter name
      final nameController = TextEditingController(
        text: selectedDirectory.split('/').last,
      );
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Add Local Folder'),
          content: TextField(
            controller: nameController,
            decoration: const InputDecoration(
              labelText: 'Source Name',
              hintText: 'Enter a name for this source',
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Add'),
            ),
          ],
        ),
      );

      if (confirmed == true && nameController.text.isNotEmpty) {
        final dbService = LocalDatabaseService.instance;
        await dbService.initialize();

        final source = FileSource(
          name: nameController.text,
          type: FileSourceType.local,
          localPath: selectedDirectory,
          createdAt: DateTime.now(),
        );

        final sourceId = dbService.insertFileSource(source);
        ref.read(fileSourcesRefreshProvider.notifier).state++;

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Local folder added successfully. Scanning for books...',
              ),
              backgroundColor: Colors.green,
            ),
          );

          // Auto-trigger scan for the newly added source
          _scanSingleSource(sourceId);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error adding local folder: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _addWebDavSource() async {
    final urlController = TextEditingController();
    final usernameController = TextEditingController();
    final passwordController = TextEditingController();
    final nameController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add WebDAV Source'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Source Name',
                  hintText: 'Enter a name for this source',
                ),
                autofocus: true,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: urlController,
                decoration: const InputDecoration(
                  labelText: 'WebDAV URL',
                  hintText: 'https://example.com/dav',
                ),
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
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Connect & Select Folder'),
          ),
        ],
      ),
    );

    if (confirmed == true &&
        nameController.text.isNotEmpty &&
        urlController.text.isNotEmpty &&
        usernameController.text.isNotEmpty &&
        passwordController.text.isNotEmpty) {
      // Navigate to WebDAV browser to select folder
      final selectedPath = await Navigator.of(context).push<String>(
        MaterialPageRoute(
          builder: (context) => WebDavBrowserWidget(
            url: urlController.text,
            username: usernameController.text,
            password: passwordController.text,
          ),
        ),
      );

      if (selectedPath != null && mounted) {
        try {
          final dbService = LocalDatabaseService.instance;
          await dbService.initialize();

          final source = FileSource(
            name: nameController.text,
            type: FileSourceType.webdav,
            url: urlController.text,
            username: usernameController.text,
            password: passwordController.text,
            selectedPath: selectedPath,
            createdAt: DateTime.now(),
          );

          final sourceId = dbService.insertFileSource(source);
          ref.read(fileSourcesRefreshProvider.notifier).state++;

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'WebDAV source added successfully. Scanning for books...',
                ),
                backgroundColor: Colors.green,
              ),
            );

            // Auto-trigger scan for the newly added source
            _scanSingleSource(sourceId);
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Error adding WebDAV source: $e'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      }
    }
  }

  Future<void> _editSource(FileSource source) async {
    if (source.type == FileSourceType.local) {
      await _editLocalSource(source);
    } else {
      await _editWebDavSource(source);
    }
  }

  Future<void> _editLocalSource(FileSource source) async {
    final nameController = TextEditingController(text: source.name);
    final pathController = TextEditingController(text: source.localPath ?? '');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Local Folder'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Source Name'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: pathController,
              decoration: const InputDecoration(labelText: 'Folder Path'),
              readOnly: true,
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: () async {
                final String? selectedDirectory = await FilePicker.platform
                    .getDirectoryPath();
                if (selectedDirectory != null) {
                  pathController.text = selectedDirectory;
                }
              },
              icon: const Icon(Icons.folder_open),
              label: const Text('Select Folder'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (confirmed == true &&
        nameController.text.isNotEmpty &&
        pathController.text.isNotEmpty) {
      try {
        final dbService = LocalDatabaseService.instance;
        await dbService.initialize();

        final updatedSource = source.copyWith(
          name: nameController.text,
          localPath: pathController.text,
        );

        dbService.updateFileSource(updatedSource);
        ref.read(fileSourcesRefreshProvider.notifier).state++;

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Source updated successfully'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error updating source: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _editWebDavSource(FileSource source) async {
    final urlController = TextEditingController(text: source.url ?? '');
    final usernameController = TextEditingController(
      text: source.username ?? '',
    );
    final passwordController = TextEditingController(
      text: source.password ?? '',
    );
    final nameController = TextEditingController(text: source.name);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit WebDAV Source'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Source Name'),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: urlController,
                decoration: const InputDecoration(labelText: 'WebDAV URL'),
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
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Save'),
          ),
          TextButton(
            onPressed: () async {
              // Navigate to folder selector
              final selectedPath = await Navigator.of(context).push<String>(
                MaterialPageRoute(
                  builder: (context) => WebDavBrowserWidget(
                    url: urlController.text,
                    username: usernameController.text,
                    password: passwordController.text,
                    initialPath: source.selectedPath,
                  ),
                ),
              );
              if (selectedPath != null && mounted) {
                Navigator.of(context).pop(true);
                // Save with new path
                final dbService = LocalDatabaseService.instance;
                await dbService.initialize();
                final updatedSource = source.copyWith(
                  name: nameController.text,
                  url: urlController.text,
                  username: usernameController.text,
                  password: passwordController.text,
                  selectedPath: selectedPath,
                );
                dbService.updateFileSource(updatedSource);
                ref.read(fileSourcesRefreshProvider.notifier).state++;
              }
            },
            child: const Text('Change Folder'),
          ),
        ],
      ),
    );

    if (confirmed == true &&
        nameController.text.isNotEmpty &&
        urlController.text.isNotEmpty &&
        usernameController.text.isNotEmpty &&
        passwordController.text.isNotEmpty) {
      try {
        final dbService = LocalDatabaseService.instance;
        await dbService.initialize();

        final updatedSource = source.copyWith(
          name: nameController.text,
          url: urlController.text,
          username: usernameController.text,
          password: passwordController.text,
        );

        dbService.updateFileSource(updatedSource);
        ref.read(fileSourcesRefreshProvider.notifier).state++;

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Source updated successfully'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error updating source: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _deleteSource(FileSource source) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Source'),
        content: Text(
          'Are you sure you want to delete "${source.name}"? This will not delete any imported books.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && source.id != null) {
      try {
        final dbService = LocalDatabaseService.instance;
        await dbService.initialize();

        dbService.deleteFileSource(source.id!);
        ref.read(fileSourcesRefreshProvider.notifier).state++;

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Source deleted successfully'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error deleting source: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _scanSingleSource(int sourceId) async {
    try {
      final result = await ref.read(scanSingleSourceProvider(sourceId).future);

      // Refresh books list
      ref.read(booksRefreshProvider.notifier).state++;

      if (mounted) {
        final message = result.errors.isEmpty
            ? 'Scan complete: ${result.imported} new book(s) imported from ${result.scanned} file(s)'
            : 'Scan complete with ${result.errors.length} error(s): ${result.imported} new book(s) imported';

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: result.errors.isEmpty
                ? Colors.green
                : Colors.orange,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error scanning source: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _scanSources() async {
    final scanProgress = ref.read(scanProgressProvider);
    if (scanProgress != null) {
      // Already scanning
      return;
    }

    try {
      final result = await ref.read(scanSourcesProvider(true).future);

      // Refresh books list
      ref.read(booksRefreshProvider.notifier).state++;

      if (mounted) {
        final message = result.errors.isEmpty
            ? 'Scan complete: ${result.imported} new book(s) imported from ${result.scanned} file(s)'
            : 'Scan complete with ${result.errors.length} error(s): ${result.imported} new book(s) imported';

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: result.errors.isEmpty
                ? Colors.green
                : Colors.orange,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error scanning sources: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final sourcesAsync = ref.watch(fileSourcesProvider);
    final scanProgress = ref.watch(scanProgressProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('File Sources'),
        actions: [
          if (scanProgress != null)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Center(
                child: Text(scanProgress, style: const TextStyle(fontSize: 12)),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: scanProgress == null ? _scanSources : null,
            tooltip: 'Scan Sources',
          ),
        ],
      ),
      body: sourcesAsync.when(
        data: (sources) {
          if (sources.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.folder, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    'No file sources configured',
                    style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Add a source to scan for books',
                    style: TextStyle(color: Colors.grey[500]),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: sources.length,
            itemBuilder: (context, index) {
              final source = sources[index];
              return _buildSourceCard(context, source);
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
              Text('Error loading sources: $error'),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addSource,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Add Source', style: TextStyle(color: Colors.white)),
        backgroundColor: primaryColor,
      ),
    );
  }

  Widget _buildSourceCard(BuildContext context, FileSource source) {
    final sourceProgress = ref.watch(sourceScanProgressProvider);
    final progress = source.id != null ? sourceProgress[source.id] : null;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Slidable(
        key: ValueKey(source.id),
        endActionPane: ActionPane(
          motion: const BehindMotion(),
          extentRatio: 0.4,
          children: [
            SlidableAction(
              borderRadius: BorderRadius.circular(8),
              onPressed: (context) => _editSource(source),
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              icon: Icons.edit,
              label: 'Edit',
            ),
            SlidableAction(
              borderRadius: BorderRadius.circular(8),
              onPressed: (context) => _deleteSource(source),
              backgroundColor: const Color(0xFFFE4A49),
              foregroundColor: Colors.white,
              icon: Icons.delete,
              label: 'Delete',
            ),
          ],
        ),
        child: Column(
          children: [
            // Progress indicator at the top
            if (progress != null && progress.isScanning)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(4),
                    topRight: Radius.circular(4),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            progress.booksFound > 0
                                ? 'Scanning... ${progress.booksImported}/${progress.booksFound} books imported'
                                : 'Scanning for books...',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (progress.booksFound > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: LinearProgressIndicator(
                          value: progress.booksImported / progress.booksFound,
                          minHeight: 4,
                          backgroundColor: Colors.blue.withOpacity(0.2),
                        ),
                      ),
                  ],
                ),
              ),
            ListTile(
              leading: Icon(
                source.type == FileSourceType.local
                    ? Icons.folder
                    : Icons.cloud,
                color: source.type == FileSourceType.local
                    ? Colors.blue
                    : Colors.orange,
              ),
              title: Text(source.name),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(source.type.displayName),
                  if (source.type == FileSourceType.local &&
                      source.localPath != null)
                    Text(
                      source.localPath!,
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    )
                  else if (source.type == FileSourceType.webdav)
                    Text(
                      '${source.url}${source.selectedPath != null ? source.selectedPath! : ""}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  if (source.lastScannedAt != null)
                    Text(
                      'Last scanned: ${_formatDateTime(source.lastScannedAt!)}',
                      style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                    ),
                ],
              ),
              trailing: IconButton(
                icon: const Icon(Icons.refresh),
                onPressed:
                    source.id != null &&
                        (progress == null || !progress.isScanning)
                    ? () => _scanSingleSource(source.id!)
                    : null,
                tooltip: 'Scan Source',
              ),
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
