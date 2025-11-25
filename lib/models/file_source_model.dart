import 'package:sqlite3/sqlite3.dart';

/// Type of file source
enum FileSourceType {
  local,
  webdav;

  String get displayName {
    switch (this) {
      case FileSourceType.local:
        return 'Local Folder';
      case FileSourceType.webdav:
        return 'WebDAV';
    }
  }
}

/// Model for file source configuration
class FileSource {
  final int? id;
  final String name;
  final FileSourceType type;
  final String? localPath; // For local sources
  final String? bookmarkData; // Security-scoped bookmark data (iOS only, base64 encoded)
  final String? url; // For WebDAV sources
  final String? username; // For WebDAV sources
  final String? password; // For WebDAV sources (stored in plain text for now, can be encrypted later)
  final String? selectedPath; // Selected folder path for WebDAV
  final DateTime createdAt;
  final DateTime? lastScannedAt;

  FileSource({
    this.id,
    required this.name,
    required this.type,
    this.localPath,
    this.bookmarkData,
    this.url,
    this.username,
    this.password,
    this.selectedPath,
    required this.createdAt,
    this.lastScannedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'type': type.name,
      'local_path': localPath,
      'bookmark_data': bookmarkData,
      'url': url,
      'username': username,
      'password': password,
      'selected_path': selectedPath,
      'created_at': createdAt.millisecondsSinceEpoch,
      'last_scanned_at': lastScannedAt?.millisecondsSinceEpoch,
    };
  }

  factory FileSource.fromMap(Map<String, dynamic> map) {
    return FileSource(
      id: map['id'] as int?,
      name: map['name'] as String,
      type: FileSourceType.values.firstWhere(
        (e) => e.name == map['type'],
        orElse: () => FileSourceType.local,
      ),
      localPath: map['local_path'] as String?,
      bookmarkData: map['bookmark_data'] as String?,
      url: map['url'] as String?,
      username: map['username'] as String?,
      password: map['password'] as String?,
      selectedPath: map['selected_path'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      lastScannedAt: map['last_scanned_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['last_scanned_at'] as int)
          : null,
    );
  }

  factory FileSource.fromRow(Row row, List<String> columnNames) {
    int getIndex(String name) => columnNames.indexOf(name);
    return FileSource(
      id: row[getIndex('id')] as int?,
      name: row[getIndex('name')] as String,
      type: FileSourceType.values.firstWhere(
        (e) => e.name == (row[getIndex('type')] as String? ?? 'local'),
        orElse: () => FileSourceType.local,
      ),
      localPath: row[getIndex('local_path')] as String?,
      bookmarkData: row[getIndex('bookmark_data')] as String?,
      url: row[getIndex('url')] as String?,
      username: row[getIndex('username')] as String?,
      password: row[getIndex('password')] as String?,
      selectedPath: row[getIndex('selected_path')] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row[getIndex('created_at')] as int),
      lastScannedAt: row[getIndex('last_scanned_at')] != null
          ? DateTime.fromMillisecondsSinceEpoch(row[getIndex('last_scanned_at')] as int)
          : null,
    );
  }

  /// Create a copy with updated fields
  FileSource copyWith({
    int? id,
    String? name,
    FileSourceType? type,
    String? localPath,
    String? bookmarkData,
    String? url,
    String? username,
    String? password,
    String? selectedPath,
    DateTime? createdAt,
    DateTime? lastScannedAt,
  }) {
    return FileSource(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      localPath: localPath ?? this.localPath,
      bookmarkData: bookmarkData ?? this.bookmarkData,
      url: url ?? this.url,
      username: username ?? this.username,
      password: password ?? this.password,
      selectedPath: selectedPath ?? this.selectedPath,
      createdAt: createdAt ?? this.createdAt,
      lastScannedAt: lastScannedAt ?? this.lastScannedAt,
    );
  }
}













