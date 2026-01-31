import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';

import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wifi_scan/wifi_scan.dart';

import '../../core/api/endpoints.dart';
import '../../core/config/app_config.dart';

class BLEProvisionScreen extends StatefulWidget {
  const BLEProvisionScreen({super.key, required this.topic});
  final String topic; // scanned code/topic from QR

  @override
  State<BLEProvisionScreen> createState() => _BLEProvisionScreenState();
}

class _BLEProvisionScreenState extends State<BLEProvisionScreen> {
  final _ble = FlutterReactiveBle();
  final Map<String, DiscoveredDevice> _devices = {};
  StreamSubscription<DiscoveredDevice>? _scanSub;
  StreamSubscription<ConnectionStateUpdate>? _connSub;
  StreamSubscription<List<int>>? _wifiStatusSub;
  CancelToken? _pollCancelToken;

  // ✅ Singleton Dio dla pairingowego serwera - z AppConfig timeouts
  late final Dio _pairingDio = Dio(BaseOptions(
    baseUrl: Endpoints.pairStatusBaseUrl,
    connectTimeout: AppConfig.bleProvisioningPollTimeout,
    receiveTimeout: AppConfig.bleProvisioningPollTimeout,
  ))..httpClientAdapter = IOHttpClientAdapter(
    createHttpClient: () {
      final client = HttpClient();
      // ⚠️ TYLKO DLA DEVELOPMENTU - wyłącz weryfikację SSL
      if (kDebugMode) {
        client.badCertificateCallback = (X509Certificate cert, String host, int port) {
          if (kDebugMode) {
            debugPrint('⚠️ [SSL] Pominięto weryfikację certyfikatu dla: $host:$port (dev mode)');
          }
          return true; // Akceptuj wszystkie certyfikaty w dev mode
        };
      }
      return client;
    },
  );

  String? _connectedDeviceId;
  bool _connecting = false;
  bool _provisioning = false;
  bool _autoTriggered = false;

  final ssidCtrl = TextEditingController();
  final passCtrl = TextEditingController();

  // WiFi provisioning UUIDs provided by firmware
  final String serviceUuid = '00000001-0000-0000-0000-000000000001';
  final String ssidChar = '00000001-0000-0000-0000-000000000002';
  final String passChar = '00000001-0000-0000-0000-000000000003';
  final String applyChar = '00000001-0000-0000-0000-000000000004';
  final String statusChar = '00000001-0000-0000-0000-000000000005';
  final String ackChar = '00000001-0000-0000-0000-000000000006';

  // ✅ Cache parsed UUIDs aby uniknąć redundantnych parseów
  late final Uuid _serviceUuidParsed;
  late final Uuid _statusCharParsed;
  late final Uuid _ackCharParsed;

  @override
  void initState() {
    super.initState();
    // Parse UUIDs raz w initState z error handling
    try {
      _serviceUuidParsed = Uuid.parse(serviceUuid);
      _statusCharParsed = Uuid.parse(statusChar);
      _ackCharParsed = Uuid.parse(ackChar);
    } catch (e) {
      // Fallback - aplikacja przejdzie do nextu, ale BLE features mogą nie działać
    }
    _ensureBlePermissionsThenScan();
  }

  QualifiedCharacteristic _statusQc(String deviceId) => QualifiedCharacteristic(
        serviceId: _serviceUuidParsed,
        characteristicId: _statusCharParsed,
        deviceId: deviceId,
      );

  QualifiedCharacteristic _ackQc(String deviceId) => QualifiedCharacteristic(
        serviceId: _serviceUuidParsed,
        characteristicId: _ackCharParsed,
        deviceId: deviceId,
      );

  bool? _parseWifiStatus(List<int> value) {
    if (value.isEmpty) return null;

    // Common simple protocols: 0/1 as bytes.
    if (value.length == 1) {
      if (value[0] == 1) return true;
      if (value[0] == 0) return false;
    }

    // Text-based protocols.
    try {
      final s = utf8.decode(value, allowMalformed: true).trim().toUpperCase();
      if (s.isEmpty) return null;
      if (s == '1' || s.contains('OK') || s.contains('SUCCESS') || s.contains('CONNECTED')) return true;
      if (s == '0' || s.contains('FAIL') || s.contains('ERROR') || s.contains('DISCONNECTED')) return false;
    } catch (_) {
      // ignore
    }
    return null;
  }

