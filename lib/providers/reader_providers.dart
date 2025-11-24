import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/epub_models.dart';
import '../models/app_theme_model.dart';
import '../services/logger_service.dart';

// Selection state
const String _selectionTag = 'SelectionState';

class SelectionState {
  final Rect? selectionRect;
  final Rect? viewRect;
  final String? selectedText;
  final String? selectedCfi;
  final bool isSelectionChanging;
  final bool showAnnotationBar;
  final bool showWiktionaryPopup;
  final String? wiktionaryWord; // Word to show in Wiktionary bottom sheet

  SelectionState({
    this.selectionRect,
    this.viewRect,
    this.selectedText,
    this.selectedCfi,
    this.isSelectionChanging = false,
    this.showAnnotationBar = false,
    this.showWiktionaryPopup = false,
    this.wiktionaryWord,
  });

  SelectionState copyWith({
    Rect? Function()? selectionRect,
    Rect? Function()? viewRect,
    String? Function()? selectedText,
    String? Function()? selectedCfi,
    bool? isSelectionChanging,
    bool? showAnnotationBar,
    bool? showWiktionaryPopup,
    String? Function()? wiktionaryWord,
  }) {
    return SelectionState(
      selectionRect: selectionRect != null ? selectionRect() : this.selectionRect,
      viewRect: viewRect != null ? viewRect() : this.viewRect,
      selectedText: selectedText != null ? selectedText() : this.selectedText,
      selectedCfi: selectedCfi != null ? selectedCfi() : this.selectedCfi,
      isSelectionChanging: isSelectionChanging ?? this.isSelectionChanging,
      showAnnotationBar: showAnnotationBar ?? this.showAnnotationBar,
      showWiktionaryPopup: showWiktionaryPopup ?? this.showWiktionaryPopup,
      wiktionaryWord: wiktionaryWord != null ? wiktionaryWord() : this.wiktionaryWord,
    );
  }
}

class SelectionStateNotifier extends StateNotifier<SelectionState> {
  SelectionStateNotifier() : super(SelectionState());

  void onSelection(String selectedText, String cfiRange, Rect selectionRect, Rect viewRect) {
    logger.debug(_selectionTag, 'onSelection called - text: ${selectedText.substring(0, selectedText.length.clamp(0, 50))}...');
    logger.debug(_selectionTag, 'selectionRect: $selectionRect, viewRect: $viewRect');

    state = SelectionState(
      selectionRect: selectionRect,
      viewRect: viewRect,
      selectedText: selectedText,
      selectedCfi: cfiRange,
      isSelectionChanging: false,
      showAnnotationBar: false,
      showWiktionaryPopup: false,
    );
  }

  void onSelectionChanging() {
    logger.debug(_selectionTag, 'onSelectionChanging called - keeping overlay at current position but making it transparent');
    // Don't call setState to avoid rebuilds during dragging - state updates are handled by the notifier
    // The flag is set but won't trigger rebuilds
    if (state.showAnnotationBar) {
      state = state.copyWith(showAnnotationBar: false);
    }
    if (state.showWiktionaryPopup) {
      state = state.copyWith(showWiktionaryPopup: false);
    }
  }

  void onDeselection() {
    logger.debug(_selectionTag, 'onDeselection called - clearing overlay');
    state = SelectionState();
  }

  void clearSelection() {
    logger.debug(_selectionTag, 'Clearing selection manually');
    state = SelectionState();
  }

  void toggleAnnotationBar() {
    state = state.copyWith(showAnnotationBar: !state.showAnnotationBar);
  }

  void closeAnnotationBar() {
    state = state.copyWith(showAnnotationBar: false);
  }

  void setWiktionaryWord(String? word) {
    if (word == null) {
      // Clear wiktionary word and popup flag
      state = state.copyWith(showWiktionaryPopup: false, wiktionaryWord: () => null);
    } else {
      // Set wiktionary word and show popup
      state = state.copyWith(showWiktionaryPopup: true, wiktionaryWord: () => word);
    }
  }
}

// Annotation state (style + color)
class AnnotationState {
  final String selectedStyle; // 'highlight', 'underline', or 'squiggly'
  final Color selectedColor;
  final List<Color> colors;

  AnnotationState({this.selectedStyle = 'highlight', required this.selectedColor, required this.colors});

  AnnotationState copyWith({String? selectedStyle, Color? selectedColor, List<Color>? colors}) {
    return AnnotationState(
      selectedStyle: selectedStyle ?? this.selectedStyle,
      selectedColor: selectedColor ?? this.selectedColor,
      colors: colors ?? this.colors,
    );
  }
}

class AnnotationNotifier extends StateNotifier<AnnotationState> {
  AnnotationNotifier()
    : super(
        AnnotationState(
          selectedStyle: 'highlight',
          selectedColor: const Color(0xFFFFEB3B),
          colors: const [
            Color(0xFFEF9A9A), // Red/Coral
            Color(0xFFCE93D8), // Purple
            Color(0xFF90CAF9), // Blue
            Color(0xFFA5D6A7), // Green
            Color(0xFFFFEB3B), // Yellow
          ],
        ),
      );

