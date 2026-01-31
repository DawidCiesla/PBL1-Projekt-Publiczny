import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/endpoints.dart';
import '../../core/auth/auth_state.dart';

class NewFarmScreen extends ConsumerStatefulWidget {
  const NewFarmScreen({super.key, required this.topic});
  final String topic;

  @override
  ConsumerState<NewFarmScreen> createState() => _NewFarmScreenState();
}

class _NewFarmScreenState extends ConsumerState<NewFarmScreen> {
  final nameCtrl = TextEditingController();
  final locationCtrl = TextEditingController();
  bool loading = false;
  String? msg;

  @override
  void dispose() {
    nameCtrl.dispose();
    locationCtrl.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (loading) return;
    final name = nameCtrl.text.trim();
    final location = locationCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => msg = 'Nazwa kurnika jest wymagana');
      return;
    }

    setState(() {
      loading = true;
      msg = null;
    });

    final dio = ref.read(dioProvider);
    try {
      final res = await dio.post(Endpoints.farms, data: {
        'topic': widget.topic,
        'name': name,
        'location': location,
      });
      if (res.statusCode == 201 || (res.data != null && res.data is Map)) {
        if (!mounted) return;
        setState(() => msg = 'Utworzono kurnik');
        // return true to caller so it can refresh list
        Navigator.of(context).pop(true);
      } else {
        setState(() => msg = 'Nieoczekiwany wynik: ${res.statusCode}');
      }
    } on DioException catch (e) {
      String friendly = 'Błąd sieci';
      if (e.response?.statusCode == 400) friendly = 'Niepoprawne dane';
      if (e.response?.statusCode == 401) friendly = 'Brak uprawnień';
      if (e.response?.statusCode == 409) friendly = 'Kurnik o tym topicu już istnieje';
      setState(() => msg = friendly);
    } catch (e) {
      setState(() => msg = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nowy kurnik')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Topic:', style: Theme.of(context).textTheme.bodySmall),
                Text(widget.topic, style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Nazwa kurnika'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: locationCtrl,
                  decoration: const InputDecoration(labelText: 'Lokalizacja (opcjonalnie)'),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: loading ? null : _create,
                  child: loading ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator()) : const Text('Utwórz kurnik'),
                ),
                const SizedBox(height: 12),
                if (msg != null) Text(msg!, textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
