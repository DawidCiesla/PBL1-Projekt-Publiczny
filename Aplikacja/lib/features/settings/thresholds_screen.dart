import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../models/sensor.dart';
import '../../models/thresholds.dart';
import 'widgets/threshold_card.dart';

final thresholdsProvider = FutureProvider.family
    .autoDispose<Thresholds, String>((ref, farmId) async {
      return ref.watch(thresholdsRepoProvider).getThresholds(farmId);
    });

class ThresholdsScreen extends ConsumerStatefulWidget {
  const ThresholdsScreen({super.key, required this.farmId});
  final String farmId;

  @override
  ConsumerState<ThresholdsScreen> createState() => _ThresholdsScreenState();
}

class _ThresholdsScreenState extends ConsumerState<ThresholdsScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    // ✅ Obserwuj tylko normy, unikaj zbędnych rebuiltów
    final async = ref.watch(
      thresholdsProvider(widget.farmId).select((data) => data),
    );

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text('Błąd: $e'),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () =>
                  ref.invalidate(thresholdsProvider(widget.farmId)),
              icon: const Icon(Icons.refresh),
              label: const Text('Spróbuj ponownie'),
            ),
          ],
        ),
      ),
      data: (t) {
        return RefreshIndicator(
          onRefresh: () async =>
              ref.invalidate(thresholdsProvider(widget.farmId)),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Theme.of(
                          context,
                        ).colorScheme.primaryContainer.withValues(alpha: 0.3),
                        Theme.of(context).colorScheme.surface,
                      ],
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).colorScheme.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                Icons.tune_rounded,
                                color: Theme.of(context).colorScheme.primary,
                                size: 28,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Normy pomiarów',
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineSmall
                                        ?.copyWith(fontWeight: FontWeight.w800),
                                  ),
                                  const SizedBox(height: 4),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            OutlinedButton.icon(
                              onPressed: () => _openEditLimits(t),
                              icon: const Icon(Icons.edit_rounded),
                              label: const Text('Edytuj'),
                              style: OutlinedButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        ...SensorMetric.values.map((m) {
                          final th = t.byMetric[m];
                          if (th == null) return const SizedBox.shrink();

                          String fmt(double? v) => v == null
                              ? '—'
                              : v.toStringAsFixed(v % 1 == 0 ? 0 : 1);

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: ThresholdCard(
                              metric: m,
                              threshold: th,
                              formatter: fmt,
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _openEditLimits(Thresholds thresholds) {
    // ✅ Upewniamy się że mamy wszystkie metryki (nawet jeśli brak danych z backendu)
    final safeThresholds = thresholds.byMetric.isEmpty
        ? Thresholds.defaultForFarm(widget.farmId)
        : thresholds;

    // ✅ Tworzymy kontrolery PRZED showModalBottomSheet aby mieć do nich dostęp po zamknięciu
    final controllers = <SensorMetric, Map<String, TextEditingController>>{
      for (final metric in SensorMetric.values)
        metric: {
          'min': TextEditingController(
            text: _formatVal(safeThresholds.byMetric[metric]?.min),
          ),
          'max': TextEditingController(
            text: _formatVal(safeThresholds.byMetric[metric]?.max),
          ),
        },
    };

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      isDismissible: true,
      enableDrag: true,
      builder: (ctx) {
        final formKey = GlobalKey<FormState>();

        bool saving = false;

        return StatefulBuilder(
          builder: (context, setModalState) {
            Future<void> submit() async {
              if (!formKey.currentState!.validate()) return;

              final updated = <SensorMetric, MetricLimits>{};
              final rootContext = context; // safe refs for post-await usage
              final sheetContext = ctx;

              double? parse(String? raw) {
                final txt = (raw ?? '').trim();
                if (txt.isEmpty) return null;
                return double.tryParse(txt.replaceAll(',', '.'));
              }

              // ✅ Waliduj przed zbudowaniem mapy
              final errors = <String>[];
              controllers.forEach((metric, map) {
                final minVal = parse(map['min']?.text);
                final maxVal = parse(map['max']?.text);
                if (minVal != null && maxVal != null) {
                  if (minVal >= maxVal) {
                    errors.add(
                      '${metric.label}: min musi być mniejsze niż max',
                    );
                  }
                }
              });

              if (errors.isNotEmpty) {
                setModalState(() => saving = false);
                ScaffoldMessenger.of(rootContext).showSnackBar(
                  SnackBar(
                    content: Text(errors.join('\n')),
                    backgroundColor: Colors.red[700],
                  ),
                );
                return;
              }

              controllers.forEach((metric, map) {
                final minVal = parse(map['min']?.text);
                final maxVal = parse(map['max']?.text);
                updated[metric] = MetricLimits(min: minVal, max: maxVal);
              });

              final newThresholds = Thresholds(
                farmId: widget.farmId,
                byMetric: updated,
              );

              try {
                setModalState(() => saving = true);
                await ref
                    .read(thresholdsRepoProvider)
                    .updateThresholds(newThresholds);
                if (!mounted || !rootContext.mounted) return;
                if (sheetContext.mounted) {
                  Navigator.of(sheetContext).pop();
                }
                ref.invalidate(thresholdsProvider(widget.farmId));
                ScaffoldMessenger.of(
                  rootContext,
                ).showSnackBar(const SnackBar(content: Text('Zapisano normy')));
              } catch (e) {
                setModalState(() => saving = false);
                if (!mounted || !rootContext.mounted) return;
                ScaffoldMessenger.of(
                  rootContext,
                ).showSnackBar(SnackBar(content: Text('Błąd zapisu: $e')));
              }
            }

            return DraggableScrollableSheet(
              initialChildSize: 0.75,
              minChildSize: 0.5,
              maxChildSize: 0.95,
              expand: false,
              builder: (context, scrollController) {
                return Padding(
                  padding: EdgeInsets.only(
                    left: 16,
                    right: 16,
                    top: 12,
                    // ✅ viewInsetsOf jest bardziej wydajne
                    bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
                  ),
                  child: Form(
                    key: formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.tune_rounded),
                            const SizedBox(width: 8),
                            Text(
                              'Edytuj normy',
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const Spacer(),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: ListView(
                            controller: scrollController,
                            children: controllers.entries.map((entry) {
                              final metric = entry.key;
                              final ctrls = entry.value;
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 14),
                                child: Card(
                                  elevation: 1,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(14),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Icon(
                                              switch (metric) {
                                                SensorMetric.temperature =>
                                                  Icons.thermostat_rounded,
                                                SensorMetric.humidity =>
                                                  Icons.water_drop_rounded,
                                                SensorMetric.co2 =>
                                                  Icons.co2_rounded,
                                                SensorMetric.nh3 =>
                                                  Icons.science_rounded,
                                                SensorMetric.sunlight =>
                                                  Icons.wb_sunny_rounded,
                                              },
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.primary,
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              metric.label,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleMedium
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              metric.unit,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .labelSmall
                                                  ?.copyWith(
                                                    color: Colors.grey[600],
                                                  ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 12),
                                        Row(
                                          children: [
                                            if (metric != SensorMetric.nh3 &&
                                                metric != SensorMetric.co2)
                                              Expanded(
                                                child: TextFormField(
                                                  controller: ctrls['min'],
                                                  decoration: const InputDecoration(
                                                    labelText: 'Min',
                                                    prefixIcon: Icon(
                                                      Icons
                                                          .arrow_downward_rounded,
                                                    ),
                                                  ),
                                                  keyboardType:
                                                      const TextInputType.numberWithOptions(
                                                        signed: false,
                                                        decimal: true,
                                                      ),
                                                  validator: (v) {
                                                    if (v == null ||
                                                        v.trim().isEmpty) {
                                                      return null;
                                                    }
                                                    final parsed =
                                                        double.tryParse(
                                                          v.trim().replaceAll(
                                                            ',',
                                                            '.',
                                                          ),
                                                        );
                                                    if (parsed == null) {
                                                      return 'Podaj liczbę';
                                                    }
                                                    return null;
                                                  },
                                                ),
                                              ),
                                            if (metric != SensorMetric.nh3 &&
                                                metric != SensorMetric.co2)
                                              const SizedBox(width: 12),
                                            Expanded(
                                              child: TextFormField(
                                                controller: ctrls['max'],
                                                decoration: const InputDecoration(
                                                  labelText: 'Max',
                                                  prefixIcon: Icon(
                                                    Icons.arrow_upward_rounded,
                                                  ),
                                                ),
                                                keyboardType:
                                                    const TextInputType.numberWithOptions(
                                                      signed: false,
                                                      decimal: true,
                                                    ),
                                                validator: (v) {
                                                  if (v == null ||
                                                      v.trim().isEmpty) {
                                                    return null;
                                                  }
                                                  final parsed =
                                                      double.tryParse(
                                                        v.trim().replaceAll(
                                                          ',',
                                                          '.',
                                                        ),
                                                      );
                                                  if (parsed == null) {
                                                    return 'Podaj liczbę';
                                                  }
                                                  return null;
                                                },
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: saving
                                    ? null
                                    : () => Navigator.of(context).pop(),
                                child: const Text('Anuluj'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: saving ? null : submit,
                                icon: saving
                                    ? const SizedBox(
                                        height: 18,
                                        width: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.save_rounded),
                                label: Text(saving ? 'Zapisywanie…' : 'Zapisz'),
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    ).whenComplete(() {
      // ✅ Dispose wszystkich kontrolerów po zamknięciu BottomSheet
      // Używamy try-catch dla bezpieczeństwa
      for (final map in controllers.values) {
        try {
          map['min']?.dispose();
        } catch (_) {}
        try {
          map['max']?.dispose();
        } catch (_) {}
      }
    });
  }

  String _formatVal(double? v) {
    if (v == null) return '';
    return v.toStringAsFixed(v % 1 == 0 ? 0 : 2);
  }
}
