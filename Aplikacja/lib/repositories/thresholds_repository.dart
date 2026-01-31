import 'package:dio/dio.dart';

import '../core/api/endpoints.dart';
import '../models/thresholds.dart';

class ThresholdsRepository {
  final Dio dio;
  ThresholdsRepository(this.dio);

  Future<Thresholds> getThresholds(String farmId) async {
    try {
      final res = await dio.get(Endpoints.farmLimits(farmId));
      final body = res.data;

      if (body is Map) {
        final dynamic data = (body['data'] is Map) ? body['data'] : body;
        if (data is Map) {
          final parsed = Thresholds.fromJson(Map<String, dynamic>.from(data));
          return _withFallbackFarmId(parsed, farmId);
        }
      }

      return Thresholds.defaultForFarm(farmId);
    } on DioException catch (e) {
      // Spróbuj aliasu coops
      if (e.response?.statusCode == 404) {
        try {
          final res = await dio.get(Endpoints.coopLimits(farmId));
          final body = res.data;
          if (body is Map) {
            final dynamic data = (body['data'] is Map) ? body['data'] : body;
            if (data is Map) {
              final parsed = Thresholds.fromJson(Map<String, dynamic>.from(data));
              return _withFallbackFarmId(parsed, farmId);
            }
          }
        } on DioException catch (_) {}
      }
      // Spróbuj starego endpointu thresholds na wypadek starego backendu
      if (e.response?.statusCode == 404) {
        try {
          final res = await dio.get(Endpoints.thresholds(farmId));
          final body = res.data;
          if (body is Map) {
            final dynamic data = (body['data'] is Map) ? body['data'] : body;
            if (data is Map) {
              final parsed = Thresholds.fromJson(Map<String, dynamic>.from(data));
              return _withFallbackFarmId(parsed, farmId);
            }
          }
          return Thresholds.defaultForFarm(farmId);
        } on DioException catch (fallback) {
          if (fallback.response?.statusCode == 404) {
            return Thresholds.defaultForFarm(farmId);
          }
          rethrow;
        }
      }
      if (e.response?.statusCode == 404) {
        return Thresholds.defaultForFarm(farmId);
      }
      rethrow;
    }
  }

  Future<void> updateThresholds(Thresholds thresholds) async {
    try {
      await dio.put(
        Endpoints.farmLimits(thresholds.farmId),
        data: thresholds.toJson(),
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        // spróbuj aliasu coops
        try {
          await dio.put(
            Endpoints.coopLimits(thresholds.farmId),
            data: thresholds.toJson(),
          );
          return;
        } catch (_) {}
      }
      if (e.response?.statusCode == 404) {
        // spróbuj starej ścieżki thresholds
        await dio.put(
          Endpoints.thresholds(thresholds.farmId),
          data: thresholds.toJson(),
        );
        return;
      }
      rethrow;
    }
  }

  Thresholds _withFallbackFarmId(Thresholds parsed, String fallbackId) {
    if (parsed.farmId.isNotEmpty) return parsed;
    return Thresholds(farmId: fallbackId, byMetric: parsed.byMetric);
  }
}