import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/reader_providers.dart';
import '../providers/sync_providers.dart';
import '../services/sync_manager_service.dart';
import '../models/epub_models.dart';

class SyncConflictBottomSheet extends ConsumerWidget {
  final SyncConflictDetails conflict;
  final int bookId;
  final VoidCallback onResolveWithLocal;
  final VoidCallback onResolveWithRemote;

  const SyncConflictBottomSheet({
    super.key,
    required this.conflict,
    required this.bookId,
    required this.onResolveWithLocal,
    required this.onResolveWithRemote,
  });

  static Future<void> show(
    BuildContext context,
    SyncConflictDetails conflict,
    int bookId,
    VoidCallback onResolveWithLocal,
    VoidCallback onResolveWithRemote,
  ) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SyncConflictBottomSheet(
        conflict: conflict,
        bookId: bookId,
        onResolveWithLocal: onResolveWithLocal,
        onResolveWithRemote: onResolveWithRemote,
      ),
    );
  }

  /// Extract spine index from XPath (1-based to 0-based)
  int? _extractSpineIndexFromXPath(String? xpath) {
    if (xpath == null || !xpath.startsWith('/body/DocFragment[')) {
      return null;
    }
    final match = RegExp(r'DocFragment\[(\d+)\]').firstMatch(xpath);
    if (match != null) {
      // XPath uses 1-based indices, convert to 0-based
      return int.parse(match.group(1)!) - 1;
    }
    return null;
  }

  /// Find chapter name from XPath or percentage
  String? _findChapterName(String? xpath, double? percentage, List<EpubChapter> chapters) {
    if (chapters.isEmpty) return null;

    // Try to find chapter by spine index from XPath
    final spineIndex = _extractSpineIndexFromXPath(xpath);
    if (spineIndex != null && spineIndex >= 0 && spineIndex < chapters.length) {
      // For now, use percentage-based estimation since chapters might not map 1:1 to spine
      // But we can try to find a chapter that matches
    }

    // Use percentage to estimate chapter
    if (percentage != null && percentage > 0.0) {
      final chapterIndex = (percentage * chapters.length).floor().clamp(0, chapters.length - 1);
      return chapters[chapterIndex].title;
    }

    return null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeVariant = ref.watch(themeVariantProvider);
    final activeServerAsync = ref.watch(activeSyncServerProvider);
    final chapters = ref.watch(epubStateProvider).chapters;

    return Container(
      color: themeVariant.backgroundColor,
      padding: const EdgeInsets.all(20),
      child: activeServerAsync.when(
        data: (activeServer) {
          final deviceName = activeServer?.deviceName ?? 'server';

          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header with back button and title
              Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.chevron_left, color: themeVariant.textColor),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  Expanded(
                    child: Text(
                      'Sync Conflict',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: themeVariant.textColor),
                    ),
                  ),
                  const SizedBox(width: 48), // Balance the back button
                ],
              ),
              const SizedBox(height: 16),
              // Question text
              Text(
                'Sync reading progress from "$deviceName"?',
                style: TextStyle(fontSize: 16, color: themeVariant.textColor),
              ),
              const SizedBox(height: 24),
              // Local Progress Card
              InkWell(
                onTap: () {
                  Navigator.of(context).pop();
                  onResolveWithLocal();
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: themeVariant.cardColor.darken(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Local Progress',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: themeVariant.textColor),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${conflict.book.title} (${(conflict.localPercentage * 100).toStringAsFixed(0)}%)',
                        style: TextStyle(fontSize: 14, color: themeVariant.textColor.withValues(alpha: 0.7)),
                      ),
                      if (chapters.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Builder(
                          builder: (context) {
                            // Local has CFI, not XPath, so use percentage only
                            final chapterName = _findChapterName(
                              null, // Local doesn't have XPath
                              conflict.localPercentage,
                              chapters,
                            );
                            if (chapterName != null) {
                              return Text(
                                'Chapter: $chapterName',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: themeVariant.textColor.withValues(alpha: 0.6),
                                  fontStyle: FontStyle.italic,
                                ),
                              );
                            }
                            return const SizedBox.shrink();
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Remote Progress Card (highlighted in blue)
              InkWell(
                onTap: () {
                  Navigator.of(context).pop();
                  onResolveWithRemote();
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: themeVariant.primaryColor, borderRadius: BorderRadius.circular(12)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Remote Progress',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      const SizedBox(height: 8),
                      Text(conflict.remotePreview, style: const TextStyle(fontSize: 14, color: Colors.white)),
                      if (chapters.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Builder(
                          builder: (context) {
                            final chapterName = _findChapterName(
                              conflict.remoteProgress,
                              conflict.remotePercentage,
                              chapters,
                            );
                            if (chapterName != null) {
                              return Text(
                                'Chapter: $chapterName',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.white70,
                                  fontStyle: FontStyle.italic,
                                ),
                              );
                            }
                            return const SizedBox.shrink();
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red[300]),
            const SizedBox(height: 16),
            Text('Error loading sync information', style: TextStyle(color: Colors.red[700])),
          ],
        ),
      ),
    );
  }
}

extension on Color {
  Color darken(double d) {
    // d is the darkening factor: 0.0 = no change, 1.0 = black
    // Interpolate between original color and black
    final factor = 1.0 - d.clamp(0.0, 1.0);
    return Color.fromARGB(alpha, (red * factor).round(), (green * factor).round(), (blue * factor).round());
  }
}
