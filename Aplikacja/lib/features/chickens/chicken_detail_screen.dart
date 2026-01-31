import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../repositories/chicken_repository.dart';
import 'chicken_list_screen.dart';

// Provider dla zdarzeń kury
final chickenEventsProvider = FutureProvider.family<ChickenEventsResult,
    (String farmId, String chickenId)>((ref, params) async {
  final repo = ref.watch(chickenRepoProvider);
  final (farmId, chickenId) = params;
  return repo.getChickenEvents(
    farmId,
    chickenId,
    limit: 100,
  );
});

class ChickenDetailScreen extends ConsumerStatefulWidget {
  const ChickenDetailScreen({
    super.key,
    required this.farmId,
    required this.chickenId,
    required this.chickenNumber,
    this.initialName,
  });

  final String farmId;
  final String chickenId; // Zmienione z int na String - ID może być alfanumeryczne
  final String chickenNumber; // Zmienione z int na String - ID może być alfanumeryczne
  final String? initialName;

  @override
  ConsumerState<ChickenDetailScreen> createState() =>
      _ChickenDetailScreenState();
}

class _ChickenDetailScreenState extends ConsumerState<ChickenDetailScreen> {
  String? _overrideName;
  bool _isRenaming = false;

  @override
  Widget build(BuildContext context) {
    final eventsAsync = ref.watch(
      chickenEventsProvider((widget.farmId, widget.chickenId)),
    );

    final currentName = _overrideName ??
        eventsAsync.maybeWhen(
          data: (result) => result.name,
          orElse: () => null,
        ) ??
        widget.initialName ??
        'Kura #${widget.chickenNumber}';

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(currentName),
            Text(
              'ID: ${widget.chickenNumber}',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_note),
            tooltip: 'Zmień imię',
            onPressed: _isRenaming
                ? null
                : () => _showRenameDialog(context, currentName),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Usuń kurę',
            onPressed: () => _showDeleteDialog(context),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          return ref.refresh(
            chickenEventsProvider((widget.farmId, widget.chickenId)).future,
          );
        },
        child: eventsAsync.when(
          data: (result) {
            final events = result.events;

            if (events.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.history,
                      size: 64,
                      color: Colors.grey[400],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Brak zdarzeń dla tej kury',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: Colors.grey[600],
                          ),
                    ),
                  ],
                ),
              );
            }

            return ListView.builder(
              itemCount: events.length,
              itemBuilder: (context, index) {
                final event = events[index];
                return Card(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: ListTile(
                    leading: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: event.tryb == 1
                            ? Colors.blue.withValues(alpha: 0.2)
                            : Colors.orange.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        event.tryb == 1 ? Icons.home : Icons.park_rounded,
                        color: event.tryb == 1 ? Colors.blue : Colors.orange,
                      ),
                    ),
                    title: Text(event.trybText),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        Text(
                          'Waga: ${event.wagaText}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        Text(
                          _formatDateTime(event.eventTime),
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Colors.grey,
                              ),
                        ),
                      ],
                    ),
                    trailing: event.id != null
                        ? Text(
                            '#${event.id}',
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                  color: Colors.grey,
                                ),
                          )
                        : null,
                  ),
                );
              },
            );
          },
          loading: () => const Center(
            child: CircularProgressIndicator(),
          ),
          error: (err, stack) => Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 64,
                  color: Colors.red[400],
                ),
                const SizedBox(height: 16),
                Text(
                  'Błąd podczas ładowania zdarzeń',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: Colors.red[600],
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  err.toString(),
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () {
                    ref.refresh(
                      chickenEventsProvider(
                        (widget.farmId, widget.chickenId),
                      ).future,
                    ).ignore();
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Spróbuj ponownie'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showDeleteDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Usunąć kurę?'),
        content: Text(
          'Czy na pewno chcesz usunąć wszystkie zdarzenia dla kury #${widget.chickenNumber}? '
          'Tej operacji nie można cofnąć.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Anuluj'),
          ),
          TextButton(
            onPressed: () => _deleteChicken(context),
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            child: const Text('Usuń'),
          ),
        ],
      ),
    );
  }

  void _deleteChicken(BuildContext dialogContext) async {
    // Używamy kontekstu dialogu do zamknięcia popupu, a kontekstu stanu do wyjścia z ekranu.
    final rootNavigator = Navigator.of(dialogContext, rootNavigator: true);

    try {
      final repo = ref.read(chickenRepoProvider);
      await repo.deleteChicken(widget.farmId, widget.chickenId);

      if (!mounted) return;

      ref.refresh(chickensProvider(widget.farmId).future).ignore();

      // Najpierw zamykamy dialog, potem ekran szczegółów kury.
      rootNavigator.pop();
      Navigator.of(context).pop();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Kura została usunięta'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      // Jeśli dialog jest otwarty, zamknij go aby nie blokował dalszych działań.
      if (rootNavigator.canPop()) {
        rootNavigator.pop();
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Błąd: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.day}.${dateTime.month.toString().padLeft(2, '0')}.${dateTime.year} '
        '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}:${dateTime.second.toString().padLeft(2, '0')}';
  }

  Future<void> _showRenameDialog(BuildContext context, String currentName) async {
    final controller = TextEditingController(text: currentName);

    final newName = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Zmień imię kury'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'Imię',
              hintText: 'np. Basia',
            ),
            maxLength: 100,
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Anuluj'),
            ),
            TextButton(
              onPressed: () {
                final value = controller.text.trim();
                Navigator.of(dialogContext).pop(value);
              },
              child: const Text('Zapisz'),
            ),
          ],
        );
      },
    );

    if (newName != null && newName.trim().isNotEmpty) {
      await _renameChicken(newName.trim());
    }
  }

  Future<void> _renameChicken(String newName) async {
    setState(() {
      _isRenaming = true;
    });

    try {
      final repo = ref.read(chickenRepoProvider);
      final updatedName = await repo.renameChicken(
        widget.farmId,
        widget.chickenId,
        newName,
      );

      if (!mounted) return;

      setState(() {
        _overrideName = updatedName;
      });

      ref.refresh(chickensProvider(widget.farmId).future).ignore();
      ref.refresh(chickenEventsProvider((widget.farmId, widget.chickenId)).future).ignore();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Zmieniono imię na "$updatedName"'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Nie udało się zmienić imienia: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isRenaming = false;
        });
      }
    }
  }
}
