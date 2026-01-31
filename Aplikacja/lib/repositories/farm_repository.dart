import 'package:dio/dio.dart';

import '../core/api/endpoints.dart';
import '../core/utils/response_parser.dart';
import '../models/farm.dart';

class FarmRepository {
  final Dio dio;
  FarmRepository(this.dio);

  Future<List<Farm>> listFarms() async {
    final res = await dio.get(Endpoints.farms);
    final body = res.data;

    // Użyj centralizowanego helpera
    final items = ResponseParser.extractList(body);

    return items.whereType<Map>().map((e) {
      try {
        return Farm.fromJson(Map<String, dynamic>.from(e));
      } catch (ex) {
        rethrow;
      }
    }).toList();
  }

  /// Aktualizuje nazwę i opis kurnika
  ///
  /// Endpoint: PATCH /api/v1/farms/{id}
  /// Body JSON: {"name": "...", "location": "...", "topic": "..."}
  Future<Farm> updateFarm(
    String farmId, {
    String? name,
    String? location,
    String? topic,
  }) async {
    final data = <String, dynamic>{};
    if (name != null) data['name'] = name;
    if (location != null) data['location'] = location;
    if (topic != null) data['topic'] = topic;

    final endpoint = Endpoints.updateFarm(farmId);
    final res = await dio.patch(endpoint, data: data);

    return Farm.fromJson(Map<String, dynamic>.from(res.data));
  }

  /// Usuwa kurnik
  ///
  /// Endpoint: DELETE /api/v1/farms/{id}
  /// Tylko właściciel lub admin może usunąć.
  Future<void> deleteFarm(String farmId) async {
    final endpoint = Endpoints.deleteFarm(farmId);
    await dio.delete(endpoint);
  }
}
