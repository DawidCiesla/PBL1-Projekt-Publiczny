import 'package:flutter/material.dart';

import '../../../models/sensor.dart';
import '../../../models/thresholds.dart';

class ThresholdCard extends StatelessWidget {
  const ThresholdCard({
    super.key,
    required this.metric,
    required this.threshold,
    required this.formatter,
  });

  final SensorMetric metric;
  final MetricLimits threshold;
  final String Function(double?) formatter;

  IconData _iconFor(SensorMetric m) => switch (m) {
    SensorMetric.temperature => Icons.thermostat_rounded,
    SensorMetric.humidity => Icons.water_drop_rounded,
    SensorMetric.co2 => Icons.co2_rounded,
    SensorMetric.nh3 => Icons.science_rounded,
    SensorMetric.sunlight => Icons.wb_sunny_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = scheme.primary;
    final iconBackground = scheme.primaryContainer.withValues(alpha: 0.35);
    final borderColor = scheme.outlineVariant.withValues(alpha: 0.6);
    final neutralBadgeBg = scheme.surfaceContainerHighest.withValues(alpha: 0.65);
    final neutralBadgeFg = scheme.onSurfaceVariant;
    final unit = metric.unit;
    final parts = <String>[
      if (threshold.min != null) 'min: ${formatter(threshold.min)} $unit',
      if (threshold.max != null) 'max: ${formatter(threshold.max)} $unit',
      if (threshold.min == null && threshold.max == null) 'Brak danych',
    ];

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor, width: 1),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.surface,
            scheme.surfaceContainerHighest.withValues(alpha: 0.6),
          ],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: iconBackground,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(_iconFor(metric), color: accent, size: 26),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    metric.label,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: scheme.onSurface,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: parts.map((p) {
                      final bool isMin = p.startsWith('min');
                      final bool isMax = p.startsWith('max');
                      final Color bg = isMin
                        ? scheme.tertiaryContainer.withValues(alpha: 0.85)
                        : isMax
                          ? const Color(0xFFFFE7B8)
                          : neutralBadgeBg;
                      final Color fg = isMin
                        ? scheme.onTertiaryContainer
                        : isMax
                          ? const Color(0xFFB45A00)
                          : neutralBadgeFg;
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: bg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: fg.withValues(alpha: 0.28),
                            width: 1,
                          ),
                        ),
                        child: Text(
                          p,
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: fg,
                            letterSpacing: 0.2,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
