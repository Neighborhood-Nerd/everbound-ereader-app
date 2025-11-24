import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:screen_brightness/screen_brightness.dart';
import '../models/app_theme_model.dart';
import '../providers/reader_providers.dart';

class ThemeBottomSheet extends ConsumerStatefulWidget {
  const ThemeBottomSheet({super.key});

  @override
  ConsumerState<ThemeBottomSheet> createState() => _ThemeBottomSheetState();
}

class _ThemeBottomSheetState extends ConsumerState<ThemeBottomSheet> {
  double _brightness = 0.5; // Device brightness value (0.0 to 1.0)

  @override
  void initState() {
    super.initState();
    _loadCurrentBrightness();
  }

  Future<void> _loadCurrentBrightness() async {
    try {
      final brightness = await ScreenBrightness().current;
      if (mounted) {
        setState(() {
          _brightness = brightness;
        });
      }
    } catch (e) {
      print('Error loading brightness: $e');
    }
  }

  Future<void> _setBrightness(double value) async {
    try {
      await ScreenBrightness().setScreenBrightness(value);
      setState(() {
        _brightness = value;
      });
    } catch (e) {
      print('Error setting brightness: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final readingSettings = ref.watch(readingSettingsProvider);
    final isDark = readingSettings.isDarkMode;
    final textColor = isDark ? Colors.white : Colors.black;
    final selectedTheme = AppThemes.getThemeByName(readingSettings.selectedThemeName);
    final variant = selectedTheme.getVariant(readingSettings.isDarkMode);
    final backgroundColor = variant.cardColor;

    return Material(
      color: backgroundColor,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: Container(
        padding: const EdgeInsets.only(left: 24, right: 24, top: 16, bottom: 24),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Container(
                width: 60,
                height: 4,
                margin: const EdgeInsets.only(bottom: 24),
                decoration: BoxDecoration(color: Colors.grey[400], borderRadius: BorderRadius.circular(2)),
              ),

              // Brightness slider with circular design
              _buildBrightnessSlider(textColor, isDark, variant),

              const SizedBox(height: 32),

              // Color section
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Color',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: textColor),
                ),
              ),

              const SizedBox(height: 16),

              // Theme color buttons
              _buildThemeButtons(readingSettings, textColor),

              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBrightnessSlider(Color textColor, bool isDark, ThemeVariant variant) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        GestureDetector(
          onTap: () async {
            await ref.read(readingSettingsProvider.notifier).toggleDarkMode();
          },
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(shape: BoxShape.circle, color: variant.backgroundColor),
            child: Icon(isDark ? Icons.dark_mode : Icons.light_mode, color: textColor, size: 24),
          ),
        ),

        const SizedBox(width: 16),
        // Slider track
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 8,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 0),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 0),
              activeTrackColor: isDark ? Colors.grey[600] : Colors.grey[400],
              inactiveTrackColor: isDark ? Colors.grey[800] : Colors.grey[300],
            ),
            child: Slider(
              value: _brightness,
              min: 0.0,
              max: 1.0,
              onChanged: (value) {
                _setBrightness(value);
              },
            ),
          ),
        ),
        const SizedBox(width: 16),
        // Center circle showing brightness value (as percentage)
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(shape: BoxShape.circle, color: variant.backgroundColor),
          child: Center(
            child: Text(
              '${(_brightness * 100).round()}',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: textColor),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildThemeButtons(ReadingSettingsState readingSettings, Color textColor) {
    final isDark = readingSettings.isDarkMode;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: AppThemes.allThemes.map((theme) {
        final isSelected = theme.name == readingSettings.selectedThemeName;
        final variant = theme.getVariant(readingSettings.isDarkMode);

        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: GestureDetector(
              onTap: () async {
                // Set the theme - appThemeProvider will automatically rebuild since it watches readingSettingsProvider
                await ref.read(readingSettingsProvider.notifier).setSelectedTheme(theme.name);
              },
              child: Container(
                height: 80,
                decoration: BoxDecoration(
                  color: isSelected
                      ? (isDark ? Colors.grey[800] : Colors.grey[200])
                      : (isDark ? Colors.grey[900] : Colors.grey[100]),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected ? variant.primaryColor : (isDark ? Colors.grey[700]! : Colors.grey[300]!),
                    width: isSelected ? 2 : 1,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Color preview circle
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isDark ? variant.cardColor : variant.primaryColor,
                      ),
                      child: isSelected ? const Icon(Icons.check, size: 16, color: Colors.white) : null,
                    ),
                    const SizedBox(height: 8),
                    // Theme name
                    Text(
                      theme.name,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                        color: textColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
