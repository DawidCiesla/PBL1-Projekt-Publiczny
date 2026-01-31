// models/alert.dart

import '../core/utils/date_parser.dart';

class AlertModel {
  final String id;
  final String farmId;
  final String? farmName;
  final String title;
  final String message;
  final DateTime ts;
  final bool acknowledged;
  final String? normSection; // Sekcja normy (np. "Temperatura", "Wilgotność")

  const AlertModel({
    required this.id,
    required this.farmId,
    this.farmName,
    required this.title,
    required this.message,
    required this.ts,
    required this.acknowledged,
    this.normSection,
  });

  // ---------- helpers ----------

  static bool _parseBool(dynamic v) {
    if (v == null) return false;
    if (v is bool) return v;
    if (v is num) return v != 0;

    final s = v.toString().trim().toLowerCase();
    return s == 'true' || s == '1' || s == 'yes' || s == 'y' || s == 'on';
  }

  // ---------- factory ----------

  factory AlertModel.fromJson(Map<String, dynamic> json) {
    // Graceful fallback zamiast crash - generuj UUID jeśli brak ID
    final rawId = json['id'];
    final id = (rawId?.toString().isEmpty ?? true)
        ? 'alert_${DateTime.now().millisecondsSinceEpoch}'
        : rawId.toString();

    return AlertModel(
      id: id,
      farmId: json['farm_id']?.toString() ??
          json['farmId']?.toString() ??
          '',
      farmName: json['farm_name']?.toString() ?? json['farmName']?.toString(),
      title: json['title']?.toString().trim().isNotEmpty == true
          ? json['title'].toString()
          : 'Alert',
      message: json['message']?.toString() ?? '',
      ts: DateParser.parse(json['ts'] ?? json['timestamp'] ?? json['created_at']),
      acknowledged: _parseBool(json['acknowledged']),
      normSection: json['norm_section']?.toString() ??
          json['normSection']?.toString() ??
          json['section']?.toString(),
    );
  }
}