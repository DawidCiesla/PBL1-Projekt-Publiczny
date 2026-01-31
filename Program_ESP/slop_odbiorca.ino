#include "ESP32_NOW.h"
#include "WiFi.h"
#include <esp_mac.h>

/* --- Struktura danych (Musi być identyczna jak u nadawcy) --- */
struct DaneCzujnika {
  double temp_dht;
  double wilg_dht;
  double temp_ntc;
  double swiatlo;
  double gaz_dym;
  double alkohol;
};

#define ESPNOW_WIFI_CHANNEL 6

/* --- Klasa Odbiorcy --- */
class ESP_NOW_Receiver_Peer : public ESP_NOW_Peer {
public:
  ESP_NOW_Receiver_Peer(const uint8_t *mac_addr, uint8_t channel, wifi_interface_t iface, const uint8_t *lmk) 
    : ESP_NOW_Peer(mac_addr, channel, iface, lmk) {}

  // Publiczna funkcja do rejestracji peera (rozwiązuje błąd 'protected')
  bool add_peer() {
    return add();
  }

  // Funkcja wywoływana automatycznie przy odbiorze danych
  void onReceive(const uint8_t *data, size_t len, bool broadcast) override {
    if (len == sizeof(DaneCzujnika)) {
      DaneCzujnika odebrane;
      memcpy(&odebrane, data, sizeof(DaneCzujnika));

      Serial.println("\n>>> ODEBRANO DANE Z CZUJNIKÓW <<<");
      Serial.printf("Temp DHT: %.2f C | Wilg: %.2f %%\n", odebrane.temp_dht, odebrane.wilg_dht);
      Serial.printf("Temp NTC: %.2f C | LDR:  %.2f %%\n", odebrane.temp_ntc, odebrane.swiatlo);
      Serial.printf("Gaz/Dym:  %.2f %% | Alk:  %.2f %%\n", odebrane.gaz_dym, odebrane.alkohol);
      Serial.println("---------------------------------");
    } else {
      // Obsługa wiadomości tekstowych (np. "In search for receiver")
      Serial.printf("Odebrano tekst: %s\n", (char*)data);
    }
  }

  bool send_reply(const char* msg) {
    return send((uint8_t*)msg, strlen(msg) + 1);
  }
};

ESP_NOW_Receiver_Peer *sender_node = NULL;

/* --- Callback dla nowych urządzeń --- */
void register_new_sender(const esp_now_recv_info_t *info, const uint8_t *data, int len, void *arg) {
  // Sprawdzamy czy to wiadomość rozgłoszeniowa
  if (memcmp(info->des_addr, ESP_NOW.BROADCAST_ADDR, 6) == 0) {
    Serial.printf("Wykryto nadawcę: " MACSTR ". Rejestruję...\n", MAC2STR(info->src_addr));

    if (sender_node != NULL) {
      delete sender_node;
    }

    sender_node = new ESP_NOW_Receiver_Peer(info->src_addr, ESPNOW_WIFI_CHANNEL, WIFI_IF_STA, NULL);
    
    // Używamy naszej publicznej funkcji add_peer() zamiast add()
    if (sender_node->add_peer()) {
      Serial.println("Nadawca zarejestrowany. Wysyłam potwierdzenie...");
      sender_node->send_reply("I am here!"); 
    } else {
      Serial.println("Błąd rejestracji nadawcy.");
      delete sender_node;
      sender_node = NULL;
    }
  }
}

void setup() {
  Serial.begin(115200);
  delay(1000);

  WiFi.mode(WIFI_STA);
  WiFi.setChannel(ESPNOW_WIFI_CHANNEL);
  while (!WiFi.STA.started()) delay(100);

  if (!ESP_NOW.begin()) {
    Serial.println("Błąd ESP-NOW. Restart...");
    delay(3000);
    ESP.restart();
  }

  // Rejestracja callbacku, który wykryje nadawcę
  ESP_NOW.onNewPeer(register_new_sender, NULL);

  Serial.println("Odbiorca gotowy. Mój MAC: " + WiFi.macAddress());
  Serial.println("Czekam na nadawcę...");
}

void loop() {
  delay(1000);
}