  void selectStyle(String style) {
    state = state.copyWith(selectedStyle: style);
  }

  void selectColor(Color color) {
    state = state.copyWith(selectedColor: color);
  }
}

// Theme variant provider - provides the current theme variant based on reading settings
final themeVariantProvider = Provider<ThemeVariant>((ref) {
  final readingSettings = ref.watch(readingSettingsProvider);
  final selectedTheme = AppThemes.getThemeByName(readingSettings.selectedThemeName);
  return selectedTheme.getVariant(readingSettings.isDarkMode);
});

// Legacy highlight color state (kept for backward compatibility)
class HighlightColorState {
  final Color selectedColor;
  final List<Color> colors;

  HighlightColorState({required this.selectedColor, required this.colors});

  HighlightColorState copyWith({Color? selectedColor, List<Color>? colors}) {
    return HighlightColorState(selectedColor: selectedColor ?? this.selectedColor, colors: colors ?? this.colors);
  }
}

class HighlightColorNotifier extends StateNotifier<HighlightColorState> {
  HighlightColorNotifier()
    : super(
        HighlightColorState(
          selectedColor: const Color(0xFFFFEB3B),
          colors: const [
            Color(0xFFEF9A9A), // Red/Coral
            Color(0xFFCE93D8), // Purple
            Color(0xFF90CAF9), // Blue
            Color(0xFFA5D6A7), // Green
            Color(0xFFFFEB3B), // Yellow
          ],
        ),
      );

  void selectColor(Color color) {
    state = state.copyWith(selectedColor: color);
  }
}

// UI controls state
class UIControlsState {
  final bool showControls;
  final bool isBookmarked;

  UIControlsState({this.showControls = false, this.isBookmarked = false});

  UIControlsState copyWith({bool? showControls, bool? isBookmarked}) {
    return UIControlsState(
      showControls: showControls ?? this.showControls,
      isBookmarked: isBookmarked ?? this.isBookmarked,
    );
  }
}

class UIControlsNotifier extends StateNotifier<UIControlsState> {
  UIControlsNotifier() : super(UIControlsState());

  void toggleControls() {
    state = state.copyWith(showControls: !state.showControls);
  }

  void showControls() {
    state = state.copyWith(showControls: true);
  }

  void toggleBookmark() {
    state = state.copyWith(isBookmarked: !state.isBookmarked);
  }
}

// Reading settings state
class ReadingSettingsState {
  final int fontSize;
  final bool isDarkMode;
  final bool themeManuallySet;
  final bool autoOpenWiktionary;
  final String selectedThemeName;
  final bool keepMenusOpen;

  ReadingSettingsState({
    this.fontSize = 18,
    this.isDarkMode = false,
    this.themeManuallySet = false,
    this.autoOpenWiktionary = false,
    this.selectedThemeName = 'Default',
    this.keepMenusOpen = false,
  });

  ReadingSettingsState copyWith({
    int? fontSize,
    bool? isDarkMode,
    bool? themeManuallySet,
    bool? autoOpenWiktionary,
    String? selectedThemeName,
    bool? keepMenusOpen,
  }) {
    return ReadingSettingsState(
      fontSize: fontSize ?? this.fontSize,
      isDarkMode: isDarkMode ?? this.isDarkMode,
      themeManuallySet: themeManuallySet ?? this.themeManuallySet,
      autoOpenWiktionary: autoOpenWiktionary ?? this.autoOpenWiktionary,
      selectedThemeName: selectedThemeName ?? this.selectedThemeName,
      keepMenusOpen: keepMenusOpen ?? this.keepMenusOpen,
    );
  }
}

const String _tag = 'ReadingSettings';

class ReadingSettingsNotifier extends StateNotifier<ReadingSettingsState> {
  static const String _autoOpenWiktionaryKey = 'auto_open_wiktionary';
  static const String _isDarkModeKey = 'is_dark_mode';
  static const String _selectedThemeKey = 'selected_theme';
  static const String _fontSizeKey = 'font_size';
  static const String _keepMenusOpenKey = 'keep_menus_open';

