/*
    ESP-NOW Broadcast Slave
    Lucas Saavedra Vaz - 2024

    This sketch demonstrates how to receive broadcast messages from a master device using the ESP-NOW protocol.

    The master device will broadcast a message every 5 seconds to all devices within the network.

    The slave devices will receive the broadcasted messages. If they are not from a known master, they will be registered as a new master
    using a callback function.
*/

#include "ESP32_NOW.h"
#include "WiFi.h"

#include <esp_mac.h>  // For the MAC2STR and MACSTR macros

#include <vector>

/* Definitions */

#define ESPNOW_WIFI_CHANNEL 6

struct DaneCzujnika{
  double temp_dht;
  double wilg_dht;
  double temp_ntc;
  double swiatlo;
  double gaz_dym;
  double alkohol;
};

/* Classes */

// Creating a new class that inherits from the ESP_NOW_Peer class is required.

class ESP_NOW_Peer_Class : public ESP_NOW_Peer {
public:
  // Constructor of the class
  ESP_NOW_Peer_Class(const uint8_t *mac_addr, uint8_t channel, wifi_interface_t iface, const uint8_t *lmk) : ESP_NOW_Peer(mac_addr, channel, iface, lmk) {}

  // Destructor of the class
  ~ESP_NOW_Peer_Class() {}

  // Function to register the master peer
  bool add_peer() {
    if (!add()) {
      log_e("Failed to register the broadcast peer");
      return false;
    }
    return true;
  }

  // Function to print the received messages from the master
  void onReceive(const uint8_t *data, size_t len, bool broadcast) {
    Serial.printf("Received a message from sender " MACSTR " (%s)\n", MAC2STR(addr()), broadcast ? "broadcast" : "unicast");
    if (broadcast) {
      char* tekst = (char*)data;
      Serial.printf("Message: %s\n",data);

      char data_to_send[32];
      snprintf(data_to_send,sizeof(data_to_send),"I am your receiver");
      send_message((uint8_t*)data_to_send,sizeof(data_to_send));

    }
    else {
      DaneCzujnika dane_druk;
      memcpy(&dane_druk, data, sizeof(dane_druk));
      
      Serial.printf("Temperatura z DHT: %lf\n",dane_druk.temp_dht);
      Serial.printf("Wilgotność z DHT: %lf\n",dane_druk.wilg_dht);
      Serial.printf("Temperatura z NTC: %lf\n",dane_druk.temp_ntc);
      Serial.printf("Swiatlo: %lf\n",dane_druk.swiatlo);
      Serial.printf("Gaz/Dym: %lf\n",dane_druk.gaz_dym);
      Serial.printf("Alkohol: %lf\n",dane_druk.alkohol);
    }


  }
  bool send_message(const uint8_t *data, size_t len) {
    if (!send(data, len)) {
      log_e("Failed to broadcast message");
      return false;
    }
    return true;
  }
};

/* Global Variables */

// List of all the masters. It will be populated when a new master is registered
// Note: Using pointers instead of objects to prevent dangling pointers when the vector reallocates
std::vector<ESP_NOW_Peer_Class *> senders;

/* Callbacks */

// Callback called when an unknown peer sends a message
void register_new_sender(const esp_now_recv_info_t *info, const uint8_t *data, int len, void *arg) {
  if (memcmp(info->des_addr, ESP_NOW.BROADCAST_ADDR, 6) == 0) {
    Serial.printf("Unknown peer " MACSTR " sent a broadcast message\n", MAC2STR(info->src_addr));
    Serial.println("Registering the peer as a sender");

    ESP_NOW_Peer_Class *new_sender= new ESP_NOW_Peer_Class(info->src_addr, ESPNOW_WIFI_CHANNEL, WIFI_IF_STA, nullptr);
    if (!new_sender->add_peer()) {
      Serial.println("Failed to register the new sender");
      delete new_sender;
      return;
    }
    senders.push_back(new_sender);
    Serial.printf("Successfully registered master " MACSTR " (total masters: %zu)\n", MAC2STR(new_sender->addr()), senders.size());
  } else {
    // The receiver will only receive unicast messages
    log_v("Received a unicast message from " MACSTR, MAC2STR(info->src_addr));
    log_v("Igorning the message");
  }
}

/* Main */

void setup() {
  Serial.begin(115200);

  // Initialize the Wi-Fi module
  WiFi.mode(WIFI_STA);
  WiFi.setChannel(ESPNOW_WIFI_CHANNEL);
  while (!WiFi.STA.started()) {
    delay(100);
  }
  Serial.println("ESP-NOW Example - Broadcast Slave");
  Serial.println("Wi-Fi parameters:");
  Serial.println("  Mode: STA");
  Serial.println("  MAC Address: " + WiFi.macAddress());
  Serial.printf("  Channel: %d\n", ESPNOW_WIFI_CHANNEL);

  // Initialize the ESP-NOW protocol
  if (!ESP_NOW.begin()) {
    Serial.println("Failed to initialize ESP-NOW");
    Serial.println("Reeboting in 5 seconds...");
    delay(5000);
    ESP.restart();
  }

  Serial.printf("ESP-NOW version: %d, max data length: %d\n", ESP_NOW.getVersion(), ESP_NOW.getMaxDataLen());

  // Register the new peer callback
  ESP_NOW.onNewPeer(register_new_sender, nullptr);

  Serial.println("Setup complete. Waiting for a sender to broadcast a message...");
}

void loop() {
  // Print debug information every 24 seconds
  static unsigned long last_debug = 0;
  if (millis() - last_debug > 24000) {
    last_debug = millis();
    Serial.printf("Registered senders: %zu\n", senders.size());
    for (size_t i = 0; i < senders.size(); i++) {
      if (senders[i]) {
        Serial.printf("  Senders %zu: " MACSTR "\n", i, MAC2STR(senders[i]->addr()));
      }
    }
  }

  delay(100);
}
