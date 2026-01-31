import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../models/chicken.dart';
import 'chicken_detail_screen.dart';

// Provider dla listy kur w danym kurnie
// ✅ autoDispose zwalnia pamięć gdy ekran jest zamknięty
final chickensProvider =
    FutureProvider.family.autoDispose<List<Chicken>, String>((ref, farmId) async {
  final repo = ref.watch(chickenRepoProvider);
  return repo.listChickens(farmId);
});

class ChickenListScreen extends ConsumerStatefulWidget {
  const ChickenListScreen({super.key, required this.farmId});

  final String farmId;

  @override
  ConsumerState<ChickenListScreen> createState() => _ChickenListScreenState();
}

class _ChickenListScreenState extends ConsumerState<ChickenListScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final chickensAsync = ref.watch(chickensProvider(widget.farmId));

    return RefreshIndicator(
      onRefresh: () async {
        return ref.refresh(chickensProvider(widget.farmId).future);
      },
      child: chickensAsync.when(
        data: (chickens) {
          if (chickens.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.close,
                    size: 64,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Brak kur w tym kurniku',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: Colors.grey[600],
                        ),
                  ),
                ],
              ),
            );
          }

          // Zlicz ile razy występuje każde imię, aby dodać sufiks (1,2,3...) przy duplikatach.
          final Map<String, int> nameCounts = {};
          for (final chicken in chickens) {
            final baseName = chicken.displayName;
            nameCounts[baseName] = (nameCounts[baseName] ?? 0) + 1;
          }
          final Map<String, int> nameSeen = {};

          return ListView.builder(
            itemCount: chickens.length,
            itemBuilder: (context, index) {
              final chicken = chickens[index];
              final baseName = chicken.displayName;
              final count = nameCounts[baseName] ?? 1;
              final occurrence = (nameSeen[baseName] ?? 0) + 1;
              nameSeen[baseName] = occurrence;
                // Pierwsze wystąpienie zostaw bez sufiksu, kolejne dostają (1), (2)...
                final displayName = count > 1 && occurrence > 1
                  ? '$baseName (${occurrence - 1})'
                  : baseName;
              
              // Określ kolor i ikonę bazując na trybie
              final Color iconColor;
              final Color bgColor;
              final IconData icon;
              
              if (chicken.lastMode == 1) {
                iconColor = Colors.blue;
                bgColor = Colors.blue.withValues(alpha: 0.2);
                icon = Icons.home;
              } else if (chicken.lastMode == 0) {
                iconColor = Colors.orange;
                bgColor = Colors.orange.withValues(alpha: 0.2);
                icon = Icons.park_rounded;
              } else {
                // Brak danych o trybie
                iconColor = Colors.grey;
                bgColor = Colors.grey.withValues(alpha: 0.2);
                icon = Icons.help_outline;
              }
              
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: ListTile(
                  leading: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: bgColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      icon,
                      color: iconColor,
                    ),
                  ),
                  title: Text(displayName),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      Text(
                        'Waga: ${chicken.weightText}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      Text(
                        'Status: ${chicken.modeText}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: chicken.lastMode == 1
                                  ? Colors.blue
                                  : chicken.lastMode == 0
                                      ? Colors.orange
                                      : Colors.grey,
                            ),
                      ),
                      if (chicken.lastEventTime != null)
                        Text(
                          'Ostatnia aktualizacja: ${_formatTime(chicken.lastEventTime!)}',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Colors.grey,
                              ),
                        ),
                    ],
                  ),
                  trailing: Icon(Icons.chevron_right,
                      color: Colors.grey[400]),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => ChickenDetailScreen(
                          farmId: widget.farmId,
                          chickenId: chicken.id, // Teraz String
                          chickenNumber: chicken.id, // Teraz String
                          initialName: displayName,
                        ),
                      ),
                    );
                  },
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
                'Błąd podczas ładowania kur',
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
                  ref.refresh(chickensProvider(widget.farmId).future).ignore();
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Spróbuj ponownie'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime dateTime) {
    final now = DateTime.now();
    final diff = now.difference(dateTime);

    if (diff.inMinutes < 1) {
      return 'Właśnie teraz';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes} min temu';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}h temu';
    } else {
      return '${dateTime.day}.${dateTime.month}.${dateTime.year}';
    }
  }
}
