// oled.h
// OLED framework for SSD1306 128x64 I2C display
// Provides boot/loading menu and sensor readings menu

#ifndef OLED_H
#define OLED_H

#include <Arduino.h>
#include <stdint.h>

class OLEDDisplay {
public:
  OLEDDisplay();
  // Initialize the display. Returns true on success.
  bool begin();

  // Show a full-screen boot/startup view with optional progress (0-100).
  void showBootScreen(const char* title = "KURNIK", const char* line = "Uruchamianie...", uint8_t progress = 0);

  // Call repeatedly during initialization to animate a small spinner.
  void showLoadingAnimated();

  // Show provisioning / app-connection screen. Optional `addr` can contain
  // BLE address or device name to display.
  void showProvisioningScreen(const char* addr = nullptr);

  // Show successful connection confirmation screen with WiFi SSID.
  void showConnectionSuccess(const char* ssid = nullptr);

  // Show WiFi initialization screen with progress bar.
  void showWiFiInit(uint8_t progress = 0);

  // Show NTP time synchronization screen with progress bar.
  void showNTPSync(uint8_t progress = 0);

  // Show MQTT connection initialization screen with progress bar.
  void showMQTTInit(uint8_t progress = 0);

  // Display current sensor readings with pre-read values.
  void showSensorReadings(float dhtTemp, float dhtHum, float ntcTemp, int ldrVal, int eCO2Val, int tvocVal);

  // Display connection status screen with WiFi and MQTT info.
  void showConnectionStatus(bool wifiConnected, bool mqttConnected);

  // Display mesh status: number of connected nodes
  void showMeshStatus(int nodeCount);

  // Clear the display buffer and push to screen.
  void clear();

  // Adjust contrast 0-255 (best-effort, may be no-op depending on library build).
  void setContrast(uint8_t c);

private:
  unsigned long _lastAnimMillis;
  uint8_t _animPhase;
  uint8_t _contrast;
  void _drawProgressBar(uint8_t progress);
};

// Globalna instancja do wygodnego użycia w całym projekcie
extern OLEDDisplay oled;

#endif // OLED_H
