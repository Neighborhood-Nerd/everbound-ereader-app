import 'package:flutter/material.dart';

/// Represents a color variant (light or dark) of a theme
class ThemeVariant {
  final Color backgroundColor;
  final Color readerBackgroundColor;
  final Color textColor;
  final Color secondaryTextColor;
  final Color iconColor;
  final Color primaryColor;
  final Color secondaryColor;
  final Color surfaceColor;
  final Color cardColor;

  const ThemeVariant({
    required this.backgroundColor,
    required this.readerBackgroundColor,
    required this.textColor,
    required this.secondaryTextColor,
    required this.iconColor,
    required this.primaryColor,
    required this.secondaryColor,
    required this.surfaceColor,
    required this.cardColor,
  });

  bool get isDark => backgroundColor.computeLuminance() < 0.5;
}

/// Represents a complete theme with both light and dark variants
class AppTheme {
  final String name;
  final ThemeVariant lightVariant;
  final ThemeVariant darkVariant;

  const AppTheme({required this.name, required this.lightVariant, required this.darkVariant});

  /// Get the appropriate variant based on dark mode
  ThemeVariant getVariant(bool isDark) => isDark ? darkVariant : lightVariant;
}

//backgroundColor - main background color
//readerBackgroundColor - only for reader screen background color
//cardColor - bottom/top navigation bar, reader settings, etc.

/// Predefined app themes
class AppThemes {
  // Default theme (Paper White)
  static const AppTheme paperWhite = AppTheme(
    name: 'Default',
    lightVariant: ThemeVariant(
      backgroundColor: Color(0xFFF5F5F5),
      readerBackgroundColor: Color(0xFFeeeded),
      textColor: Color(0xFF000000),
      secondaryTextColor: Color(0xFF000000),
      iconColor: Color(0xFF49454f),
      primaryColor: Color(0xFF26a9e4),
      secondaryColor: Color(0xFF1976D2),
      surfaceColor: Color(0xFFFFFFFF),
      cardColor: Color(0xFFFFFFFF),
    ),
    darkVariant: ThemeVariant(
      backgroundColor: Color.fromARGB(255, 51, 51, 51),
      readerBackgroundColor: Color.fromARGB(255, 34, 34, 34),
      textColor: Color(0xFFc6c6c6),
      secondaryTextColor: Color(0xFFc6c6c6),
      iconColor: Color(0xFFc6c6c6),
      primaryColor: Color.fromARGB(255, 18, 135, 189),
      secondaryColor: Color(0xFF42A5F5),
      surfaceColor: Color(0xFF2C2C2C),
      cardColor: Color(0xFF3C3C3C),
    ),
  );

  //Grass theme
  static const AppTheme grass = AppTheme(
    name: 'Grass',
    lightVariant: ThemeVariant(
      backgroundColor: Color(0xFFD8DBBC),
      readerBackgroundColor: Color(0xFFD8DBBC),
      textColor: Color(0xFF2E3440),
      secondaryTextColor: Color(0xFF2E3440),
      iconColor: Color(0xFF4C566A),
      primaryColor: Color(0xFF5E6C42),
      secondaryColor: Color(0xFF81A1C1),
      surfaceColor: Color(0xFFBFC595),
      cardColor: Color(0xFFCFD2AD),
    ),
    darkVariant: ThemeVariant(
      backgroundColor: Color(0xFF333627),
      readerBackgroundColor: Color(0xFF333627),
      textColor: Color(0xFFD9DEBA),
      secondaryTextColor: Color(0xFFD9DEBA),
      iconColor: Color(0xFFD8DEE9),
      primaryColor: Color(0xFFD9DEBA),
      secondaryColor: Color(0xFF81A1C1),
      surfaceColor: Color(0xFF555941),
      cardColor: Color(0xFF414431),
    ),
  );

  // Nord theme
  static const AppTheme nord = AppTheme(
    name: 'Nord',
    lightVariant: ThemeVariant(
      backgroundColor: Color(0xFFECEFF4), // Nord Snow Storm
      readerBackgroundColor: Color.fromARGB(255, 185, 204, 208), // Nord Snow Storm
      textColor: Color(0xFF2E3440), // Nord Polar Night
      secondaryTextColor: Color.fromARGB(255, 204, 221, 222),
      iconColor: Color(0xFF4C566A),
      primaryColor: Color(0xFF88C0D0), // Nord Frost
      secondaryColor: Color(0xFF81A1C1),
      surfaceColor: Color(0xFF5E81AC),
      cardColor: Color(0xFF5e81ac),
    ),
    darkVariant: ThemeVariant(
      backgroundColor: Color(0xFF2E3440), // Nord Polar Night
      readerBackgroundColor: Color(0xFF3B4252), // Nord Polar Night
      textColor: Color(0xFFECEFF4), // Nord Snow Storm
      secondaryTextColor: Color(0xFFECEFF4),
      iconColor: Color(0xFFD8DEE9),
      primaryColor: Color(0xFF88C0D0), // Nord Frost
      secondaryColor: Color(0xFF81A1C1),
      surfaceColor: Color(0xFF3B4252),
      cardColor: Color(0xFF434C5E),
    ),
  );

