import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_html/flutter_html.dart';
import 'package:Everbound/models/app_theme_model.dart';
import '../providers/reader_providers.dart';

class HtmlViewerScreen extends ConsumerStatefulWidget {
  final String url;
  final String title;

  const HtmlViewerScreen({
    super.key,
    required this.url,
    required this.title,
  });

  @override
  ConsumerState<HtmlViewerScreen> createState() => _HtmlViewerScreenState();
}

class _HtmlViewerScreenState extends ConsumerState<HtmlViewerScreen> {
  String? _htmlContent;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadHtmlContent();
  }

  Future<void> _loadHtmlContent() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      final response = await http.get(Uri.parse(widget.url));
      
      if (response.statusCode == 200) {
        setState(() {
          _htmlContent = response.body;
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = 'Failed to load content: ${response.statusCode}';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Error loading content: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final readingSettings = ref.watch(readingSettingsProvider);
    final selectedTheme = AppThemes.getThemeByName(readingSettings.selectedThemeName);
    final variant = selectedTheme.getVariant(readingSettings.isDarkMode);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, style: TextStyle(color: variant.secondaryTextColor)),
        toolbarHeight: 80,
        backgroundColor: variant.backgroundColor,
      ),
      backgroundColor: variant.backgroundColor,
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(
                color: variant.textColor,
              ),
            )
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline, size: 48, color: variant.textColor),
                      const SizedBox(height: 16),
                      Text(
                        _error!,
                        style: TextStyle(color: variant.textColor),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadHtmlContent,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: variant.primaryColor,
                          foregroundColor: variant.isDark ? Colors.black : Colors.white,
                        ),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : _htmlContent != null
                  ? SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Html(
                        data: _htmlContent,
                        style: {
                          "html": Style(
                            backgroundColor: variant.backgroundColor,
                            color: variant.textColor,
                          ),
                          "body": Style(
                            backgroundColor: variant.backgroundColor,
                            color: variant.textColor,
                            fontSize: FontSize(16),
                            lineHeight: LineHeight(1.6),
                          ),
                          "h1": Style(
                            backgroundColor: variant.backgroundColor,
                            color: variant.textColor,
                            fontSize: FontSize(24),
                            fontWeight: FontWeight.bold,
                            margin: Margins.only(bottom: 16),
                          ),
                          "h2": Style(
                            backgroundColor: variant.backgroundColor,
                            color: variant.textColor,
                            fontSize: FontSize(20),
                            fontWeight: FontWeight.bold,
                            margin: Margins.only(top: 24, bottom: 12),
                          ),
                          "h3": Style(
                            backgroundColor: variant.backgroundColor,
                            color: variant.textColor,
                            fontSize: FontSize(18),
                            fontWeight: FontWeight.bold,
                            margin: Margins.only(top: 20, bottom: 10),
                          ),
                          "h4": Style(
                            backgroundColor: variant.backgroundColor,
                            color: variant.textColor,
                            fontSize: FontSize(16),
                            fontWeight: FontWeight.bold,
                            margin: Margins.only(top: 16, bottom: 8),
                          ),
                          "p": Style(
                            backgroundColor: variant.backgroundColor,
                            color: variant.textColor,
                            margin: Margins.only(bottom: 12),
                          ),
                          "a": Style(
                            backgroundColor: variant.backgroundColor,
                            color: variant.primaryColor,
                            textDecoration: TextDecoration.underline,
                          ),
                          "ul": Style(
                            backgroundColor: variant.backgroundColor,
                            margin: Margins.only(bottom: 12),
                          ),
                          "ol": Style(
                            backgroundColor: variant.backgroundColor,
                            margin: Margins.only(bottom: 12),
                          ),
                          "li": Style(
                            backgroundColor: variant.backgroundColor,
                            color: variant.textColor,
                            margin: Margins.only(bottom: 8),
                          ),
                          "strong": Style(
                            backgroundColor: variant.backgroundColor,
                            color: variant.textColor,
                            fontWeight: FontWeight.bold,
                          ),
                          "b": Style(
                            backgroundColor: variant.backgroundColor,
                            color: variant.textColor,
                            fontWeight: FontWeight.bold,
                          ),
                          "em": Style(
                            backgroundColor: variant.backgroundColor,
                            color: variant.textColor,
                            fontStyle: FontStyle.italic,
                          ),
                          "i": Style(
                            backgroundColor: variant.backgroundColor,
                            color: variant.textColor,
                            fontStyle: FontStyle.italic,
                          ),
                          "code": Style(
                            backgroundColor: variant.surfaceColor,
                            color: variant.textColor,
                            fontFamily: 'monospace',
                          ),
                          "pre": Style(
                            backgroundColor: variant.surfaceColor,
                            color: variant.textColor,
                            fontFamily: 'monospace',
                          ),
                          "blockquote": Style(
                            backgroundColor: variant.backgroundColor,
                            color: variant.textColor,
                            border: Border(
                              left: BorderSide(
                                color: variant.primaryColor,
                                width: 4,
                              ),
                            ),
                            padding: HtmlPaddings.only(left: 16),
                            margin: Margins.only(left: 0, top: 12, bottom: 12),
                          ),
                          "table": Style(
                            backgroundColor: variant.backgroundColor,
                            border: Border.all(color: variant.textColor.withOpacity(0.3)),
                          ),
                          "th": Style(
                            backgroundColor: variant.surfaceColor,
                            color: variant.textColor,
                            padding: HtmlPaddings.all(8),
                          ),
                          "td": Style(
                            backgroundColor: variant.backgroundColor,
                            color: variant.textColor,
                            padding: HtmlPaddings.all(8),
                          ),
                          "div": Style(
                            backgroundColor: variant.backgroundColor,
                            color: variant.textColor,
                          ),
                          "span": Style(
                            backgroundColor: variant.backgroundColor,
                            color: variant.textColor,
                          ),
                        },
                      ),
                    )
                  : const SizedBox.shrink(),
    );
  }
}

