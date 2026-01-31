import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/config/app_config.dart';
import '../../../models/sensor_sample.dart';

class SensorLineChart extends StatefulWidget {
  const SensorLineChart({
    super.key,
    required this.samples,
    this.maxPoints, // jeśli null -> auto wg szerokości
  });

  final List<SensorSample> samples;
  final int? maxPoints;

  @override
  State<SensorLineChart> createState() => _SensorLineChartState();
}

class _SensorLineChartState extends State<SensorLineChart>
    with AutomaticKeepAliveClientMixin {
  // cache - ✅ aby uniknąć redundantnych sortowań
  List<SensorSample> _sorted = const [];
  List<SensorSample> _reduced = const [];
  int _lastLen = -1;
  int _lastFirstMs = -1;
  int _lastLastMs = -1;
  int _lastMaxPoints = -1;

  // ✅ Cache dla FlSpot - unikaj ponownego tworzenia listy przy każdym renderze
  List<FlSpot>? _cachedSpots;

  // ✅ Panning w poziomie (0..1), bez wychodzenia poza wykres
  double _panPos = 0.0; // 0 = początek, 1 = koniec zakresu
  static const double _viewportFractionX =
      0.5; // ✅ Zwiększono z 0.35 dla lepszej czytelności

  // ✅ Zachowaj stan widgetu przy przełączaniu zakładek
  @override
  bool get wantKeepAlive => true;

  /// ✅ Czy cache jest ważny
  bool _isCacheValid(List<SensorSample> samples, int maxPts) {
    if (_lastLen != samples.length) return false;
    if (_lastMaxPoints != maxPts) return false;
    if (samples.isEmpty) return true; // Obie listy puste

    // Jeśli pierwszy/ostatni timestamp się zmienił -> cache invalid
    final firstMs = samples.first.ts.millisecondsSinceEpoch;
    final lastMs = samples.last.ts.millisecondsSinceEpoch;
    return _lastFirstMs == firstMs && _lastLastMs == lastMs;
  }

  @override
  void dispose() {
    // Wyczyść cache aby zwolnić pamięć
    _sorted = const [];
    _reduced = const [];
    _cachedSpots = null;
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant SensorLineChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    // ✅ Jeśli dane się zmieniły, wyczyść cache aby wymusiło rebuild
    if (oldWidget.samples != widget.samples) {
      _lastLen = -1;
      _cachedSpots = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // ✅ Wymagane dla AutomaticKeepAliveClientMixin

    if (widget.samples.isEmpty) {
      return const Center(child: Text('Brak danych w tym zakresie.'));
    }

    // ✅ Cache theme na początku - unikaj wielokrotnego pobierania
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    return LayoutBuilder(
      builder: (context, c) {
        try {
          final maxPts = widget.maxPoints ?? _autoMaxPoints(c.maxWidth);

          // ✅ Sprawdź czy cache jest wciąż ważny
          if (!_isCacheValid(widget.samples, maxPts)) {
            _sorted = [...widget.samples]..sort((a, b) => a.ts.compareTo(b.ts));
            _reduced = _downsampleLttb(_sorted, maxPoints: maxPts);

            _lastLen = widget.samples.length;
            _lastFirstMs = widget.samples.first.ts.millisecondsSinceEpoch;
            _lastLastMs = widget.samples.last.ts.millisecondsSinceEpoch;
            _lastMaxPoints = maxPts;
            _cachedSpots = null; // ✅ Invalidate cache spots
          }

          final reduced = _reduced;
          if (reduced.isEmpty) {
            return const Center(child: Text('Brak danych w tym zakresie.'));
          }

          // ✅ Cache FlSpots - unikaj tworzenia nowej listy przy każdym renderze
          _cachedSpots ??= [
            for (final s in reduced)
              FlSpot(s.ts.millisecondsSinceEpoch.toDouble(), s.value),
          ];
          final spots = _cachedSpots!;

          // ✅ Sprawdź czy mamy wystarczająco punktów do wykresu
          if (spots.length < 2) {
            return const Center(
              child: Text('Za mało danych do wyświetlenia wykresu.'),
            );
          }

          final minX = spots.first.x;
          final maxX = spots.last.x;
          final spanX = (maxX - minX).abs();

          // ✅ Gdy spanX jest 0 (wszystkie punkty w tym samym czasie), dodaj sztuczny zakres
          if (spanX == 0) {
            return const Center(
              child: Text('Wszystkie dane mają ten sam znacznik czasu.'),
            );
          }

          double minY = reduced.first.value;
          double maxY = reduced.first.value;
          for (final s in reduced) {
            if (s.value < minY) minY = s.value;
            if (s.value > maxY) maxY = s.value;
          }
          final rangeY = (maxY - minY).abs();
          final padY = rangeY == 0 ? 1.0 : rangeY * 0.15;

          // ✅ Upewnij się, że minY nigdy nie będzie mniejszy niż 0 (chyba że dane mają wartości ujemne)
          final calculatedMinY = minY - padY;
          final finalMinY = minY >= 0 && calculatedMinY < 0
              ? 0.0
              : calculatedMinY;

          String formatX(double x) {
            final dt = DateTime.fromMillisecondsSinceEpoch(x.toInt());
            final isShort = spanX <= const Duration(hours: 36).inMilliseconds;
            if (isShort) {
              final hh = dt.hour.toString().padLeft(2, '0');
              final mm = dt.minute.toString().padLeft(2, '0');
              return '$hh:$mm';
            } else {
              final dd = dt.day.toString().padLeft(2, '0');
              final mo = dt.month.toString().padLeft(2, '0');
              return '$dd.$mo';
            }
          }

          // ✅ Wyznacz okno widoku X (viewport) i pozycję panningu (0..1)
          final windowX = (spanX * _viewportFractionX).clamp(1.0, spanX);
          final minStartX = minX;
          final maxStartX = maxX - windowX;
          final startX = minStartX + (maxStartX - minStartX) * _panPos;

          final viewMinX = startX;
          final viewMaxX = startX + windowX;
          final viewMinY = finalMinY; // brak pionowego panningu
          final viewMaxY = (maxY + padY);

          // ✅ Interwał Y i kontrola zagęszczenia etykiet
          final intervalY = _niceIntervalY(rangeY);
          final rangeViewY = (viewMaxY - viewMinY).abs();
          // ✅ Zabezpieczenie przed dzieleniem przez 0 i Infinity
          final ticksY = rangeViewY > 0 && intervalY > 0
              ? (rangeViewY / intervalY).abs()
              : 1.0;
          int showEveryY = 1;
          if (ticksY > 14) {
            showEveryY = 3;
          } else if (ticksY > 8) {
            showEveryY = 2;
          }
          int decimalsY;
          if (intervalY >= 1) {
            decimalsY = 0;
          } else if (intervalY >= 0.1) {
            decimalsY = 1;
          } else if (intervalY >= 0.01) {
            decimalsY = 2;
          } else {
            decimalsY = 3;
          }

          // ✅ Cel: ~5 podpisów na osi X – dobierz „ładny” krok czasu
          final windowMs = (viewMaxX - viewMinX).abs();
          final intervalX = _niceTimeIntervalMs(windowMs, targetTickCount: 5);

          return Stack(
            children: [
              LineChart(
                LineChartData(
                  minX: viewMinX,
                  maxX: viewMaxX,
                  minY: viewMinY,
                  maxY: viewMaxY,
                  // Przytnij rysowanie do obszaru wykresu
                  clipData: const FlClipData(
                    left: true,
                    right: true,
                    top: true,
                    bottom: true,
                  ),
                  // ✅ Ulepszone grid - mniej linii ale czytelniejsze
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: intervalY,
                    getDrawingHorizontalLine: (value) {
                      return FlLine(
                        color: Colors.grey.withValues(alpha: 0.2),
                        strokeWidth: 1,
                        dashArray: [5, 5],
                      );
                    },
                  ),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 50,
                        interval: intervalY,
                        getTitlesWidget: (value, meta) {
                          // Ukryj skrajne i przefiltruj co n-ty tytuł, jeśli za gęsto
                          if (value == meta.min || value == meta.max) {
                            return const SizedBox.shrink();
                          }
                          final idx = ((value - viewMinY) / intervalY).round();
                          if (idx % showEveryY != 0) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Text(
                              value.toStringAsFixed(decimalsY),
                              style: textTheme.bodySmall?.copyWith(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                        interval: intervalX,
                        getTitlesWidget: (value, meta) {
                          // Ukryj skrajne etykiety (często dublują się na krawędziach)
                          if (value == meta.min || value == meta.max) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              formatX(value),
                              style: textTheme.bodySmall?.copyWith(
                                fontSize: 10,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  lineTouchData: LineTouchData(
                    enabled: true,
                    handleBuiltInTouches: true,
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipColor: (touchedSpot) =>
                          colorScheme.primaryContainer,
                      tooltipRoundedRadius: 8,
                      tooltipPadding: const EdgeInsets.all(8),
                      getTooltipItems: (touchedSpots) {
                        return touchedSpots.map((spot) {
                          final dt = DateTime.fromMillisecondsSinceEpoch(
                            spot.x.toInt(),
                          );
                          final dd = dt.day.toString().padLeft(2, '0');
                          final mo = dt.month.toString().padLeft(2, '0');
                          final hh = dt.hour.toString().padLeft(2, '0');
                          final mm = dt.minute.toString().padLeft(2, '0');
                          // Zawsze pokazuj dokładną wartość z 2 miejscami po przecinku
                          return LineTooltipItem(
                            '$dd.$mo $hh:$mm\n${spot.y.toStringAsFixed(2)}',
                            TextStyle(
                              color: colorScheme.onPrimaryContainer,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          );
                        }).toList();
                      },
                    ),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      curveSmoothness:
                          0.35, // ✅ Zmniejszono dla lepszej wydajności
                      barWidth: 2.5,
                      isStrokeCapRound: true,
                      preventCurveOverShooting: true,
                      // ✅ Zaokrąglone końce punktów dla lepszego wyglądu
                      gradient: LinearGradient(
                        colors: [
                          colorScheme.primary,
                          colorScheme.primary.withValues(alpha: 0.7),
                        ],
                      ),
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(
                        show: true,
                        gradient: LinearGradient(
                          colors: [
                            colorScheme.primary.withValues(alpha: 0.15),
                            colorScheme.primary.withValues(alpha: 0),
                          ],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // ✅ Scrollbar dla osi X (dół) z fraction + viewport width
              Positioned(
                bottom: 0,
                left: 50,
                right: 0,
                height: 16,
                child: GestureDetector(
                  onPanUpdate: (details) {
                    final barWidth = c.maxWidth - 50;
                    final delta = details.delta.dx / barWidth;
                    setState(() {
                      _panPos = (_panPos + delta).clamp(0.0, 1.0);
                    });
                  },
                  onTapDown: (details) {
                    final barWidth = c.maxWidth - 50;
                    final localX = details.localPosition.dx;
                    final thumbWidth = barWidth * _viewportFractionX;
                    // Ustaw pozycję tak, aby środek thumba był pod kliknięciem
                    final newPos =
                        (localX - thumbWidth / 2) / (barWidth - thumbWidth);
                    setState(() {
                      _panPos = newPos.clamp(0.0, 1.0);
                    });
                  },
                  child: _ScrollbarX(
                    fraction: _panPos,
                    viewportFraction: _viewportFractionX,
                    color: colorScheme.primary,
                  ),
                ),
              ),
            ],
          );
        } catch (e) {
          // Graceful error handling - nie crashuj aplikacji
          return Center(
            child: Text(
              'Błąd wyświetlania wykresu',
              style: TextStyle(color: colorScheme.error),
            ),
          );
        }
      },
    );
  }

  int _autoMaxPoints(double width) {
    // ✅ Z AppConfig - zmniejszono z 950 do 650 dla lepszej wydajności
    final v = (width * 0.9).round();
    return v.clamp(
      AppConfig.sensorChartMinPoints,
      AppConfig.sensorChartMaxPoints,
    );
  }

  /// ✅ Oblicz ładny interwał dla osi Y
  double _niceIntervalY(double rangeY) {
    if (rangeY == 0) return 1.0;

    // Znajdź rząd wielkości
    final magnitude = math
        .pow(10, (math.log(rangeY) / math.log(10)).floor())
        .toDouble();

    // Podziel zakres na ~4-5 sekcji
    final step = magnitude / 2;
    return step > 0 ? step : 1.0;
  }

  /// ✅ Dobiera ładny krok czasu (ms) dla osi X tak, by liczba etykiet
  /// była bliska `targetTickCount` w aktualnym oknie widoku.
  double _niceTimeIntervalMs(double windowMs, {int targetTickCount = 5}) {
    if (windowMs <= 0) {
      return const Duration(minutes: 1).inMilliseconds.toDouble();
    }

    final steps = <Duration>[
      const Duration(minutes: 1),
      const Duration(minutes: 2),
      const Duration(minutes: 5),
      const Duration(minutes: 10),
      const Duration(minutes: 15),
      const Duration(minutes: 30),
      const Duration(hours: 1),
      const Duration(hours: 2),
      const Duration(hours: 3),
      const Duration(hours: 6),
      const Duration(hours: 12),
      const Duration(days: 1),
      const Duration(days: 2),
      const Duration(days: 3),
      const Duration(days: 7),
      const Duration(days: 14),
      const Duration(days: 30),
      const Duration(days: 90),
      const Duration(days: 180),
      const Duration(days: 365),
    ].map((d) => d.inMilliseconds.toDouble()).toList();

    double best = steps.first;
    double bestScore = double.infinity;
    for (final s in steps) {
      final count = windowMs / s;
      if (count < 1) continue; // pomiń kroki większe niż okno (brak tytułów)
      final score = (count - targetTickCount).abs();
      if (score < bestScore) {
        bestScore = score;
        best = s;
      }
    }
    return best;
  }

  /// Largest-Triangle-Three-Buckets (LTTB)
  List<SensorSample> _downsampleLttb(
    List<SensorSample> data, {
    required int maxPoints,
  }) {
    if (maxPoints < 3) return data;
    if (data.length <= maxPoints) return data;

    final sampled = <SensorSample>[];
    sampled.add(data.first);

    final bucketCount = maxPoints - 2;
    final bucketSize = (data.length - 2) / bucketCount;

    int a = 0;

    for (int i = 0; i < bucketCount; i++) {
      final start = (1 + (i * bucketSize)).floor();
      final end = (1 + ((i + 1) * bucketSize)).floor().clamp(
        1,
        data.length - 1,
      );

      final nextStart = (1 + ((i + 1) * bucketSize)).floor();
      final nextEnd = (1 + ((i + 2) * bucketSize)).floor().clamp(
        1,
        data.length,
      );

      double avgX = 0;
      double avgY = 0;

      final avgRangeStart = nextStart.clamp(1, data.length - 1);
      final avgRangeEnd = nextEnd.clamp(1, data.length);
      final avgLen = math.max(1, avgRangeEnd - avgRangeStart);

      for (int j = avgRangeStart; j < avgRangeEnd; j++) {
        avgX += data[j].ts.millisecondsSinceEpoch.toDouble();
        avgY += data[j].value;
      }
      avgX /= avgLen;
      avgY /= avgLen;

      final ax = data[a].ts.millisecondsSinceEpoch.toDouble();
      final ay = data[a].value;

      double maxArea = -1;
      int maxAreaIndex = start;

      for (int j = start; j < end; j++) {
        final bx = data[j].ts.millisecondsSinceEpoch.toDouble();
        final by = data[j].value;

        final area = ((ax - avgX) * (by - ay) - (ax - bx) * (avgY - ay)).abs();
        if (area > maxArea) {
          maxArea = area;
          maxAreaIndex = j;
        }
      }

      sampled.add(data[maxAreaIndex]);
      a = maxAreaIndex;
    }

    sampled.add(data.last);
    return sampled;
  }
}

/// ✅ Scrollbar dla osi X
class _ScrollbarX extends StatelessWidget {
  const _ScrollbarX({
    required this.fraction,
    required this.viewportFraction,
    required this.color,
  });

  final double fraction; // 0..1
  final double viewportFraction; // 0..1
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _ScrollbarPainter(
        position: fraction,
        viewportFraction: viewportFraction,
        isHorizontal: true,
        color: color,
      ),
    );
  }
}

/// ✅ Custom painter dla scrollbarów
class _ScrollbarPainter extends CustomPainter {
  const _ScrollbarPainter({
    required this.position, // 0.0 - 1.0
    this.viewportFraction,
    required this.isHorizontal,
    required this.color,
  });

  final double position;
  final double? viewportFraction;
  final bool isHorizontal;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // Tło scrollbara
    final bgPaint = Paint()
      ..color = Colors.grey.withValues(alpha: 0.1)
      ..style = PaintingStyle.fill;

    if (isHorizontal) {
      canvas.drawRRect(
        RRect.fromLTRBR(
          0,
          0,
          size.width,
          size.height,
          const Radius.circular(4),
        ),
        bgPaint,
      );

      // Thumb (drażek)
      final vf = (viewportFraction ?? 0.3).clamp(0.05, 1.0);
      final thumbWidth = size.width * vf; // proporcja do okna
      final thumbX = (size.width - thumbWidth) * position;

      final thumbPaint = Paint()
        ..color = color.withValues(alpha: 0.6)
        ..style = PaintingStyle.fill;

      canvas.drawRRect(
        RRect.fromLTRBR(
          thumbX,
          0,
          thumbX + thumbWidth,
          size.height,
          const Radius.circular(4),
        ),
        thumbPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_ScrollbarPainter oldDelegate) {
    return oldDelegate.position != position ||
        oldDelegate.isHorizontal != isHorizontal ||
        oldDelegate.color != color;
  }
}
