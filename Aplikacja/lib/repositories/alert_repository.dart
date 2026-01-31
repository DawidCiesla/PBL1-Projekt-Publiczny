import 'package:dio/dio.dart';

import '../core/api/endpoints.dart';
import '../core/utils/response_parser.dart';
import '../models/alert.dart';

class AlertRepository {
  final Dio dio;
  AlertRepository(this.dio);

  /// ✅ Alerty dla konkretnego kurnika (farmy)
  Future<List<AlertModel>> listAlerts(String farmId) async {
    final res = await dio.get(Endpoints.alerts(farmId));
    final body = res.data;

    // ✅ Użyj centralizowanego helpera
    final items = ResponseParser.extractList(body);

    return items
        .whereType<Map>()
        .map((e) => AlertModel.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<void> acknowledgeAlert(String alertId) async {
    await dio.post(Endpoints.ackAlert(alertId));
  }
}