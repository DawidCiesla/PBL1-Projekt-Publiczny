// oled.cpp
#include "oled.h"
#include <Wire.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SH110X.h>
#include "czujniki.h"

// Konfiguracja ekranu
static const int SCREEN_WIDTH = 128;
static const int SCREEN_HEIGHT = 64;

// Utworzenie instancji wyświetlacza (I2C) dla sterownika SH1106G
static Adafruit_SH1106G display(SCREEN_WIDTH, SCREEN_HEIGHT, &Wire, -1);

OLEDDisplay oled;

OLEDDisplay::OLEDDisplay(): _lastAnimMillis(0), _animPhase(0), _contrast(0) {}

bool OLEDDisplay::begin() {
  Wire.begin();
  // Sygnatura wywołania SH110x: begin(i2caddr = 0x3C, reset = true)
  if(!display.begin(0x3C, true)) {
    return false;
  }
  display.clearDisplay();
  display.display();
  return true;
}

void OLEDDisplay::_drawProgressBar(uint8_t progress) {
  const int bw = SCREEN_WIDTH - 16;
  const int bh = 8;
  const int bx = 8;
  const int by = SCREEN_HEIGHT - 12;

  display.drawRect(bx, by, bw, bh, SH110X_WHITE);
  int fill = (progress * (bw - 2)) / 100;
  if(fill > 0) display.fillRect(bx + 1, by + 1, fill, bh - 2, SH110X_WHITE);
}

void OLEDDisplay::showBootScreen(const char* title, const char* line, uint8_t progress) {
  display.clearDisplay();

  display.setTextColor(SH110X_WHITE);
  display.setTextSize(2);
  int16_t x1, y1;
  uint16_t w, h;
  display.getTextBounds(title, 0, 0, &x1, &y1, &w, &h);
  display.setCursor((SCREEN_WIDTH - w) / 2, 8);
  display.print(title);

  display.setTextSize(1);
  display.getTextBounds(line, 0, 0, &x1, &y1, &w, &h);
  display.setCursor((SCREEN_WIDTH - w) / 2, 34);
  display.print(line);

  _drawProgressBar(progress);
  display.display();
}

void OLEDDisplay::showLoadingAnimated() {
  const unsigned long interval = 180;
  unsigned long now = millis();
  if(now - _lastAnimMillis < interval) return;
  _lastAnimMillis = now;
  const char* spinner = "|/-\\";
  char s[2] = { spinner[_animPhase % 4], 0 };
  _animPhase++;

  display.clearDisplay();
  display.setTextColor(SH110X_WHITE);
  display.setTextSize(1);
  display.setCursor(8, 12);
  display.print("Uruchamianie");

  display.setTextSize(2);
  display.setCursor(SCREEN_WIDTH - 24, 8);
  display.print(s);
  display.setTextSize(1);
  display.setCursor(8, 44);
  display.print("Trwa inicjalizacja...");

  display.display();
}

void OLEDDisplay::showProvisioningScreen(const char* addr) {
  const unsigned long interval = 200;
  unsigned long now = millis();
  if(now - _lastAnimMillis >= interval) {
    _lastAnimMillis = now;
    _animPhase++;
  }
  const char* spinner = "|/-\\";
  char s[2] = { spinner[_animPhase % 4], 0 };

  display.clearDisplay();
  display.setTextColor(SH110X_WHITE);

  display.setTextSize(1);
  display.setCursor(10, 2);
  display.print("KONFIGURACJA");

  display.setTextSize(1);
  display.setCursor(2, 18);
  display.print("Otworz aplikacje");
  display.setCursor(2, 28);
  display.print("i polacz sie z");
  display.setCursor(2, 38);
  display.print("urzadzeniem...");

  if(addr) {
    display.setTextSize(1);
    display.setCursor(2, 52);
    display.print(addr);
  }

  display.setTextSize(1);
  display.setCursor(SCREEN_WIDTH - 16, 2);
  display.print(s);

  display.display();
}

static void _printValueLabel(const char* label, const char* value, int y) {
  display.setTextSize(1);
  display.setCursor(2, y);
  display.print(label);
  display.setCursor(86, y);
  display.print(value);
}

void OLEDDisplay::showConnectionSuccess(const char* ssid) {
  display.clearDisplay();
  display.setTextColor(SH110X_WHITE);

  display.setTextSize(2);
  display.setCursor(30, 8);
  display.print("SUKCES!");

  display.setTextSize(1);
  display.setCursor(6, 32);
  display.print("Polaczono z sieciq:");

  if(ssid) {
    display.setTextSize(1);
    display.setCursor(6, 44);
    display.print(ssid);
  }

  display.setTextSize(1);
  display.setCursor(20, 56);
  display.print("Uruchamianie...");

  display.display();
}

