import 'package:dio/dio.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../core/api/endpoints.dart';
import '../models/sensor.dart';
import '../models/sensor_sample.dart';

class SensorRepository {
  final Dio dio;
  final Map<String, WebSocketChannel> _activeConnections = {};
  
  SensorRepository(this.dio);
  
  /// ✅ Zamyka WebSocket dla danego farm
  void closeLiveWs(String farmId) {
    _activeConnections[farmId]?.sink.close();
    _activeConnections.remove(farmId);
  }
  
  /// ✅ Zamyka wszystkie WebSockety
  void closeAllWs() {
    for (final channel in _activeConnections.values) {
      try {
        channel.sink.close();
      } catch (_) {}
    }
    _activeConnections.clear();
  }
  
  /// ✅ Cleanup do użytku z Riverpod onDispose
  void dispose() {
    closeAllWs();
  }

  Future<Map<String, dynamic>> fetchLive(String farmId) async {
    final res = await dio.get(Endpoints.live(farmId));
    final body = res.data;

    if (body is Map) {
      final data = (body['data'] is Map) ? body['data'] : body;
      return Map<String, dynamic>.from(data as Map);
    }

    throw Exception('Niepoprawny format LIVE: ${body.runtimeType}');
  }

  Future<List<SensorSample>> fetchHistory({
    required String farmId,
    required SensorMetric metric,
    required DateTime from,
    required DateTime to,
  }) async {
    try {
      final res = await dio.get(
        Endpoints.history(farmId),
        queryParameters: {
          'metric': metric.key,
          'from': from.toUtc().toIso8601String(),
          'to': to.toUtc().toIso8601String(),
        },
      );

      final body = res.data;

      List<dynamic> items;
      if (body is List) {
        items = body;
      } else if (body is Map) {
        if (body['items'] is List) {
          items = body['items'] as List;
        } else if (body['series'] is List) {
          items = body['series'] as List;
        } else if (body['data'] is Map && body['data']['items'] is List) {
          items = body['data']['items'] as List;
        } else if (body['data'] is Map && body['data']['series'] is List) {
          items = body['data']['series'] as List;
        } else {
          items = const <dynamic>[];
        }
      } else {
        items = const <dynamic>[];
      }

      final samples = items
          .whereType<Map>()
          .map((e) => SensorSample.fromJson(Map<String, dynamic>.from(e)))
          .toList()
        ..sort((a, b) => a.ts.compareTo(b.ts));

      return samples;
    } on DioException catch (e) {
      // ✅ jeśli backend nie ma metryki / nie ma danych -> nie wywalaj UI/raportu
      if (e.response?.statusCode == 404) {
        return const <SensorSample>[];
      }
      rethrow;
    }
  }

  /// ✅ Otworzy WebSocket i cache'uje połączenie
  WebSocketChannel openLiveWs(String farmId, {required String token}) {
    // Zamknij stare połączenie jeśli istnieje
    closeLiveWs(farmId);
    
    final uri = Endpoints.wsUri(
      Endpoints.wsLive(farmId),
      query: {'token': token},
    );
    final channel = WebSocketChannel.connect(uri);
    _activeConnections[farmId] = channel;
    return channel;
  }
}