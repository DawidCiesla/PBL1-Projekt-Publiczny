import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth/auth_state.dart';
import '../repositories/alert_repository.dart';
import '../repositories/device_repository.dart';
import '../repositories/farm_repository.dart';
import '../repositories/sensor_repository.dart';
import '../repositories/thresholds_repository.dart';
import '../repositories/chicken_repository.dart';
import '../models/farm.dart';

final farmRepoProvider = Provider<FarmRepository>((ref) {
  final dio = ref.watch(dioProvider);
  return FarmRepository(dio);
});

/// Provider listy kurników - przeniesiony tutaj z farm_list_screen.dart
/// aby uniknąć cyklicznej zależności (core importuje features)
final farmsProvider = FutureProvider<List<Farm>>((ref) async {
  return ref.watch(farmRepoProvider).listFarms();
});

final sensorRepoProvider = Provider<SensorRepository>((ref) {
  final dio = ref.watch(dioProvider);
  final repo = SensorRepository(dio);
  
  // ✅ Cleanup: zamknij wszystkie WebSockety gdy provider jest dispose'd
  ref.onDispose(() {
    repo.dispose();
  });
  
  return repo;
});

final deviceRepoProvider = Provider<DeviceRepository>((ref) {
  final dio = ref.watch(dioProvider);
  return DeviceRepository(dio);
});

final alertRepoProvider = Provider<AlertRepository>((ref) {
  final dio = ref.watch(dioProvider);
  return AlertRepository(dio);
});

final thresholdsRepoProvider = Provider<ThresholdsRepository>((ref) {
  final dio = ref.watch(dioProvider);
  return ThresholdsRepository(dio);
});

final chickenRepoProvider = Provider<ChickenRepository>((ref) {
  final dio = ref.watch(dioProvider);
  return ChickenRepository(dio);
});