void OLEDDisplay::showWiFiInit(uint8_t progress) {
  display.clearDisplay();
  display.setTextColor(SH110X_WHITE);

  display.setTextSize(1);
  display.setCursor(10, 20);
  display.print("Laczenie z WiFi...");

  display.setTextSize(1);
  display.setCursor(30, 40);
  display.print("Prosze czekac");

  _drawProgressBar(progress);
  display.display();
}

void OLEDDisplay::showNTPSync(uint8_t progress) {
  display.clearDisplay();
  display.setTextColor(SH110X_WHITE);

  display.setTextSize(1);
  display.setCursor(6, 20);
  display.print("Synchronizacja czasu");
  display.setCursor(20, 32);
  display.print("z serwera NTP...");

  _drawProgressBar(progress);
  display.display();
}

void OLEDDisplay::showMQTTInit(uint8_t progress) {
  display.clearDisplay();
  display.setTextColor(SH110X_WHITE);

  display.setTextSize(1);
  display.setCursor(10, 20);
  display.print("Laczenie z MQTT...");

  display.setTextSize(1);
  display.setCursor(30, 40);
  display.print("Prosze czekac");

  _drawProgressBar(progress);
  display.display();
}

void OLEDDisplay::showSensorReadings(float dhtT, float dhtH, float ntcT, int ldr, int eCO2, int tvoc) {
  char buf[32];
  display.clearDisplay();
  display.setTextColor(SH110X_WHITE);

  // Temperatura z DHT
  if(!isnan(dhtT) && dhtT != 0.0f) snprintf(buf, sizeof(buf), "%.1f C", dhtT); else strcpy(buf, "---");
  _printValueLabel("DHT T:", buf, 4);

  // Wilgotność z DHT
  if(!isnan(dhtH) && dhtH != 0.0f) snprintf(buf, sizeof(buf), "%.1f %%", dhtH); else strcpy(buf, "---");
  _printValueLabel("DHT H:", buf, 16);

  // Temperatura z NTC
  if(!isnan(ntcT)) snprintf(buf, sizeof(buf), "%.1f C", ntcT); else strcpy(buf, "---");
  _printValueLabel("NTC:", buf, 28);

  // LDR (percent)
  // LDR w luksach
  snprintf(buf, sizeof(buf), "%d lx", ldr);
  _printValueLabel("LDR:", buf, 40);

  // eCO2 (ppm)
  display.setTextSize(1);
  display.setCursor(2, 52);
  if(eCO2 >= 0) snprintf(buf, sizeof(buf), "CO2:%dppm", eCO2); else strcpy(buf, "CO2:--");
  display.print(buf);
  
  // TVOC (ppb)
  display.setCursor(66, 52);
  if(tvoc >= 0) snprintf(buf, sizeof(buf), "TVOC:%dppb", tvoc); else strcpy(buf, "TVOC:--");
  display.print(buf);

  display.display();
}

void OLEDDisplay::showConnectionStatus(bool wifiConnected, bool mqttConnected) {
  display.clearDisplay();
  display.setTextColor(SH110X_WHITE);

  display.setTextSize(2);
  int16_t x1, y1;
  uint16_t w, h;
  display.getTextBounds("STATUS", 0, 0, &x1, &y1, &w, &h);
  display.setCursor((SCREEN_WIDTH - w) / 2, 4);
  display.print("STATUS");

  display.setTextSize(1);
  display.setCursor(10, 28);
  display.print("WiFi: ");
  display.print(wifiConnected ? "Polaczony" : "Rozlaczony");

  display.setCursor(10, 42);
  display.print("MQTT: ");
  display.print(mqttConnected ? "Polaczony" : "Rozlaczony");

  display.display();
}

void OLEDDisplay::showMeshStatus(int nodeCount) {
  display.clearDisplay();
  display.setTextColor(SH110X_WHITE);

  display.setTextSize(2);
  int16_t x1, y1;
  uint16_t w, h;
  display.getTextBounds("MESH", 0, 0, &x1, &y1, &w, &h);
  display.setCursor((SCREEN_WIDTH - w) / 2, 4);
  display.print("MESH");

  display.setTextSize(1);
  display.setCursor(10, 30);
  char buf[32];
  snprintf(buf, sizeof(buf), "Wezly: %d", nodeCount);
  display.print(buf);

  display.setCursor(10, 44);
  // Pokaż połączono / niepołączono (bez znaków diakrytycznych)
  if (nodeCount > 0) {
    display.print("Polaczono");
  } else {
    display.print("Niepolaczono");
  }

  display.display();
}

void OLEDDisplay::clear() {
  display.clearDisplay();
  display.display();
}

void OLEDDisplay::setContrast(uint8_t c) {
  // Wiele wersji biblioteki Adafruit nie udostępnia publicznej metody ustawiania kontrastu; przechowujemy wartość do celów referencyjnych.
  _contrast = c;
  (void)c;
}
