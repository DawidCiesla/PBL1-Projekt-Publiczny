import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pretty_dio_logger/pretty_dio_logger.dart';

import '../api/endpoints.dart';
import '../config/app_config.dart';
import '../providers.dart';
import 'auth_repository.dart';

class AuthState {
  final bool isAuthenticated;
  final String? email;
  final DateTime? lastLoginTime;

  const AuthState({
    required this.isAuthenticated,
    this.email,
    this.lastLoginTime,
  });

  /// Ile czasu użytkownik pozostał zalogowany
  Duration? get sessionDuration {
    if (!isAuthenticated || lastLoginTime == null) return null;
    return DateTime.now().difference(lastLoginTime!);
  }
}

/// ✅ Jedno źródło prawdy dla SecureStorage (te same opcje wszędzie)
final secureStorageProvider = Provider<FlutterSecureStorage>((ref) {
  return const FlutterSecureStorage(
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
});

final dioProvider = Provider<Dio>((ref) {
  final storage = ref.watch(secureStorageProvider);

  final baseOptions = BaseOptions(
    baseUrl: Endpoints.baseUrl,
    connectTimeout: AppConfig.apiTimeout,
    receiveTimeout: AppConfig.apiTimeout,
  );

  final dio = Dio(baseOptions);

  Completer<bool>? refreshingCompleter;

  Future<void> clearSession() async {
    await Future.wait([
      storage.delete(key: AuthRepository.tokenKey),
      storage.delete(key: AuthRepository.emailKey),
      storage.delete(key: AuthRepository.lastLoginKey),
      storage.delete(key: AuthRepository.refreshTokenKey),
    ]);

    // wymuś ponowną ocenę stanu auth (router przełączy widok)
    ref.invalidate(authControllerProvider);
  }

  Future<bool> refreshAccessToken() async {
    if (refreshingCompleter != null) {
      // Dodaj timeout aby uniknąć nieskończonego czekania
      return refreshingCompleter!.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () => false,
      );
    }

    final completer = Completer<bool>();
    refreshingCompleter = completer;

    final repo = AuthRepository(dio, storage: storage);

    unawaited(
      repo
          .refreshToken()
          .then((value) {
            if (!completer.isCompleted) completer.complete(value);
          })
          .catchError((_) {
            if (!completer.isCompleted) completer.complete(false);
          })
          .whenComplete(() {
            if (identical(refreshingCompleter, completer)) {
              refreshingCompleter = null;
            }
          }),
    );

    return completer.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () {
        if (!completer.isCompleted) completer.complete(false);
        return false;
      },
    );
  }

  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) async {
        try {
          final raw = await storage.read(key: AuthRepository.tokenKey);
          final token = raw?.trim(); // ✅ usuwa \n, spacje, dziwne końcówki

          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
        } catch (_) {}
        handler.next(options);
      },
      onError: (err, handler) async {
        final is401 = err.response?.statusCode == 401;
        final skipRefresh = err.requestOptions.extra['skipRefresh'] == true;

        if (!is401 || skipRefresh) {
          handler.next(err);
          return;
        }

        final refreshed = await refreshAccessToken();

        if (refreshed) {
          final token = await storage.read(key: AuthRepository.tokenKey);

          try {
            final retryOptions = err.requestOptions
              ..headers['Authorization'] = token != null
                  ? 'Bearer ${token.trim()}'
                  : null
              ..extra['skipRefresh'] = true;

            final response = await dio.fetch(retryOptions);
            handler.resolve(response);
            return;
          } catch (retryError) {
            // Tylko wyczyść sesję jeśli retry też zwrócił 401
            if (retryError is DioException &&
                retryError.response?.statusCode == 401) {
              await clearSession();
            }
            handler.reject(retryError is DioException ? retryError : err);
            return;
          }
        } else {
          // Refresh nie powiódł się - sprawdź czy mamy zapisanego użytkownika
          // Nie wylogowuj od razu - może to problem z siecią
          final savedEmail = await storage.read(key: AuthRepository.emailKey);
          if (savedEmail == null) {
            // Brak zapisanych danych - wyloguj
            await clearSession();
          }
        }

        handler.next(err);
      },
    ),
  );

  if (!kReleaseMode) {
    dio.interceptors.add(
      PrettyDioLogger(
        requestHeader: true,
        requestBody: true,
        responseHeader: false,
        responseBody: true,
        error: true,
        compact: true,
        maxWidth: 120,
      ),
    );
  }

  return dio;
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final dio = ref.watch(dioProvider);
  final storage = ref.watch(secureStorageProvider);
  return AuthRepository(dio, storage: storage);
});

