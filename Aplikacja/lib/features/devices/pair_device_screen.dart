import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_state.dart';
import '../../core/api/endpoints.dart';
import 'qr_scan_sheet.dart';
import 'new_farm_screen.dart';

class PairDeviceScreen extends ConsumerStatefulWidget {
  const PairDeviceScreen({super.key, required this.farmId});
  final String farmId;

  @override
  ConsumerState<PairDeviceScreen> createState() => _PairDeviceScreenState();
}

class _PairDeviceScreenState extends ConsumerState<PairDeviceScreen> {
  final codeCtrl = TextEditingController();

  bool loading = false;
  String? msg;
  bool success = false;

  static const int _minLen = 6;
  static const int _maxLen = 32;

  // Dopuszczamy litery/cyfry + myślnik/underscore oraz dwukropek (np. MAC: 41:E8:..)
  final RegExp _codeRe = RegExp(r'^[A-Za-z0-9\-_:]+$');

  @override
  void dispose() {
    codeCtrl.dispose();
    super.dispose();
  }

  String _normalize(String raw) {
    var s = raw.trim();

    // jeśli QR jest URL-em (np. ...?code=ABC123), spróbuj wyciągnąć code
    try {
      final uri = Uri.tryParse(s);
      final qp = uri?.queryParameters;
      if (qp != null && qp['code'] != null && qp['code']!.trim().isNotEmpty) {
        s = qp['code']!.trim();
      }
    } catch (_) {}

    return s.toUpperCase();
  }

  String? _validate(String code) {
    if (code.isEmpty) return 'Kod jest wymagany';
    if (code.length < _minLen) return 'Kod za krótki (min. $_minLen znaków)';
    if (code.length > _maxLen) return 'Kod za długi (max. $_maxLen znaków)';
    if (!_codeRe.hasMatch(code)) return 'Kod ma niedozwolone znaki (dozwolone: litery, cyfry, :, -, _)';
    return null;
  }

  String _prettyError(Object e) {
    if (e is DioException) {
      final status = e.response?.statusCode;
      final data = e.response?.data;

      String? backendMsg;
      if (data is Map) {
        backendMsg = (data['message'] ?? data['detail'] ?? data['error'])?.toString();
      } else if (data is String) {
        backendMsg = data;
      }

      // timeouty/brak sieci
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.sendTimeout) {
        return 'Przekroczono czas połączenia. Sprawdź internet.';
      }
      if (e.type == DioExceptionType.connectionError) {
        return 'Brak połączenia z internetem lub serwerem.';
      }

      // specyficzne kody
      if (status == 400) return backendMsg ?? 'Niepoprawny kod parowania.';
      if (status == 401 || status == 403) return backendMsg ?? 'Brak uprawnień (zaloguj się ponownie).';
      if (status == 404) return backendMsg ?? 'Nie znaleziono zasobu (sprawdź farmId/kod).';

      return [
        if (status != null) 'HTTP $status',
        backendMsg ?? e.message ?? 'Nieznany błąd sieci',
      ].where((s) => s.trim().isNotEmpty).join(' • ');
    }

    return e.toString();
  }

  Future<void> _scanQr() async {
    if (loading) return;

    final res = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const SizedBox(
        height: 520,
        child: QrScanSheet(),
      ),
    );

    if (res == null) return;
    if (!mounted) return;

    final normalized = _normalize(res);
    codeCtrl.text = normalized;
    setState(() => msg = null);

    // Immediately navigate to new-farm form with scanned topic
    if (!mounted) return;
    final created = await Navigator.of(context).push<bool?>(
      MaterialPageRoute(builder: (_) => NewFarmScreen(topic: normalized)),
    );
    if (!mounted) return;
    if (created == true) {
      setState(() {
        msg = 'Kurnik utworzony i dodany do listy.';
        success = true;
      });
      await Future.delayed(const Duration(milliseconds: 800));
      if (mounted) Navigator.of(context).maybePop(true);
    }
  }

  Future<void> _pair() async {
  if (loading) return;

  final dio = ref.read(dioProvider);
  final code = _normalize(codeCtrl.text);

  final err = _validate(code);
  if (err != null) {
    setState(() {
      msg = err;
      success = false;
    });
    return;
  }

  setState(() {
    loading = true;
    msg = null;
    success = false;
  });

  try {
    await dio.post(
      Endpoints.pairDevice(widget.farmId),
      data: {'code': code},
    );

    if (!mounted) return;

    setState(() {
      msg = 'Sparowano poprawnie';
      success = true;
    });

    // auto-cofnięcie po sukcesie
    await Future.delayed(const Duration(milliseconds: 800));
    if (mounted) {
      Navigator.of(context).maybePop(true);
    }
  } catch (e) {
    if (!mounted) return;

    setState(() {
      msg = 'Błąd parowania: ${_prettyError(e)}';
      success = false;
    });
  } finally {
    // ❗️ BEZ return
    if (mounted) {
      setState(() => loading = false);
    }
  }
}

  @override
  Widget build(BuildContext context) {
    final code = _normalize(codeCtrl.text);
    final canSubmit = _validate(code) == null && !loading;

    return Scaffold(
      appBar: AppBar(title: const Text('Parowanie modułu')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Wpisz kod parowania',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Kod może być wygenerowany na urządzeniu (przycisk parowania) '
                  'lub wydrukowany jako QR. Backend potwierdzi powiązanie modułu z kurnikiem.',
                ),
                const SizedBox(height: 16),

                // QR + pole
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: codeCtrl,
                        enabled: !loading,
                        textCapitalization: TextCapitalization.characters,
                        onChanged: (_) => setState(() => msg = null),
                        decoration: InputDecoration(
                          labelText: 'Kod (min. $_minLen znaków)',
                          prefixIcon: const Icon(Icons.qr_code_rounded),
                          errorText: (codeCtrl.text.isEmpty || loading) ? null : _validate(code),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    IconButton.filledTonal(
                      onPressed: loading ? null : _scanQr,
                      icon: const Icon(Icons.qr_code_scanner_rounded),
                      tooltip: 'Skanuj QR',
                    ),
                  ],
                ),

                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: canSubmit ? _pair : null,
                  icon: loading
                      ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator())
                      : const Icon(Icons.link_rounded),
                  label: const Text('Sparuj'),
                ),

                const SizedBox(height: 12),
                if (msg != null)
                  Text(
                    msg!,
                    style: TextStyle(
                      color: success
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.error,
                    ),
                    textAlign: TextAlign.center,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}