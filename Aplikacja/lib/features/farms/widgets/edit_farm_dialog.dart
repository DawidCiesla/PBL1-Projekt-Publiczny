import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../../models/farm.dart';

/// Dialog do edycji nazwy i opisu kurnika
class EditFarmDialog extends ConsumerStatefulWidget {
  const EditFarmDialog({super.key, required this.farm});

  final Farm farm;

  @override
  ConsumerState<EditFarmDialog> createState() => _EditFarmDialogState();
}

class _EditFarmDialogState extends ConsumerState<EditFarmDialog> {
  late final TextEditingController nameCtrl;
  late final TextEditingController locationCtrl;
  bool loading = false;
  bool deleting = false;
  String? errorMsg;

  @override
  void initState() {
    super.initState();
    nameCtrl = TextEditingController(
      text: widget.farm.name == '—' ? '' : widget.farm.name,
    );
    locationCtrl = TextEditingController(text: widget.farm.location);
  }

  @override
  void dispose() {
    nameCtrl.dispose();
    locationCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (loading || deleting) return;

    final name = nameCtrl.text.trim();
    final location = locationCtrl.text.trim();

    if (name.isEmpty) {
      setState(() => errorMsg = 'Nazwa kurnika jest wymagana');
      return;
    }

    setState(() {
      loading = true;
      errorMsg = null;
    });

    try {
      final repo = ref.read(farmRepoProvider);
      await repo.updateFarm(widget.farm.id, name: name, location: location);

      // Odśwież listę kurników
      ref.invalidate(farmsProvider);

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on DioException catch (e) {
      String friendly = 'Błąd podczas zapisywania';
      if (e.response?.statusCode == 400) friendly = 'Niepoprawne dane';
      if (e.response?.statusCode == 401) friendly = 'Brak uprawnień';
      if (e.response?.statusCode == 404) {
        friendly = 'Kurnik nie został znaleziony';
      }
      setState(() => errorMsg = friendly);
    } catch (e) {
      setState(() => errorMsg = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Usuń kurnik'),
        content: Text(
          'Czy na pewno chcesz usunąć kurnik "${widget.farm.name}"?\n\n'
          'Ta operacja jest nieodwracalna i spowoduje usunięcie wszystkich powiązanych danych.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Anuluj'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Usuń'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    await _deleteFarm();
  }

  Future<void> _deleteFarm() async {
    if (loading || deleting) return;

    setState(() {
      deleting = true;
      errorMsg = null;
    });

    try {
      final repo = ref.read(farmRepoProvider);
      await repo.deleteFarm(widget.farm.id);

      // Odśwież listę kurników
      ref.invalidate(farmsProvider);

      if (!mounted) return;

      // Zamknij dialog
      Navigator.of(context).pop('deleted');

      // Przekieruj na listę kurników
      if (context.mounted) {
        context.go('/farms');
      }
    } on DioException catch (e) {
      String friendly = 'Błąd podczas usuwania';
      if (e.response?.statusCode == 403) {
        friendly = 'Brak uprawnień do usunięcia';
      }
      if (e.response?.statusCode == 404) {
        friendly = 'Kurnik nie został znaleziony';
      }
      setState(() => errorMsg = friendly);
    } catch (e) {
      setState(() => errorMsg = e.toString());
    } finally {
      if (mounted) setState(() => deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isProcessing = loading || deleting;

    return AlertDialog(
      title: const Text('Edytuj kurnik'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Nazwa kurnika',
                hintText: 'np. Kurnik główny',
                prefixIcon: Icon(Icons.warehouse_rounded),
              ),
              textCapitalization: TextCapitalization.sentences,
              enabled: !isProcessing,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: locationCtrl,
              decoration: const InputDecoration(
                labelText: 'Opis / Lokalizacja',
                hintText: 'np. ul. Wiejska 15',
                prefixIcon: Icon(Icons.location_on_outlined),
              ),
              textCapitalization: TextCapitalization.sentences,
              enabled: !isProcessing,
              maxLines: 2,
            ),
            if (errorMsg != null) ...[
              const SizedBox(height: 16),
              Text(
                errorMsg!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
                side: BorderSide(
                  color: theme.colorScheme.error.withValues(alpha: 0.5),
                ),
              ),
              onPressed: isProcessing ? null : _confirmDelete,
              icon: deleting
                  ? SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: theme.colorScheme.error,
                      ),
                    )
                  : const Icon(Icons.delete_outline_rounded),
              label: Text(deleting ? 'Usuwanie...' : 'Usuń kurnik'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: isProcessing
              ? null
              : () => Navigator.of(context).pop(false),
          child: const Text('Anuluj'),
        ),
        FilledButton(
          onPressed: isProcessing ? null : _save,
          child: loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Zapisz'),
        ),
      ],
    );
  }
}

/// Funkcja pomocnicza do wyświetlenia dialogu edycji
Future<bool?> showEditFarmDialog(BuildContext context, Farm farm) {
  return showDialog<bool>(
    context: context,
    builder: (context) => EditFarmDialog(farm: farm),
  );
}
