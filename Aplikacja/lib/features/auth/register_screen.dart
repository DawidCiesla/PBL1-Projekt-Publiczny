import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_state.dart';
import '../../core/utils/validators.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  final bool clearError;
  
  const RegisterScreen({super.key, this.clearError = false});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final emailCtrl = TextEditingController();
  final usernameCtrl = TextEditingController();
  final passCtrl = TextEditingController();
  final confirmCtrl = TextEditingController();

  bool hidePass = true;
  bool hideConfirm = true;
  bool _errorCleared = false;

  @override
  void initState() {
    super.initState();
    if (widget.clearError) {
      // Wyczyść błąd z poprzedniego ekranu po zbudowaniu widgetu
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_errorCleared) {
          _errorCleared = true;
          ref.read(authControllerProvider.notifier).clearError();
        }
      });
    }
  }

  @override
  void dispose() {
    usernameCtrl.dispose();
    emailCtrl.dispose();
    passCtrl.dispose();
    confirmCtrl.dispose();
    super.dispose();
  }

  String _prettyRegisterError(Object e) {
    if (e is DioException) {
      final code = e.response?.statusCode;

      if (code == 400 || code == 401 || code == 403) {
        return 'Nie udało się utworzyć konta';
      }
      if (code == 409) {
        return 'Takie konto już istnieje';
      }

      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.sendTimeout) {
        return 'Przekroczono czas połączenia. Sprawdź internet.';
      }

      if (e.type == DioExceptionType.connectionError) {
        return 'Brak połączenia z internetem lub serwerem.';
      }

      final data = e.response?.data;
      if (data is Map) {
        final msg = data['message'] ?? data['detail'] ?? data['error'];
        if (msg != null) return msg.toString();
      }

      return 'Nie udało się utworzyć konta (HTTP ${code ?? "?"}).';
    }

    final s = e.toString();
    if (s.startsWith('Exception: ')) return s.replaceFirst('Exception: ', '');
    return s.isNotEmpty ? s : 'Nie udało się utworzyć konta.';
  }

  String? _confirmError(String password, String confirm) {
    if (confirm.isEmpty) return null;
    if (password != confirm) return 'Hasła nie są takie same';
    return null;
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();

    await ref
        .read(authControllerProvider.notifier)
        .register(
          emailCtrl.text.trim(),
          passCtrl.text,
          usernameCtrl.text.trim(),
        );
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);

    final emailError = Validators.email(emailCtrl.text);
    String? usernameError;
    final username = usernameCtrl.text.trim();
    if (username.isEmpty) {
      usernameError = 'Nazwa użytkownika jest wymagana';
    } else if (username.length < 3) {
      usernameError = 'Nazwa użytkownika min. 3 znaki';
    }
    final passError = Validators.password(passCtrl.text);
    final confirmError = _confirmError(passCtrl.text, confirmCtrl.text);

    final canSubmit = usernameError == null &&
        emailError == null &&
        passError == null &&
        confirmError == null &&
        !auth.isLoading;
    final errorText = auth.hasError ? _prettyRegisterError(auth.error!) : null;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Theme.of(context).colorScheme.primaryContainer,
              Theme.of(context).colorScheme.surface,
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Card(
                  elevation: 16,
                  shadowColor: Colors.black.withValues(alpha: 0.25),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                    side: BorderSide(
                      color: const Color(0xFF5CE1E6).withValues(alpha: 0.3),
                      width: 1.5,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(
                          child: Column(
                            children: [
                              SizedBox(
                                height: 120,
                                child: Center(
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: RichText(
                                      text: TextSpan(
                                        style: TextStyle(
                                          fontFamily: 'Montserrat',
                                          fontSize: 38,
                                          fontWeight: FontWeight.bold,
                                          color: Theme.of(context).brightness == Brightness.dark
                                              ? const Color(0xFFFFFFFF)
                                              : const Color(0xFF000000),
                                        ),
                                        children: const [
                                          TextSpan(text: 'MacNugget'),
                                          TextSpan(
                                            text: 'Net',
                                            style: TextStyle(color: Color(0xFF5CE1E6)),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Utwórz nowe konto',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: usernameCtrl,
                          enabled: !auth.isLoading,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.username],
                          onChanged: (_) {
                            ref.read(authControllerProvider.notifier).clearError();
                            setState(() {});
                          },
                          decoration: InputDecoration(
                            labelText: 'Nazwa użytkownika',
                            prefixIcon: const Icon(Icons.person_outline),
                            errorText: usernameCtrl.text.isEmpty
                                ? null
                                : usernameError,
                            filled: true,
                            fillColor: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        TextField(
                          controller: emailCtrl,
                          enabled: !auth.isLoading,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [
                            AutofillHints.username,
                            AutofillHints.email,
                          ],
                          onChanged: (_) {
                            ref.read(authControllerProvider.notifier).clearError();
                            setState(() {});
                          },
                          decoration: InputDecoration(
                            labelText: 'Adres email',
                            hintText: 'przyklad@email.pl',
                            prefixIcon: const Icon(Icons.email_outlined),
                            errorText: emailCtrl.text.isEmpty ? null : emailError,
                            filled: true,
                            fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: passCtrl,
                          enabled: !auth.isLoading,
                          obscureText: hidePass,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.newPassword],
                          onChanged: (_) {
                            ref.read(authControllerProvider.notifier).clearError();
                            setState(() {});
                          },
                          decoration: InputDecoration(
                            labelText: 'Hasło',
                            prefixIcon: const Icon(Icons.lock_outline),
                            errorText: passCtrl.text.isEmpty ? null : passError,
                            filled: true,
                            fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide.none,
                            ),
                            suffixIcon: IconButton(
                              onPressed: auth.isLoading
                                  ? null
                                  : () => setState(() => hidePass = !hidePass),
                              icon: Icon(
                                hidePass
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: confirmCtrl,
                          enabled: !auth.isLoading,
                          obscureText: hideConfirm,
                          textInputAction: TextInputAction.done,
                          autofillHints: const [AutofillHints.newPassword],
                          onChanged: (_) {
                            ref.read(authControllerProvider.notifier).clearError();
                            setState(() {});
                          },
                          onSubmitted: (_) {
                            if (canSubmit) _submit();
                          },
                          decoration: InputDecoration(
                            labelText: 'Powtórz hasło',
                            prefixIcon: const Icon(Icons.lock_reset_outlined),
                            errorText:
                                confirmCtrl.text.isEmpty ? null : confirmError,
                            filled: true,
                            fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide.none,
                            ),
                            suffixIcon: IconButton(
                              onPressed: auth.isLoading
                                  ? null
                                  : () => setState(() => hideConfirm = !hideConfirm),
                              icon: Icon(
                                hideConfirm
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        FilledButton(
                          onPressed: canSubmit ? _submit : null,
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: auth.isLoading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text(
                                  'Utwórz konto',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                        ),
                        const SizedBox(height: 12),
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: auth.isLoading
                              ? null
                              : () => context.go('/login?from=register'),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              'Masz już konto? Zaloguj się',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                          ),
                        ),
                        if (errorText != null) ...[
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.red.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.red.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.error_outline,
                                  color: Colors.red[700],
                                  size: 20,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    errorText,
                                    style: TextStyle(color: Colors.red[700]),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
