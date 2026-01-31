class Validators {
  Validators._();

  // --------------------
  // EMAIL
  // --------------------

  static bool isEmail(String v) {
    final s = v.trim();
    final re = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
    return re.hasMatch(s);
  }

  /// ✅ nowa, docelowa nazwa
  static String? email(String? v) {
    if (v == null || v.trim().isEmpty) return 'Email jest wymagany';
    if (!isEmail(v)) return 'Niepoprawny email';
    return null;
  }

  /// ✅ alias – dla istniejącego LoginScreen
  static String? emailOrNull(String? v) => email(v);

  // --------------------
  // PASSWORD
  // --------------------

  /// ✅ nowa, docelowa nazwa (dla rejestracji - sprawdza długość)
  static String? password(String? v) {
    if (v == null || v.trim().isEmpty) return 'Hasło jest wymagane';

    final s = v.trim();
    if (s.length < 6) return 'Hasło powinno mieć min. 6 znaków';
    return null;
  }

  /// ✅ alias – dla istniejącego RegisterScreen (rejestracja)
  static String? passwordOrNull(String? v) => password(v);

  /// ✅ walidator hasła dla logowania (tylko sprawdza pustość)
  static String? passwordLogin(String? v) {
    if (v == null || v.trim().isEmpty) return 'Hasło jest wymagane';
    return null;
  }

  // --------------------
  // GENERIC
  // --------------------

  static String? nonEmpty(
    String? v, {
    String message = 'Pole wymagane',
  }) {
    if (v == null || v.trim().isEmpty) return message;
    return null;
  }

  // --------------------
  // PAIR DEVICE
  // --------------------

  static String? pairCode(String? v) {
    final s = v?.trim() ?? '';

    if (s.isEmpty) return 'Kod parowania jest wymagany';
    if (s.length < 6) return 'Kod jest za krótki (min. 6 znaków)';
    if (s.length > 32) return 'Kod jest za długi';

    final re = RegExp(r'^[a-zA-Z0-9_-]+$');
    if (!re.hasMatch(s)) {
      return 'Kod zawiera niedozwolone znaki';
    }

    return null;
  }
}