  // Contrast theme (high contrast for accessibility)
  static const AppTheme contrast = AppTheme(
    name: 'Contrast',
    lightVariant: ThemeVariant(
      backgroundColor: Color(0xFFFFFFFF),
      readerBackgroundColor: Color(0xFFf5f5f5),
      textColor: Color(0xFF000000),
      secondaryTextColor: Color(0xFF000000),
      iconColor: Color(0xFF000000),
      primaryColor: Color(0xFF0066CC),
      secondaryColor: Color(0xFF0052A3),
      surfaceColor: Color(0xFFF5F5F5),
      cardColor: Color(0xFFFFFFFF),
    ),
    darkVariant: ThemeVariant(
      backgroundColor: Color(0xFF000000),
      readerBackgroundColor: Colors.black,
      textColor: Color(0xFFFFFFFF),
      secondaryTextColor: Color(0xFF000000),
      iconColor: Color(0xFFFFFFFF),
      primaryColor: Color(0xFF66B3FF),
      secondaryColor: Color(0xFF3399FF),
      surfaceColor: Color(0xFF1A1A1A),
      cardColor: Color(0xFF2A2A2A),
    ),
  );

  // Gruvbox theme (retro groove warm colors)
  static const AppTheme gruvbox = AppTheme(
    name: 'Gruvbox',
    lightVariant: ThemeVariant(
      backgroundColor: Color(0xFFFBF1C7), // Light bg
      readerBackgroundColor: Color(0xFFFBF1C7), // Light bg
      textColor: Color(0xFF3C3836), // Dark text
      secondaryTextColor: Color(0xFF3C3836),
      iconColor: Color(0xFF928374), // Gray
      primaryColor: Color(0xFFD65D0E), // Orange
      secondaryColor: Color(0xFFB57614), // Brown
      surfaceColor: Color(0xFFF2E5BC), // Light gray
      cardColor: Color(0xFFEBDBB2), // Lighter gray
    ),
    darkVariant: ThemeVariant(
      backgroundColor: Color(0xFF282828), // Dark bg
      readerBackgroundColor: Color(0xFF282828), // Dark bg
      textColor: Color(0xFFEBDBB2), // Light text
      secondaryTextColor: Color(0xFFEBDBB2),
      iconColor: Color(0xFFBDAE93), // Gray
      primaryColor: Color(0xFFFE8019), // Bright orange
      secondaryColor: Color(0xFFD65D0E), // Orange
      surfaceColor: Color(0xFF3C3836), // Dark gray
      cardColor: Color(0xFF504945), // Lighter dark gray
    ),
  );

  // Tokyo Night theme (Japanese-inspired cool colors)
  static const AppTheme tokyoNight = AppTheme(
    name: 'Tokyo',
    lightVariant: ThemeVariant(
      backgroundColor: Color(0xFFE1E2E7), // Light lavender
      readerBackgroundColor: Color(0xFFd1d5e2), // Light lavender
      textColor: Color(0xFF6471ab), // Dark navy
      secondaryTextColor: Color(0xFFd1d5e2),
      iconColor: Color(0xFFd1d5e2), // Medium navy
      primaryColor: Color(0xFF7AA2F7), // Bright blue
      secondaryColor: Color(0xFF9ECE6A), // Green
      surfaceColor: Color(0xFF6172B0), // Light blue
      cardColor: Color(0xFF6172B0), // Light purple
    ),
    darkVariant: ThemeVariant(
      backgroundColor: Color.fromARGB(255, 52, 54, 74), // Dark navy
      readerBackgroundColor: Color(0xFF1A1B26), // Dark navy
      textColor: Color(0xFFC0CAF5), // Light lavender
      secondaryTextColor: Color(0xFFC0CAF5),
      iconColor: Color(0xFF7AA2F7), // Blue
      primaryColor: Color(0xFF7AA2F7), // Bright blue
      secondaryColor: Color(0xFFBB9AF7), // Purple
      surfaceColor: Color(0xFF3B4261), // Medium navy
      cardColor: Color(0xFF414868), // Darker navy
    ),
  );

  /// List of all available themes
  static const List<AppTheme> allThemes = [paperWhite, nord, gruvbox, tokyoNight, grass];

  /// Get a theme by name
  static AppTheme getThemeByName(String name) {
    return allThemes.firstWhere((theme) => theme.name == name, orElse: () => paperWhite);
  }
}
