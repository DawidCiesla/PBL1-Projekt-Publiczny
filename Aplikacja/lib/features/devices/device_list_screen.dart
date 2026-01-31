import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/providers.dart';
import '../../models/device.dart';

// ✅ Lista urządzeń
// Backend zwraca wszystkie device_id które mają telemetrykę (dane w kurniki_dane),
// z LEFT JOIN do tabeli devices dla name/paired_at.
//
// Devices z name=null to "cienie telemetrii" - mają historyczne dane ale nie są sparowane.
// Te są FILTROWANE w DeviceRepository.listDevices() zgodnie z instrukcją backendu:
// "UWAGA, jezeli nazwa równa się NULL interpretuj to jako brak urządzenia"
//
// Po DELETE urządzenia:
// - Wpis znika z tabeli devices (name staje się null)
// - Telemetria pozostaje w kurniki_dane
// - Endpoint /devices zwraca je z name=null
// - Frontend je filtruje → znikają z listy ✅
final devicesProvider = FutureProvider.family
    .autoDispose<List<DeviceModel>, String>((ref, farmId) async {
      return ref.watch(deviceRepoProvider).listDevices(farmId);
    });

class DeviceListScreen extends ConsumerStatefulWidget {
  const DeviceListScreen({super.key, required this.farmId});
  final String farmId;

  @override
  ConsumerState<DeviceListScreen> createState() => _DeviceListScreenState();
}

