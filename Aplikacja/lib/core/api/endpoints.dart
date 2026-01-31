import '../config/app_config.dart';

class Endpoints {
  // ✅ Główny API endpoint - z AppConfig
  static String get baseUrl => AppConfig.apiBaseUrl;

  // Auth
  static const login = 'auth/login';
  static const register = 'auth/register';
  static const me = 'auth/me';
  static const refresh = 'auth/refresh';

  // Farms
  static const farms = 'farms';
  static String farm(String id) => 'farms/$id';

  // Coops (kurniki) - PATCH/DELETE farms/{id}
  static String updateFarm(String id) => 'farms/$id';
  static String deleteFarm(String id) => 'farms/$id';

  // Devices
  static String devices(String farmId) => 'farms/$farmId/devices';
  static String pairDevice(String farmId) => 'farms/$farmId/pair';
  static String device(String deviceId) => 'devices/$deviceId';
  static String renameDevice(String farmId, String deviceId) =>
      'farms/$farmId/devices/$deviceId';
  static String deleteDevice(String farmId, String deviceId) =>
      'farms/$farmId/devices/$deviceId';

  // Sensors
  static String live(String farmId) => 'farms/$farmId/live';
  static String history(String farmId) => 'farms/$farmId/history';
  static String wsLive(String farmId) => 'ws/farms/$farmId/live';

  // ✅ Alerts (PER FARM)
  static String alerts(String farmId) => 'farms/$farmId/alerts';
  static String ackAlert(String alertId) => 'alerts/$alertId/ack';

  // Limits (normy)
  static String farmLimits(String farmId) => 'farms/$farmId/limits';
  static String coopLimits(String farmId) => 'coops/$farmId/limits';

  // Deprecated alias – zostawiamy na wypadek starych wywołań
  static String thresholds(String farmId) => farmLimits(farmId);

  // Chickens (kury) - używamy zwykłe ID kurnika (farm.id) nie topic_id
  // ID kury może być alfanumeryczne (np. F74...), więc używamy String
  static String chickens(String farmId) => 'farms/$farmId/kury';
  static String chicken(String farmId, String chickenId) =>
      'farms/$farmId/kury/$chickenId';
  static String chickenEvents(String farmId, String chickenId) =>
      'farms/$farmId/kury/$chickenId'; // 🔧 Może zwraca bezpośrednio tablicę zdarzeń
  static String chickenName(String farmId, String chickenId) =>
      'farms/$farmId/kury/$chickenId/name';

  // ✅ Pair status (provisioning) - CONFIGURABLE z AppConfig
  static String get pairStatusBaseUrl => AppConfig.pairingServerUrl;
  static const pairStatus = 'pair/status';

  static Uri wsUri(String path, {Map<String, String>? query}) {
    final base = Uri.parse(baseUrl);
    final resolved = base.resolve(path);
    final wsScheme = base.scheme == 'https' ? 'wss' : 'ws';
    return resolved.replace(scheme: wsScheme, queryParameters: query);
  }
}
