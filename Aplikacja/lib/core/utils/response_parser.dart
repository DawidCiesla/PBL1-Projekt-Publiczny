/// ✅ Centralizowany helper do ekstrakcji listy z różnych formatów JSON responses
class ResponseParser {
  /// Ekstrakt listę z dynamicznej odpowiedzi API
  /// Obsługuje wiele formatów:
  /// - Bezpośredni Array: [item1, item2, ...]
  /// - Wrapped: { "items": [...] }
  /// - Wrapped: { "data": [...] }
  /// - Wrapped: { "devices": [...] }
  /// - Wrapped: { "coops": [...] }
  /// - Wrapped: { "series": [...] }
  /// - Wrapped: { "kury": [...] }
  /// - Wrapped: { "chickens": [...] }
  /// - Wrapped: { "events": [...] }
  /// - Deeply wrapped: { "data": { "items": [...] } }
  static List<dynamic> extractList(
    dynamic body, [
    List<String> keys = const [
      'items',
      'data',
      'devices',
      'coops',
      'series',
      'kury',
      'chickens',
      'events', // 🔧 Dodajemy 'events' dla zdarzeń kury
    ],
  ]) {
    // Przypadek 1: Direct array
    if (body is List) {
      return body;
    }

    // Przypadek 2: Map wrapper
    if (body is Map) {
      // Spróbuj każdy klucz na poziomie głównym
      for (final key in keys) {
        if (body[key] is List) {
          return body[key] as List;
        }
      }

      // Przypadek 3: Deeply wrapped (np. data.items)
      final data = body['data'];
      if (data is Map) {
        for (final key in keys) {
          if (data[key] is List) {
            return data[key] as List;
          }
        }
      }

      // ⚠️ Nie znaleziono listy - zwróć pustą listę
      return const [];
    }

    return const [];
  }
}
