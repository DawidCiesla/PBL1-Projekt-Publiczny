import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../../models/farm.dart';
import 'edit_farm_dialog.dart';

/// Compact farm card with readable text and no overflow.
class FarmCard extends ConsumerWidget {
  const FarmCard({super.key, required this.farm});

  final Farm farm;

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Usuń kurnik'),
        content: Text(
          'Czy na pewno chcesz usunąć kurnik "${farm.name}"?\n\n'
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

    if (confirmed != true || !context.mounted) return;

    try {
      final repo = ref.read(farmRepoProvider);
      await repo.deleteFarm(farm.id);
      ref.invalidate(farmsProvider);

      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Kurnik został usunięty')));
      }
    } on DioException catch (e) {
      if (!context.mounted) return;
      String msg = 'Błąd podczas usuwania';
      if (e.response?.statusCode == 403) msg = 'Brak uprawnień do usunięcia';
      if (e.response?.statusCode == 404) msg = 'Kurnik nie został znaleziony';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Błąd: $e'), backgroundColor: Colors.red),
      );
    }
  }

  void _showEditMenu(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_rounded),
              title: const Text('Edytuj kurnik'),
              onTap: () async {
                Navigator.of(ctx).pop();
                final updated = await showEditFarmDialog(context, farm);
                if (updated == true && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Zapisano zmiany')),
                  );
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.open_in_new_rounded),
              title: const Text('Otwórz'),
              onTap: () {
                Navigator.of(ctx).pop();
                context.go('/farms/${farm.id}');
              },
            ),
            const Divider(),
            ListTile(
              leading: Icon(
                Icons.delete_outline_rounded,
                color: theme.colorScheme.error,
              ),
              title: Text(
                'Usuń kurnik',
                style: TextStyle(color: theme.colorScheme.error),
              ),
              onTap: () {
                Navigator.of(ctx).pop();
                _confirmDelete(context, ref);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // ✅ Cache theme i colors na początku metody dla lepszej wydajności
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final textTheme = theme.textTheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        onTap: () => context.go('/farms/${farm.id}'),
        onLongPress: () => _showEditMenu(context, ref),
        child: Container(
          constraints: const BoxConstraints(minHeight: 150),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                colors.primaryContainer.withValues(alpha: 0.25),
                colors.surfaceContainerHighest.withValues(alpha: 0.08),
              ],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.warehouse_rounded,
                    size: 24,
                    color: colors.primary,
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      farm.name,
                      style:
                          textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.05,
                          ) ??
                          const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 15,
                          color: Colors.grey[600],
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            farm.location,
                            style:
                                textTheme.bodyMedium?.copyWith(
                                  color: Colors.grey[700],
                                  height: 1.2,
                                ) ??
                                const TextStyle(fontSize: 13),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
