import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/book_model.dart';
import '../models/app_theme_model.dart';
import 'my_books_providers.dart';
import 'reader_providers.dart';

// Reading progress books - books with progress > 0 (any book that has been viewed at least once)
final readingProgressBooksProvider = Provider<List<BookModel>>((ref) {
  final booksAsync = ref.watch(myBooksProvider);
  return booksAsync.when(
    data: (books) => books.where((book) => (book.progressPercentage ?? 0.0) > 0.0).toList(),
    loading: () => [],
    error: (_, __) => [],
  );
});

// Reader choice books - all books
final readerChoiceBooksProvider = Provider<List<BookModel>>((ref) {
  final booksAsync = ref.watch(myBooksProvider);
  return booksAsync.when(data: (books) => books, loading: () => [], error: (_, __) => []);
});

// Recommended books - empty for now
final recommendedBooksProvider = Provider<List<BookModel>>((ref) {
  return [];
});

final selectedCategoryProvider = StateProvider<String>((ref) => 'Reader Choice');

final userNameProvider = Provider<String>((ref) => 'James Walter');

// Volume key setting state
class VolumeKeySettingState {
  final bool enabled;

  VolumeKeySettingState({required this.enabled});
}

class VolumeKeySettingNotifier extends StateNotifier<VolumeKeySettingState> {
  static const String _prefsKey = 'volume_keys_enabled';

  VolumeKeySettingNotifier() : super(VolumeKeySettingState(enabled: true)) {
    _loadSetting();
  }

  Future<void> _loadSetting() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool(_prefsKey) ?? true; // Default to true
      state = VolumeKeySettingState(enabled: enabled);
    } catch (e) {
      print('Error loading volume key setting: $e');
      // Keep default value (true)
    }
  }

  Future<void> setEnabled(bool enabled) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsKey, enabled);
      state = VolumeKeySettingState(enabled: enabled);
    } catch (e) {
      print('Error saving volume key setting: $e');
    }
  }

  Future<void> toggle() async {
    await setEnabled(!state.enabled);
  }
}

final volumeKeySettingProvider = StateNotifierProvider<VolumeKeySettingNotifier, VolumeKeySettingState>((ref) {
  return VolumeKeySettingNotifier();
});

// Keep screen awake setting state
class KeepScreenAwakeSettingState {
  final bool enabled;

  KeepScreenAwakeSettingState({required this.enabled});
}

class KeepScreenAwakeSettingNotifier extends StateNotifier<KeepScreenAwakeSettingState> {
  static const String _prefsKey = 'keep_screen_awake_enabled';

  KeepScreenAwakeSettingNotifier() : super(KeepScreenAwakeSettingState(enabled: false)) {
    _loadSetting();
  }

  Future<void> _loadSetting() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool(_prefsKey) ?? false; // Default to false
      state = KeepScreenAwakeSettingState(enabled: enabled);
    } catch (e) {
      print('Error loading keep screen awake setting: $e');
      // Keep default value (false)
    }
  }

  Future<void> setEnabled(bool enabled) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsKey, enabled);
      state = KeepScreenAwakeSettingState(enabled: enabled);
    } catch (e) {
      print('Error saving keep screen awake setting: $e');
    }
  }

  Future<void> toggle() async {
    await setEnabled(!state.enabled);
  }
}

final keepScreenAwakeSettingProvider =
    StateNotifierProvider<KeepScreenAwakeSettingNotifier, KeepScreenAwakeSettingState>((ref) {
      return KeepScreenAwakeSettingNotifier();
    });

// App theme provider - generates MaterialApp ThemeData based on selected theme and dark mode
final appThemeProvider = Provider<ThemeData>((ref) {
  final readingSettings = ref.watch(readingSettingsProvider);
  final selectedTheme = AppThemes.getThemeByName(readingSettings.selectedThemeName);
  final variant = selectedTheme.getVariant(readingSettings.isDarkMode);

  return ThemeData(
    useMaterial3: true,
    brightness: readingSettings.isDarkMode ? Brightness.dark : Brightness.light,
    primaryColor: variant.primaryColor,
    scaffoldBackgroundColor: variant.backgroundColor,
    cardColor: variant.cardColor,
    colorScheme: ColorScheme(
      brightness: readingSettings.isDarkMode ? Brightness.dark : Brightness.light,
      primary: variant.primaryColor,
      onPrimary: readingSettings.isDarkMode ? Colors.black : Colors.white,
      secondary: variant.secondaryColor,
      onSecondary: readingSettings.isDarkMode ? Colors.black : Colors.white,
      error: Colors.red,
      onError: Colors.white,
      surface: variant.surfaceColor,
      onSurface: variant.textColor,
    ),
    iconTheme: IconThemeData(color: variant.iconColor),
    textTheme: TextTheme(
      bodyLarge: TextStyle(color: variant.textColor),
      bodyMedium: TextStyle(color: variant.textColor),
      bodySmall: TextStyle(color: variant.textColor),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: variant.primaryColor,
      selectionColor: variant.primaryColor.withOpacity(0.2),
      selectionHandleColor: variant.primaryColor,
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: variant.primaryColor,
      inactiveTrackColor: readingSettings.isDarkMode ? Colors.grey[800] : Colors.grey[200],
      thumbColor: Colors.white,
      overlayColor: variant.primaryColor.withOpacity(0.2),
      valueIndicatorColor: variant.primaryColor,
      valueIndicatorTextStyle: const TextStyle(color: Colors.white),
    ),
    switchTheme: SwitchThemeData(
      trackColor: WidgetStateProperty.resolveWith<Color>((states) {
        if (states.contains(WidgetState.selected)) {
          return variant.primaryColor;
        }
        return readingSettings.isDarkMode ? Colors.grey[850]! : Colors.grey[200]!;
      }),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      thumbColor: WidgetStateProperty.all(Colors.white),
      overlayColor: WidgetStateProperty.all(variant.primaryColor.withValues(alpha: 0.2)),
    ),
  );
});