final authControllerProvider = AsyncNotifierProvider<AuthController, AuthState>(
  AuthController.new,
);

class AuthController extends AsyncNotifier<AuthState> {
  @override
  Future<AuthState> build() async {
    final repo = ref.read(authRepositoryProvider);

    final token = await repo.getToken();
    if (token == null || token.isEmpty) {
      return const AuthState(isAuthenticated: false);
    }

    // Mamy token - pobierz zapisane dane użytkownika
    final savedEmail = await repo.getEmail();
    final lastLoginTime = await repo.getLastLoginTime();

    try {
      // Spróbuj pobrać dane użytkownika (wymaga internetu)
      final me = await repo.me();
      final email = me['email']?.toString() ?? savedEmail;

      return AuthState(
        isAuthenticated: true,
        email: email,
        lastLoginTime: lastLoginTime,
      );
    } catch (e) {
      // Sprawdź czy to problem z siecią (nie z tokenem)
      if (e is DioException && _isNetworkError(e)) {
        // Logowanie offline – token jest ważny, brak sieci
        if (savedEmail != null) {
          return AuthState(
            isAuthenticated: true,
            email: savedEmail,
            lastLoginTime: lastLoginTime,
          );
        }
      }

      // Sprawdź czy to błąd 401 - spróbuj odświeżyć token
      if (e is DioException && e.response?.statusCode == 401) {
        final refreshed = await repo.refreshToken();
        if (refreshed) {
          // Token odświeżony - spróbuj ponownie
          try {
            final me = await repo.me();
            final email = me['email']?.toString() ?? savedEmail;
            return AuthState(
              isAuthenticated: true,
              email: email,
              lastLoginTime: lastLoginTime,
            );
          } catch (_) {
            // Jeśli nadal nie działa - wyloguj
          }
        }
      }

      // Dla innych błędów – wyloguj (token nieważny)
      await repo.logout();
      return const AuthState(isAuthenticated: false);
    }
  }

  /// Sprawdza czy błąd DioException to problem z siecią (nie z autoryzacją)
  bool _isNetworkError(DioException e) {
    return e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.unknown && e.error != null;
  }

  Future<void> login(String email, String password) async {
    state = const AsyncLoading();

    state = await AsyncValue.guard(() async {
      final repo = ref.read(authRepositoryProvider);
      await repo.login(email: email, password: password);

      final me = await repo.me();
      final userEmail = me['email']?.toString();
      final lastLoginTime = await repo.getLastLoginTime();

      // Po poprawnym zalogowaniu — wymuś odświeżenie listy kurników
      try {
        ref.invalidate(farmsProvider);
      } catch (e) {
        // Failed to invalidate farmsProvider - ignore
      }

      return AuthState(
        isAuthenticated: true,
        email: userEmail,
        lastLoginTime: lastLoginTime,
      );
    });
  }

  Future<void> register(String email, String password, String username) async {
    state = const AsyncLoading();

    state = await AsyncValue.guard(() async {
      final repo = ref.read(authRepositoryProvider);
      await repo.register(email: email, password: password, username: username);

      final me = await repo.me();
      final userEmail = me['email']?.toString();
      final lastLoginTime = await repo.getLastLoginTime();

      try {
        ref.invalidate(farmsProvider);
      } catch (e) {
        // Failed to invalidate farmsProvider after register - ignore
      }

      return AuthState(
        isAuthenticated: true,
        email: userEmail,
        lastLoginTime: lastLoginTime,
      );
    });
  }

  /// Czyści błąd bez przeładowywania (np. przy przejściu login ↔ register)
  void clearError() {
    if (state.hasError) {
      state = const AsyncData(AuthState(isAuthenticated: false));
    }
  }

  Future<void> logout() async {
    // UX: od razu ustawiamy stan jako wylogowany (router szybciej zareaguje)
    state = const AsyncData(AuthState(isAuthenticated: false));

    final repo = ref.read(authRepositoryProvider);
    await repo.logout();

    // Po wylogowaniu usuń cache listy kurników
    try {
      ref.invalidate(farmsProvider);
    } catch (e) {
      // Failed to invalidate farmsProvider on logout - ignore
    }
  }
}
