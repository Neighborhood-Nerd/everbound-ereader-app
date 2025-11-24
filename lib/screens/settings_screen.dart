import 'package:Everbound/models/app_theme_model.dart';
import 'package:Everbound/widgets/theme_bottom_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:modal_bottom_sheet/modal_bottom_sheet.dart';
import '../providers/reader_providers.dart';
import 'koreader_sync_settings_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final readingSettings = ref.watch(readingSettingsProvider);
    final selectedTheme = AppThemes.getThemeByName(readingSettings.selectedThemeName);
    final variant = selectedTheme.getVariant(readingSettings.isDarkMode);
    return Scaffold(
      appBar: AppBar(
        title: Text('Settings', style: TextStyle(color: variant.secondaryTextColor)),
        toolbarHeight: 80,
      ),
      body: ListView(
        children: [
          // Sync Settings Section
          _buildSectionHeader('Sync'),
          ListTile(
            leading: const Icon(Icons.cloud_sync),
            title: const Text('KOReader Sync'),
            subtitle: const Text('Manage KOReader sync settings'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(MaterialPageRoute(builder: (context) => const KoreaderSyncSettingsScreen()));
            },
          ),
          _buildSectionHeader('Theme'),
          ListTile(
            leading: Icon(Icons.palette, color: variant.textColor),
            title: Text('Theme', style: TextStyle(color: variant.textColor)),
            subtitle: Text('Change the theme of the app', style: TextStyle(color: variant.textColor)),
            trailing: Icon(Icons.chevron_right, color: variant.textColor),
            onTap: () {
              showMaterialModalBottomSheet(
                context: context,
                barrierColor: Colors.transparent,
                shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                builder: (context) => ThemeBottomSheet(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey, letterSpacing: 0.5),
      ),
    );
  }
}
