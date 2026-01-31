import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth/auth_state.dart';

import '../../features/auth/login_screen.dart';
import '../../features/auth/splash_screen.dart';
import '../../features/auth/register_screen.dart';
import '../../features/home/home_shell.dart';
import '../../features/farms/farm_list_screen.dart';
import '../../features/farms/farm_detail_screen.dart';
import '../../features/devices/pair_device_screen.dart';
import '../../features/farms/pair_farm_screen.dart';
import '../../features/sensors/sensor_history_screen.dart';
import '../../features/alerts/alerts_screen.dart';
import '../../features/reports/reports_screen.dart';
import '../../features/settings/profile_screen.dart';

final routerRefreshProvider = Provider<ValueNotifier<int>>((ref) {
  final notifier = ValueNotifier<int>(0);

  // ✅ ping router tylko gdy zmienia się isAuthenticated lub isLoading
  // (nie przy błędzie logowania - żeby nie resetować strony)
  ref.listen(authControllerProvider, (prev, next) {
    // nie pinguj jeśli to dokładnie ten sam stan (np. rebuild)
    if (prev == next) return;
    
    final prevIsAuthed = prev?.value?.isAuthenticated;
    final nextIsAuthed = next.value?.isAuthenticated;
    final prevIsLoading = prev?.isLoading ?? false;
    final nextIsLoading = next.isLoading;
    
    // Pinguj tylko gdy zmienia się stan logowania lub ładowania
    if (prevIsAuthed != nextIsAuthed || prevIsLoading != nextIsLoading) {
      notifier.value++;
    }
  }, fireImmediately: true);

  ref.onDispose(notifier.dispose);
  return notifier;
});

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ref.watch(routerRefreshProvider);

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: refresh,
    debugLogDiagnostics: !kReleaseMode,
    redirectLimit: 10,
    redirect: (context, state) {
      // ✅ Używamy ref.read zamiast ref.watch - router sam odświeża się przez refreshListenable
      final auth = ref.read(authControllerProvider);
      
      final path = state.uri.path;
      final isLoggingIn = path == '/login';
      final isSplash = path == '/splash';
      final isRegistering = path == '/register';
      final isAuthScreen = isLoggingIn || isRegistering;

      // ✅ dopóki sprawdzamy token/me – trzymaj na splash
      if (auth.isLoading) {
        return isSplash ? null : '/splash';
      }

      // ✅ Jeśli jest błąd logowania i jesteśmy na ekranie auth, 
      // pozwól na nawigację między login a register
      if (auth.hasError && isAuthScreen) {
        return null;
      }

      final isAuthed = auth.value?.isAuthenticated == true;

      // ✅ niezalogowany -> trzymaj tylko na login/register
      if (!isAuthed) {
        return isAuthScreen ? null : '/login';
      }

      // ✅ zalogowany -> nie trzymaj na splash/login/register
      if (isAuthed && (isLoggingIn || isSplash || isRegistering)) {
        return '/farms';
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) {
          // Jeśli przychodzimy z ekranu rejestracji, wyczyść błąd
          final fromRegister = state.uri.queryParameters['from'] == 'register';
          return LoginScreen(clearError: fromRegister);
        },
      ),
      GoRoute(
        path: '/register',
        builder: (context, state) {
          // Jeśli przychodzimy z ekranu logowania, wyczyść błąd
          final fromLogin = state.uri.queryParameters['from'] == 'login';
          return RegisterScreen(clearError: fromLogin);
        },
      ),

      ShellRoute(
        builder: (context, state, child) => HomeShell(child: child),
        routes: [
          GoRoute(
            path: '/farms',
            builder: (context, state) => const FarmListScreen(),
            routes: [
              GoRoute(
                path: 'pair',
                builder: (context, state) => const PairFarmScreen(),
              ),
              GoRoute(
                path: ':farmId',
                builder: (context, state) {
                  final farmId = state.pathParameters['farmId'];
                  if (farmId == null || farmId.isEmpty) {
                    // ✅ guard na brak parametru
                    return const FarmListScreen();
                  }
                  return FarmDetailScreen(farmId: farmId);
                },
                routes: [
                  GoRoute(
                    path: 'pair',
                    builder: (context, state) {
                      final farmId = state.pathParameters['farmId'];
                      if (farmId == null || farmId.isEmpty) {
                        return const FarmListScreen();
                      }
                      return PairDeviceScreen(farmId: farmId);
                    },
                  ),
                  GoRoute(
                    path: 'history/:metric',
                    builder: (context, state) {
                      final farmId = state.pathParameters['farmId'];
                      final metric = state.pathParameters['metric'];

                      if (farmId == null || farmId.isEmpty) {
                        return const FarmListScreen();
                      }
                      if (metric == null || metric.isEmpty) {
                        // jak brak metryki, wróć do kurników
                        return FarmDetailScreen(farmId: farmId);
                      }

                      return SensorHistoryScreen(
                        farmId: farmId,
                        metric: metric,
                      );
                    },
                  ),
                ],
              ),
            ],
          ),

          GoRoute(
            path: '/alerts',
            builder: (context, state) => const AlertsScreen(),
          ),
          GoRoute(
            path: '/reports',
            builder: (context, state) => const ReportsScreen(),
          ),
          GoRoute(
            path: '/profile',
            builder: (context, state) => const ProfileScreen(),
          ),
        ],
      ),
    ],
  );
});