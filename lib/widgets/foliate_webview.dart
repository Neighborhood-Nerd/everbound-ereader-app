import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../services/book_import_service.dart';

typedef FoliateSelectionCallback = void Function(Map<String, dynamic> detail);

typedef FoliateRelocatedCallback = void Function(Map<String, dynamic> location);

typedef FoliateAnnotationEventCallback = void Function(Map<String, dynamic> detail);
typedef FoliateSelectionEventCallback = void Function(Map<String, dynamic> detail);
typedef FoliateShowAnnotationEventCallback = void Function(Map<String, dynamic> detail);
typedef FoliateTouchEventCallback = void Function(Map<String, dynamic> touchData);

class FoliateReaderController {
  InAppWebViewController? _webViewController;

  void attach(InAppWebViewController controller) {
    _webViewController = controller;
  }

  bool get isAttached => _webViewController != null;

  Future<void> openBook({
    required List<int> bytes,
    Map<String, dynamic>? initialLocation,
    String flow = 'paginated',
    Color? backgroundColor,
    Color? textColor,
    double? fontSize,
  }) async {
    final controller = _webViewController;
    if (controller == null) return;

    if (kDebugMode) {
      debugPrint('[Foliate] openBook: bytes.length=${bytes.length}');
    }

    final base64Data = base64Encode(bytes);
    final theme = <String, dynamic>{};
    if (backgroundColor != null) {
      theme['backgroundColor'] = _colorToCss(backgroundColor);
    }
    if (textColor != null) {
      theme['textColor'] = _colorToCss(textColor);
    }
    if (fontSize != null) {
      theme['fontSize'] = fontSize;
    }

    final options = <String, dynamic>{
      'bytesBase64': base64Data,
      'flow': flow,
      if (initialLocation != null) 'initialLocation': initialLocation,
      if (theme.isNotEmpty) 'theme': theme,
    };

    final jsonOptions = jsonEncode(options);
    // Check if the JS bridge is actually present before calling it.
    final bridgeType = await controller.evaluateJavascript(source: 'typeof window.everboundReader');
    if (kDebugMode) {
      debugPrint('[Foliate] typeof window.everboundReader => $bridgeType');
      debugPrint('[Foliate] calling window.everboundReader.openBook(...) with options: $jsonOptions');
    }
    try {
      final result = await controller.evaluateJavascript(source: 'window.everboundReader?.openBook($jsonOptions);');
      if (kDebugMode) {
        debugPrint('[Foliate] openBook JavaScript call completed, result: $result');
      }
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('[Foliate] evaluateJavascript openBook error: $e');
        debugPrint('[Foliate] Stack trace: $stackTrace');
      }
    }
  }

  Future<void> nextPage() async {
    final controller = _webViewController;
    if (controller == null) return;
    await controller.evaluateJavascript(source: 'window.everboundReader?.nextPage();');
  }

  Future<void> prevPage() async {
    final controller = _webViewController;
    if (controller == null) return;
    await controller.evaluateJavascript(source: 'window.everboundReader?.prevPage();');
  }

  Future<void> goToFraction(double fraction) async {
    final controller = _webViewController;
    if (controller == null) return;
    await controller.evaluateJavascript(source: 'window.everboundReader?.goToFraction($fraction);');
  }

  Future<void> goToLocation(Map<String, dynamic> location) async {
    final controller = _webViewController;
    if (controller == null) return;
    final jsonLocation = jsonEncode(location);
    // Wrap in void operator to ensure we return undefined immediately, not a Promise
    // The navigation will happen asynchronously, and we'll get notified via the 'relocated' event
    controller.evaluateJavascript(source: 'void window.everboundReader?.goToLocation($jsonLocation);').catchError((e) {
      // Silently handle the error - the navigation will still happen
      if (kDebugMode) {
        debugPrint('[Foliate] goToLocation error (ignored): $e');
      }
    });
  }

  Future<void> setTheme({Color? backgroundColor, Color? textColor, double? fontSize}) async {
    final controller = _webViewController;
    if (controller == null) {
      if (kDebugMode) {
        debugPrint('[Foliate] setTheme: controller is null');
      }
      return;
    }
    final theme = <String, dynamic>{};
    if (backgroundColor != null) {
      theme['backgroundColor'] = _colorToCss(backgroundColor);
    }
    if (textColor != null) {
      theme['textColor'] = _colorToCss(textColor);
    }
    if (fontSize != null) {
      theme['fontSize'] = fontSize;
    }
    if (theme.isEmpty) {
      if (kDebugMode) {
        debugPrint('[Foliate] setTheme: theme is empty, skipping');
      }
      return;
    }
    final jsonTheme = jsonEncode(theme);
    if (kDebugMode) {
      debugPrint('[Foliate] setTheme: calling window.everboundReader.setTheme with: $jsonTheme');
    }
    await controller.evaluateJavascript(source: 'window.everboundReader?.setTheme($jsonTheme);');
  }

  Future<void> setAnimationDuration(int durationMs) async {
    final controller = _webViewController;
    if (controller == null) return;
    await controller.evaluateJavascript(source: 'window.everboundReader?.setAnimationDuration($durationMs);');
  }

  Future<void> setAnimated(bool enabled) async {
    final controller = _webViewController;
    if (controller == null) return;
    await controller.evaluateJavascript(source: 'window.everboundReader?.setAnimated($enabled);');
  }

  Future<void> addAnnotation({required String value, required String type, Color? color, String? note}) async {
    final controller = _webViewController;
    if (controller == null) return;
    // Use 'style' instead of 'type' to match foliate-js format
    final annotation = <String, dynamic>{
      'style': type, // foliate-js expects 'style', not 'type'
      'value': value,
      if (color != null) 'color': _colorToCss(color),
      if (note != null) 'note': note,
    };
    final jsonAnnotation = jsonEncode(annotation);
    await controller.evaluateJavascript(source: 'window.everboundReader?.addAnnotation($jsonAnnotation);');
  }

  Future<void> removeAnnotation(String value) async {
    final controller = _webViewController;
    if (controller == null) return;
    final annotation = jsonEncode({'value': value});
    await controller.evaluateJavascript(source: 'window.everboundReader?.removeAnnotation($annotation);');
  }

  Future<void> clearSelection() async {
    final controller = _webViewController;
    if (controller == null) return;
    await controller.evaluateJavascript(source: 'window.everboundReader?.clearSelection();');
  }

  String _colorToCss(Color color) {
    return '#${color.value.toRadixString(16).padLeft(8, '0').substring(2)}';
  }
}

