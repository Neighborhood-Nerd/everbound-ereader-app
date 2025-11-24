import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'package:flutter_html/flutter_html.dart';
import '../providers/reader_providers.dart';

class WiktionaryBottomSheet extends ConsumerStatefulWidget {
  final String word;
  final VoidCallback? onClose;

  const WiktionaryBottomSheet({super.key, required this.word, this.onClose});

  @override
  ConsumerState<WiktionaryBottomSheet> createState() => _WiktionaryBottomSheetState();
}

class _WiktionaryBottomSheetState extends ConsumerState<WiktionaryBottomSheet> {
  Map<String, dynamic>? _definitions;
  bool _isLoading = true;
  String? _error;
  String _lookupWord = '';

  @override
  void initState() {
    super.initState();
    // Clean the word: trim, remove punctuation, take first word if multiple
    final cleanedWord = _cleanWord(widget.word);
    _lookupWord = cleanedWord;
    _fetchDefinitions(cleanedWord);
  }

  String _cleanWord(String text) {
    // Remove leading/trailing whitespace
    text = text.trim();
    // Remove common punctuation at the end
    text = text.replaceAll(RegExp(r'[.,;:!?]+$'), '');
    // Take only the first word if multiple words
    final words = text.split(RegExp(r'\s+'));
    return words.isNotEmpty ? words[0].toLowerCase() : text.toLowerCase();
  }

