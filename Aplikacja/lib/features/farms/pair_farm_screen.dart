import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api/endpoints.dart';
import '../../core/auth/auth_state.dart';
import '../devices/qr_scan_sheet.dart';

class PairFarmScreen extends ConsumerStatefulWidget {
  const PairFarmScreen({super.key});

  @override
  ConsumerState<PairFarmScreen> createState() => _PairFarmScreenState();
}

class _PairFarmScreenState extends ConsumerState<PairFarmScreen> {
  final topicCtrl = TextEditingController();
  final nameCtrl = TextEditingController();
  final locationCtrl = TextEditingController();

  bool loading = false;
  String? msg;
  bool success = false;

  @override
  void dispose() {
    topicCtrl.dispose();
    nameCtrl.dispose();
    locationCtrl.dispose();
    super.dispose();
  }

  String _normalizeTopic(String raw) {
    var s = raw.trim();
    try {
      final uri = Uri.tryParse(s);
      if (uri != null) {
        final qp = uri.queryParameters;
        if (qp.containsKey('topic')) return qp['topic']!.trim();
        if (qp.containsKey('topic_id')) return qp['topic_id']!.trim();
      }
    } catch (_) {}
    return s;
  }

  Future<void> _scanQr() async {
    final res = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const SizedBox(height: 520, child: QrScanSheet()),
    );
    if (res == null) return;
    final topic = _normalizeTopic(res);
    topicCtrl.text = topic;
    setState(() => msg = null);
  }

  String _prettyError(Object e) {
    if (e is Exception) return e.toString();
    return e.toString();
  }

  Future<void> _createFarm() async {
    if (loading) return;
    final topic = topicCtrl.text.trim();
    final name = nameCtrl.text.trim();
    final location = locationCtrl.text.trim();

    if (topic.isEmpty || name.isEmpty) {
      setState(() {
        msg = 'Topic i nazwa są wymagane';
        success = false;
      });
      return;
    }

    setState(() {
      loading = true;
      msg = null;
      success = false;
    });

    try {
      final dio = ref.read(dioProvider);
      final res = await dio.post(
        Endpoints.farms,
        data: {'topic': topic, 'name': name, 'location': location},
      );

      final data = res.data;
      final id = data is Map
          ? (data['id'] ?? data['ID'] ?? data['kurnik_id'])
          : null;

      setState(() {
        msg = 'Kurnik dodany';
        success = true;
      });

      await Future.delayed(const Duration(milliseconds: 600));
      if (!mounted) return;

      if (id != null) {
        final sid = id.toString();
        // navigate to created farm
        if (context.mounted) context.go('/farms/$sid');
      } else {
        if (context.mounted) context.go('/farms');
      }
    } catch (e) {
      setState(() {
        msg = 'Błąd: ${_prettyError(e)}';
        success = false;
      });
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canSubmit =
        !loading &&
        topicCtrl.text.trim().isNotEmpty &&
        nameCtrl.text.trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('Dodaj kurnik (QR)')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Zeskanuj QR z modułu aby pobrać topic MQTT'),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: topicCtrl,
                        decoration: const InputDecoration(
                          labelText: 'MQTT topic',
                        ),
                        enabled: !loading,
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      onPressed: loading ? null : _scanQr,
                      icon: const Icon(Icons.qr_code_scanner_rounded),
                    ),
                  ],
                ),

                const SizedBox(height: 12),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Nazwa kurnika'),
                  enabled: !loading,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: locationCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Lokalizacja (opcjonalnie)',
                  ),
                  enabled: !loading,
                ),

                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: canSubmit ? _createFarm : null,
                  icon: loading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(),
                        )
                      : const Icon(Icons.add_rounded),
                  label: const Text('Utwórz kurnik'),
                ),

                const SizedBox(height: 12),
                if (msg != null)
                  Text(
                    msg!,
                    style: TextStyle(
                      color: success
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.error,
                    ),
                    textAlign: TextAlign.center,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
