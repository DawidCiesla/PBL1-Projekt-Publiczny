import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Klucz do przechowywania trybu motywu w storage
const _themeModeKey = 'theme_mode';

/// Provider dla FlutterSecureStorage
final _storageProvider = Provider<FlutterSecureStorage>((ref) {
  return const FlutterSecureStorage();
});

/// Provider dla trybu motywu z persystencją
final themeModeProvider =
    StateNotifierProvider<ThemeModeNotifier, ThemeMode>((ref) {
  final storage = ref.watch(_storageProvider);
  return ThemeModeNotifier(storage);
});

/// Notifier zarządzający trybem motywu
class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  final FlutterSecureStorage _storage;

  ThemeModeNotifier(this._storage) : super(ThemeMode.system) {
    _loadThemeMode();
  }

  /// Wczytaj zapisany tryb motywu
  Future<void> _loadThemeMode() async {
    final stored = await _storage.read(key: _themeModeKey);
    if (stored != null) {
      state = _themeModeFromString(stored);
    }
  }

  /// Zmień tryb motywu i zapisz
  Future<void> setThemeMode(ThemeMode mode) async {
    state = mode;
    await _storage.write(key: _themeModeKey, value: mode.name);
  }

  /// Konwersja stringa na ThemeMode
  ThemeMode _themeModeFromString(String value) {
    switch (value) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }
}

/// Helper do wyświetlania nazwy trybu motywu po polsku
String themeModeLabel(ThemeMode mode) {
  switch (mode) {
    case ThemeMode.light:
      return 'Jasny';
    case ThemeMode.dark:
      return 'Ciemny';
    case ThemeMode.system:
      return 'Zgodny z systemem';
  }
}

/// Helper do wyboru ikony dla trybu motywu
IconData themeModeIcon(ThemeMode mode) {
  switch (mode) {
    case ThemeMode.light:
      return Icons.light_mode_rounded;
    case ThemeMode.dark:
      return Icons.dark_mode_rounded;
    case ThemeMode.system:
      return Icons.settings_suggest_rounded;
  }
}
