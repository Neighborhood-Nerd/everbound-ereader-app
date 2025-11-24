import 'package:sqlite3/sqlite3.dart';

/// Model for KOReader sync server configuration
class SyncServer {
  final int? id;
  final String name;
  final String url;
  final String username;
  final String password; // Stored in plain text for now, can be encrypted later
  final String? deviceId; // Unique device identifier for this server
  final String? deviceName; // Display name for this device
  final DateTime createdAt;
  final bool isActive; // Whether this is the active sync server

  SyncServer({
    this.id,
    required this.name,
    required this.url,
    required this.username,
    required this.password,
    this.deviceId,
    this.deviceName,
    required this.createdAt,
    this.isActive = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'url': url,
      'username': username,
      'password': password,
      'device_id': deviceId,
      'device_name': deviceName,
      'created_at': createdAt.millisecondsSinceEpoch,
      'is_active': isActive ? 1 : 0,
    };
  }

  factory SyncServer.fromMap(Map<String, dynamic> map) {
    return SyncServer(
      id: map['id'] as int?,
      name: map['name'] as String,
      url: map['url'] as String,
      username: map['username'] as String,
      password: map['password'] as String,
      deviceId: map['device_id'] as String?,
      deviceName: map['device_name'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      isActive: (map['is_active'] as int? ?? 0) == 1,
    );
  }

  factory SyncServer.fromRow(Row row, List<String> columnNames) {
    int getIndex(String name) => columnNames.indexOf(name);
    int? getIndexOrNull(String name) {
      final idx = columnNames.indexOf(name);
      return idx >= 0 ? idx : null;
    }

    return SyncServer(
      id: row[getIndex('id')] as int?,
      name: row[getIndex('name')] as String,
      url: row[getIndex('url')] as String,
      username: row[getIndex('username')] as String,
      password: row[getIndex('password')] as String,
      deviceId: getIndexOrNull('device_id') != null
          ? row[getIndexOrNull('device_id')!] as String?
          : null,
      deviceName: getIndexOrNull('device_name') != null
          ? row[getIndexOrNull('device_name')!] as String?
          : null,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row[getIndex('created_at')] as int),
      isActive: getIndexOrNull('is_active') != null
          ? (row[getIndexOrNull('is_active')!] as int? ?? 0) == 1
          : false,
    );
  }

  /// Create a copy with updated fields
  SyncServer copyWith({
    int? id,
    String? name,
    String? url,
    String? username,
    String? password,
    String? deviceId,
    String? deviceName,
    DateTime? createdAt,
    bool? isActive,
  }) {
    return SyncServer(
      id: id ?? this.id,
      name: name ?? this.name,
      url: url ?? this.url,
      username: username ?? this.username,
      password: password ?? this.password,
      deviceId: deviceId ?? this.deviceId,
      deviceName: deviceName ?? this.deviceName,
      createdAt: createdAt ?? this.createdAt,
      isActive: isActive ?? this.isActive,
    );
  }
}

