import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/config/app_config.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Załaduj konfigurację
  try {
    await AppConfig().initialize();
  } catch (e) {
    // Konfiguracja nie załadowana
  }
  
  runApp(const ProviderScope(child: MacNuggetNetApp()));
}