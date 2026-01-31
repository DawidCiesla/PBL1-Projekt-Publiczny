import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/config/app_config.dart';
import '../../models/sensor.dart';
import 'widgets/kpi_card.dart';

final liveProvider = FutureProvider.family
    .autoDispose<Map<String, dynamic>, String>((ref, farmId) async {
      return ref.watch(sensorRepoProvider).fetchLive(farmId);
    });

class SensorsDashboardScreen extends ConsumerStatefulWidget {
  const SensorsDashboardScreen({
    super.key,
    required this.farmId,
    required this.active,
  });

  final String farmId;

  /// ✅ Czy dashboard jest aktualnie widoczny (tab 0 w FarmDetailScreen)
  final bool active;

  @override
  ConsumerState<SensorsDashboardScreen> createState() =>
      _SensorsDashboardScreenState();
}

class _SensorsDashboardScreenState extends ConsumerState<SensorsDashboardScreen>
    with WidgetsBindingObserver, AutomaticKeepAliveClientMixin {
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _syncPolling();
  }

  @override
  void didUpdateWidget(covariant SensorsDashboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    // ✅ jeśli zmieniło się farmId albo aktywność -> odświeżamy logikę pollingu
    if (oldWidget.farmId != widget.farmId ||
        oldWidget.active != widget.active) {
      _syncPolling(forceInvalidate: oldWidget.farmId != widget.farmId);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopPolling();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // ✅ w tle nie strzelamy requestów
    if (state == AppLifecycleState.resumed) {
      _syncPolling();
    } else {
      _stopPolling();
    }
  }

  void _startPolling() {
    _poll?.cancel();
    // ✅ Polling co 15 sekund (z AppConfig) - dla lepszej wydajności
    _poll = Timer.periodic(
      AppConfig.liveSensorsPollInterval,
      (_) => ref.invalidate(liveProvider(widget.farmId)),
    );
  }

  void _stopPolling() {
    _poll?.cancel();
    _poll = null;
  }

  void _syncPolling({bool forceInvalidate = false}) {
    if (!mounted) return;

    if (widget.active) {
      if (forceInvalidate) {
        ref.invalidate(liveProvider(widget.farmId));
      }
      _startPolling();
    } else {
      _stopPolling();
    }
  }

  double? _num(Map<String, dynamic> live, String key) {
    final v = live[key];
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  double? _numAny(Map<String, dynamic> live, List<String> keys) {
    for (final k in keys) {
      final n = _num(live, k);
      if (n != null) return n;
    }
    return null;
  }

  // ✅ Cache: bufor timestamp
  String? _cachedTsText;
  dynamic _lastRawTs;

  String? _formatTs(dynamic rawTs) {
    // ✅ Zwróć buforowany wynik jeśli timestamp się nie zmienił
    if (rawTs == _lastRawTs && _cachedTsText != null) {
      return _cachedTsText;
    }
    _lastRawTs = rawTs;
    if (rawTs == null) return null;

    // backend może dać ISO string, millis, seconds, etc.
    DateTime? dt;

    if (rawTs is num) {
      final n = rawTs.toInt();
      dt = n > 1000000000000
          ? DateTime.fromMillisecondsSinceEpoch(n, isUtc: true)
          : DateTime.fromMillisecondsSinceEpoch(n * 1000, isUtc: true);
    } else {
      dt = DateTime.tryParse(rawTs.toString());
    }

    if (dt == null) {
      // fallback: cokolwiek przyszło
      return rawTs.toString().replaceFirst('T', ' ').split('.').first;
    }

    final local = dt.toLocal();
    String two(int x) => x.toString().padLeft(2, '0');
    _cachedTsText = '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
    return _cachedTsText;
  }

  bool _isDataLive(dynamic rawTs) {
    if (rawTs == null) return false;

    DateTime? dt;

    if (rawTs is num) {
      final n = rawTs.toInt();
      dt = n > 1000000000000
          ? DateTime.fromMillisecondsSinceEpoch(n, isUtc: true)
          : DateTime.fromMillisecondsSinceEpoch(n * 1000, isUtc: true);
    } else {
      dt = DateTime.tryParse(rawTs.toString());
    }

    if (dt == null) return false;

    final now = DateTime.now();
    final difference = now.difference(dt);

    // Dane są na żywo jeśli ostatnie odświeżenie było w ciągu ostatnich 2 minut
    return difference.inSeconds < 120;
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final live = ref.watch(liveProvider(widget.farmId));

    return live.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Błąd: $e')),
      data: (data) {
        final tsText = _formatTs(data['ts']);
        final isLive = _isDataLive(data['ts']);

        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(liveProvider(widget.farmId)),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  Text(
                    'Mikroklimat',
                    style: Theme.of(context).textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const Spacer(),
                  if (tsText != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: isLive
                            ? Colors.green.withValues(alpha: 0.15)
                            : Colors.red.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isLive ? Colors.green : Colors.red,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                isLive ? 'Na żywo' : 'Brak połączenia',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: isLive ? Colors.green[700] : Colors.red[700],
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Ostatnie: $tsText',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: isLive ? Colors.green[700] : Colors.red[700],
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),

              GridView.count(
                shrinkWrap: true,
                // ✅ MediaQuery.sizeOf jest bardziej wydajne - nie nasłuchuje wszystkich zmian MediaQuery
                crossAxisCount: MediaQuery.sizeOf(context).width > 700 ? 2 : 1,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: MediaQuery.sizeOf(context).width > 700 ? 2.2 : 2.5,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  KpiCard(
                    title: 'Temperatura',
                    value:
                        (_numAny(data, const [
                          'temperature',
                        ])?.toStringAsFixed(1) ??
                        '—'),
                    unit: '°C',
                    subtitle: 'Kliknij aby zobaczyć historię',
                    icon: Icons.thermostat_rounded,
                    onTap: () => context.go('/farms/${widget.farmId}/history/${SensorMetric.temperature.key}'),
                  ),
                  KpiCard(
                    title: 'Wilgotność',
                    value:
                        (_numAny(data, const [
                          'humidity',
                        ])?.toStringAsFixed(0) ??
                        '—'),
                    unit: '%',
                    subtitle: 'Kliknij aby zobaczyć historię',
                    icon: Icons.water_drop_rounded,
                    onTap: () => context.go('/farms/${widget.farmId}/history/${SensorMetric.humidity.key}'),
                  ),
                  KpiCard(
                    title: 'CO₂',
                    value:
                        (_numAny(data, const ['co2'])?.toStringAsFixed(0) ??
                        '—'),
                    unit: 'ppm',
                    subtitle: 'Kliknij aby zobaczyć historię',
                    icon: Icons.co2_rounded,
                    onTap: () => context.go('/farms/${widget.farmId}/history/${SensorMetric.co2.key}'),
                  ),
                  KpiCard(
                    title: 'Amoniak (NH₃)',
                    value:
                        (_numAny(data, const ['nh3'])?.toStringAsFixed(1) ??
                        '—'),
                    unit: 'ppm',
                    subtitle: 'Kliknij aby zobaczyć historię',
                    icon: Icons.science_rounded,
                    onTap: () => context.go('/farms/${widget.farmId}/history/${SensorMetric.nh3.key}'),
                  ),

                  KpiCard(
                    title: 'Nasłonecznienie',
                    value:
                        (_numAny(data, const [
                          'sunlight',
                        ])?.toStringAsFixed(0) ??
                        '—'),
                    unit: 'lx',
                    subtitle: 'Kliknij aby zobaczyć historię',
                    icon: Icons.wb_sunny_rounded,
                    onTap: () => context.go('/farms/${widget.farmId}/history/${SensorMetric.sunlight.key}'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
