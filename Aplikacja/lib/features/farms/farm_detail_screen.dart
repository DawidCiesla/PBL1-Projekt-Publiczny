import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../core/providers.dart';
import '../../models/farm.dart';
import '../sensors/sensors_dashboard_screen.dart';
import '../devices/device_list_screen.dart';
import '../settings/thresholds_screen.dart';
import '../chickens/chicken_list_screen.dart';
import 'widgets/edit_farm_dialog.dart';

class FarmDetailScreen extends ConsumerStatefulWidget {
  const FarmDetailScreen({super.key, required this.farmId});

  final String farmId;

  @override
  ConsumerState<FarmDetailScreen> createState() => _FarmDetailScreenState();
}

class _FarmDetailScreenState extends ConsumerState<FarmDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(_onTabChanged);
  }

  void _onTabChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void didUpdateWidget(covariant FarmDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    // ✅ zmiana kurnika → wracamy na Dashboard
    if (oldWidget.farmId != widget.farmId) {
      _tabController.index = 0;
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final farmsAsync = ref.watch(farmsProvider);

    String farmName = 'Kurnik';
    Farm? currentFarm;
    farmsAsync.whenData((farms) {
      final farm = farms.cast<Farm?>().firstWhere(
        (f) => f?.id == widget.farmId,
        orElse: () => null,
      );
      if (farm != null) {
        currentFarm = farm;
        if (farm.name.isNotEmpty && farm.name != '—') {
          farmName = 'Kurnik - ${farm.name}';
        }
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(farmName),
        actions: [
          if (currentFarm != null)
            IconButton(
              tooltip: 'Edytuj kurnik',
              icon: const Icon(Icons.edit_rounded),
              onPressed: () async {
                final updated = await showEditFarmDialog(context, currentFarm!);
                if (updated == true && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Zapisano zmiany')),
                  );
                }
              },
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelPadding: const EdgeInsets.symmetric(vertical: 10),
          tabs: const [
            Tab(
              icon: Icon(Icons.dashboard_customize_rounded),
              text: 'Dashboard',
            ),
            Tab(icon: Icon(Icons.memory_rounded), text: 'Urządzenia'),
            Tab(
              icon: FaIcon(FontAwesomeIcons.kiwiBird, size: 20),
              text: 'Kury',
            ),
            Tab(icon: Icon(Icons.tune_rounded), text: 'Normy'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          SensorsDashboardScreen(
            key: PageStorageKey('sensors_${widget.farmId}'),
            farmId: widget.farmId,
            active: _tabController.index == 0,
          ),
          DeviceListScreen(
            key: PageStorageKey('devices_${widget.farmId}'),
            farmId: widget.farmId,
          ),
          ChickenListScreen(
            key: PageStorageKey('chickens_${widget.farmId}'),
            farmId: widget.farmId,
          ),
          ThresholdsScreen(
            key: PageStorageKey('thresholds_${widget.farmId}'),
            farmId: widget.farmId,
          ),
        ],
      ),
    );
  }
}
