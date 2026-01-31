import '../core/utils/date_parser.dart';

class ChickenEvent {
  final int? id; // Opcjonalne - może nie być w odpowiedzi z API
  final String idKury; // Zmienione z int na String - ID kury może być alfanumeryczne (np. F74...)
  final String? kurnikId; // Opcjonalne - może nie być w odpowiedzi z API
  final int? deviceId;
  final int tryb; // 1 = w kurniku, 0 = na zewnątrz
  final double waga;
  final DateTime eventTime;
  final String? payloadRaw;
  final DateTime createdAt;

  const ChickenEvent({
    this.id,
    required this.idKury,
    this.kurnikId,
    this.deviceId,
    required this.tryb,
    required this.waga,
    required this.eventTime,
    this.payloadRaw,
    required this.createdAt,
  });

  factory ChickenEvent.fromJson(Map<String, dynamic> json) {
    // Graceful parsing z fallbacks
    // ID kury może być alfanumeryczne (np. F74...), więc używamy String
    final rawIdKury = json['id_kury'];
    final idKury = rawIdKury?.toString() ?? '';

    final rawTryb = json['tryb_kury'];
    final tryb = rawTryb is int 
        ? rawTryb 
        : int.tryParse(rawTryb?.toString() ?? '') ?? 0;

    final rawWaga = json['waga'];
    final waga = rawWaga is num 
        ? rawWaga.toDouble() 
        : double.tryParse(rawWaga?.toString() ?? '') ?? 0.0;

    return ChickenEvent(
      id: json['id'] as int?,
      idKury: idKury,
      kurnikId: json['kurnik'] as String?,
      deviceId: json['device_id'] as int?,
      tryb: tryb,
      waga: waga,
      eventTime: DateParser.parse(json['event_time'], fallback: DateTime.now()),
      payloadRaw: json['payload_raw'] as String?,
      createdAt: DateParser.parse(json['created_at'], fallback: DateTime.now()),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'id_kury': idKury,
      'kurnik': kurnikId,
      'device_id': deviceId,
      'tryb_kury': tryb,
      'waga': waga,
      'event_time': eventTime.toIso8601String(),
      'payload_raw': payloadRaw,
      'created_at': createdAt.toIso8601String(),
    };
  }

  String get trybText => tryb == 1 ? 'W kurniku' : 'Na zewnątrz';
  String get wagaText => '${waga.toStringAsFixed(2)} kg';
}