class FoliateWebView extends StatefulWidget {
  const FoliateWebView({
    super.key,
    required this.controller,
    required this.epubFilePath,
    this.onBookLoaded,
    this.onRelocated,
    this.onAnnotationEvent,
    this.onShowAnnotationEvent,
    this.onSelection,
    this.suppressNativeContextMenu = false,
    this.onSectionLoaded,
    this.onTocReceived,
    this.onTouchEvent,
    this.initialLocation,
    this.backgroundColor,
    this.textColor,
    this.fontSize,
    this.pageTurnAnimationDuration,
    this.enableAnimations = true,
  });

  final FoliateReaderController controller;
  final String epubFilePath;
  final VoidCallback? onBookLoaded;
  final FoliateRelocatedCallback? onRelocated;
  final FoliateAnnotationEventCallback? onAnnotationEvent;
  final FoliateShowAnnotationEventCallback? onShowAnnotationEvent;
  final FoliateSelectionEventCallback? onSelection;
  final bool suppressNativeContextMenu;
  final void Function(Map<String, dynamic>)? onSectionLoaded;
  final FoliateTouchEventCallback? onTouchEvent;
  final void Function(List<Map<String, dynamic>>)? onTocReceived;
  final Map<String, dynamic>? initialLocation;
  final Color? backgroundColor;
  final Color? textColor;
  final double? fontSize;
  final int? pageTurnAnimationDuration;
  final bool enableAnimations;

  @override
  State<FoliateWebView> createState() => _FoliateWebViewState();
}

class _FoliateWebViewState extends State<FoliateWebView> {
  // Serve foliate-js assets over a localhost HTTP server so ES module imports work on iOS.
  static final InAppLocalhostServer _localhostServer = InAppLocalhostServer(documentRoot: 'assets');
  static bool _serverStarted = false;
  static Future<void>? _serverStartFuture;

