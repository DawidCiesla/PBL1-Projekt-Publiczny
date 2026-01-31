import 'package:flutter/foundation.dart' show kDebugMode;

/// Centralna konfiguracja aplikacji
/// Załadowuje wartości domyślne
class AppConfig {
  static final AppConfig _instance = AppConfig._internal();
  
  /// Singleton getter
  factory AppConfig() {
    return _instance;
  }
  
  AppConfig._internal();
  
  bool _initialized = false;
  
  // Przechowywanie wartości konfiguracyjnych
  final Map<String, dynamic> _config = {
    'api_base_url': 'https://macnuggetnet.pl/api/v1/',
    'pairing_server_url_dev': 'https://macnuggetnet.pl/api/v1/',
    'pairing_server_url_prod': 'https://macnuggetnet.pl/api/v1/',
    'api_timeout_seconds': 10,
    'ble_provisioning_timeout_seconds': 30,
    'ble_provisioning_poll_timeout_seconds': 5,
    'live_sensors_poll_interval_seconds': 15,
    'alerts_poll_interval_seconds': 30,
    'sensor_chart_max_points': 300, // Zmniejszono z 400 dla szybszego renderowania
    'sensor_chart_min_points': 80,  // Zmniejszono z 120 dla szybszego renderowania
    'enable_http_logging': kDebugMode,
    'enable_debug_info': kDebugMode,
    'enable_offline_mode': false,
  };

  /// Inicjalizuj konfigurację
  /// Powinna być wywołana w main() przed runApp()
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
  }
  
  /// Pobierz wartość z konfiguracji
  dynamic get(String key, dynamic defaultValue) {
    return _config[key] ?? defaultValue;
  }

  // ============= ENDPOINTS =============
  
  /// Główny API endpoint
  static String get apiBaseUrl {
    return _instance._config['api_base_url'] as String;
  }

  /// Serwer Wi-Fi provisioning (pairing przez BLE)
  /// Automatycznie wybiera dev/prod w zależności od kDebugMode
  static String get pairingServerUrl {
    if (kDebugMode) {
      return _instance._config['pairing_server_url_dev'] as String;
    } else {
      return _instance._config['pairing_server_url_prod'] as String;
    }
  }

  // ============= TIMEOUTS =============
  
  /// Timeout dla zwykłych API requestów
  static Duration get apiTimeout {
    final seconds = _instance._config['api_timeout_seconds'] as int;
    return Duration(seconds: seconds);
  }

  /// Timeout dla BLE provisioning pollingu
  static Duration get bleProvisioningTimeout {
    final seconds = _instance._config['ble_provisioning_timeout_seconds'] as int;
    return Duration(seconds: seconds);
  }

  /// Timeout dla BLE provisioning pollingu jednego requestu
  static Duration get bleProvisioningPollTimeout {
    final seconds = _instance._config['ble_provisioning_poll_timeout_seconds'] as int;
    return Duration(seconds: seconds);
  }

  // ============= POLLING =============
  
  /// Jak często pobieramy live data sensorów
  static Duration get liveSensorsPollInterval {
    final seconds = _instance._config['live_sensors_poll_interval_seconds'] as int;
    return Duration(seconds: seconds);
  }

  /// Jak często pobieramy listę alertów
  static Duration get alertsPollInterval {
    final seconds = _instance._config['alerts_poll_interval_seconds'] as int;
    return Duration(seconds: seconds);
  }

  // ============= CACHE & PERFORMANCE =============
  
  /// Maksimum punktów na sensor history charcie
  static int get sensorChartMaxPoints {
    return _instance._config['sensor_chart_max_points'] as int;
  }

  /// Minimalny liczba punktów do wyświetlenia
  static int get sensorChartMinPoints {
    return _instance._config['sensor_chart_min_points'] as int;
  }

  // ============= FEATURE FLAGS =============
  
  /// Czy logować HTTP requests
  static bool get enableHttpLogging {
    return _instance._config['enable_http_logging'] as bool;
  }

  /// Czy wyświetlać debug info
  static bool get enableDebugInfo {
    return _instance._config['enable_debug_info'] as bool;
  }

  /// Czy umożliwić offline mode (future feature)
  static bool get enableOfflineMode {
    return _instance._config['enable_offline_mode'] as bool;
  }
}
