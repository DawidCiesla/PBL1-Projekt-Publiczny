import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../models/alert.dart';
import '../../models/farm.dart';
import '../../models/sensor.dart';
import '../../models/thresholds.dart';

DateTime? _parseTs(dynamic rawTs) {
  if (rawTs == null) return null;
  if (rawTs is DateTime) return rawTs;
  if (rawTs is num) {
    final n = rawTs.toInt();
    return n > 1000000000000
        ? DateTime.fromMillisecondsSinceEpoch(n, isUtc: true).toLocal()
        : DateTime.fromMillisecondsSinceEpoch(n * 1000, isUtc: true).toLocal();
  }
  return DateTime.tryParse(rawTs.toString())?.toLocal();
}

double? _numVal(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}

AlertModel? _buildAlertForMetric({
  required Farm farm,
  required SensorMetric metric,
  required double? value,
  required MetricLimits? limits,
  required DateTime ts,
}) {
  if (value == null || limits == null) return null;

  final min = limits.min;
  final max = limits.max;

  String? direction;
  if (min != null && value < min) direction = 'low';
  if (max != null && value > max) direction = 'high';
  if (direction == null) return null; // w normie

  final label = metric.label;
  final unit = metric.unit;

  String titleSuffix;
  switch (metric) {
    case SensorMetric.co2:
    case SensorMetric.nh3:
      titleSuffix = direction == 'high' ? 'za wysokie stężenie' : 'za niskie stężenie';
      break;
    case SensorMetric.humidity:
      titleSuffix = direction == 'high' ? 'za wysoka' : 'za niska';
      break;
    case SensorMetric.temperature:
      titleSuffix = direction == 'high' ? 'za wysoka' : 'za niska';
      break;
    case SensorMetric.sunlight:
      titleSuffix = direction == 'high' ? 'za wysokie' : 'za niskie';
      break;
  }

  String fmt(double? v) {
    if (v == null) return '—';
    final isInt = v % 1 == 0;
    return v.toStringAsFixed(isInt ? 0 : 1);
  }

  String limitText;
  if (min != null && max != null) {
    limitText = '${fmt(min)}–${fmt(max)} $unit';
  } else if (min != null) {
    limitText = 'min ${fmt(min)} $unit';
  } else if (max != null) {
    limitText = 'max ${fmt(max)} $unit';
  } else {
    limitText = 'brak normy';
  }

  final message = '$label: ${fmt(value)} $unit, norma: $limitText';

  final id = 'gen_${farm.id}_${metric.key}_${ts.millisecondsSinceEpoch}';

  return AlertModel(
    id: id,
    farmId: farm.id,
    farmName: farm.name,
    title: titleSuffix,
    message: message,
    ts: ts,
    acknowledged: false,
    normSection: label,
  );
}

// ✅ Alerty: generowane na podstawie aktualnych odczytów i norm
// Tylko dla kurników które mają przynajmniej jedno urządzenie online
final alertsProvider = FutureProvider.autoDispose<List<AlertModel>>((
  ref,
) async {
  // 1) pobierz kurniki
  final farms = await ref.watch(farmRepoProvider).listFarms();
  final sensorRepo = ref.watch(sensorRepoProvider);
  final thresholdsRepo = ref.watch(thresholdsRepoProvider);
  final deviceRepo = ref.watch(deviceRepoProvider);

  if (farms.isEmpty) return [];

  // 2) generuj alerty lokalnie na podstawie odczytów i norm
  final generated = <AlertModel>[];

  for (final farm in farms) {
    try {
      // ✅ Sprawdź czy kurnik ma przynajmniej jedno urządzenie online
      final devices = await deviceRepo.listDevices(farm.id);
      final hasOnlineDevice = devices.any((d) => d.isOnline);
      
      // Jeśli żadne urządzenie nie jest online, pomijamy alerty dla tego kurnika
      if (!hasOnlineDevice) {
        continue;
      }
      
      final thresholds = await thresholdsRepo.getThresholds(farm.id);
      final live = await sensorRepo.fetchLive(farm.id);
      final liveTs = _parseTs(live['ts']) ?? DateTime.now();

      for (final metric in SensorMetric.values) {
        final value = _numVal(live[metric.key]);
        final limits = thresholds.byMetric[metric];
        final alert = _buildAlertForMetric(
          farm: farm,
          metric: metric,
          value: value,
          limits: limits,
          ts: liveTs,
        );
        if (alert != null) {
          generated.add(alert);
        }
      }
    } catch (_) {
      // ignorujemy pojedyncze błędy aby nie zabić listy
      continue;
    }
  }

  // 3) sort: najnowsze na górze
  generated.sort((a, b) => b.ts.compareTo(a.ts));
  return generated;
});

class AlertsScreen extends ConsumerStatefulWidget {
  const AlertsScreen({super.key});

