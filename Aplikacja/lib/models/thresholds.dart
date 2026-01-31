import 'sensor.dart';

class MetricLimits {
  final double? min;
  final double? max;

  const MetricLimits({
    this.min,
    this.max,
  });

  // ---------- helpers ----------

  static double? _numOrNull(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();

    final s = v.toString().trim().replaceAll(',', '.');
    return double.tryParse(s);
  }

  // ---------- factory ----------

  factory MetricLimits.fromJson(Map<String, dynamic> json) {
    return MetricLimits(
      min: _numOrNull(json['min']),
      max: _numOrNull(json['max']),
    );
  }

  Map<String, dynamic> toJson() => {
        if (min != null) 'min': min,
        if (max != null) 'max': max,
      };
}

class Thresholds {
  final String farmId;
  final Map<SensorMetric, MetricLimits> byMetric;

  const Thresholds({
    required this.farmId,
    required this.byMetric,
  });

  // ---------- defaults ----------

  factory Thresholds.defaultForFarm(String farmId) {
    return Thresholds(
      farmId: farmId,
      byMetric: const {
        SensorMetric.temperature: MetricLimits(),
        SensorMetric.humidity: MetricLimits(),
        SensorMetric.co2: MetricLimits(),
        SensorMetric.nh3: MetricLimits(),
        SensorMetric.sunlight: MetricLimits(),
      },
    );
  }

  // ---------- factory ----------

  factory Thresholds.fromJson(Map<String, dynamic> json) {
    final farmId =
        json['farm_id']?.toString() ??
        json['farmId']?.toString() ??
        '';

    final rawLimits =
        (json['limits'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};

    // startujemy od defaultów, aby mieć komplet metryk
    final base = Thresholds.defaultForFarm(farmId);
    final map = <SensorMetric, MetricLimits>{
      ...base.byMetric,
    };

    // nadpisujemy tylko to, co przyszło z backendu
    rawLimits.forEach((key, raw) {
      final metric = SensorMetricX.tryFromKey(key);
      if (metric != null && raw is Map) {
        map[metric] = MetricLimits.fromJson(
          raw.cast<String, dynamic>(),
        );
      }
    });

    return Thresholds(
      farmId: farmId,
      byMetric: map,
    );
  }

  Map<String, dynamic> toJson() => {
        for (final e in byMetric.entries)
          if (e.value.min != null || e.value.max != null)
            e.key.key: e.value.toJson(),
      };
}