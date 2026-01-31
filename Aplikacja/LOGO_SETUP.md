# Logo & Splash Screen Setup - MacNuggetNet

Data: 18 stycznia 2026

---

## ⚡ Szybki Start (3 minuty)

### 1. Przygotuj grafiki

Umieść 3 pliki PNG w `assets/images/`:

```text
logo.png             # 1024×1024px (pełne logo)
logo_clean.png       # 1024×1024px (sam symbol)
logo_with_text.png   # 1080×1920px (splash screen)
```

### 2. Uruchom setup

```bash
chmod +x setup_logo.sh
./setup_logo.sh
```

### 3. Testuj

```bash
flutter run
```

---

## 📋 Co zostało zmienione

### pubspec.yaml

```yaml
flutter_launcher_icons:
  android: true
  ios: true
  windows: true
  macos: true
  adaptive_icon_background: "#00BCD4"
  adaptive_icon_foreground: "assets/images/logo_clean.png"

flutter_native_splash:
  color: "#F5F5F5"
  image: assets/images/logo_with_text.png
```

### Android

- `mipmap-anydpi-v26/ic_launcher.xml` - Adaptive icons
- `values/colors.xml` - Kolor główny #00BCD4
- `values-night/colors.xml` - Dark mode kolory
- `values/styles.xml` - Launch theme
- `values-v31/styles.xml` - Android 12+ splash

### iOS

- `Base.lproj/LaunchScreen.storyboard` - Launch screen (#F5F5F5)
- `Info.plist` - Konfiguracja launch screen

---

## 🎯 Funkcjonalności

- ✅ Adaptive Icons (Android API 21+)
- ✅ Material You (Android 12+)
- ✅ Dark Mode (Android 10+)
- ✅ Launch Screen iOS z kolorystyką
- ✅ Splash Screen na wszystkich platformach

---

## 🎨 Kolory

| Element   | Jasny   | Ciemny  |
| --------- | ------- | ------- |
| Główny    | #00BCD4 | #00BCD4 |
| Tło       | #F5F5F5 | #121212 |
| Icon BG   | #00BCD4 | #1A1A1A |

---

## ⚠️ Problemy?

### Ikona się nie zmienia

```bash
flutter clean
flutter pub run flutter_launcher_icons:main
```

### iOS Launch Screen biały

```bash
cd ios && pod install && cd ..
flutter clean && flutter run
```

### Splash screen nie widać

Dodaj opóźnienie w `main()`:

```dart
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  Future.delayed(const Duration(seconds: 1), () {
    runApp(const ProviderScope(child: MacNuggetNetApp()));
  });
}
```

---

## 🔧 Ręczny setup (jeśli skrypt nie zadziała)

```bash
flutter pub get
flutter pub run flutter_launcher_icons:main
flutter pub run flutter_native_splash:create
cd ios && pod install && cd ..
flutter clean && flutter pub get
flutter run
```

---

## 📚 Dokumentacja Flutter

- [flutter_launcher_icons](https://pub.dev/packages/flutter_launcher_icons)
- [flutter_native_splash](https://pub.dev/packages/flutter_native_splash)

---

## ✅ Checklist

- [ ] Przygotowano 3 pliki PNG
- [ ] Uruchomiono setup_logo.sh
- [ ] flutter clean && flutter pub get
- [ ] flutter run testa na Android
- [ ] flutter run testa na iOS
- [ ] Ikony pojawiły się w dock'u/home screen

---

## Implementacja gotowa

🚀
