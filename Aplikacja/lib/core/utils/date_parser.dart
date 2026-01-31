import 'package:intl/intl.dart';

/// ✅ Centralizowany helper do parsowania dat z różnych formatów API
class DateParser {
  DateParser._();
  
  /// Format RFC 1123 używany przez backend (np. "Thu, 22 Jan 2026 13:32:40 GMT")
  static final _rfc1123Format = DateFormat('EEE, dd MMM yyyy HH:mm:ss', 'en_US');

  /// Parsuje timestamp z różnych formatów:
  /// - epoch seconds (np. 1700000000)
  /// - epoch millis (np. 1700000000000)
  /// - ISO string (np. "2024-01-15T12:00:00Z")
  /// - RFC 1123 (np. "Thu, 22 Jan 2026 13:32:40 GMT")
  /// - null → zwraca fallback
  static DateTime parse(dynamic v, {DateTime? fallback}) {
    fallback ??= DateTime.fromMillisecondsSinceEpoch(0);

    if (v == null) return fallback;
    if (v is DateTime) return v;

    // epoch seconds / millis
    if (v is num) {
      final n = v.toInt();
      final dt = n > 1000000000000
          ? DateTime.fromMillisecondsSinceEpoch(n, isUtc: true)
          : DateTime.fromMillisecondsSinceEpoch(n * 1000, isUtc: true);
      return dt.toLocal();
    }

    final s = v.toString().trim();
    if (s.isEmpty) return fallback;

    // epoch as string
    final asInt = int.tryParse(s);
    if (asInt != null) {
      final dt = asInt > 1000000000000
          ? DateTime.fromMillisecondsSinceEpoch(asInt, isUtc: true)
          : DateTime.fromMillisecondsSinceEpoch(asInt * 1000, isUtc: true);
      return dt.toLocal();
    }

    // ISO string
    final parsed = DateTime.tryParse(s);
    if (parsed != null) {
      return parsed.toLocal();
    }
    
    // RFC 1123 format (np. "Thu, 22 Jan 2026 13:32:40 GMT")
    final rfc1123Parsed = _tryParseRfc1123(s);
    if (rfc1123Parsed != null) {
      return rfc1123Parsed.toLocal();
    }
    
    return fallback;
  }

  /// Parsuje timestamp, zwraca null jeśli nie można sparsować
  static DateTime? tryParse(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;

    // epoch seconds / millis
    if (v is num) {
      final n = v.toInt();
      final dt = n > 1000000000000
          ? DateTime.fromMillisecondsSinceEpoch(n, isUtc: true)
          : DateTime.fromMillisecondsSinceEpoch(n * 1000, isUtc: true);
      return dt.toLocal();
    }

    // string ISO / epoch as string
    final s = v.toString().trim();
    if (s.isEmpty) return null;

    final asInt = int.tryParse(s);
    if (asInt != null) {
      final dt = asInt > 1000000000000
          ? DateTime.fromMillisecondsSinceEpoch(asInt, isUtc: true)
          : DateTime.fromMillisecondsSinceEpoch(asInt * 1000, isUtc: true);
      return dt.toLocal();
    }

    // ISO string
    final parsed = DateTime.tryParse(s);
    if (parsed != null) {
      return parsed.toLocal();
    }
    
    // RFC 1123 format (np. "Thu, 22 Jan 2026 13:32:40 GMT")
    final rfc1123Parsed = _tryParseRfc1123(s);
    if (rfc1123Parsed != null) {
      return rfc1123Parsed.toLocal();
    }
    
    return null;
  }
  
  /// Próbuje sparsować datę w formacie RFC 1123
  /// np. "Thu, 22 Jan 2026 13:32:40 GMT"
  static DateTime? _tryParseRfc1123(String s) {
    try {
      // Usuń suffix GMT/UTC jeśli obecny
      var cleaned = s.replaceAll(RegExp(r'\s*(GMT|UTC)$', caseSensitive: false), '').trim();
      final dt = _rfc1123Format.parseUtc(cleaned);
      return dt;
    } catch (_) {
      return null;
    }
  }

  /// Formatuje datę do czytelnego stringa
  static String format(DateTime dt, {bool includeTime = true}) {
    String two(int x) => x.toString().padLeft(2, '0');
    
    if (includeTime) {
      return '${dt.year}-${two(dt.month)}-${two(dt.day)} '
          '${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}';
    }
    return '${dt.year}-${two(dt.month)}-${two(dt.day)}';
  }
}