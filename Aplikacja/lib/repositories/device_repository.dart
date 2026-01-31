import 'package:dio/dio.dart';

import '../core/api/endpoints.dart';
import '../core/utils/response_parser.dart';
import '../models/device.dart';

class DeviceRepository {
  final Dio dio;
  DeviceRepository(this.dio);

  Future<List<DeviceModel>> listDevices(String farmId) async {
    final res = await dio.get(Endpoints.devices(farmId));
    final body = res.data;

    // Use centralized helper
    final items = ResponseParser.extractList(body);

    // Sprawdź, czy items zawiera obiekty czy tylko ID
    final List<DeviceModel> result = [];

    for (final item in items) {
      if (item is Map) {
        // Pełny obiekt urządzenia
        final map = Map<String, dynamic>.from(item);
        // API zwraca device_id zamiast id
        map['id'] ??= map['device_id'];
        // Wstrzyknij farmId jeśli brak
        map['farm_id'] ??= farmId;
        
        // FILTER devices with name=null per backend docs:
        // "WARNING: if name equals NULL interpret as no device"
        // These devices only have telemetry in kurniki_dane but no entry in devices table
        final rawName = map['name'];
        if (rawName == null || rawName.toString().trim().isEmpty) {
          continue;  // Skip this device
        }
        
        final device = DeviceModel.fromJson(map);
        
        result.add(device);
      } else if (item is int || item is String) {
        // Samo ID - utwórz minimalne urządzenie
        final deviceId = item.toString();
        result.add(
          DeviceModel(
            id: deviceId,
            farmId: farmId,
            name: 'Urządzenie #$deviceId',
            role: DeviceRole.main,
            online: false, // Nieznany status
          ),
        );
      }
    }

    // main device first, then online devices, then sort by name
    // Używamy isOnline (getter obliczający status z last_seen) a nie pole online z API
    result.sort((a, b) {
      // 1. Urządzenie główne zawsze na górze
      if (a.role != b.role) {
        if (a.role == DeviceRole.main) return -1;
        if (b.role == DeviceRole.main) return 1;
      }
      // 2. Online przed offline
      if (a.isOnline != b.isOnline) return a.isOnline ? -1 : 1;
      // 3. Alfabetycznie po nazwie
      return a.name.compareTo(b.name);
    });

    return result;
  }

  Future<DeviceModel> getDevice(String deviceId) async {
    final res = await dio.get(Endpoints.device(deviceId));
    final body = res.data;

    if (body is Map) {
      return DeviceModel.fromJson(Map<String, dynamic>.from(body));
    }

    throw Exception(
      'Niepoprawny format odpowiedzi dla urządzenia: ${body.runtimeType}',
    );
  }

  Future<void> renameDevice(
    String farmId,
    String deviceId,
    String newName,
  ) async {
    await dio.patch(
      Endpoints.renameDevice(farmId, deviceId),
      data: {'name': newName},
    );
  }

  Future<void> deleteDevice(String farmId, String deviceId) async {
    final endpoint = Endpoints.deleteDevice(farmId, deviceId);
    await dio.delete(endpoint);
  }
}
