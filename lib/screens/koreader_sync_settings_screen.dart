import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/reader_providers.dart';
import '../widgets/koreader_sync_settings_widget.dart';

class KoreaderSyncSettingsScreen extends ConsumerWidget {
  const KoreaderSyncSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final readingSettings = ref.watch(readingSettingsProvider);
    final themeVariant = ref.watch(themeVariantProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('KOReader Sync Settings'), backgroundColor: themeVariant.backgroundColor),
      backgroundColor: themeVariant.backgroundColor,
      body: const Padding(padding: EdgeInsets.all(20), child: KoreaderSyncSettingsWidget()),
    );
  }
}
