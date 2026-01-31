import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../api/endpoints.dart';

class AuthRepository {
  static const tokenKey = 'auth_token';
  static const emailKey = 'auth_email';
  static const lastLoginKey = 'auth_last_login';
  static const refreshTokenKey = 'auth_refresh_token';

  final Dio _dio;
  final FlutterSecureStorage _storage;

  AuthRepository(this._dio, {required FlutterSecureStorage storage})
    : _storage = storage;

  Future<String?> getToken() => _storage.read(key: tokenKey);

  Future<String?> getEmail() => _storage.read(key: emailKey);

  Future<DateTime?> getLastLoginTime() async {
    final raw = await _storage.read(key: lastLoginKey);
    if (raw == null) return null;
    try {
      return DateTime.parse(raw);
    } catch (_) {
      return null;
    }
  }

  Future<void> logout() async {
    // Usuń wszystkie dane sesji
    await Future.wait([
      _storage.delete(key: tokenKey),
      _storage.delete(key: emailKey),
      _storage.delete(key: lastLoginKey),
      _storage.delete(key: refreshTokenKey),
    ]);
  }

  /// Próbuje odświeżyć access token używając refresh tokenu.
  /// Zwraca `true` jeśli udało się zapisać nowy token.
  Future<bool> refreshToken() async {
    final storedRefresh = await _storage.read(key: refreshTokenKey);
    if (storedRefresh == null || storedRefresh.isEmpty) return false;

    final refreshDio = Dio(
      BaseOptions(
        baseUrl: Endpoints.baseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
      ),
    );

    try {
      final res = await refreshDio.post(
        Endpoints.refresh,
        data: {'refresh_token': storedRefresh},
      );

      final raw = res.data;
      if (raw == null) return false;

      final map = raw is Map<String, dynamic>
          ? raw
          : raw is Map
          ? Map<String, dynamic>.from(raw)
          : <String, dynamic>{};

      final newToken = _extractToken(map)?.trim();
      if (newToken == null || newToken.isEmpty) return false;

      await _storage.write(key: tokenKey, value: newToken);
      await _storage.write(
        key: lastLoginKey,
        value: DateTime.now().toIso8601String(),
      );

      final newRefresh = map['refresh_token'] ?? map['refreshToken'];
      if (newRefresh != null && newRefresh.toString().isNotEmpty) {
        await _storage.write(
          key: refreshTokenKey,
          value: newRefresh.toString(),
        );
      }

      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> register({
    required String email,
    required String password,
    required String username,
  }) async {
    try {
      final res = await _dio.post(
        Endpoints.register,
        data: {'email': email, 'password': password, 'username': username},
        options: Options(extra: {'skipRefresh': true}), // ✅ Nie próbuj odświeżać tokenu przy rejestracji
      );

      final data = res.data;
      if (data == null) {
        throw const FormatException('Pusta odpowiedź serwera');
      }

      final map = data is Map
          ? Map<String, dynamic>.from(data)
          : <String, dynamic>{};

      final token = _extractToken(map);
      if (token == null || token.isEmpty) {
        throw const FormatException('Brak tokenu w odpowiedzi backendu');
      }

      await _storage.write(key: tokenKey, value: token.trim());
      await _storage.write(key: emailKey, value: email.trim());
      await _storage.write(
        key: lastLoginKey,
        value: DateTime.now().toIso8601String(),
      );

      final refreshToken = map['refresh_token'] ?? map['refreshToken'];
      if (refreshToken != null && refreshToken.toString().isNotEmpty) {
        await _storage.write(
          key: refreshTokenKey,
          value: refreshToken.toString(),
        );
      }
    } on DioException catch (e) {
      final code = e.response?.statusCode;

      if (code == 400 || code == 401 || code == 403 || code == 409) {
        final backendMsg = _backendMessage(e.response?.data);
        throw Exception(backendMsg ?? 'Nie udało się utworzyć konta');
      }

      final backendMsg = _backendMessage(e.response?.data);
      if (backendMsg != null) {
        throw Exception(backendMsg);
      }

      throw Exception(_dioPrettyMessage(e));
    }
  }

  Future<void> login({required String email, required String password}) async {
    try {
      final res = await _dio.post(
        Endpoints.login,
        data: {'email': email, 'password': password},
        options: Options(extra: {'skipRefresh': true}), // ✅ Nie próbuj odświeżać tokenu przy logowaniu
      );

      final data = res.data;
      if (data == null) {
        throw const FormatException('Pusta odpowiedź serwera');
      }

      final map = data is Map
          ? Map<String, dynamic>.from(data)
          : <String, dynamic>{};

      final token = _extractToken(map);
      if (token == null || token.isEmpty) {
        throw const FormatException('Brak tokenu w odpowiedzi backendu');
      }

      await _storage.write(
        key: tokenKey,
        value: token.trim(), // ← TO JEST KLUCZOWE
      );

      // Zapisz email do cache (przydatne dla logowania offline)
      await _storage.write(key: emailKey, value: email.trim());

      // Zapisz czas zalogowania i refresh token (jeśli jest dostępny)
      await _storage.write(
        key: lastLoginKey,
        value: DateTime.now().toIso8601String(),
      );

      // Jeśli backend zwróci refresh token, zapisz go
      final refreshToken = map['refresh_token'] ?? map['refreshToken'];
      if (refreshToken != null) {
        await _storage.write(
          key: refreshTokenKey,
          value: refreshToken.toString(),
        );
      }
    } on DioException catch (e) {
      final code = e.response?.statusCode;

      if (code == 400 || code == 401 || code == 403) {
        final backendMsg = _backendMessage(e.response?.data);
        throw Exception(backendMsg ?? 'Błędny email lub hasło');
      }

      final backendMsg = _backendMessage(e.response?.data);
      if (backendMsg != null) {
        throw Exception(backendMsg);
      }

      throw Exception(_dioPrettyMessage(e));
    }
  }

  Future<Map<String, dynamic>> me() async {
    try {
      final res = await _dio.get(Endpoints.me);

      final data = res.data;
      if (data is! Map) {
        throw const FormatException('Niepoprawna odpowiedź backendu /auth/me');
      }

      final raw = Map<String, dynamic>.from(data);
      final inner = raw['data'];
      final result = inner is Map ? Map<String, dynamic>.from(inner) : raw;

      // ✅ Zaktualizuj zapisany email (cache dla trybu offline)
      final email = result['email']?.toString();
      if (email != null && email.isNotEmpty) {
        await _storage.write(key: emailKey, value: email);
      }

      return result;
    } on DioException catch (e) {
      final backendMsg = _backendMessage(e.response?.data);
      throw Exception(backendMsg ?? _dioPrettyMessage(e));
    }
  }

  /// Sprawdza czy użytkownik ma zapisane dane sesji (token + email)
  Future<bool> hasValidSession() async {
    final token = await getToken();
    final email = await getEmail();
    return token != null && token.isNotEmpty && email != null;
  }

  // ───────────────── helpers ─────────────────

  static String? _extractToken(Map<String, dynamic> map) {
    final direct = map['access_token'] ?? map['token'] ?? map['accessToken'];
    if (direct != null) return direct.toString();

    final data = map['data'];
    if (data is Map) {
      final inner = Map<String, dynamic>.from(data);
      final innerToken =
          inner['access_token'] ?? inner['token'] ?? inner['accessToken'];
      if (innerToken != null) return innerToken.toString();
    }
    return null;
  }

  static String? _backendMessage(dynamic data) {
    if (data == null) return null;

    if (data is String) {
      final s = data.trim();
      if (s.isEmpty) return null;
      return _translateError(s);
    }

    if (data is Map) {
      final map = Map<String, dynamic>.from(data);
      final msg = map['message'] ?? map['detail'] ?? map['error'];
      final s = msg?.toString().trim();
      if (s == null || s.isEmpty) return null;
      return _translateError(s);
    }

    return null;
  }

  static String _translateError(String message) {
    // Tłumaczenie typowych angielskich błędów na user-friendly polski
    // Normalizujemy underscores na spacje dla lepszego matchowania
    final normalized = message.toLowerCase().replaceAll('_', ' ');

    if (normalized.contains('invalid credentials')) {
      return 'Błędne hasło lub login';
    }
    if (normalized.contains('invalid password')) {
      return 'Sprawdź poprawność hasła';
    }
    if (normalized.contains('incorrect password')) {
      return 'Błędne hasło lub login';
    }
    if (normalized.contains('wrong password')) {
      return 'Sprawdź poprawność hasła';
    }
    if (normalized.contains('user not found')) {
      return 'Nie znaleziono takiego konta';
    }
    if (normalized.contains('not found')) {
      return 'Konto nie istnieje';
    }
    if (normalized.contains('unauthorized')) {
      return 'Nie jesteś zalogowany';
    }
    if (normalized.contains('forbidden')) {
      return 'Brak dostępu do tego zasobu';
    }
    if (normalized.contains('already exists')) {
      return 'To konto już istnieje';
    }
    if (normalized.contains('invalid email')) {
      return 'Niepoprawny adres email';
    }
    if (normalized.contains('email required')) {
      return 'Podaj adres email';
    }
    if (normalized.contains('password required')) {
      return 'Podaj hasło';
    }
    if (normalized.contains('weak password')) {
      return 'Hasło jest za słabe. Użyj min. 8 znaków i mieszaj litery/cyfry.';
    }

    return message;
  }

  static String _dioPrettyMessage(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return 'Przekroczono czas połączenia. Sprawdź internet.';
      case DioExceptionType.connectionError:
        return 'Brak połączenia z internetem lub serwerem.';
      case DioExceptionType.badResponse:
        final code = e.response?.statusCode;
        return 'Błąd serwera (HTTP ${code ?? "?"}).';
      default:
        return 'Błąd sieci: ${e.message ?? "nieznany"}';
    }
  }
}
