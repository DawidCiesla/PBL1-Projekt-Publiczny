#include "ESP32_NOW.h"
#include "WiFi.h"
#include <esp_mac.h>
#include <vector>
#include <DHT.h>
#include <Wire.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SH110X.h>
#include <Arduino.h>

/* --- Definicje Pinów i Parametrów --- */
#define ESPNOW_WIFI_CHANNEL 6
#define I2C_SDA 8
#define I2C_SCL 9
#define PIN_DHT22 4 
#define PIN_NTC 5
#define PIN_LDR 6
#define PIN_MQ135 7
#define PIN_MQ3 15

/* --- Struktura Danych --- */
struct DaneCzujnika {
  double temp_dht;
  double wilg_dht;
  double temp_ntc;
  double swiatlo;
  double gaz_dym;
  double alkohol;
};

/* --- Obiekty --- */
Adafruit_SH1106G display = Adafruit_SH1106G(128, 64, &Wire, -1);
DHT dht22(PIN_DHT22, DHT22);
const float BETA = 3950;

/* --- Klasy ESP-NOW (Z Twojego kodu) --- */
class ESP_NOW_Broadcast_Peer : public ESP_NOW_Peer {
public:
  ESP_NOW_Broadcast_Peer(uint8_t channel, wifi_interface_t iface, const uint8_t *lmk) : ESP_NOW_Peer(ESP_NOW.BROADCAST_ADDR, channel, iface, lmk) {}
  ~ESP_NOW_Broadcast_Peer() { remove(); }
  bool begin() {
    if (!ESP_NOW.begin() || !add()) {
      log_e("Failed to initialize ESP-NOW or register the broadcast peer");
      return false;
    }
    return true;
  }
  bool send_message(const uint8_t *data, size_t len) {
    if (!send(data, len)) {
      log_e("Failed to broadcast message");
      return false;
    }
    return true;
  }
};

class ESP_NOW_Peer_Class : public ESP_NOW_Peer {
public:
  ESP_NOW_Peer_Class(const uint8_t *mac_addr, uint8_t channel, wifi_interface_t iface, const uint8_t *lmk) : ESP_NOW_Peer(mac_addr, channel, iface, lmk) {}
  bool add_peer() {
    if (!add()) {
      log_e("Failed to register the peer");
      return false;
    }
    return true;
  }
  void onReceive(const uint8_t *data, size_t len, bool broadcast) {
    Serial.printf("Received a message from device " MACSTR " (%s)\n", MAC2STR(addr()), broadcast ? "broadcast" : "unicast");
  }
  bool send_message(const uint8_t *data, size_t len) {
    return send(data, len);
  }
};

/* --- Zmienne Globalne ESP-NOW --- */
ESP_NOW_Broadcast_Peer broadcast_peer(ESPNOW_WIFI_CHANNEL, WIFI_IF_STA, nullptr);
ESP_NOW_Peer_Class *receiver = NULL;

/* --- Funkcje Pomiarowe (Z Twojego kodu) --- */
float measureDHT22_Temp() {
  float t = dht22.readTemperature();
  return isnan(t) ? 0.0 : t;
}
float measureDHT22_Hum() {
  float h = dht22.readHumidity();
  return isnan(h) ? 0.0 : h;
}
float measureNTC() {
  int raw = analogRead(PIN_NTC);
  raw = constrain(raw, 1, 4094);
  return 1 / (log(1 / (4095. / raw - 1)) / BETA + 1.0 / 298.15) - 273.15;
}
int measureLDR() {
  int raw = analogRead(PIN_LDR);
  raw = constrain(raw, 500, 3800);
  return map(raw, 3800, 500, 0, 100);
}
int measureMQ135() {
  const int maxEffectiveADC = (5.0 / 3.3) * (1.0 / 3.0) * 4095;
  return map(analogRead(PIN_MQ135), 0, maxEffectiveADC, 0, 100);
}
int measureMQ3() {
  const int maxEffectiveADC = (5.0 / 3.3) * (1.0 / 3.0) * 4095;
  return map(analogRead(PIN_MQ3), 0, maxEffectiveADC, 0, 100);
}

