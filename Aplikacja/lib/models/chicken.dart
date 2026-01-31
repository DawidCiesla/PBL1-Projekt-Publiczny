class Chicken {
  final String id; // Zmienione z int na String - ID może być alfanumeryczne (np. F74...)
  final String kurnikId;
  final String? name;
  final int? deviceId;
  final int? lastMode; // 1 = w kurniku, 0 = na zewnątrz
  final double? lastWeight;
  final DateTime? lastEventTime;
  final int eventCount;

  const Chicken({
    required this.id,
    required this.kurnikId,
    this.name,
    this.deviceId,
    this.lastMode,
    this.lastWeight,
    this.lastEventTime,
    this.eventCount = 0,
  });

  factory Chicken.fromJson(Map<String, dynamic> json, {String? farmId}) {
    // Graceful parsing - API może zwracać int lub String
    // ID kury może być alfanumeryczne (np. F74...), więc używamy String
    final rawId = json['id_kury'];
    final id = rawId?.toString() ?? '';

    final rawDeviceId = json['device_id'];
    final deviceId = rawDeviceId is int 
        ? rawDeviceId 
        : int.tryParse(rawDeviceId?.toString() ?? '');

    final rawLastMode = json['tryb_kury'];
    final lastMode = rawLastMode is int 
        ? rawLastMode 
        : int.tryParse(rawLastMode?.toString() ?? '');

    final rawWeight = json['waga'];
    final lastWeight = rawWeight is num 
        ? rawWeight.toDouble() 
        : double.tryParse(rawWeight?.toString() ?? '');

    final rawEventCount = json['event_count'];
    final eventCount = rawEventCount is int 
        ? rawEventCount 
        : int.tryParse(rawEventCount?.toString() ?? '') ?? 0;

    DateTime? lastEventTime;
    if (json['event_time'] != null) {
      try {
        lastEventTime = DateTime.parse(json['event_time'].toString());
      } catch (_) {
        lastEventTime = null;
      }
    }

    return Chicken(
      id: id,
      kurnikId: json['kurnik']?.toString() ?? farmId ?? '',
      name: json['name']?.toString(),
      deviceId: deviceId,
      lastMode: lastMode,
      lastWeight: lastWeight,
      lastEventTime: lastEventTime,
      eventCount: eventCount,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id_kury': id,
      'kurnik': kurnikId,
      'name': name,
      'device_id': deviceId,
      'tryb_kury': lastMode,
      'waga': lastWeight,
      'event_time': lastEventTime?.toIso8601String(),
      'event_count': eventCount,
    };
  }

  String get modeText => lastMode == 1 ? 'W kurniku' : lastMode == 0 ? 'Na zewnątrz' : 'Nieznany';
  String get weightText => lastWeight != null ? '${lastWeight!.toStringAsFixed(2)} kg' : '—';
  String get displayName => (name != null && name!.trim().isNotEmpty) ? name!.trim() : 'Kura #$id';
}
