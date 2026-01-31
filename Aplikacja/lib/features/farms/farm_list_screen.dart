import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../devices/new_farm_screen.dart';
import '../devices/qr_scan_sheet.dart';
import '../devices/ble_provision_screen.dart';
import 'widgets/farm_card.dart';

// farmsProvider przeniesiony do core/providers.dart aby uniknąć cyklicznych importów

class FarmListScreen extends ConsumerWidget {
  const FarmListScreen({super.key});

  Future<void> _scanAndCreateFarm(BuildContext context, WidgetRef ref) async {
    final res = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const SizedBox(height: 520, child: QrScanSheet()),
    );
    if (res == null) return;
    var s = res.trim();
    try {
      final uri = Uri.tryParse(s);
      final qp = uri?.queryParameters;
      if (qp != null && qp['code'] != null && qp['code']!.trim().isNotEmpty) {
        s = qp['code']!.trim();
      }
    } catch (_) {}
    final topic = s.toUpperCase();

    // First provision device via BLE; if successful, open NewFarmScreen
    if (!context.mounted) return;
    final provisioned = await Navigator.of(context).push<bool?>(
      MaterialPageRoute(
        builder: (_) => BLEProvisionScreen(topic: topic),
      ),
    );
    if (!context.mounted) return;
    if (provisioned == true) {
      final created = await Navigator.of(context).push<bool?>(
        MaterialPageRoute(
          builder: (_) => NewFarmScreen(topic: topic),
        ),
      );
      if (!context.mounted) return;
      if (created == true) {
        ref.invalidate(farmsProvider);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Kurnik utworzony')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // ✅ Obserwuj tylko listę farm, nie przeładowuj całego providera
    final farms = ref.watch(
      farmsProvider.select((async) => async.whenData((f) => f)),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kurniki'),
        actions: [
          IconButton(
            tooltip: 'Skanuj i utwórz kurnik',
            icon: const Icon(Icons.qr_code_scanner_rounded),
            onPressed: () => _scanAndCreateFarm(context, ref),
          ),
        ],
      ),
      body: farms.when(
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
                onPressed: () => ref.invalidate(farmsProvider),
                icon: const Icon(Icons.refresh),
                label: const Text('Spróbuj ponownie'),
              ),
            ],
          ),
        ),
        data: (items) {
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(farmsProvider),
            child: items.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      const SizedBox(height: 120),
                      Center(
                        child: Column(
                          children: [
                            Icon(
                              Icons.warehouse_outlined,
                              size: 80,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Brak kurników',
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(color: Colors.grey[600]),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Dodaj swój pierwszy kurnik\nskanując kod QR',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey[600]),
                            ),
                            const SizedBox(height: 24),
                            FilledButton.icon(
                              onPressed: () => _scanAndCreateFarm(context, ref),
                              icon: const Icon(Icons.qr_code_scanner),
                              label: const Text('Skanuj kod QR'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final width = constraints.maxWidth;
                      // Responsywne kolumny: telefony = 2, tablety = 3–4
                      final crossAxisCount = width >= 1100
                          ? 4
                          : width >= 800
                              ? 3
                              : 2;
                      // Nieco szersze kafelki, aby zachować czytelność
                      final aspect = width >= 800 ? 1.35 : 1.25;
                      return GridView.builder(
                        padding: const EdgeInsets.all(16),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          mainAxisSpacing: 14,
                          crossAxisSpacing: 14,
                          childAspectRatio: aspect,
                        ),
                        itemCount: items.length,
                        itemBuilder: (context, i) {
                          final f = items[i];
                          return FarmCard(farm: f);
                        },
                      );
                    },
                  ),
          );
        },
      ),
    );
  }
}