  @override
  ConsumerState<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends ConsumerState<AlertsScreen> {
  String? _filterSection; // ✅ Filtr po sekcji normy (np. "Temperatura")

  @override
  Widget build(BuildContext context) {
    final alertsAsync = ref.watch(alertsProvider);
    final currentAlerts = alertsAsync.asData?.value ?? [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Alerty'),
        actions: [
          // ✅ Dynamiczny filtr sekcji norm
          _buildSectionFilterMenu(currentAlerts),
        ],
      ),
      body: alertsAsync.when(
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
                onPressed: () => ref.invalidate(alertsProvider),
                icon: const Icon(Icons.refresh),
                label: const Text('Spróbuj ponownie'),
              ),
            ],
          ),
        ),
        data: (items) => _buildAlertsList(items),
      ),
    );
  }

  Widget _buildAlertsList(List<AlertModel> items) {
    // ✅ Filtruj po sekcji normy jeśli wybrana
    final filtered = _filterSection == null
        ? items
        : items.where((a) => a.normSection == _filterSection).toList();
    
    // ✅ Cache MediaQuery na początku metody - jedno wywołanie
    final screenSize = MediaQuery.sizeOf(context);
    final screenWidth = screenSize.width;
    final screenHeight = screenSize.height;

    if (filtered.isEmpty) {
      return RefreshIndicator(
        onRefresh: () async => ref.invalidate(alertsProvider),
        strokeWidth: 0,
        color: Colors.transparent,
        backgroundColor: Colors.transparent,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.symmetric(
            horizontal: screenWidth > 600 ? 32 : 16,
            vertical: 16,
          ),
          children: [
            SizedBox(height: screenHeight * 0.15),
            Center(
              child: Column(
                children: [
                  Icon(
                    Icons.notifications_off_outlined,
                    size: screenWidth > 600 ? 100 : 80,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Brak alertów',
                    style: Theme.of(context).textTheme.headlineSmall
                        ?.copyWith(color: Colors.grey[600]),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Wszystko działa prawidłowo ✅',
                    style: TextStyle(color: Colors.grey[600]),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final horizontalPadding = screenWidth > 600 ? 32.0 : 16.0;

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(alertsProvider),
      strokeWidth: 0,
      color: Colors.transparent,
      backgroundColor: Colors.transparent,
      child: ListView.separated(
        padding: EdgeInsets.all(horizontalPadding),
        itemCount: filtered.length,
        separatorBuilder: (context, index) => const SizedBox(height: 12),
        itemBuilder: (context, i) => _AlertCard(alert: filtered[i]),
      ),
    );
  }

  // ✅ Buduj dynamiczne menu filtrowania sekcji norm
  Widget _buildSectionFilterMenu(List<AlertModel> alerts) {
    // ✅ Predefiniowane sekcje norm na podstawie SensorMetric
    final allSections = [
      'Temperatura',
      'Wilgotność',
      'CO₂',
      'Amoniak (NH₃)',
      'Nasłonecznienie',
    ];

    // Zbierz które sekcje faktycznie mają alerty
    final activeSections = <String>{};
    for (final alert in alerts) {
      if (alert.normSection != null && alert.normSection!.isNotEmpty) {
        activeSections.add(alert.normSection!);
      }
    }

    // ✅ MediaQuery.sizeOf jest bardziej wydajne
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isSmallScreen = screenWidth < 400;

    return PopupMenuButton<String?>(
      icon: const Icon(Icons.tune_rounded),
      tooltip: 'Filtruj po sekcji normy',
      onSelected: (value) => setState(() => _filterSection = value),
      itemBuilder: (context) => [
        // Opcja "Wszystkie"
        PopupMenuItem<String?>(
          value: null,
          onTap: () => setState(() => _filterSection = null),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.all_inclusive, size: 20),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  'Wszystkie sekcje',
                  style: TextStyle(
                    fontWeight: _filterSection == null ? FontWeight.w700 : null,
                    fontSize: isSmallScreen ? 13 : 14,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(height: 8),
        // Wszystkie sekcje (aktywne pokazane w boldzie)
        ...allSections.map((section) {
          final count = alerts.where((a) => a.normSection == section).length;
          final isActive = activeSections.contains(section);
          
          // ✅ Ikony współgrające z kurnikami
          final IconData sectionIcon = switch (section) {
            'Temperatura' => Icons.thermostat_rounded,
            'Wilgotność' => Icons.water_drop_rounded,
            'CO₂' => Icons.co2_rounded,
            'Amoniak (NH₃)' => Icons.science_rounded,
            'Nasłonecznienie' => Icons.wb_sunny_rounded,
            _ => Icons.tune_rounded,
          };
          
          return PopupMenuItem(
            value: section,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    sectionIcon,
                    size: 18,
                    color: isActive ? null : Colors.grey[400],
                  ),
                  const SizedBox(width: 12),
                  Text(
                    section,
                    style: TextStyle(
                      fontWeight: _filterSection == section ? FontWeight.w700 : null,
                      color: isActive ? null : Colors.grey[500],
                      fontSize: isSmallScreen ? 13 : 14,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (count > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        count.toString(),
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }
}

class _AlertCard extends StatefulWidget {
  const _AlertCard({required this.alert});

  final AlertModel alert;

  @override
  State<_AlertCard> createState() => _AlertCardState();
}

class _AlertCardState extends State<_AlertCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final alert = widget.alert;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final leadingIcon = _sectionIcon(alert.normSection);
    final leadingColor = _sectionColor(alert.normSection, colorScheme);
    // ✅ MediaQuery.sizeOf jest bardziej wydajne
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isSmallScreen = screenWidth < 400;
    final isMediumScreen = screenWidth < 600;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outline.withValues(alpha: 0.2), width: 1),
      ),
      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      child: Column(
        children: [
            ListTile(
              contentPadding: EdgeInsets.fromLTRB(
                isSmallScreen ? 12 : 16,
                isSmallScreen ? 8 : 8,
                isSmallScreen ? 4 : 8,
                isSmallScreen ? 8 : 8,
              ),
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: leadingColor.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  leadingIcon,
                  color: leadingColor,
                  size: isSmallScreen ? 24 : 28,
                ),
              ),
              title: Text(
                _titleWithSection(alert),
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: isSmallScreen ? 14 : 16,
                ),
                maxLines: isMediumScreen ? 2 : 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.access_time,
                        size: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          _formatTimestampDetailed(alert.ts),
                          style: TextStyle(
                            fontSize: 11,
                            color: colorScheme.onSurfaceVariant,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  if ((alert.farmName != null && alert.farmName!.isNotEmpty) ||
                      alert.farmId.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.warehouse_outlined,
                          size: 12,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            alert.farmName ??
                                (alert.farmId.isNotEmpty
                                    ? 'Kurnik #${alert.farmId}'
                                    : 'Kurnik'),
                            style: TextStyle(
                              fontSize: 11,
                              color: colorScheme.onSurfaceVariant,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
              trailing: IconButton(
                icon: Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  size: isSmallScreen ? 20 : 24,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                onPressed: () => setState(() => _expanded = !_expanded),
              ),
            ),
            if (_expanded) ...[
              const Divider(height: 1),
              Padding(
                padding: EdgeInsets.all(isSmallScreen ? 12 : 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (alert.message.isNotEmpty) ...[
                      Text(
                        'Szczegóły',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          fontSize: isSmallScreen ? 12 : 14,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: EdgeInsets.all(isSmallScreen ? 10 : 12),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          alert.message,
                          style: TextStyle(
                            color: colorScheme.onSurfaceVariant,
                            height: 1.4,
                            fontSize: isSmallScreen ? 12 : 13,
                          ),
                        ),
                      ),
                    ] else
                      Text(
                        'Brak dodatkowych szczegółów',
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                          fontStyle: FontStyle.italic,
                          fontSize: isSmallScreen ? 12 : 13,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
    );
  }

  String _formatTimestamp(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inMinutes < 1) return 'Teraz';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min temu';
    if (diff.inHours < 24) return '${diff.inHours} godz. temu';
    if (diff.inDays == 1) return 'Wczoraj';
    return '${diff.inDays} dni temu';
  }

  String _formatTimestampDetailed(DateTime dt) {
    // Wyłącznie względny czas, bez daty absolutnej
    return _formatTimestamp(dt);
  }

  String _titleWithSection(AlertModel alert) {
    final section = alert.normSection?.trim();
    if (section == null || section.isEmpty) return alert.title;

    final title = alert.title.trim();
    final lowerSection = section.toLowerCase();
    var suffix = title;

    // jeśli tytuł zaczyna się od sekcji, usuń duplikat
    if (title.toLowerCase().startsWith(lowerSection)) {
      suffix = title.substring(section.length).trimLeft();
    }

    // spłaszcz pierwszą literę w suffiksie, żeby brzmiało "za wysokie/za niskie"
    if (suffix.isNotEmpty) {
      suffix = suffix[0].toLowerCase() + suffix.substring(1);
    }

    return suffix.isNotEmpty ? '$section - $suffix' : section;
  }

  IconData _sectionIcon(String? section) {
    switch (section) {
      case 'Temperatura':
        return Icons.thermostat_rounded;
      case 'Wilgotność':
        return Icons.water_drop_rounded;
      case 'CO₂':
        return Icons.co2_rounded;
      case 'Amoniak (NH₃)':
        return Icons.science_rounded;
      case 'Nasłonecznienie':
        return Icons.wb_sunny_rounded;
      default:
        return Icons.notifications_active_rounded;
    }
  }

  Color _sectionColor(String? section, ColorScheme scheme) {
    switch (section) {
      case 'Temperatura':
        return Colors.deepOrange;
      case 'Wilgotność':
        return Colors.blue;
      case 'CO₂':
        return Colors.teal;
      case 'Amoniak (NH₃)':
        return Colors.purple;
      case 'Nasłonecznienie':
        return Colors.amber[800] ?? scheme.primary;
      default:
        return scheme.primary;
    }
  }
}
