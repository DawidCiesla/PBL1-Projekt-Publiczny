import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';
import 'package:flutter/foundation.dart';
import 'package:pdf/widgets.dart' as pw;
import 'dart:async';
import 'dart:developer' as dev;
import 'package:flutter/services.dart';

import '../../core/providers.dart';
import '../../models/farm.dart';
import '../../models/sensor.dart';
import '../../models/sensor_sample.dart';
import 'report_pdf.dart';

// ✅ Separate function for compute isolation
Future<Uint8List> _generatePdfInIsolate(Map<String, dynamic> params) async {
  final pdf = await ReportPdfBuilder.build(
    farmName: params['farmName'] as String,
    from: params['from'] as DateTime,
    to: params['to'] as DateTime,
    series: params['series'] as Map<SensorMetric, List<SensorSample>>,
    fontRegularOverride: params['fontRegular'] as pw.Font?,
    fontBoldOverride: params['fontBold'] as pw.Font?,
  );
  final bytes = await pdf.save();
  return Uint8List.fromList(bytes);
}

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  DateTimeRange range = DateTimeRange(
    start: DateTime.now().subtract(const Duration(days: 7)),
    end: DateTime.now(),
  );

  String? selectedFarmId;

  bool loading = false;
  String? status;
  
  Timer? _refreshDebounce;

  @override
  void dispose() {
    _refreshDebounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final farmsAsync = ref.watch(farmsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Raporty')),
      body: ListView(
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
                padding: const EdgeInsets.all(24),
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
                            ).colorScheme.primary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(
                            Icons.picture_as_pdf_rounded,
                            size: 32,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Generuj raport PDF',
                                style: Theme.of(context).textTheme.headlineSmall
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Automatyczny eksport danych',
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Wybierz kurnik',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 8),
                    farmsAsync.when(
                      loading: () => Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const SizedBox(
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                      error: (err, stack) => Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.red[100],
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          'Błąd ładowania kurników: $err',
                          style: TextStyle(color: Colors.red[800]),
                        ),
                      ),
                      data: (farms) {
                        if (farms.isEmpty) {
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.orange[100],
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(
                              'Brak dostępnych kurników',
                              style: TextStyle(color: Colors.orange[800]),
                            ),
                          );
                        }

                        return DropdownButtonFormField<String>(
                          initialValue: selectedFarmId,
                          items: farms
                              .map(
                                (farm) => DropdownMenuItem<String>(
                                  value: farm.id,
                                  child: Text(farm.name),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            setState(() => selectedFarmId = value);
                          },
                          decoration: InputDecoration(
                            labelText: 'Kurnik',
                            prefixIcon: const Icon(Icons.warehouse_rounded),
                            filled: true,
                            fillColor: Theme.of(
                              context,
                            ).colorScheme.surfaceContainerHighest,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          validator: (value) =>
                              value == null ? 'Wybierz kurnik' : null,
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final picked = await showDateRangePicker(
                          context: context,
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now(),
                          initialDateRange: range,
                        );
                        if (picked != null) {
                          setState(() => range = picked);
                        }
                      },
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.all(16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      icon: const Icon(Icons.date_range_rounded),
                      label: Text(
                        'Zakres: ${range.start.toString().split(' ').first} → ${range.end.toString().split(' ').first}',
                      ),
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: (loading || selectedFarmId == null)
                          ? null
                          : _generatePdf,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      icon: loading
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.picture_as_pdf_rounded),
                      label: Text(
                        loading ? 'Generowanie...' : 'Generuj PDF',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (status != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: status!.contains('Błąd')
                              ? Colors.red.withValues(alpha: 0.1)
                              : status!.contains('✅')
                              ? Colors.green.withValues(alpha: 0.1)
                              : Colors.blue.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: status!.contains('Błąd')
                                ? Colors.red.withValues(alpha: 0.3)
                                : status!.contains('✅')
                                ? Colors.green.withValues(alpha: 0.3)
                                : Colors.blue.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              status!.contains('Błąd')
                                  ? Icons.error_outline
                                  : status!.contains('✅')
                                  ? Icons.check_circle_outline
                                  : Icons.info_outline,
                              color: status!.contains('Błąd')
                                  ? Colors.red[700]
                                  : status!.contains('✅')
                                  ? Colors.green[700]
                                  : Colors.blue[700],
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                status!,
                                style: TextStyle(
                                  color: status!.contains('Błąd')
                                      ? Colors.red[700]
                                      : status!.contains('✅')
                                      ? Colors.green[700]
                                      : Colors.blue[700],
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          // Diagnoztyczne przyciski usunięte
        ],
      ),
    );
  }

  Future<void> _generatePdf() async {
    if (selectedFarmId == null) return;

    setState(() {
      loading = true;
      status = 'Pobieranie danych…';
    });

    try {
      final farmId = selectedFarmId!;
      final repo = ref.read(sensorRepoProvider);

      // ✅ stabilne granice (pełne dni)
      final from = DateTime(
        range.start.year,
        range.start.month,
        range.start.day,
      );
      final to = DateTime(
        range.end.year,
        range.end.month,
        range.end.day,
        23,
        59,
        59,
      );

      final series = <SensorMetric, List<SensorSample>>{};
      final failed = <SensorMetric, Object>{};

      // ✅ pobieraj równolegle, ale nie wysypuj całego raportu gdy 1 metryka padnie
      await Future.wait([
        for (final m in SensorMetric.values)
          () async {
            try {
              final s = await repo.fetchHistory(
                farmId: farmId,
                metric: m,
                from: from,
                to: to,
              );
              series[m] = s;
            } catch (e) {
              // jeśli backend np. nie ma metryki / jest błąd -> pomiń metrykę
              series[m] = const <SensorSample>[];
              failed[m] = e;
            }
          }(),
      ]);

      if (!mounted) return;
      setState(() => status = 'Generowanie PDF…');

      // Załaduj farms aby uzyskać nazwę wybranego kurnika
      final farmsAsync = ref.read(farmsProvider);
      final farmName =
          farmsAsync
              .whenData((farms) {
                final farm = farms.firstWhere(
                  (f) => f.id == selectedFarmId,
                  orElse: () =>
                      Farm(id: selectedFarmId!, name: 'Kurnik', location: ''),
                );
                return farm.name;
              })
              .asData
              ?.value ??
          'Kurnik';

      final pdfSw = Stopwatch()..start();
      
      // ✅ Załaduj czcionki w głównym thread'zie (ma dostęp do rootBundle)
      late final pw.Font fontRegular;
      late final pw.Font fontBold;
      try {
        final fontRegularData = await rootBundle.load('assets/fonts/NotoSans-Regular.ttf');
        final fontBoldData = await rootBundle.load('assets/fonts/NotoSans-Bold.ttf');
        fontRegular = pw.Font.ttf(fontRegularData);
        fontBold = pw.Font.ttf(fontBoldData);
      } catch (e) {
        // Fallback na czcionki domyślne
        fontRegular = pw.Font.helvetica();
        fontBold = pw.Font.helveticaBold();
      }
      
      // ✅ Przeniesiono generowanie PDF do compute aby nie blokowało UI
      final pdfBytes = await compute(_generatePdfInIsolate, {
        'farmName': farmName,
        'from': from,
        'to': to,
        'series': series,
        'fontRegular': fontRegular,
        'fontBold': fontBold,
      });
      pdfSw.stop();
      dev.log('PDF build isolate: ${pdfSw.elapsedMilliseconds} ms', name: 'PDF');

      if (!mounted) return;
      // Bezpośrednio udostępnij plik, bez otwierania natywnego podglądu wydruku.
      try {
        setState(() => status = 'Udostępnianie pliku…');
        final fname = 'Raport_${farmName.replaceAll(' ', '_')}.pdf';
        await Printing.sharePdf(bytes: pdfBytes, filename: fname);
        if (!mounted) return;
        setState(() => status = 'Udostępniono');
      } catch (eShare, stShare) {
        dev.log('Share PDF error: $eShare', name: 'PDF', error: eShare, stackTrace: stShare);
        if (mounted) {
          setState(() => status = 'Błąd udostępniania: $eShare');
        }
      }

      if (!mounted) return;

      if (failed.isEmpty) {
        setState(() => status = 'Gotowe');
      } else {
        final names = failed.keys.map((m) => m.key).join(', ');
        setState(() => status = 'Gotowe (pominięto: $names)');
      }
    } catch (e) {
      if (mounted) {
        setState(() => status = 'Błąd: $e');
      }
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }
}
