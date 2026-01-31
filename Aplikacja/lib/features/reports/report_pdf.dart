import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../models/sensor.dart';
import '../../models/sensor_sample.dart';

class ReportPdfBuilder {
  static Future<pw.Document> build({
    required String farmName,
    required DateTime from,
    required DateTime to,
    required Map<SensorMetric, List<SensorSample>> series,
    PdfPageFormat? pageFormat,
    pw.Font? fontRegularOverride,
    pw.Font? fontBoldOverride,
  }) async {
    final doc = pw.Document();

    // Użyj przekazanych fontów jeśli dostępne; w przeciwnym razie załaduj z assets
    late final pw.Font fontRegular;
    late final pw.Font fontBold;

    if (fontRegularOverride != null && fontBoldOverride != null) {
      fontRegular = fontRegularOverride;
      fontBold = fontBoldOverride;
    } else {
      final fontRegularData = await rootBundle.load(
        'assets/fonts/NotoSans-Regular.ttf',
      );
      final fontBoldData = await rootBundle.load(
        'assets/fonts/NotoSans-Bold.ttf',
      );
      fontRegular = pw.Font.ttf(fontRegularData);
      fontBold = pw.Font.ttf(fontBoldData);
    }

    final textStyle = pw.TextStyle(font: fontRegular, fontSize: 11);
    final textStyleBold = pw.TextStyle(font: fontBold, fontSize: 11);

    String fmt(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')} '
        '${d.hour.toString().padLeft(2, '0')}:'
        '${d.minute.toString().padLeft(2, '0')}';

    pw.Widget metricBlock(SensorMetric metric, List<SensorSample> samples) {
      if (samples.isEmpty) {
        return pw.Container(
          margin: const pw.EdgeInsets.only(bottom: 12),
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey300),
            borderRadius: pw.BorderRadius.circular(8),
          ),
          child: pw.Text(
            '${metric.label}: brak danych w wybranym zakresie.',
            style: textStyle.copyWith(color: PdfColors.grey700),
          ),
        );
      }

      final sorted = [...samples]..sort((a, b) => a.ts.compareTo(b.ts));
      final values = sorted.map((s) => s.value).toList();

      final min = values.reduce((a, b) => a < b ? a : b);
      final max = values.reduce((a, b) => a > b ? a : b);
      final avg = values.fold<double>(0.0, (a, b) => a + b) / values.length;

      return pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 12),
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey300),
          borderRadius: pw.BorderRadius.circular(8),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(metric.label, style: textStyleBold.copyWith(fontSize: 14)),
            pw.SizedBox(height: 6),
            pw.Text(
              'Średnia: ${avg.toStringAsFixed(2)} ${metric.unit}',
              style: textStyle,
            ),
            pw.Text(
              'Min: ${min.toStringAsFixed(2)} ${metric.unit}',
              style: textStyle,
            ),
            pw.Text(
              'Max: ${max.toStringAsFixed(2)} ${metric.unit}',
              style: textStyle,
            ),
            pw.SizedBox(height: 6),
            pw.Text('Liczba próbek: ${values.length}', style: textStyle),
            pw.SizedBox(height: 4),
            pw.Text(
              'Zakres próbek: ${fmt(sorted.first.ts)} - ${fmt(sorted.last.ts)}',
              style: textStyle.copyWith(fontSize: 9, color: PdfColors.grey700),
            ),
          ],
        ),
      );
    }

    doc.addPage(
      pw.MultiPage(
        pageFormat: pageFormat ?? PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Strona ${context.pageNumber} / ${context.pagesCount}',
            style: textStyle.copyWith(fontSize: 9, color: PdfColors.grey600),
          ),
        ),
        build: (_) => [
          pw.Text(
            'Raport mikroklimatu – $farmName',
            style: textStyleBold.copyWith(fontSize: 20),
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            'Zakres raportu: ${fmt(from)} - ${fmt(to)}',
            style: textStyle.copyWith(fontSize: 11),
          ),
          pw.Divider(height: 24),

          for (final metric in SensorMetric.values)
            metricBlock(metric, series[metric] ?? const []),

        ],
      ),
    );

    return doc;
  }
}
