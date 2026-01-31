import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../models/sensor.dart';
import '../../models/sensor_sample.dart';
import 'widgets/sensor_line_chart.dart';

typedef HistoryArgs = ({
  String farmId,
  SensorMetric metric,
  DateTime from,
  DateTime to,
});

/// ✅ Cache klucza dla historyProvider - cache przez 5 minut
/// Dzięki keepAlive dane nie są ponownie pobierane przy przełączaniu zakładek
final historyProvider = FutureProvider.family<List<SensorSample>, HistoryArgs>((
  ref,
  args,
) async {
  // ✅ Auto-dispose po 5 minutach nieużywania (oszczędność pamięci)
  final link = ref.keepAlive();
  final timer = Timer(const Duration(minutes: 5), () {
    link.close();
  });
  ref.onDispose(() => timer.cancel());

  final repo = ref.watch(sensorRepoProvider);
  return repo.fetchHistory(
    farmId: args.farmId,
    metric: args.metric,
    from: args.from,
    to: args.to,
  );
});

class SensorHistoryScreen extends ConsumerStatefulWidget {
  const SensorHistoryScreen({
    super.key,
    required this.farmId,
    required this.metric,
  });

  final String farmId;
  final String metric;

  @override
  ConsumerState<SensorHistoryScreen> createState() =>
      _SensorHistoryScreenState();
}

class _SensorHistoryScreenState extends ConsumerState<SensorHistoryScreen> {
  int rangeIdx = 1; // 0=1h, 1=24h, 2=7d, 3=30d

  Timer? _rangeDebounce;

  /// ✅ Opóźnione renderowanie wykresu dla płynniejszego UI
  bool _chartReady = false;

  @override
  void initState() {
    super.initState();
    // ✅ Pozwól na wyrenderowanie szkieletu UI przed ciężkim wykresem
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() => _chartReady = true);
      }
    });
  }

  @override
  void dispose() {
    _rangeDebounce?.cancel();
    super.dispose();
  }

  SensorMetric get metric => SensorMetric.values.firstWhere(
    (m) => m.key == widget.metric,
    orElse: () => SensorMetric.temperature,
  );

  DateTimeRange _rangeFor(int idx, DateTime now) {
    // ✅ stabilne "teraz" -> zaokrąglone do minuty (nie zmienia się co sekundę)
    final stableNow = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute,
    );

    final duration = switch (idx) {
      0 => const Duration(hours: 1),
      1 => const Duration(hours: 24),
      2 => const Duration(days: 7),
      _ => const Duration(days: 30),
    };

    return DateTimeRange(start: stableNow.subtract(duration), end: stableNow);
  }

  @override
  Widget build(BuildContext context) {
    final r = _rangeFor(rangeIdx, DateTime.now());

    final args = (
      farmId: widget.farmId,
      metric: metric,
      from: r.start,
      to: r.end,
    );

    final asyncSamples = ref.watch(historyProvider(args));

    return Scaffold(
      appBar: AppBar(title: Text('Historia – ${metric.label}')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, label: Text('1h')),
                ButtonSegment(value: 1, label: Text('24h')),
                ButtonSegment(value: 2, label: Text('7d')),
                ButtonSegment(value: 3, label: Text('30d')),
              ],
              selected: {rangeIdx},
              onSelectionChanged: (s) {
                // ✅ Debounce 300ms aby uniknąć zbyt częstych requestów
                _rangeDebounce?.cancel();
                _rangeDebounce = Timer(const Duration(milliseconds: 300), () {
                  if (!mounted) return;
                  setState(() => rangeIdx = s.first);
                });
              },
            ),
            const SizedBox(height: 12),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  // ✅ ręczne odświeżenie tych samych args
                  ref.invalidate(historyProvider(args));
                },
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: asyncSamples.when(
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (e, _) => Center(child: Text('Błąd: $e')),
                      data: (samples) => Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${metric.label} (${metric.unit})',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 12),
                          Expanded(
                            // ✅ RepaintBoundary izoluje przerysowywanie wykresu
                            child: RepaintBoundary(
                              child: _chartReady
                                  ? SensorLineChart(samples: samples)
                                  : const Center(
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
