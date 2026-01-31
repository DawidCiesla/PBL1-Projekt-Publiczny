import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_state.dart';
import '../../core/theme/theme_provider.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Wylogować?'),
        content: const Text('Utracisz dostęp do danych do czasu ponownego logowania.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Anuluj')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Wyloguj')),
        ],
      ),
    );

    if (ok == true) {
      await ref.read(authControllerProvider.notifier).logout();
    }
  }

  Future<void> _showThemeModeDialog(
    BuildContext context,
    WidgetRef ref,
    ThemeMode currentMode,
  ) async {
    final selected = await showDialog<ThemeMode>(
      context: context,
      builder: (ctx) => _ThemeModeDialog(currentMode: currentMode),
    );

    if (selected != null && selected != currentMode) {
      await ref.read(themeModeProvider.notifier).setThemeMode(selected);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authAsync = ref.watch(
      authControllerProvider.select((async) => async),
    );
    final themeMode = ref.watch(themeModeProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Profil')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ═══════════════════════════════════════════════════════════════
          // SEKCJA: KONTO
          // ═══════════════════════════════════════════════════════════════
          _buildSectionHeader(context, 'Konto'),
          const SizedBox(height: 8),
          Card(
            child: authAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Nie udało się wczytać profilu.',
                      style: TextStyle(color: colorScheme.error),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      e.toString(),
                      style: Theme.of(context).textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => ref.invalidate(authControllerProvider),
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('Odśwież'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () => _confirmLogout(context, ref),
                            icon: const Icon(Icons.logout_rounded),
                            label: const Text('Wyloguj'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              data: (auth) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      leading: const Icon(Icons.person_rounded),
                      title: Text(auth.email ?? '—'),
                      subtitle: const Text('Konto użytkownika'),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.logout_rounded),
                      title: const Text('Wyloguj'),
                      onTap: () => _confirmLogout(context, ref),
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 24),

          // ═══════════════════════════════════════════════════════════════
          // SEKCJA: USTAWIENIA
          // ═══════════════════════════════════════════════════════════════
          _buildSectionHeader(context, 'Ustawienia'),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: Icon(
                    themeModeIcon(themeMode),
                    color: colorScheme.primary,
                  ),
                  title: const Text('Motyw aplikacji'),
                  subtitle: Text(themeModeLabel(themeMode)),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _showThemeModeDialog(context, ref, themeMode),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// DIALOG WYBORU MOTYWU
// ═══════════════════════════════════════════════════════════════════════════

class _ThemeModeDialog extends StatelessWidget {
  final ThemeMode currentMode;

  const _ThemeModeDialog({required this.currentMode});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return AlertDialog(
      title: const Text('Wybierz motyw'),
      contentPadding: const EdgeInsets.symmetric(vertical: 16),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: ThemeMode.values.map((mode) {
          final isSelected = mode == currentMode;
          return ListTile(
            leading: Icon(
              themeModeIcon(mode),
              color: isSelected ? colorScheme.primary : null,
            ),
            title: Text(
              themeModeLabel(mode),
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                color: isSelected ? colorScheme.primary : null,
              ),
            ),
            trailing: isSelected
                ? Icon(Icons.check_rounded, color: colorScheme.primary)
                : null,
            onTap: () => Navigator.pop(context, mode),
          );
        }).toList(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Anuluj'),
        ),
      ],
    );
  }
}