  bool _bridgeReady = false;
  bool _hasOpenedBook = false;
  InAppWebViewController? _webViewController;

  @override
  void initState() {
    super.initState();
    // Force clear cache BEFORE starting server
    InAppWebViewController.clearAllCache().then((_) {
      _serverStartFuture ??= _startServer();
    });

    // Clear WebView cache in debug mode for fresh JS files
    if (kDebugMode) {
      debugPrint('[Foliate] Cache cleared on init');
    }
  }

  @override
  void didUpdateWidget(FoliateWebView oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Check if any theme parameter changed
    final bgChanged = oldWidget.backgroundColor?.value != widget.backgroundColor?.value;
    final textChanged = oldWidget.textColor?.value != widget.textColor?.value;
    final fontChanged = oldWidget.fontSize != widget.fontSize;
    final animationsChanged = oldWidget.enableAnimations != widget.enableAnimations;

    if (kDebugMode && (bgChanged || textChanged || fontChanged || animationsChanged)) {
      debugPrint(
        '[Foliate] didUpdateWidget - bg: $bgChanged, text: $textChanged, font: $fontChanged, animations: $animationsChanged',
      );
      debugPrint(
        '[Foliate] Old: bg=${oldWidget.backgroundColor}, text=${oldWidget.textColor}, font=${oldWidget.fontSize}, animations=${oldWidget.enableAnimations}',
      );
      debugPrint(
        '[Foliate] New: bg=${widget.backgroundColor}, text=${widget.textColor}, font=${widget.fontSize}, animations=${widget.enableAnimations}',
      );
    }

    // If theme colors or font size changed AND book is open, reapply the theme
    if ((bgChanged || textChanged || fontChanged) && _hasOpenedBook) {
      if (kDebugMode) {
        debugPrint('[Foliate] Reapplying theme due to widget update');
      }
      widget.controller.setTheme(
        backgroundColor: widget.backgroundColor,
        textColor: widget.textColor,
        fontSize: widget.fontSize,
      );
    }

    // If animations setting changed AND book is open, update animations
    if (animationsChanged && _hasOpenedBook) {
      if (kDebugMode) {
        debugPrint('[Foliate] Updating animations due to widget update: ${widget.enableAnimations}');
      }
      widget.controller.setAnimated(widget.enableAnimations);
    }
  }

  /// Clear WebView cache in debug mode to ensure fresh JS files
  Future<void> _clearCacheInDebugMode() async {
    try {
      await InAppWebViewController.clearAllCache();
      if (kDebugMode) {
        debugPrint('[Foliate] Cleared WebView cache in debug mode');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[Foliate] Error clearing WebView cache: $e');
      }
    }
  }