class _DeviceListScreenState extends ConsumerState<DeviceListScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final devices = ref.watch(devicesProvider(widget.farmId));

    return devices.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                'Błąd pobierania urządzeń:',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text('$e', textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => ref.invalidate(devicesProvider(widget.farmId)),
                icon: const Icon(Icons.refresh),
                label: const Text('Spróbuj ponownie'),
              ),
            ],
          ),
        ),
      ),
      data: (items) {
        if (items.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.devices_other, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text(
                    'Brak urządzeń',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Nie znaleziono żadnych urządzeń dla tego kurnika.\nMoże trzeba sparować nowe urządzenie?',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () => ref.invalidate(devicesProvider(widget.farmId)),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Odśwież'),
                  ),
                ],
              ),
            ),
          );
        }

        // Zlicz ile razy występuje każda nazwa, aby dodać sufiks (1,2,3...) przy duplikatach.
        final Map<String, int> nameCounts = {};
        for (final device in items) {
          final baseName = device.name;
          nameCounts[baseName] = (nameCounts[baseName] ?? 0) + 1;
        }
        final Map<String, int> nameSeen = {};

        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(devicesProvider(widget.farmId)),
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, i) {
              final d = items[i];
              final baseName = d.name;
              final count = nameCounts[baseName] ?? 1;
              final occurrence = (nameSeen[baseName] ?? 0) + 1;
              nameSeen[baseName] = occurrence;
              // Pierwsze wystąpienie zostaw bez sufiksu, kolejne dostają (1), (2)...
              final displayName = count > 1 && occurrence > 1
                  ? '$baseName (${occurrence - 1})'
                  : baseName;

              final statusColor = d.isOnline ? Colors.green : Colors.grey;
              final statusText = d.isOnline ? 'Online' : 'Offline';

              String lastSeenText = '';
              if (!d.isOnline && d.lastSeen != null) {
                final formatter = DateFormat('dd.MM.yyyy HH:mm');
                lastSeenText = 'Ostatnio: ${formatter.format(d.lastSeen!)}';
              }

              final rssiText = d.rssi != null ? 'RSSI: ${d.rssi} dBm' : '';
              final fwText = d.fw != null ? 'FW: ${d.fw}' : '';

              final roleText = d.role.label;

              return Card(
                child: ListTile(
                  leading: Icon(
                    d.role == DeviceRole.main
                        ? Icons.router_rounded
                        : Icons.memory_rounded,
                    size: 40,
                  ),
                  title: Text(
                    displayName,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: statusColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(statusText),
                          const SizedBox(width: 12),
                          Text(
                            roleText,
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                        ],
                      ),
                      if (lastSeenText.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          lastSeenText,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                      if (rssiText.isNotEmpty || fwText.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          [
                            rssiText,
                            fwText,
                          ].where((s) => s.isNotEmpty).join(' • '),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ),
                  isThreeLine: true,
                  trailing: Center(
                    widthFactor: 1,
                    child: Icon(
                      Icons.chevron_right,
                      color: Colors.grey[400],
                    ),
                  ),
                  onTap: () => _showDeviceDetails(context, ref, d, displayName),
                ),
              );
            },
          ),
        );
      },
    );
  }

  void _showDeviceDetails(BuildContext context, WidgetRef ref, DeviceModel device, String displayName) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (sheetContext, scrollController) => Container(
          padding: const EdgeInsets.all(16),
          child: ListView(
            controller: scrollController,
            children: [
              Row(
                children: [
                  Icon(
                    device.role == DeviceRole.main
                        ? Icons.router_rounded
                        : Icons.memory_rounded,
                    size: 48,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayName,
                          style: Theme.of(sheetContext).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                      ],
                    ),
                  ),
                ],
              ),
              const Divider(height: 32),
              _buildDetailRow(
                sheetContext,
                'Status',
                device.isOnline ? 'Online' : 'Offline',
                icon: Icons.power,
                valueColor: device.isOnline ? Colors.green : Colors.grey,
              ),
              _buildDetailRow(
                sheetContext,
                'Rola',
                device.role.label,
                icon: Icons.category_outlined,
              ),
              if (device.fw != null)
                _buildDetailRow(
                  sheetContext,
                  'Wersja firmware',
                  device.fw!,
                  icon: Icons.memory,
                ),
              if (device.rssi != null)
                _buildDetailRow(
                  sheetContext,
                  'Siła sygnału',
                  '${device.rssi} dBm',
                  icon: Icons.wifi,
                ),
              if (device.lastSeen != null && !device.isOnline)
                _buildDetailRow(
                  sheetContext,
                  'Ostatnia aktywność',
                  DateFormat('dd.MM.yyyy HH:mm:ss').format(device.lastSeen!),
                  icon: Icons.schedule,
                ),
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 8),
              // Akcje
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Zmień nazwę'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showRenameDialog(context, ref, device);
                },
              ),
              ListTile(
                leading: Icon(Icons.delete_outline, color: Colors.red[400]),
                title: Text('Usuń urządzenie', style: TextStyle(color: Colors.red[400])),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showDeleteDialog(context, ref, device);
                },
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () => Navigator.pop(sheetContext),
                icon: const Icon(Icons.close),
                label: const Text('Zamknij'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(
    BuildContext context,
    String label,
    String value, {
    IconData? icon,
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 20, color: Colors.grey[600]),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: Colors.grey[700],
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(fontWeight: FontWeight.w600, color: valueColor),
          ),
        ],
      ),
    );
  }

  Future<void> _showRenameDialog(
    BuildContext context,
    WidgetRef ref,
    DeviceModel device,
  ) async {
    final controller = TextEditingController(text: device.name);

    final newName = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Zmień nazwę urządzenia'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Nowa nazwa',
            hintText: 'np. Sensor Temp #1',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Anuluj'),
          ),
          FilledButton(
            onPressed: () {
              final val = controller.text.trim();
              // Walidacja - po prostu nie zamykaj dialogu jeśli puste
              if (val.isEmpty) {
                return;
              }
              if (val == device.name) {
                Navigator.pop(dialogContext);
                return;
              }
              Navigator.pop(dialogContext, val);
            },
            child: const Text('Zapisz'),
          ),
        ],
      ),
    );

    // ✅ Dispose controllera dopiero PO zamknięciu dialogu (po następnej klatce)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller.dispose();
    });

    if (newName == null || newName == device.name) return;
    
    if (!mounted) return;

    try {
      final deviceRepo = ref.read(deviceRepoProvider);
      
      if (device.farmId.isEmpty) {
        if (mounted && context.mounted) {
          try {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Błąd: brak ID kurnika')),
            );
          } catch (e) {
            // Ignoruj błędy ScaffoldMessenger
          }
        }
        return;
      }
      
      await deviceRepo.renameDevice(device.farmId, device.id, newName);

      if (!mounted || !context.mounted) return;
      
      try {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Nazwa zmieniona na "$newName"')),
        );
      } catch (e) {
        // Ignoruj błędy ScaffoldMessenger
      }
      
      ref.invalidate(devicesProvider(device.farmId));
    } on DioException catch (e) {
      if (!mounted || !context.mounted) return;
      final status = e.response?.statusCode;
      final code = e.response?.data is Map ? e.response?.data['error'] : null;
      String msg = 'Błąd: ${e.message}';
      if (status == 400 && code == 'missing_name') {
        msg = 'Brak pola name';
      } else if (status == 404) {
        msg = 'Nie znaleziono urządzenia lub brak dostępu';
      }
      try {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
        );
      } catch (e2) {
        // Ignoruj błędy ScaffoldMessenger
      }
    } catch (e) {
      if (!mounted || !context.mounted) return;
      try {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Błąd: $e')),
        );
      } catch (e2) {
        // Ignoruj błędy ScaffoldMessenger
      }
    }
  }

  void _showDeleteDialog(BuildContext context, WidgetRef ref, DeviceModel device) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Usuń urządzenie'),
        content: Text(
          'Czy na pewno chcesz usunąć urządzenie "${device.name}"?\n\n'
          'Usunięcie skasuje rekord urządzenia w tej farmie. Telemetria historyczna pozostanie.\n\n'
          '⚠️ Jeśli urządzenie wysyła dane MQTT, pojawi się ponownie na liście.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Anuluj'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              
              if (!context.mounted) return;
              
              try {
                final repo = ref.read(deviceRepoProvider);
                if (device.farmId.isEmpty) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Błąd: brak ID kurnika')),
                    );
                  }
                  return;
                }
                
                // Usuń na backendzie
                try {
                  await repo.deleteDevice(device.farmId, device.id);
                  
                  if (!context.mounted) return;
                  
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Urządzenie usunięte z bazy danych')),
                  );
                  
                  // Natychmiast odśwież aby usunąć z UI
                  ref.invalidate(devicesProvider(device.farmId));
                  
                  // Odśwież ponownie po 3 sekundach aby sprawdzić czy ESP nie wysłał nowych danych MQTT
                  await Future.delayed(const Duration(seconds: 3));
                  if (context.mounted) {
                    ref.invalidate(devicesProvider(device.farmId));
                  }
                } catch (e) {
                  if (!context.mounted) return;
                  
                  // Odśwież aby pokazać aktualny stan
                  ref.invalidate(devicesProvider(device.farmId));
                  
                  rethrow;
                }
              } on DioException catch (e) {
                if (!context.mounted) return;
                final status = e.response?.statusCode;
                final code = e.response?.data is Map ? e.response?.data['error'] : null;
                String msg = 'Błąd: ${e.message}';
                if (status == 404) msg = 'Nie znaleziono urządzenia lub brak uprawnień';
                if (status == 500 && code == 'delete_failed') msg = 'Nie udało się usunąć urządzenia';
                
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
                }
              } catch (e) {
                if (!context.mounted) return;
                
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Błąd: $e')),
                );
              }
            },
            child: const Text('Usuń'),
          ),
        ],
      ),
    );
  }
}
