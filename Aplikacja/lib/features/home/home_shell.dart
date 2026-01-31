import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class HomeShell extends StatelessWidget {
  const HomeShell({super.key, required this.child});
  final Widget child;

  static const _tabs = <_Tab>[
    _Tab('/farms', Icons.home_rounded, 'Kurniki'),
    _Tab('/alerts', Icons.notifications_rounded, 'Alerty'),
    _Tab('/reports', Icons.picture_as_pdf_rounded, 'Raporty'),
    _Tab('/profile', Icons.person_rounded, 'Profil'),
  ];

  int _locationToIndex(String path) {
    final idx = _tabs.indexWhere((t) => path.startsWith(t.path));
    return idx == -1 ? 0 : idx;
  }

  @override
  Widget build(BuildContext context) {
    final path = GoRouterState.of(context).uri.path;
    final index = _locationToIndex(path);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: RichText(
          text: TextSpan(
            style: TextStyle(
              fontFamily: 'Montserrat',
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: theme.brightness == Brightness.dark
                  ? const Color(0xFFFFFFFF)
                  : const Color(0xFF000000),
            ),
            children: [
              TextSpan(
                text: 'MacNugget',
              ),
              TextSpan(
                text: 'Net',
                style: TextStyle(
                  color: const Color(0xFF5CE1E6),
                ),
              ),
            ],
          ),
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: theme.colorScheme.surface,
      ),
      body: SafeArea(child: child),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) {
          final target = _tabs[i].path;
          // Nawiguj jeśli: inna sekcja LUB jesteśmy w pod-ścieżce (np. /farms/xyz -> /farms)
          if (path != target) {
            context.go(target);
          }
        },
        destinations: [
          for (final t in _tabs)
            NavigationDestination(
              icon: Icon(t.icon),
              label: t.label,
            ),
        ],
      ),
    );
  }
}

class _Tab {
  final String path;
  final IconData icon;
  final String label;

  const _Tab(this.path, this.icon, this.label);
}