  Future<void> _ensureStatusSubscription(String deviceId) async {
    await _wifiStatusSub?.cancel();
    _wifiStatusSub = null;

    // ✅ Sprawdź mounted przed rozpoczęciem subskrypcji
    if (!mounted) return;

    try {
      _wifiStatusSub = _ble.subscribeToCharacteristic(_statusQc(deviceId)).listen((value) {
        // ✅ MOUNTED CHECK NA POCZĄTKU - zapobiegaj memory leak
        if (!mounted) {
          _wifiStatusSub?.cancel();
          return;
        }
        
        final parsed = _parseWifiStatus(value);
        if (parsed == null) return;

        // If device reports connected, send ACK back so firmware can be sure app received it.
        if (parsed == true && mounted) {
          // Fire-and-forget z obsługą błędów - nie blokuj UI
          _ble.writeCharacteristicWithResponse(_ackQc(deviceId), value: [1]).then((_) {
            // ACK sent successfully
          }).catchError((e) {
            // ACK write error - ignore
          });
        }
      }, onError: (e) {
        if (!mounted) return; // MOUNTED CHECK NA POCZĄTKU
        // BLE STATUS subscription error - ignore
      });
    } catch (e) {
      // BLE STATUS subscription setup failed - ignore
    }
  }

  // Returns true if received, false if server explicitly reports not received (unlikely),
  // or null on timeout.
  Future<bool?> _waitForServerConfirmation(String topic, {Duration? timeout}) async {
    timeout ??= AppConfig.bleProvisioningTimeout;
    
    // ✅ Anuluj poprzednie żądanie jeśli istnieje
    _pollCancelToken?.cancel();
    _pollCancelToken = CancelToken();

    // ✅ Usuń prefiks "kurnik/" jeśli istnieje - w bazie danych jest tylko MAC
    String macAddress = topic.toLowerCase();
    if (macAddress.startsWith('kurnik/')) {
      macAddress = macAddress.substring(7); // Usuń "kurnik/"
    }

    final baseUrl = Endpoints.pairStatusBaseUrl;
    final endpoint = Endpoints.pairStatus;
    final fullUrl = '$baseUrl$endpoint?topic=$macAddress';
    
    if (kDebugMode) {
      debugPrint('🔍 [PROVISIONING] Rozpoczynam polling serwera dla MAC: $macAddress');
      debugPrint('🔍 [PROVISIONING] URL: $fullUrl');
      debugPrint('🔍 [PROVISIONING] Timeout: ${timeout.inSeconds}s');
    }

    final sw = Stopwatch()..start();
    int pollCount = 0;
    
    while (sw.elapsed < timeout && !_pollCancelToken!.isCancelled) {
      pollCount++;
      try {
        if (kDebugMode) {
          debugPrint('🔍 [PROVISIONING] Poll #$pollCount - odpytuję serwer... (elapsed: ${sw.elapsed.inSeconds}s)');
        }
        
        final resp = await _pairingDio.get(
          Endpoints.pairStatus,
          queryParameters: {'topic': macAddress},
          cancelToken: _pollCancelToken,
        );
        
        if (kDebugMode) {
          debugPrint('✅ [PROVISIONING] Poll #$pollCount - odpowiedź otrzymana: ${resp.statusCode}');
          debugPrint('✅ [PROVISIONING] Poll #$pollCount - request URL: ${resp.requestOptions.uri}');
          debugPrint('✅ [PROVISIONING] Poll #$pollCount - dane: ${resp.data}');
        }
        
        if (resp.statusCode == 200) {
          final data = resp.data;
          if (data is Map && data['received'] == true) {
            if (kDebugMode) {
              debugPrint('🎉 [PROVISIONING] SUKCES! Urządzenie wysłało wiadomość MQTT (MAC: $macAddress)');
            }
            return true;
          } else {
            if (kDebugMode) {
              debugPrint('⏳ [PROVISIONING] Poll #$pollCount - serwer odpowiedział, ale received != true');
            }
          }
        }
      } catch (e) {
        if (e is DioException && e.type == DioExceptionType.cancel) {
          if (kDebugMode) {
            debugPrint('🚫 [PROVISIONING] Polling anulowany');
          }
          return null;
        }
        if (kDebugMode) {
          debugPrint('❌ [PROVISIONING] Poll #$pollCount - błąd: $e');
          if (e is DioException) {
            debugPrint('❌ [PROVISIONING] DioError type: ${e.type}');
            debugPrint('❌ [PROVISIONING] DioError message: ${e.message}');
            debugPrint('❌ [PROVISIONING] Request URL: ${e.requestOptions.uri}');
            debugPrint('❌ [PROVISIONING] DioError response: ${e.response}');
          }
        }
      }
      await Future.delayed(const Duration(seconds: 1));
    }
    
    if (kDebugMode) {
      debugPrint('⏱️ [PROVISIONING] Timeout! Wykonano $pollCount pollów w ${sw.elapsed.inSeconds}s');
    }
    return null;
  }