  Future<void> _startServer() async {
    if (_serverStarted) return;
    try {
      await _localhostServer.start();
      _serverStarted = true;
      if (kDebugMode) {
        debugPrint('[Foliate] Localhost server started on port 8080');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[Foliate] Error starting localhost server: $e');
      }
      // If server is already running, that's okay
      _serverStarted = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Use theme background color for container to prevent white flash
    final webViewBackgroundColor = widget.backgroundColor ?? Colors.white;

    final initialSettings = InAppWebViewSettings(
      javaScriptEnabled: true,
      transparentBackground: true, // Make WebView transparent so Container background shows through
      mediaPlaybackRequiresUserGesture: false,
      allowsInlineMediaPlayback: true,
      isInspectable: kDebugMode,
      supportZoom: false,
      verticalScrollBarEnabled: false,
      disableLongPressContextMenuOnLinks: true,
      // Disable caching in debug mode for faster JS development iteration
      cacheEnabled: !kDebugMode,
    );

    // Wait for server to start before loading URL
    return FutureBuilder<void>(
      future: _serverStartFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          // Show loading indicator while server starts
          return const Center(child: CircularProgressIndicator());
        }

        // Add cache-busting query parameter in debug mode to ensure fresh JS files
        final baseUrl = 'http://localhost:8080/foliate/flutter_reader.html';
        final urlWithCacheBust = kDebugMode ? '$baseUrl?v=${DateTime.now().millisecondsSinceEpoch}' : baseUrl;

        // Wrap WebView in Container with theme background to prevent white flash
        return Container(
          color: webViewBackgroundColor,
          child: InAppWebView(
            // Load foliate HTML over HTTP so that ES module imports (view.js, etc.) work correctly.
            // Only load after server is ready
            initialUrlRequest: _serverStarted ? URLRequest(url: WebUri(urlWithCacheBust)) : null,
            initialSettings: initialSettings,
            contextMenu: widget.suppressNativeContextMenu
                ? ContextMenu(settings: ContextMenuSettings(hideDefaultSystemContextMenuItems: true), menuItems: [])
                : null,
            onLongPressHitTestResult: widget.suppressNativeContextMenu
                ? (controller, hitTestResult) {
                    // Prevent native context menu on long press
                    // The callback itself prevents the menu, no return value needed
                  }
                : null,
            onWebViewCreated: (controller) async {
              _webViewController = controller;

              // If server wasn't ready when webview was created, load URL now
              if (!_serverStarted && _serverStartFuture != null) {
                await _serverStartFuture;
                if (_serverStarted && mounted) {
                  // Use cache-busting in debug mode
                  final fallbackUrl = kDebugMode
                      ? 'http://localhost:8080/foliate/flutter_reader.html?v=${DateTime.now().millisecondsSinceEpoch}'
                      : 'http://localhost:8080/foliate/flutter_reader.html';
                  await controller.loadUrl(urlRequest: URLRequest(url: WebUri(fallbackUrl)));
                }
              }
              // Inject JavaScript to prevent context menu if suppression is enabled
              if (widget.suppressNativeContextMenu) {
                await controller.evaluateJavascript(
                  source: '''
            document.addEventListener('contextmenu', function(e) {
              e.preventDefault();
              e.stopPropagation();
              return false;
            });
            document.addEventListener('selectstart', function(e) {
              // Allow text selection
            });
          ''',
                );
              }
              widget.controller.attach(controller);

              controller.addJavaScriptHandler(
                handlerName: 'bookLoaded',
                callback: (data) {
                  debugPrint('[Foliate] bookLoaded handler called with data type: ${data.runtimeType}');
                  // Mark book as successfully opened when foliate-js notifies us.
                  _hasOpenedBook = true;
                  debugPrint('[Foliate] bookLoaded: marked _hasOpenedBook=true');
                  widget.onBookLoaded?.call();

                  // Set animation duration after a short delay to ensure paginator is initialized
                  if (widget.pageTurnAnimationDuration != null) {
                    Future.delayed(const Duration(milliseconds: 100), () {
                      if (kDebugMode) {
                        debugPrint('[Foliate] Setting animation duration to ${widget.pageTurnAnimationDuration}ms');
                      }
                      widget.controller.setAnimationDuration(widget.pageTurnAnimationDuration!);
                    });
                  }

                  // Set animations enabled/disabled after a short delay to ensure paginator is initialized
                  Future.delayed(const Duration(milliseconds: 100), () {
                    if (kDebugMode) {
                      debugPrint('[Foliate] Setting animations enabled: ${widget.enableAnimations}');
                    }
                    widget.controller.setAnimated(widget.enableAnimations);
                  });

                  // Pass TOC data if available
                  try {
                    if (data is List && data.isNotEmpty) {
                      if (kDebugMode) {
                        debugPrint('[Foliate] bookLoaded data is List, first element type: ${data[0].runtimeType}');
                      }
                      final dataMap = Map<String, dynamic>.from(data[0] as Map<dynamic, dynamic>);
                      if (dataMap['toc'] is List) {
                        final tocList = dataMap['toc'] as List;
                        if (kDebugMode) {
                          debugPrint('[Foliate] Found TOC with ${tocList.length} items');
                        }
                        final toc = tocList.map((item) {
                          if (item is Map) {
                            return Map<String, dynamic>.from(item as Map<dynamic, dynamic>);
                          }
                          return <String, dynamic>{};
                        }).toList();
                        if (kDebugMode) {
                          debugPrint('[Foliate] Calling onTocReceived with ${toc.length} chapters');
                        }
                        widget.onTocReceived?.call(toc);
                      }
                    }
                  } catch (e) {
                    if (kDebugMode) {
                      debugPrint('[Foliate] Error processing TOC: $e');
                    }
                  }
                  return null;
                },
              );

              controller.addJavaScriptHandler(
                handlerName: 'relocated',
                callback: (data) {
                  try {
                    if (data is Map) {
                      final detail = Map<String, dynamic>.from(data as Map<dynamic, dynamic>);
                      widget.onRelocated?.call(detail);
                    } else if (data is List && data.isNotEmpty && data.first is Map) {
                      final detail = Map<String, dynamic>.from(data.first as Map<dynamic, dynamic>);
                      widget.onRelocated?.call(detail);
                    }
                  } catch (_) {}
                  return null;
                },
              );

              controller.addJavaScriptHandler(
                handlerName: 'sectionLoaded',
                callback: (data) {
                  try {
                    if (data is Map) {
                      final detail = Map<String, dynamic>.from(data as Map<dynamic, dynamic>);
                      widget.onSectionLoaded?.call(detail);
                    } else if (data is List && data.isNotEmpty && data.first is Map) {
                      final detail = Map<String, dynamic>.from(data.first as Map<dynamic, dynamic>);
                      widget.onSectionLoaded?.call(detail);
                    }
                  } catch (_) {}
                  return null;
                },
              );

              controller.addJavaScriptHandler(
                handlerName: 'showAnnotation',
                callback: (data) {
                  print('🔔 [Foliate] showAnnotation handler called with data type: ${data.runtimeType}');
                  print('🔔 [Foliate] showAnnotation data: $data');
                  try {
                    Map<String, dynamic>? detail;
                    if (data is Map) {
                      detail = Map<String, dynamic>.from(data as Map<dynamic, dynamic>);
                      print('🔔 [Foliate] showAnnotation: parsed as Map, keys: ${detail.keys}');
                      print('🔔 [Foliate] showAnnotation: value = ${detail['value']}');
                    } else if (data is List && data.isNotEmpty && data.first is Map) {
                      detail = Map<String, dynamic>.from(data.first as Map<dynamic, dynamic>);
                      print('🔔 [Foliate] showAnnotation: parsed as List[Map], keys: ${detail.keys}');
                      print('🔔 [Foliate] showAnnotation: value = ${detail['value']}');
                    } else {
                      print('🔔 [Foliate] showAnnotation: unexpected data format: ${data.runtimeType}, data: $data');
                      return null;
                    }

                    if (detail != null) {
                      print('🔔 [Foliate] showAnnotation: calling onAnnotationEvent callback');
                      widget.onAnnotationEvent?.call(detail);
                      print('🔔 [Foliate] showAnnotation: callback completed');
                    }
                  } catch (e, stackTrace) {
                    print('❌ [Foliate] Error in showAnnotation handler: $e');
                    print('❌ [Foliate] Stack trace: $stackTrace');
                  }
                  return null;
                },
              );

              controller.addJavaScriptHandler(
                handlerName: 'jsLog',
                callback: (data) {
                  if (kDebugMode) {
                    debugPrint('[foliate-js] $data');
                  }
                  return null;
                },
              );

              controller.addJavaScriptHandler(
                handlerName: 'selection',
                callback: (data) {
                  try {
                    if (data is Map) {
                      final detail = Map<String, dynamic>.from(data as Map<dynamic, dynamic>);
                      widget.onSelection?.call(detail);
                    } else if (data is List && data.isNotEmpty && data.first is Map) {
                      final detail = Map<String, dynamic>.from(data.first as Map<dynamic, dynamic>);
                      widget.onSelection?.call(detail);
                    }
                  } catch (_) {}
                  return null;
                },
              );

              controller.addJavaScriptHandler(
                handlerName: 'bridgeReady',
                callback: (data) {
                  debugPrint('[Foliate] bridgeReady event received');
                  _bridgeReady = true;

                  // Apply theme immediately when bridge is ready (before book loads)
                  // This prevents white background flash
                  if (widget.backgroundColor != null || widget.textColor != null || widget.fontSize != null) {
                    debugPrint('[Foliate] bridgeReady: applying initial theme');
                    widget.controller.setTheme(
                      backgroundColor: widget.backgroundColor,
                      textColor: widget.textColor,
                      fontSize: widget.fontSize,
                    );
                  }

                  // Set animation duration if specified (early, before book loads)
                  if (widget.pageTurnAnimationDuration != null) {
                    debugPrint('[Foliate] Setting initial animation duration to ${widget.pageTurnAnimationDuration}ms');
                    widget.controller.setAnimationDuration(widget.pageTurnAnimationDuration!);
                  }
                  // Note: We'll set animations enabled/disabled after book loads when renderer is ready
                  if (!_hasOpenedBook) {
                    debugPrint('[Foliate] bridgeReady: opening book (hasOpenedBook=false)');
                    _openBookFromFile(widget.epubFilePath);
                  } else {
                    debugPrint('[Foliate] bridgeReady: book already opened (hasOpenedBook=true)');
                  }
                  return null;
                },
              );

              controller.addJavaScriptHandler(
                handlerName: 'touchEvent',
                callback: (data) {
                  try {
                    if (kDebugMode) {
                      debugPrint('[Foliate] touchEvent received, type: ${data.runtimeType}, data: $data');
                    }

                    Map<String, dynamic>? touchData;
                    if (data is Map) {
                      touchData = Map<String, dynamic>.from(data as Map<dynamic, dynamic>);
                    } else if (data is List && data.isNotEmpty && data.first is Map) {
                      touchData = Map<String, dynamic>.from(data.first as Map<dynamic, dynamic>);
                    }

                    if (touchData != null) {
                      if (kDebugMode) {
                        debugPrint('[Foliate] Calling onTouchEvent with: $touchData');
                        debugPrint(
                          '[Foliate] onTouchEvent callback is ${widget.onTouchEvent == null ? "NULL" : "SET"}',
                        );
                      }
                      if (widget.onTouchEvent != null) {
                        widget.onTouchEvent!(touchData);
                      } else {
                        if (kDebugMode) {
                          debugPrint('[Foliate] onTouchEvent callback is null, not calling');
                        }
                      }
                    } else {
                      if (kDebugMode) {
                        debugPrint('[Foliate] touchEvent data format not recognized');
                      }
                    }
                  } catch (e, stackTrace) {
                    if (kDebugMode) {
                      debugPrint('[Foliate] Error handling touch event: $e');
                      debugPrint('[Foliate] Stack trace: $stackTrace');
                    }
                  }
                  return null;
                },
              );
            },
            onConsoleMessage: (controller, consoleMessage) {
              // Log in both debug and profile mode for troubleshooting
              debugPrint('[Foliate] Console [${consoleMessage.messageLevel}]: ${consoleMessage.message}');
            },
            onLoadStart: (controller, url) async {
              // Apply theme as soon as page starts loading to prevent black flash
              // This runs before the HTML is fully parsed, so we set CSS variables
              if (widget.backgroundColor != null || widget.textColor != null || widget.fontSize != null) {
                try {
                  // Helper function to convert Color to CSS hex
                  String colorToCss(Color color) {
                    return '#${color.value.toRadixString(16).padLeft(8, '0').substring(2)}';
                  }

                  final bgColor = widget.backgroundColor != null ? colorToCss(widget.backgroundColor!) : '#ffffff';
                  final fgColor = widget.textColor != null ? colorToCss(widget.textColor!) : '#000000';
                  final fontSize = widget.fontSize ?? 18;

                  // Inject theme immediately via CSS variables (works even before DOM is ready)
                  // Use a retry mechanism since document might not be ready in onLoadStart
                  await controller.evaluateJavascript(
                    source:
                        '''
                    (function() {
                      const bg = '$bgColor';
                      const fg = '$fgColor';
                      const fs = ${fontSize};
                      
                      function applyTheme() {
                        // Set CSS variables
                        if (document.documentElement) {
                          document.documentElement.style.setProperty('--theme-bg', bg);
                          document.documentElement.style.setProperty('--theme-fg', fg);
                          document.documentElement.style.backgroundColor = bg;
                          document.documentElement.style.color = fg;
                          document.documentElement.style.fontSize = fs + 'px';
                        }
                        if (document.body) {
                          document.body.style.backgroundColor = bg;
                          document.body.style.color = fg;
                          document.body.style.fontSize = fs + 'px';
                        }
                        const container = document.getElementById('foliate-container');
                        if (container) {
                          container.style.backgroundColor = bg;
                        }
                        
                        // Also inject style tag for persistence
                        if (document.head && !document.getElementById('flutter-initial-theme')) {
                          const style = document.createElement('style');
                          style.id = 'flutter-initial-theme';
                          style.textContent = \`
                            :root {
                              --theme-bg: \${bg} !important;
                              --theme-fg: \${fg} !important;
                            }
                            html, body, #foliate-container {
                              background-color: \${bg} !important;
                              color: \${fg} !important;
                              font-size: \${fs}px !important;
                            }
                          \`;
                          document.head.appendChild(style);
                        }
                      }
                      
                      // Try immediately
                      applyTheme();
                      
                      // Also try when DOM is ready (if not already)
                      if (document.readyState === 'loading') {
                        document.addEventListener('DOMContentLoaded', applyTheme);
                      }
                      
                      // And try after a short delay as fallback
                      setTimeout(applyTheme, 10);
                    })();
                  ''',
                  );
                  debugPrint('[Foliate] onLoadStart: injected initial theme CSS');
                } catch (e) {
                  debugPrint('[Foliate] Error applying theme in onLoadStart: $e');
                }
              }
            },
            onLoadStop: (controller, url) async {
              debugPrint('[Foliate] onLoadStop: url=$url, hasOpenedBook=$_hasOpenedBook, bridgeReady=$_bridgeReady');

              // Apply theme as soon as HTML loads (before book opens) to prevent white flash
              if (!_bridgeReady &&
                  (widget.backgroundColor != null || widget.textColor != null || widget.fontSize != null)) {
                debugPrint('[Foliate] onLoadStop: applying initial theme before bridge ready');
                try {
                  // Helper function to convert Color to CSS hex
                  String colorToCss(Color color) {
                    return '#${color.value.toRadixString(16).padLeft(8, '0').substring(2)}';
                  }

                  // Build theme object
                  final bgColor = widget.backgroundColor != null ? colorToCss(widget.backgroundColor!) : null;
                  final fgColor = widget.textColor != null ? colorToCss(widget.textColor!) : null;
                  final fontSize = widget.fontSize;

                  // Apply theme directly to document
                  await controller.evaluateJavascript(
                    source:
                        '''
                    (function() {
                      const bg = ${bgColor != null ? "'$bgColor'" : 'null'};
                      const fg = ${fgColor != null ? "'$fgColor'" : 'null'};
                      const fs = ${fontSize != null ? fontSize : 'null'};
                      
                      if (bg) {
                        document.documentElement.style.backgroundColor = bg;
                        document.body.style.backgroundColor = bg;
                      }
                      if (fg) {
                        document.documentElement.style.color = fg;
                        document.body.style.color = fg;
                      }
                      if (fs !== null) {
                        document.documentElement.style.fontSize = fs + 'px';
                        document.body.style.fontSize = fs + 'px';
                      }
                      
                      // Also try to use bridge if available
                      if (window.everboundReader && window.everboundReader.setTheme) {
                        const theme = {};
                        if (bg) theme.backgroundColor = bg;
                        if (fg) theme.textColor = fg;
                        if (fs !== null) theme.fontSize = fs;
                        if (Object.keys(theme).length > 0) {
                          window.everboundReader.setTheme(theme);
                        }
                      }
                    })();
                  ''',
                  );
                } catch (e) {
                  debugPrint('[Foliate] Error applying theme in onLoadStop: $e');
                }
              }

              // Fallback: if for some reason the JS bridge doesn't report ready,
              // still attempt to open the book once after load stops.
              if (!_hasOpenedBook && widget.epubFilePath.isNotEmpty) {
                debugPrint('[Foliate] onLoadStop: opening book as fallback (bridgeReady=$_bridgeReady)');
                // Wait a bit for bridge to be ready if it hasn't fired yet
                if (!_bridgeReady) {
                  debugPrint('[Foliate] onLoadStop: waiting 500ms for bridge to be ready...');
                  await Future.delayed(const Duration(milliseconds: 500));
                }
                await _openBookFromFile(widget.epubFilePath);
              }

              // On iOS, check if content is rendering by inspecting the DOM (works in profile mode too)
              if (Platform.isIOS) {
                Future.delayed(const Duration(milliseconds: 2000), () async {
                  try {
                    debugPrint('[Foliate] iOS: Checking if content is rendering...');
                    final hasContent = await controller.evaluateJavascript(
                      source: '''
                    (function() {
                      const view = document.querySelector('foliate-view');
                      if (!view) return 'No foliate-view element found';
                      const shadowRoot = view.shadowRoot;
                      if (!shadowRoot) return 'No shadow root found';
                      const viewer = shadowRoot.querySelector('.viewer');
                      if (!viewer) return 'No viewer element found';
                      const hasContent = viewer.children.length > 0;
                      return 'Viewer has ' + viewer.children.length + ' children, hasContent: ' + hasContent;
                    })();
                  ''',
                    );
                    debugPrint('[Foliate] iOS content check result: $hasContent');

                    // Also check if bookLoaded event was fired
                    final bookLoadedCheck = await controller.evaluateJavascript(
                      source: 'window.everboundReader ? "everboundReader exists" : "everboundReader does not exist"',
                    );
                    debugPrint('[Foliate] iOS everboundReader check: $bookLoadedCheck');
                  } catch (e) {
                    debugPrint('[Foliate] Error checking iOS content: $e');
                  }
                });
              }
            },
            onLoadError: (controller, url, code, message) {
              debugPrint('[Foliate] Load error: $code - $message for URL: $url');
              // If connection refused, try to reload after a delay
              if (code == -6 || message.contains('ERR_CONNECTION_REFUSED')) {
                Future.delayed(const Duration(milliseconds: 500), () {
                  if (mounted && _serverStarted) {
                    controller.loadUrl(
                      urlRequest: URLRequest(url: WebUri('http://localhost:8080/foliate/flutter_reader.html')),
                    );
                  }
                });
              }
            },
          ),
        );
      },
    );
  }

  Future<void> _openBookFromFile(String path) async {
    try {
      // Resolve path if it's relative (handles iOS container ID changes and relative paths)
      String resolvedPath = path;
      if (!path.startsWith('/') && !path.startsWith('file://')) {
        // Path is relative, try to resolve it
        try {
          resolvedPath = await BookImportService.instance.resolvePath(path);
          debugPrint('[Foliate] _openBookFromFile: resolved relative path "$path" to "$resolvedPath"');
        } catch (e) {
          debugPrint('[Foliate] _openBookFromFile: failed to resolve path "$path": $e');
          // Continue with original path - might still work
        }
      }

      // Always log in profile mode too for debugging
      debugPrint('[Foliate] _openBookFromFile path=$resolvedPath exists=${File(resolvedPath).existsSync()}');
      if (widget.initialLocation != null) {
        debugPrint('[Foliate] _openBookFromFile initialLocation=${widget.initialLocation}');
      }

      final file = File(resolvedPath);
      if (!file.existsSync()) {
        debugPrint('[Foliate] ERROR: EPUB file does not exist at path: $resolvedPath (original: $path)');
        return;
      }

      final bytes = await file.readAsBytes();
      debugPrint('[Foliate] _openBookFromFile: read ${bytes.length} bytes');

      // Get theme from widget if available, otherwise use defaults
      // The theme will be applied immediately when opening the book
      debugPrint('[Foliate] _openBookFromFile: calling controller.openBook()');
      await widget.controller.openBook(
        bytes: bytes,
        initialLocation: widget.initialLocation,
        backgroundColor: widget.backgroundColor,
        textColor: widget.textColor,
        fontSize: widget.fontSize,
      );
      debugPrint('[Foliate] _openBookFromFile: controller.openBook() completed');
    } catch (e, stackTrace) {
      debugPrint('[Foliate] ERROR opening EPUB file: $e');
      debugPrint('[Foliate] Stack trace: $stackTrace');
    }
  }
}
