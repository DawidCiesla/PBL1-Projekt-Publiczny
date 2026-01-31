enum SensorMetric {
  temperature,
  humidity,
  co2,
  nh3,
  sunlight,
}

extension SensorMetricX on SensorMetric {
  String get key => switch (this) {
        SensorMetric.temperature => 'temperature',
        SensorMetric.humidity => 'humidity',
        SensorMetric.co2 => 'co2',
        SensorMetric.nh3 => 'nh3',
        SensorMetric.sunlight => 'sunlight',
      };

  String get label => switch (this) {
        SensorMetric.temperature => 'Temperatura',
        SensorMetric.humidity => 'Wilgotność',
        SensorMetric.co2 => 'CO₂',
        SensorMetric.nh3 => 'Amoniak (NH₃)',
        SensorMetric.sunlight => 'Nasłonecznienie',
      };

  String get unit => switch (this) {
        SensorMetric.temperature => '°C',
        SensorMetric.humidity => '%',
        SensorMetric.co2 => 'ppm',
        SensorMetric.nh3 => 'ppm',
        SensorMetric.sunlight => 'lx',
      };

  /// Zwraca null gdy nieznany klucz
  static SensorMetric? tryFromKey(String? k) {
    switch ((k ?? '').toLowerCase()) {
      case 'temperature':
        return SensorMetric.temperature;
      case 'humidity':
        return SensorMetric.humidity;
      case 'co2':
        return SensorMetric.co2;
      case 'nh3':
        return SensorMetric.nh3;

      case 'sunlight':
        return SensorMetric.sunlight;
      default:
        return null;
    }
  }

  /// Zachowujemy starą sygnaturę, ale nie ukrywamy błędów:
  /// jak przyjdzie nieznany klucz, dajemy fallback jawnie.
  static SensorMetric fromKey(String? k, {SensorMetric fallback = SensorMetric.temperature}) {
    return tryFromKey(k) ?? fallback;
  }
}