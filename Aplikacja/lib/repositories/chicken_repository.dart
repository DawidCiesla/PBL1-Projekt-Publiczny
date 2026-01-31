import 'package:dio/dio.dart';

import '../core/api/endpoints.dart';
import '../core/utils/response_parser.dart';
import '../models/chicken.dart';
import '../models/chicken_event.dart';

class ChickenEventsResult {
  final String? name;
  final List<ChickenEvent> events;

  const ChickenEventsResult({this.name, required this.events});
}

class ChickenRepository {
  final Dio dio;

  ChickenRepository(this.dio);

  /// Pobiera listę wszystkich kur dla danego kurnika
  /// GET /api/v1/farms/{farm_id}/kury
  Future<List<Chicken>> listChickens(String farmId) async {
    final endpoint = Endpoints.chickens(farmId);
    final res = await dio.get(endpoint);
    final body = res.data;

    final items = ResponseParser.extractList(body);

    final chickens = items.whereType<Map>().map((e) {
      final chicken = Chicken.fromJson(Map<String, dynamic>.from(e), farmId: farmId);
      return chicken;
    }).toList();
    
    return chickens;
  }

  /// Pobiera zdarzenia dla konkretnej kury
  /// GET /api/v1/farms/{farm_id}/kury/{id_kury}?limit=100&since=...&until=...
  Future<ChickenEventsResult> getChickenEvents(
    String farmId,
    String chickenId, {
    int? limit,
    DateTime? since,
    DateTime? until,
  }) async {
    final endpoint = Endpoints.chickenEvents(farmId, chickenId);

    final queryParams = <String, dynamic>{};
    if (limit != null) queryParams['limit'] = limit;
    if (since != null) queryParams['since'] = since.toIso8601String();
    if (until != null) queryParams['until'] = until.toIso8601String();

    final res = await dio.get(
      endpoint,
      queryParameters: queryParams.isNotEmpty ? queryParams : null,
    );
    final body = res.data;
    String? name;
    if (body is Map) {
      name = body['name']?.toString();
    }

    final items = ResponseParser.extractList(body);

    final events = items.whereType<Map>().map((e) {
      final event = ChickenEvent.fromJson(Map<String, dynamic>.from(e));
      return event;
    }).toList();
    
    return ChickenEventsResult(name: name, events: events);
  }

  Future<String> renameChicken(
    String farmId,
    String chickenId,
    String newName,
  ) async {
    final sanitized = newName.trim();
    if (sanitized.isEmpty) {
      throw ArgumentError('Name cannot be empty');
    }
    if (sanitized.length > 100) {
      throw ArgumentError('Name is too long (max 100 chars)');
    }

    final endpoint = Endpoints.chickenName(farmId, chickenId);

    final res = await dio.put(
      endpoint,
      data: {
        'name': sanitized,
      },
    );

    final body = res.data;
    final returnedName = body is Map ? body['name']?.toString() : null;
    return returnedName?.trim().isNotEmpty == true ? returnedName!.trim() : sanitized;
  }

  /// Usuwa wszystkie zdarzenia danej kury
  /// DELETE /api/v1/farms/{farm_id}/kury/{id_kury}
  Future<void> deleteChicken(String farmId, String chickenId) async {
    final endpoint = Endpoints.chicken(farmId, chickenId);
    await dio.delete(endpoint);
  }

  /// Dodaje nowe zdarzenie dla kury (opcjonalne)
  /// POST /api/v1/farms/{farm_id}/kury
  Future<ChickenEvent> addChickenEvent(
    String farmId, {
    required String idKury,
    required int tryb,
    required double waga,
    required DateTime eventTime,
  }) async {
    final endpoint = Endpoints.chickens(farmId);

    final body = {
      'id_kury': idKury,
      'tryb_kury': tryb,
      'waga': waga,
      'event_time': eventTime.toIso8601String(),
    };

    final res = await dio.post(endpoint, data: body);

    return ChickenEvent.fromJson(
      Map<String, dynamic>.from(res.data),
    );
  }
}
