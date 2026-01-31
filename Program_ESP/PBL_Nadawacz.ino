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

class ESP_NOW_Broadcast_Peer : public ESP_NOW_Peer {
public:
  // Constructor of the class using the broadcast address
  ESP_NOW_Broadcast_Peer(uint8_t channel, wifi_interface_t iface, const uint8_t *lmk) : ESP_NOW_Peer(ESP_NOW.BROADCAST_ADDR, channel, iface, lmk) {}

  // Destructor of the class
  ~ESP_NOW_Broadcast_Peer() {
    remove();
  }

  // Function to properly initialize the ESP-NOW and register the broadcast peer
  bool begin() {
    if (!ESP_NOW.begin() || !add()) {
      log_e("Failed to initialize ESP-NOW or register the broadcast peer");
      return false;
    }
    return true;
  }

  // Function to send a message to all devices within the network
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
    Serial.printf("Received a message from device " MACSTR " (%s)\n", MAC2STR(addr()), broadcast ? "broadcast" : "unicast");
    Serial.printf("  Message: %s\n", (char *)data);
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

ESP_NOW_Broadcast_Peer broadcast_peer(ESPNOW_WIFI_CHANNEL, WIFI_IF_STA, nullptr);
ESP_NOW_Peer_Class *receiver;

// Callback called when an unknown peer sends a message
void register_new_receiver(const esp_now_recv_info_t *info, const uint8_t *data, int len, void *arg) {
  Serial.println("HALO");
  if (memcmp(info->des_addr, ESP_NOW.BROADCAST_ADDR , 6) != 0) {
    Serial.printf("Unknown peer " MACSTR " sent a unicast message\n", MAC2STR(info->src_addr));
    Serial.println("Registering the peer as a receiver");

    ESP_NOW_Peer_Class *new_receiver= new ESP_NOW_Peer_Class(info->src_addr, ESPNOW_WIFI_CHANNEL, WIFI_IF_STA, nullptr);
    if (!new_receiver->add_peer()) {
      Serial.println("Failed to register the new receiver");
      delete new_receiver;
      return;
    }
    receiver = new_receiver;
    Serial.printf("Successfully registered receiver " MACSTR "\n", MAC2STR(new_receiver->addr()));
  } 
  else {
    log_v("Received a message from " MACSTR, MAC2STR(info->src_addr));
    log_v("Igorning the message");
  }
}

void esp_setup() {
  // Initialize the Wi-Fi module
  WiFi.mode(WIFI_STA);
  WiFi.setChannel(ESPNOW_WIFI_CHANNEL);
  while (!WiFi.STA.started()) {
    delay(100);
  }

  Serial.println("PBL Nadawacz");
  Serial.println("Wi-Fi parameters:");
  Serial.println("  Mode: STA");
  Serial.println("  MAC Address: " + WiFi.macAddress());
  Serial.printf("  Channel: %d\n", ESPNOW_WIFI_CHANNEL);

  // Initialize the ESP-NOW protocol
  
  if (!broadcast_peer.begin()) {
    Serial.println("Failed to initialize broadcast peer");
    Serial.println("Reebooting in 5 seconds...");
    delay(5000);
    ESP.restart();
  }

  Serial.printf("ESP-NOW version: %d, max data length: %d\n", ESP_NOW.getVersion(), ESP_NOW.getMaxDataLen());

  // Register the new peer callback
  ESP_NOW.onNewPeer(register_new_receiver, nullptr);

  Serial.println("Setup complete.");
}

void setup() {
  Serial.begin(115200);
  esp_setup();
  

}

void loop() {
  // Searching for receiver
  if(receiver==NULL) {
    char data[32];
    snprintf(data, sizeof(data), "In search for receiver");

    Serial.printf("Broadcasting message: %s\n", data);

    if (!broadcast_peer.send_message((uint8_t *)data, sizeof(data))) {
      Serial.println("Failed to broadcast message");
    }
  }
  else {
    char data[128];
    DaneCzujnika dane_czuj;

    //Tu wpisujesz swoje dane czujników z arduino
    dane_czuj.temp_dht = 32;
    dane_czuj.wilg_dht = 32;
    dane_czuj.temp_ntc = 32;
    dane_czuj.swiatlo = 32;
    dane_czuj.gaz_dym = 32;
    dane_czuj.alkohol = 32;

    memcpy(data, &dane_czuj, sizeof(dane_czuj));
    Seiral.println("Sending data to receiver");
    if (!receiver->send_message((uint8_t *)data, sizeof(data))) {
      Serial.println("Failed to broadcast message");
    }
  } 

  delay(5000);

}