  @override
  void dispose() {
    // ✅ Anuluj wszystkie subskrypcje i requesty PRZED super.dispose()
    _scanSub?.cancel();
    _scanSub = null;
    _connSub?.cancel();
    _connSub = null;
    _wifiStatusSub?.cancel();
    _wifiStatusSub = null;
    
    // ✅ Anuluj polling request
    try {
      _pollCancelToken?.cancel();
      _pollCancelToken = null;
    } catch (_) {}
    
    // ✅ Zamknij Dio instance
    _pairingDio.close(force: true);
    
    ssidCtrl.dispose();
    passCtrl.dispose();
    super.dispose();
  }

  Future<void> _ensureBlePermissionsThenScan() async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      _startScan();
      return;
    }

    if (Platform.isIOS) {
      // iOS permission prompt is driven by Info.plist keys; no runtime request needed.
      _startScan();
      return;
    }

    // Android: BLE scan requires runtime permissions (Android 12+), and location on older Android.
    final permissions = <Permission>[
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ];

    final results = await permissions.request();
    final denied = results.entries.where((e) => !e.value.isGranted).map((e) => e.key).toList();
    if (denied.isNotEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Brak uprawnień Bluetooth/Lokalizacja — nie można skanować BLE')),
      );
      return;
    }

    _startScan();
  }

  void _startScan() {
    _devices.clear();
    _scanSub?.cancel();
    _autoTriggered = false;
    _scanSub = _ble.scanForDevices(withServices: []).listen((device) {
      if (!mounted) return; // ✅ MOUNTED CHECK NA POCZĄTKU
      
      // Keep last seen
      setState(() => _devices[device.id] = device);
      // Auto-connect if device name or id contains scanned topic
      if (!_autoTriggered && widget.topic.isNotEmpty) {
        final needle = widget.topic.toUpperCase();
        final name = device.name.toUpperCase();
        final id = device.id.toUpperCase();
        if (name.contains(needle) || id.contains(needle)) {
          _autoTriggered = true;
          _scanSub?.cancel();
          final msg = const SnackBar(content: Text('Znaleziono pasujące urządzenie — łączenie...'));
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(msg);
          _connectAndProvision(device.id);
        }
      }
    }, onError: (e) {
      if (!mounted) return; // ✅ MOUNTED CHECK NA POCZĄTKU
      final msg = SnackBar(content: Text('Błąd skanowania BLE: $e'));
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(msg);
    });
  }

  Future<void> _connectAndProvision(String deviceId) async {
    setState(() {
      _connecting = true;
    });

    _connSub?.cancel();
    _connSub = _ble.connectToDevice(id: deviceId, connectionTimeout: const Duration(seconds: 10)).listen((update) async {
      if (!mounted) return; // ✅ MOUNTED CHECK NA POCZĄTKU
      
      if (update.connectionState == DeviceConnectionState.connected) {
        setState(() {
          _connectedDeviceId = deviceId;
          _connecting = false;
        });

        // Subscribe early so we don't miss a fast STATUS=1 update.
        await _ensureStatusSubscription(deviceId);

        // Auto-open provision dialog when connection established
        if (mounted) _showProvisionDialog(deviceId);
      } else if (update.connectionState == DeviceConnectionState.disconnected) {
        setState(() {
          _connectedDeviceId = null;
          _connecting = false;
        });

        await _wifiStatusSub?.cancel();
        _wifiStatusSub = null;
      }
    }, onError: (e) {
      if (!mounted) return; // ✅ MOUNTED CHECK NA POCZĄTKU
      setState(() {
        _connectedDeviceId = null;
        _connecting = false;
      });
      if (kDebugMode) {
        debugPrint('BLE connection error: $e');
      }
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Błąd połączenia BLE')));
    });
  }

  void _showProvisionDialog(String deviceId) {
    // show same modal as tapping a device
    setState(() {
      ssidCtrl.text = '';
      passCtrl.text = '';
    });
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) {
        bool wifiLoading = false;
        bool wifiInit = false;
        String? wifiError;
        List<String> wifiSsids = const [];
        String? selectedSsid;

        Future<void> refreshWifi(StateSetter setModalState) async {
          if (!Platform.isAndroid) {
            setModalState(() {
              wifiSsids = const [];
              wifiError = 'Lista sieci WiFi jest niedostępna na iOS bez specjalnych uprawnień Apple.';
            });
            return;
          }

          setModalState(() {
            wifiLoading = true;
            wifiError = null;
          });

          // Android 13+ may require NEARBY_WIFI_DEVICES; older versions rely on Location.
          final results = await <Permission>[
            Permission.locationWhenInUse,
            Permission.nearbyWifiDevices,
          ].request();

          final locationOk = results[Permission.locationWhenInUse]?.isGranted ?? false;
          final nearbyOk = results[Permission.nearbyWifiDevices]?.isGranted ?? true; // treated as not-required on older Android
          if (!locationOk || !nearbyOk) {
            setModalState(() {
              wifiLoading = false;
              wifiSsids = const [];
              wifiError = 'Brak uprawnień do skanowania WiFi (lokalizacja / pobliskie urządzenia).';
            });
            return;
          }

          final canScan = await WiFiScan.instance.canStartScan(askPermissions: false);
          if (canScan != CanStartScan.yes) {
            setModalState(() {
              wifiLoading = false;
              wifiSsids = const [];
              wifiError = 'Nie można rozpocząć skanowania WiFi: $canScan';
            });
            return;
          }

          await WiFiScan.instance.startScan();

          final canGet = await WiFiScan.instance.canGetScannedResults(askPermissions: false);
          if (canGet != CanGetScannedResults.yes) {
            setModalState(() {
              wifiLoading = false;
              wifiSsids = const [];
              wifiError = 'Nie można pobrać listy sieci WiFi: $canGet';
            });
            return;
          }

          final aps = await WiFiScan.instance.getScannedResults();

          bool is24Ghz(int frequencyMhz) => frequencyMhz >= 2400 && frequencyMhz < 2500;

          // SSID can appear multiple times (2.4 + 5 GHz, different BSSIDs).
          // Keep only SSIDs that have at least one 2.4 GHz AP, and sort by the best signal strength.
          // `level` is RSSI in dBm: higher (less negative) means stronger.
          final bestLevelBySsid = <String, int>{};
          for (final ap in aps) {
            final s = ap.ssid.trim();
            if (s.isEmpty) continue;
            if (!is24Ghz(ap.frequency)) continue;

            final prev = bestLevelBySsid[s];
            if (prev == null || ap.level > prev) {
              bestLevelBySsid[s] = ap.level;
            }
          }

          final entries = bestLevelBySsid.entries.toList()
            ..sort((a, b) {
              final bySignal = b.value.compareTo(a.value);
              if (bySignal != 0) return bySignal;
              return a.key.compareTo(b.key);
            });

          final list = entries.map((e) => e.key).toList();

          setModalState(() {
            wifiLoading = false;
            wifiSsids = list;
            if (wifiSsids.isEmpty) {
              wifiError = aps.isEmpty
                  ? 'Nie wykryto sieci WiFi (albo skan jest ograniczony przez system).'
                  : 'Wykryto sieci WiFi, ale żadna nie jest 2,4 GHz.';
            }
          });
        }

        return StatefulBuilder(
          builder: (sheetContext, setModalState) {
            if (!wifiInit) {
              wifiInit = true;
              // Fire-and-forget initial scan.
              Future.microtask(() => refreshWifi(setModalState));
            }

            return Padding(
              // ✅ viewInsetsOf jest bardziej wydajne - nie nasłuchuje wszystkich zmian MediaQuery
              padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Podaj dane WiFi dla urządzenia', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 12),

                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: wifiLoading ? null : () => refreshWifi(setModalState),
                            icon: wifiLoading
                                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator())
                                : const Icon(Icons.wifi),
                            label: const Text('Skanuj WiFi'),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 8),
                    if (wifiError != null) ...[
                      Text(wifiError!, style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(height: 8),
                    ],

                    if (wifiSsids.isNotEmpty)
                      DropdownButtonFormField<String>(
                        initialValue: selectedSsid,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Wybierz SSID'),
                        items: wifiSsids
                            .map((s) => DropdownMenuItem<String>(value: s, child: Text(s, overflow: TextOverflow.ellipsis)))
                            .toList(),
                        onChanged: (v) {
                          setModalState(() => selectedSsid = v);
                          if (v != null) ssidCtrl.text = v;
                        },
                      )
                    else
                      TextField(
                        controller: ssidCtrl,
                        decoration: const InputDecoration(labelText: 'SSID'),
                      ),

                    const SizedBox(height: 8),
                    TextField(controller: passCtrl, decoration: const InputDecoration(labelText: 'Hasło'), obscureText: true),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: (_connectedDeviceId == deviceId && !_provisioning)
                          ? () => _sendCredentials(deviceId, sheetContext: sheetContext)
                          : null,
                      child: _provisioning ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator()) : const Text('Wyślij dane WiFi'),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _sendCredentials(String deviceId, {required BuildContext sheetContext}) async {
    final ssid = ssidCtrl.text.trim();
    final pass = passCtrl.text;
    if (ssid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Podaj SSID')));
      return;
    }

    setState(() => _provisioning = true);
    try {
      // Subscribe to STATUS before triggering APPLY so we don't miss the notification.
      await _ensureStatusSubscription(deviceId);

      // write SSID
      final ssidQc = QualifiedCharacteristic(
        serviceId: Uuid.parse(serviceUuid),
        characteristicId: Uuid.parse(ssidChar),
        deviceId: deviceId,
      );
      final passQc = QualifiedCharacteristic(
        serviceId: Uuid.parse(serviceUuid),
        characteristicId: Uuid.parse(passChar),
        deviceId: deviceId,
      );
      final applyQc = QualifiedCharacteristic(
        serviceId: Uuid.parse(serviceUuid),
        characteristicId: Uuid.parse(applyChar),
        deviceId: deviceId,
      );

      final ssidBytes = utf8.encode(ssid);
      final passBytes = utf8.encode(pass);

      // write SSID and password (with response)
      await _ble.writeCharacteristicWithResponse(ssidQc, value: ssidBytes);
      await _ble.writeCharacteristicWithResponse(passQc, value: passBytes);

      // write apply flag (1)
      await _ble.writeCharacteristicWithResponse(applyQc, value: [1]);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Dane WiFi wysłane — czekam na potwierdzenie...')));

      // Wait for server-side confirmation that the device published to MQTT.
      final confirmed = await _waitForServerConfirmation(widget.topic);
      if (!mounted) return;

      if (confirmed == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Urządzenie połączone z WiFi')));
          // close bottom sheet
          Navigator.of(context).pop();
          // close BLE screen and signal success (caller will open NewFarmScreen)
          Navigator.of(context).pop(true);
        }
      } else if (confirmed == false) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nie udało się połączyć z WiFi')));
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Brak potwierdzenia po BLE (timeout)')));
        }
      }
    } catch (e) {
      // ✅ Sprawdź mounted przed ScaffoldMessenger
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Błąd wysyłania: $e'))
        );
      }
    } finally {
      if (mounted) setState(() => _provisioning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = _devices.values.toList()
      ..sort((a, b) => (a.name.isEmpty ? a.id : a.name).compareTo(b.name.isEmpty ? b.id : b.name));

    return Scaffold(
      appBar: AppBar(title: const Text('Provisioning przez BLE')),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Skanuję urządzenia BLE... (szukany kod: ${widget.topic})', style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 8),
            ElevatedButton.icon(onPressed: _startScan, icon: const Icon(Icons.refresh), label: const Text('Skanuj ponownie')),
            const SizedBox(height: 8),
            Expanded(
              child: list.isEmpty
                  ? const Center(child: Text('Brak urządzeń'))
                  : ListView.separated(
                      itemCount: list.length,
                      separatorBuilder: (_, _) => const Divider(height: 8),
                      itemBuilder: (_, i) {
                        final d = list[i];
                        final display = d.name.isNotEmpty ? d.name : d.id;
                        final matchHint = display.contains(widget.topic) ? ' (pasuje do kodu)' : '';
                        final isConnected = _connectedDeviceId == d.id;
                        return ListTile(
                          title: Text(display + matchHint),
                          subtitle: Text(d.id),
                          trailing: isConnected ? const Icon(Icons.bluetooth_connected) : ElevatedButton(
                            onPressed: _connecting ? null : () async {
                              await _connectAndProvision(d.id);
                            },
                            child: const Text('Połącz'),
                          ),
                          onTap: () {
                            _showProvisionDialog(d.id);
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