/* --- Callback ESP-NOW --- */
void register_new_receiver(const esp_now_recv_info_t *info, const uint8_t *data, int len, void *arg) {
  if (memcmp(info->des_addr, ESP_NOW.BROADCAST_ADDR, 6) != 0) {
    Serial.printf("Unknown peer " MACSTR " sent a unicast message\n", MAC2STR(info->src_addr));
    if (receiver != NULL) delete receiver;
    receiver = new ESP_NOW_Peer_Class(info->src_addr, ESPNOW_WIFI_CHANNEL, WIFI_IF_STA, nullptr);
    if (!receiver->add_peer()) {
      Serial.println("Failed to register the new receiver");
      delete receiver;
      receiver = NULL;
    } else {
      Serial.printf("Successfully registered receiver " MACSTR "\n", MAC2STR(receiver->addr()));
    }
  }
}

void setup() {
  Serial.begin(115200);

  // Inicjalizacja hardware (Czujniki i OLED)
  analogReadResolution(12);
  analogSetAttenuation(ADC_11db);
  pinMode(PIN_LDR, INPUT);
  pinMode(PIN_NTC, INPUT);
  pinMode(PIN_MQ135, INPUT);
  pinMode(PIN_MQ3, INPUT);
  dht22.begin();
  Wire.begin(I2C_SDA, I2C_SCL);

  if (!display.begin(0x3C, true)) {
    Serial.println("Brak OLED");
  }
  display.setTextColor(SH110X_WHITE);
  display.clearDisplay();

  // Inicjalizacja WiFi i ESP-NOW
  WiFi.mode(WIFI_STA);
  WiFi.setChannel(ESPNOW_WIFI_CHANNEL);
  while (!WiFi.STA.started()) delay(100);

  if (!broadcast_peer.begin()) {
    Serial.println("Failed to initialize ESP-NOW");
    delay(5000);
    ESP.restart();
  }

  ESP_NOW.onNewPeer(register_new_receiver, nullptr);
  Serial.println("Setup complete.");
}

void loop() {
  // 1. Pomiar danych
  DaneCzujnika dane_czuj;
  dane_czuj.temp_dht = measureDHT22_Temp();
  dane_czuj.wilg_dht = measureDHT22_Hum();
  dane_czuj.temp_ntc = measureNTC();
  dane_czuj.swiatlo  = measureLDR();
  dane_czuj.gaz_dym  = measureMQ135();
  dane_czuj.alkohol  = measureMQ3();

  // 2. Wyświetlanie na OLED
  display.clearDisplay();
  display.setTextSize(1);
  display.setCursor(0, 0);
  display.printf("Temp DHT: %.1f C\n", dane_czuj.temp_dht);
  display.printf("Wilg DHT: %.1f %%\n", dane_czuj.wilg_dht);
  display.printf("Temp NTC: %.1f C\n", dane_czuj.temp_ntc);
  display.printf("Swiatlo:  %.0f %%\n", dane_czuj.swiatlo);
  display.printf("Gaz/dym:  %.0f %%\n", dane_czuj.gaz_dym);
  display.printf("Alkohol:  %.0f %%\n", dane_czuj.alkohol);
  display.display();

  // 3. Logika ESP-NOW
  if (receiver == NULL) {
    char search_msg[] = "In search for receiver";
    Serial.println(search_msg);
    broadcast_peer.send_message((uint8_t *)search_msg, sizeof(search_msg));
  } else {
    Serial.println("Sending sensor data to receiver...");
    if (!receiver->send_message((uint8_t *)&dane_czuj, sizeof(dane_czuj))) {
      Serial.println("Failed to send data");
    }
  }

  delay(2000); // Zmniejszyłem nieco opóźnienie, by OLED był bardziej responsywny
}