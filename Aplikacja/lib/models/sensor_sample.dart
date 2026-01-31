import '../core/utils/date_parser.dart';

class SensorSample {
  final DateTime ts;
  final double value;

  const SensorSample({
    required this.ts,
    required this.value,
  });

  factory SensorSample.fromJson(Map<String, dynamic> json) {
    final rawTs = json['ts'] ?? json['timestamp'] ?? json['created_at'];
    final parsedTs = DateParser.parse(rawTs, fallback: DateTime.now());

    final rawValue = json['value'];
    double parsedValue;

    if (rawValue is num) {
      parsedValue = rawValue.toDouble();
    } else {
      final s = (rawValue?.toString() ?? '').replaceAll(',', '.');
      parsedValue = double.tryParse(s) ?? 0.0;
    }

    return SensorSample(ts: parsedTs, value: parsedValue);
  }
}