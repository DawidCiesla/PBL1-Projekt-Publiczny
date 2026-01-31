#include <Wire.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SH110X.h>

// === KONFIGURACJA PINÓW I2C (ESP32) ===
#define I2C_ADDRESS 0x3C 
#define I2C_SDA 21
#define I2C_SCL 22

// Definicja ekranu dla sterownika SH1106G (128x64)
// -1 oznacza brak pinu reset
Adafruit_SH1106G display = Adafruit_SH1106G(128, 64, &Wire, -1);

void setup() {
  Serial.begin(115200);
  
  // Inicjalizacja magistrali I2C na konkretnych pinach ESP32
  Wire.begin(I2C_SDA, I2C_SCL);

  Serial.println("Start testu ekranu SH1106...");

  // Próba uruchomienia ekranu
  // Jeśli nie działa, spróbuj zmienić adres na 0x3D
  if(!display.begin(I2C_ADDRESS, true)) {
    Serial.println("BŁĄD: Nie znaleziono ekranu SH1106!");
    Serial.println("Sprawdź połączenia: SDA->G21, SCL->G22, VCC->3.3V, GND->GND");
    while(1); // Zatrzymaj program
  }

  Serial.println("Ekran znaleziony!");
  
  // WAŻNE: Wyczyść losowe 'śmieci' z pamięci ekranu po starcie
  display.clearDisplay();
  display.display();
  delay(500);

  // === Rysowanie statyczne ===
  display.setTextSize(1);
  display.setTextColor(SH110X_WHITE);
  
  display.setCursor(0, 0);
  display.println("TEST ARDUINO IDE");
  
  display.setCursor(0, 15);
  display.println("Model: SH1106 1.3\"");
  
  display.setCursor(0, 30);
  display.println("Status: OK");

  // Rysowanie ramki dookoła ekranu (sprawdza czy piksele są na krawędziach)
  display.drawRect(0, 0, 128, 64, SH110X_WHITE);
  
  display.display(); // Wyślij bufor na ekran
}

void loop() {
  // === Prosta animacja w pętli ===
  // Miganie tekstu na dole ekranu
  
  display.fillRect(10, 50, 100, 10, SH110X_BLACK); // Wyczyść miejsce na tekst
  display.setCursor(10, 50);
  display.print("Dziala...");
  display.display();
  delay(1000);

  display.fillRect(10, 50, 100, 10, SH110X_BLACK); // Wyczyść tekst
  display.display();
  delay(500);
}