  Future<void> _fetchDefinitions(String word) async {
    if (word.isEmpty) {
      setState(() {
        _isLoading = false;
        _error = 'No word provided';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
      _definitions = null; // Clear previous definitions
    });

    try {
      word = word.replaceAll('.', '').replaceAll('_', ' ');
      final encodedWord = Uri.encodeComponent(word);
      final url = 'https://en.wiktionary.org/api/rest_v1/page/definition/$encodedWord';
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body) as Map<String, dynamic>;
        // Get English definitions (or first available language)
        final results = jsonData['en'] ?? (jsonData.keys.isNotEmpty ? jsonData[jsonData.keys.first] : null);

        if (results == null || (results is List && results.isEmpty)) {
          setState(() {
            _isLoading = false;
            _error = 'No definitions found';
            _definitions = null;
          });
          return;
        }

        setState(() {
          _definitions = jsonData;
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false;
          _error = 'Failed to load definition (${response.statusCode})';
          _definitions = null;
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = 'Error: ${e.toString()}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final readingSettings = ref.watch(readingSettingsProvider);
    final screenHeight = MediaQuery.of(context).size.height;
    final maxHeight = screenHeight * 0.5; // 70% of screen height

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: Colors.grey[400], borderRadius: BorderRadius.circular(2)),
              ),
              // Header with word
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: readingSettings.isDarkMode ? Colors.grey[700]! : Colors.grey[300]!,
                      width: 1,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _lookupWord,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: readingSettings.isDarkMode ? Colors.white : Colors.black,
                            ),
                          ),
                          if (_definitions != null && _definitions!['en'] != null)
                            Text(
                              'English',
                              style: TextStyle(
                                fontSize: 12,
                                fontStyle: FontStyle.italic,
                                color: readingSettings.isDarkMode ? Colors.grey[400] : Colors.grey[600],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // Content area
              Flexible(
                child: _isLoading
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const CircularProgressIndicator(),
                            const SizedBox(height: 16),
                            Text(
                              'Loading definition...',
                              style: TextStyle(color: readingSettings.isDarkMode ? Colors.grey[400] : Colors.grey[600]),
                            ),
                          ],
                        ),
                      )
                    : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.error_outline,
                                size: 48,
                                color: readingSettings.isDarkMode ? Colors.grey[400] : Colors.grey[600],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _error!,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: readingSettings.isDarkMode ? Colors.grey[400] : Colors.grey[600],
                                ),
                              ),
                              const SizedBox(height: 16),
                              TextButton(
                                onPressed: () {
                                  // Open Wiktionary in browser
                                  // Note: You might want to use url_launcher package for this
                                },
                                child: const Text('Search on Wiktionary'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : _buildDefinitions(readingSettings.isDarkMode),
              ),
              // Footer
              if (!_isLoading && _error == null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(
                        color: readingSettings.isDarkMode ? Colors.grey[700]! : Colors.grey[300]!,
                        width: 1,
                      ),
                    ),
                  ),
                  child: Text(
                    'Source: Wiktionary (CC BY-SA)',
                    style: TextStyle(
                      fontSize: 12,
                      color: readingSettings.isDarkMode ? Colors.grey[400] : Colors.grey[600],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDefinitions(bool isDarkMode) {
    if (_definitions == null) {
      return Center(
        child: Text('Loading...', style: TextStyle(color: isDarkMode ? Colors.grey[400] : Colors.grey[600])),
      );
    }

    // Get English definitions (or first available language)
    dynamic results;
    if (_definitions!.containsKey('en')) {
      results = _definitions!['en'];
    } else if (_definitions!.keys.isNotEmpty) {
      results = _definitions![_definitions!.keys.first];
    }

    if (results == null || (results is List && results.isEmpty)) {
      return Center(
        child: Text('No definitions found', style: TextStyle(color: isDarkMode ? Colors.grey[400] : Colors.grey[600])),
      );
    }

    if (results is! List) {
      return Center(
        child: Text(
          'Unexpected data format',
          style: TextStyle(color: isDarkMode ? Colors.grey[400] : Colors.grey[600]),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      shrinkWrap: true,
      itemCount: results.length,
      itemBuilder: (context, index) {
        final result = results[index] as Map<String, dynamic>;
        final partOfSpeech = result['partOfSpeech']?.toString() ?? '';
        final definitions = result['definitions'] as List? ?? [];

        if (definitions.isEmpty) {
          return const SizedBox.shrink();
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (partOfSpeech.isNotEmpty) ...[
              Text(
                partOfSpeech,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: isDarkMode ? Colors.white : Colors.black,
                ),
              ),
              const SizedBox(height: 8),
            ],
            ...definitions.asMap().entries.map((entry) {
              final defIndex = entry.key;
              final def = entry.value as Map<String, dynamic>;
              final definition = def['definition']?.toString() ?? '';
              final examples = (def['examples'] as List?)?.map((e) => e.toString()).toList() ?? [];

              return Padding(
                padding: EdgeInsets.only(left: 16, bottom: defIndex < definitions.length - 1 ? 12 : 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildDefinitionText(definition, defIndex + 1, isDarkMode),
                    if (examples.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      ...examples.map(
                        (example) => Padding(
                          padding: const EdgeInsets.only(left: 16, top: 4),
                          child: _buildExampleText(example, isDarkMode),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            }),
            if (index < results.length - 1) ...[
              const SizedBox(height: 16),
              Divider(color: isDarkMode ? Colors.grey[700] : Colors.grey[300]),
              const SizedBox(height: 16),
            ],
          ],
        );
      },
    );
  }

  Widget _buildExampleText(String example, bool isDarkMode) {
    if (example.isEmpty) return const SizedBox.shrink();

    // Clean the HTML for examples
    final document = html_parser.parse(example);
    document.querySelectorAll('style, script').forEach((element) => element.remove());
    document.querySelectorAll('*').forEach((element) {
      element.attributes.remove('class');
      element.attributes.remove('style');
    });
    final cleanedHtml = document.body?.innerHtml ?? example;

    return Html(
      data: cleanedHtml,
      style: {
        'body': Style(
          margin: Margins.zero,
          padding: HtmlPaddings.zero,
          fontSize: FontSize(13),
          fontStyle: FontStyle.italic,
          color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
        ),
        'a': Style(color: isDarkMode ? Colors.blue[300] : Colors.blue[700], textDecoration: TextDecoration.underline),
      },
      onLinkTap: _handleLinkTap,
    );
  }

  void _handleLinkTap(String? url, Map<String, String> attributes, _) {
    if (url == null) return;

    // Extract word from Wiktionary links
    // Links can be like: /wiki/word or https://en.wiktionary.org/wiki/word
    final uri = Uri.tryParse(url);
    if (uri == null) return;

    String? word;
    // Check if it's a relative path like /wiki/word
    if (uri.path.startsWith('/wiki/')) {
      word = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : null;
    }
    // Check if it's a full URL
    else if (uri.host.contains('wiktionary.org') && uri.pathSegments.isNotEmpty) {
      word = uri.pathSegments.last;
    }
    // Check title attribute for word definition
    else if (attributes.containsKey('title')) {
      word = attributes['title'];
    }

    if (word != null && word.isNotEmpty) {
      // Clean the word (remove URL encoding, etc.)
      word = Uri.decodeComponent(word);
      final cleanedWord = _cleanWord(word);

      // Update lookup word and fetch new definitions
      setState(() {
        _lookupWord = cleanedWord;
      });
      _fetchDefinitions(cleanedWord);
    }
  }

  Widget _buildDefinitionText(String definition, int index, bool isDarkMode) {
    if (definition.isEmpty) return const SizedBox.shrink();

    // Clean the HTML first to remove unwanted elements and attributes
    final document = html_parser.parse(definition);

    // Remove style, script, and CSS-related elements
    document.querySelectorAll('style, script').forEach((element) => element.remove());

    // Remove class and style attributes from all elements to prevent CSS from showing as text
    document.querySelectorAll('*').forEach((element) {
      element.attributes.remove('class');
      element.attributes.remove('style');
    });

    // Get the cleaned HTML
    final cleanedHtml = document.body?.innerHtml ?? definition;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$index. ',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: isDarkMode ? Colors.grey[300] : Colors.black87,
          ),
        ),
        Expanded(
          child: Html(
            data: cleanedHtml,
            style: {
              'body': Style(
                margin: Margins.zero,
                padding: HtmlPaddings.zero,
                fontSize: FontSize(14),
                color: isDarkMode ? Colors.grey[200] : Colors.black87,
                lineHeight: const LineHeight(1.5),
              ),
              'a': Style(
                color: isDarkMode ? Colors.blue[300] : Colors.blue[700],
                textDecoration: TextDecoration.underline,
              ),
            },
            onLinkTap: _handleLinkTap,
          ),
        ),
      ],
    );
  }
}
