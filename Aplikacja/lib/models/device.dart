// models/device.dart

import '../core/utils/date_parser.dart';

enum DeviceRole { main, module }

extension DeviceRoleX on DeviceRole {
  String get key => switch (this) {
        DeviceRole.main => 'main',
        DeviceRole.module => 'module',
      };

  /// Etykieta wyświetlana w UI
  String get label => switch (this) {
        DeviceRole.main => 'Główne',
        DeviceRole.module => 'Moduł',
      };

  static DeviceRole fromKey(String? k) {
    switch ((k ?? '').toLowerCase()) {
      case 'module':
      case 'node':  // Backend może wysyłać 'node' jako rolę
        return DeviceRole.module;
      case 'main':
      case 'główne':  // Obsługa polskiej nazwy
        return DeviceRole.main;
      default:
        return DeviceRole.main;
    }
  }
}

class DeviceModel {
  final String id;
  final String farmId;
  final String name;  // fallback name from device_id if DB entry is null
  final DeviceRole role;
  final bool online;
  final int? rssi;
  final DateTime? lastSeen;
  final String? fw;

  const DeviceModel({
    required this.id,
    required this.farmId,
    required this.name,
    required this.role,
    required this.online,
    this.rssi,
    this.lastSeen,
    this.fw,
  });

  /// Check if device is really online based on last_seen timestamp
  /// Priority: 
  /// 1. If lastSeen is available, check if it's less than 2 minutes ago
  /// 2. If lastSeen is null but API reported online=true, trust it
  /// 3. Otherwise -> offline
  bool get isOnline {
    if (lastSeen != null) {
      final now = DateTime.now();
      final diff = now.difference(lastSeen!);
      // Użyj abs() - jeśli lastSeen jest "w przyszłości" z powodu różnic w czasie,
      // traktuj to jako online (urządzenie aktywne)
      final absDiffSeconds = diff.inSeconds.abs();
      return absDiffSeconds < 120;
    }
    // Fallback to the online field from API when lastSeen is not available
    return online;
  }

  static bool _parseBool(dynamic v) {
    if (v == null) return false;
    if (v is bool) return v;
    if (v is num) return v != 0;

    final s = v.toString().trim().toLowerCase();
    return s == 'true' || s == '1' || s == 'yes' || s == 'y' || s == 'on';
  }

  factory DeviceModel.fromJson(Map<String, dynamic> json) {
    final rawId = json['id'] ?? json['device_id'];
    if (rawId == null) {
      throw Exception('DeviceModel.fromJson: brak pola "id"');
    }

    final rawFarmId = json['farm_id'] ?? json['farmId'];
    final farmId = rawFarmId?.toString() ?? '';

    // Name jest wymagane - devices z name=null są filtrowane w repository
    final rawName = json['name']?.toString().trim();
    if (rawName == null || rawName.isEmpty) {
      throw Exception('DeviceModel.fromJson: name is null (should be filtered in repository)');
    }
    
    // Ustal rolę - API nie zwraca pola 'role', więc ustalamy na podstawie nazwy
    // "Root" lub brak "Node" w nazwie = główne urządzenie
    // "Node X" = moduł
    DeviceRole role;
    if (json['role'] != null) {
      role = DeviceRoleX.fromKey(json['role']?.toString());
    } else {
      // Heurystyka: nazwa zaczyna się od "Node" → moduł
      final nameLower = rawName.toLowerCase();
      if (nameLower.startsWith('node') || nameLower.contains('moduł')) {
        role = DeviceRole.module;
      } else {
        role = DeviceRole.main;
      }
    }

    return DeviceModel(
      id: rawId.toString(),
      farmId: farmId,
      name: rawName,
      role: role,
      online: _parseBool(json['online']),
      rssi: json['rssi'] is num
          ? (json['rssi'] as num).toInt()
          : int.tryParse('${json['rssi']}'),
      lastSeen: DateParser.tryParse(json['last_seen'] ?? json['lastSeen']),
      fw: json['fw']?.toString(),
    );
  }
}