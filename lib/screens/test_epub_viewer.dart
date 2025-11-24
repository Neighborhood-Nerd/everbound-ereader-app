import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../widgets/foliate_webview.dart';

class TestEpubViewerPage extends StatefulWidget {
  const TestEpubViewerPage({super.key});

  @override
  State<TestEpubViewerPage> createState() => _TestEpubViewerPageState();
}

class _TestEpubViewerPageState extends State<TestEpubViewerPage> {
  final FoliateReaderController _controller = FoliateReaderController();
  bool _isLoading = false;

  String? _epubPath;

  @override
  void initState() {
    super.initState();
  }

  Future<void> _pickEpub() async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['epub']);
      if (result == null || result.files.single.path == null) return;

      final path = result.files.single.path!;
      if (!mounted) return;

      setState(() {
        _epubPath = path;
        _isLoading = true;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error picking EPUB: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Test EPUB Viewer'),
        leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop()),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _pickEpub,
        icon: const Icon(Icons.folder_open),
        label: const Text('Open EPUB'),
      ),
      body: Stack(
        children: [
          if (_epubPath != null && _epubPath!.isNotEmpty && File(_epubPath!).existsSync())
            FoliateWebView(
              controller: _controller,
              epubFilePath: _epubPath!,
              suppressNativeContextMenu: true,
              onBookLoaded: () {
                setState(() {
                  _isLoading = false;
                });
              },
              onRelocated: (detail) {
                debugPrint('Relocated: $detail');
              },
              onSelection: (detail) {
                debugPrint('Selection: $detail');
              },
            )
          else
            const Center(child: Text('Tap “Open EPUB” to choose a book to test.')),
          AnimatedOpacity(
            opacity: _isLoading ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 300),
            child: IgnorePointer(
              ignoring: !_isLoading,
              child: Container(
                color: Colors.white.withOpacity(0.8),
                child: const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [CircularProgressIndicator(), SizedBox(height: 16), Text('Loading book...')],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