  ReadingSettingsNotifier() : super(ReadingSettingsState()) {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final autoOpenWiktionary = prefs.getBool(_autoOpenWiktionaryKey) ?? false;
      final isDarkMode = prefs.getBool(_isDarkModeKey) ?? false;
      final selectedThemeName = prefs.getString(_selectedThemeKey) ?? 'Default';
      final fontSize = prefs.getInt(_fontSizeKey) ?? 18;
      final keepMenusOpen = prefs.getBool(_keepMenusOpenKey) ?? false;
      state = state.copyWith(
        autoOpenWiktionary: autoOpenWiktionary,
        isDarkMode: isDarkMode,
        selectedThemeName: selectedThemeName,
        fontSize: fontSize,
        keepMenusOpen: keepMenusOpen,
      );
      logger.info(_tag, 'Reading settings loaded - fontSize: $fontSize, isDarkMode: $isDarkMode, theme: $selectedThemeName, keepMenusOpen: $keepMenusOpen');
    } catch (e) {
      logger.error(_tag, 'Error loading reading settings', e);
    }
  }

  Future<void> setFontSize(int size) async {
    logger.info(_tag, 'User changed font size to: $size');
    state = state.copyWith(fontSize: size);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_fontSizeKey, size);
      logger.info(_tag, 'Font size saved to cache: $size');
    } catch (e) {
      logger.error(_tag, 'Error saving font size setting', e);
      // Still update state even if save fails
      state = state.copyWith(fontSize: size);
    }
  }

  Future<void> toggleDarkMode() async {
    final newDarkMode = !state.isDarkMode;
    logger.info(_tag, 'Dark mode toggled: ${newDarkMode ? "enabled" : "disabled"}');
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_isDarkModeKey, newDarkMode);
      state = state.copyWith(isDarkMode: newDarkMode, themeManuallySet: true);
    } catch (e) {
      logger.error(_tag, 'Error saving dark mode setting', e);
      // Still update state even if save fails
      state = state.copyWith(isDarkMode: newDarkMode, themeManuallySet: true);
    }
  }

  Future<void> setDarkMode(bool isDark) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_isDarkModeKey, isDark);
      state = state.copyWith(isDarkMode: isDark);
    } catch (e) {
      logger.error(_tag, 'Error saving dark mode setting', e);
      // Still update state even if save fails
      state = state.copyWith(isDarkMode: isDark);
    }
  }

  void setThemeManuallySet(bool value) {
    state = state.copyWith(themeManuallySet: value);
  }

  Future<void> setAutoOpenWiktionary(bool enabled) async {
    logger.info(_tag, 'User changed auto-open Wiktionary setting: ${enabled ? "enabled" : "disabled"}');
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_autoOpenWiktionaryKey, enabled);
      state = state.copyWith(autoOpenWiktionary: enabled);
    } catch (e) {
      logger.error(_tag, 'Error saving auto-open Wiktionary setting', e);
    }
  }

  Future<void> setSelectedTheme(String themeName) async {
    logger.info(_tag, 'Theme changed to: $themeName');
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_selectedThemeKey, themeName);
      state = state.copyWith(selectedThemeName: themeName);
    } catch (e) {
      logger.error(_tag, 'Error saving selected theme', e);
      // Still update state even if save fails
      state = state.copyWith(selectedThemeName: themeName);
    }
  }

  Future<void> setKeepMenusOpen(bool enabled) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keepMenusOpenKey, enabled);
      state = state.copyWith(keepMenusOpen: enabled);
      logger.info(_tag, 'Keep menus open setting saved: $enabled');
    } catch (e) {
      logger.error(_tag, 'Error saving keep menus open setting', e);
      // Still update state even if save fails
      state = state.copyWith(keepMenusOpen: enabled);
    }
  }
}

// EPUB state
class EpubState {
  final bool isLoading;
  final String? error;
  final List<EpubChapter> chapters;
  final EpubLocation? currentLocation;

  EpubState({this.isLoading = true, this.error, this.chapters = const [], this.currentLocation});

  EpubState copyWith({
    bool? isLoading,
    String? Function()? error,
    List<EpubChapter>? chapters,
    EpubLocation? Function()? currentLocation,
  }) {
    return EpubState(
      isLoading: isLoading ?? this.isLoading,
      error: error != null ? error() : this.error,
      chapters: chapters ?? this.chapters,
      currentLocation: currentLocation != null ? currentLocation() : this.currentLocation,
    );
  }
}

class EpubStateNotifier extends StateNotifier<EpubState> {
  EpubStateNotifier() : super(EpubState());

  void setLoading(bool loading) {
    state = state.copyWith(isLoading: loading);
  }

  void setError(String? error) {
    state = state.copyWith(isLoading: false, error: () => error);
  }

  void setChapters(List<EpubChapter> chapters) {
    state = state.copyWith(chapters: chapters);
  }

  void setCurrentLocation(EpubLocation? location) {
    state = state.copyWith(currentLocation: () => location);
  }
}

// Providers
final selectionStateProvider = StateNotifierProvider<SelectionStateNotifier, SelectionState>((ref) {
  return SelectionStateNotifier();
});

final highlightColorProvider = StateNotifierProvider<HighlightColorNotifier, HighlightColorState>((ref) {
  return HighlightColorNotifier();
});

final annotationProvider = StateNotifierProvider<AnnotationNotifier, AnnotationState>((ref) {
  return AnnotationNotifier();
});

final uiControlsProvider = StateNotifierProvider<UIControlsNotifier, UIControlsState>((ref) {
  return UIControlsNotifier();
});

final readingSettingsProvider = StateNotifierProvider<ReadingSettingsNotifier, ReadingSettingsState>((ref) {
  return ReadingSettingsNotifier();
});

final epubStateProvider = StateNotifierProvider<EpubStateNotifier, EpubState>((ref) {
  return EpubStateNotifier();
});
