#!/bin/bash
# Setup dla Logo i Splash Screen - MacNuggetNet

echo "🚀 MacNuggetNet - Logo & Splash Screen Setup"
echo "=============================================="
echo ""

# Weryfikacja zasobów
echo "1️⃣ Sprawdzanie zasobów..."

required_assets=(
    "assets/images/logo.png"
    "assets/images/logo_clean.png"
    "assets/images/logo_with_text.png"
)

missing=false
for asset in "${required_assets[@]}"; do
    if [ ! -f "$asset" ]; then
        echo "   ❌ Brakuje: $asset"
        missing=true
    else
        echo "   ✅ $asset"
    fi
done

if [ "$missing" = true ]; then
    echo ""
    echo "⚠️ Brakuje zasobów graficznych!"
    exit 1
fi

echo ""
echo "2️⃣ Instalacja zależności..."
flutter pub get || exit 1

echo ""
echo "3️⃣ Generowanie ikon..."
flutter pub run flutter_launcher_icons:main || exit 1

echo ""
echo "4️⃣ Generowanie splash screen..."
flutter pub run flutter_native_splash:create || exit 1

echo ""
echo "5️⃣ Konfiguracja iOS..."
cd ios
pod install > /dev/null 2>&1
cd ..

echo ""
echo "6️⃣ Czyszczenie cache'u..."
flutter clean > /dev/null 2>&1
flutter pub get > /dev/null 2>&1

echo ""
echo "✨ Setup zakończony!"
echo "=============================================="
echo "Testuj: flutter run"
