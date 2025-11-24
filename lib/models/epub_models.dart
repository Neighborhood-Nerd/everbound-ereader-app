import 'package:flutter/material.dart';

/// Minimal copy of the EPUB-related models used previously from flutter_epub_viewer.
/// These are kept to avoid a large refactor and to preserve existing app logic.

class EpubChapter {
  final String title;
  final String href;
  final String id;
  final List<EpubChapter> subitems;
  final Map<String, int>? location; // {current: int, next: int, total: int} for page numbers

  EpubChapter({required this.title, required this.href, required this.id, required this.subitems, this.location});

  factory EpubChapter.fromJson(Map<String, dynamic> json) {
    Map<String, int>? location;
    if (json['location'] != null) {
      final loc = json['location'] as Map<String, dynamic>;
      location = {
        'current': (loc['current'] as num?)?.toInt() ?? 0,
        'next': (loc['next'] as num?)?.toInt() ?? 0,
        'total': (loc['total'] as num?)?.toInt() ?? 0,
      };
    }
    return EpubChapter(
      title: json['title']?.toString() ?? '',
      href: json['href']?.toString() ?? '',
      id: json['id']?.toString() ?? '',
      subitems: (json['subitems'] as List<dynamic>? ?? [])
          .map((e) => EpubChapter.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      location: location,
    );
  }

  Map<String, dynamic> toJson() => {
    'title': title,
    'href': href,
    'id': id,
    'subitems': subitems.map((e) => e.toJson()).toList(),
    if (location != null) 'location': location,
  };
}

class EpubLocation {
  String startCfi;
  String endCfi;
  String? startXpath;
  String? endXpath;
  double progress;

  EpubLocation({required this.startCfi, required this.endCfi, this.startXpath, this.endXpath, required this.progress});

  factory EpubLocation.fromJson(Map<String, dynamic> json) {
    return EpubLocation(
      startCfi: json['startCfi']?.toString() ?? '',
      endCfi: json['endCfi']?.toString() ?? '',
      startXpath: json['startXpath']?.toString(),
      endXpath: json['endXpath']?.toString(),
      progress: (json['progress'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() => {
    'startCfi': startCfi,
    'endCfi': endCfi,
    'startXpath': startXpath,
    'endXpath': endXpath,
    'progress': progress,
  };
}

enum EpubSpread { none, always, auto }

enum EpubFlow { paginated, scrolled }

enum EpubDefaultDirection { ltr, rtl }

enum EpubManager { continuous }

class EpubTheme {
  final Decoration? backgroundDecoration;
  final Color? foregroundColor;

  EpubTheme({this.backgroundDecoration, this.foregroundColor});

  factory EpubTheme.custom({required Decoration backgroundDecoration, required Color foregroundColor}) {
    return EpubTheme(backgroundDecoration: backgroundDecoration, foregroundColor: foregroundColor);
  }
}

class EpubDisplaySettings {
  int fontSize;
  EpubSpread spread;
  EpubFlow flow;
  EpubDefaultDirection defaultDirection;
  bool allowScriptedContent;
  EpubManager manager;
  bool snap;
  final bool useSnapAnimationAndroid;
  final EpubTheme? theme;
  final Color? backgroundColor;
  final Color? textColor;

  EpubDisplaySettings({
    this.fontSize = 15,
    this.spread = EpubSpread.auto,
    this.flow = EpubFlow.paginated,
    this.allowScriptedContent = false,
    this.defaultDirection = EpubDefaultDirection.ltr,
    this.snap = true,
    this.useSnapAnimationAndroid = false,
    this.manager = EpubManager.continuous,
    this.theme,
    this.backgroundColor,
    this.textColor,
  });
}
