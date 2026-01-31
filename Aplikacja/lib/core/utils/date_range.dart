import 'package:flutter/material.dart';

/// Predefiniowane szybkie zakresy czasu
enum QuickRange {
  h1,
  h24,
  d7,
  d30,
}

extension QuickRangeX on QuickRange {
  /// Etykieta do UI
  String get label {
    return switch (this) {
      QuickRange.h1 => '1h',
      QuickRange.h24 => '24h',
      QuickRange.d7 => '7d',
      QuickRange.d30 => '30d',
    };
  }

  /// Czas trwania zakresu
  Duration get duration {
    return switch (this) {
      QuickRange.h1 => const Duration(hours: 1),
      QuickRange.h24 => const Duration(hours: 24),
      QuickRange.d7 => const Duration(days: 7),
      QuickRange.d30 => const Duration(days: 30),
    };
  }

  /// Zamiana na DateTimeRange (domyślnie: teraz → wstecz)
  DateTimeRange toDateTimeRange({DateTime? now}) {
    final end = now ?? DateTime.now();
    return DateTimeRange(
      start: end.subtract(duration),
      end: end,
    );
  }
}