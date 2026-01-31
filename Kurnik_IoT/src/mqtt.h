/*
 * MODUŁ MQTT - mqtt.h
 * 
 * Zarządza komunikacją z brokerem MQTT.
 * Wysyła pakiety danych z czujników i odbiera wiadomości.
 */

#ifndef MQTT_H
#define MQTT_H

#include "main.h"
#include <WiFi.h>
#include <WiFiClient.h>
#include <AsyncMqttClient.h>

// Globalne obiekty MQTT (zdefiniowane w mqtt.cpp)
extern WiFiClient espClient;              // Klient TCP dla WiFi
extern AsyncMqttClient asyncMqttClient;   // Asynchroniczny klient MQTT

// Konfiguracja topiców MQTT
// Topic MQTT - format: "kurnik/" + adres MAC BLE urządzenia
// Powiększony rozmiar aby bezpiecznie pomieścić prefix + MAC (i uniknąć przepełnienia)
extern char topic[48];           // Topic MQTT (kurnik/MAC_ADDRESS)
extern bool topicInitialized;    // Czy topic został już zainicjalizowany

// Konfiguracja serwera MQTT
extern const int mqtt_port;           // Port brokera MQTT (1883)
extern const char *mqtt_broker;       // Adres IP serwera MQTT
extern const char *mqtt_username;     // Nazwa użytkownika MQTT
extern const char *mqtt_password;     // Hasło użytkownika MQTT

/*
 * Inicjalizuje klienta MQTT i ustawia callbacki dla zdarzeń.
 * Konfiguruje obsługę połączenia, rozłączenia i otrzymywania wiadomości.
 */
void InicjalizacjaMQTT();

/*
 * Próbuje nawiązać połączenie z brokerem MQTT (nieblokująco).
 * Wymaga działającego połączenia WiFi.
 */
void PolaczDoMQTT();

/*
 * Tworzy unikalny topic MQTT na podstawie adresu MAC urządzenia BLE.
 * Format: "kurnik/MAC_ADDRESS"
 */
void InicjalizacjaTopicuZ_MAC();

/*
 * Wysyła pakiet danych z wagą kury przez MQTT.
 * Format: id_urządzenia;id_kury;waga;timestamp
 */
void WyslijPakietKura(int id_urzadzenia, const char* id_kury, float waga, String timestamp);

/*
 * Callback wywoływany po otrzymaniu wiadomości MQTT.
 * Wyświetla topic i treść wiadomości na Serial.
 */
void OdpowiedzMQTT(char *topic, byte *payload, unsigned int length);

/*
 * Wysyła pakiet danych z czujników przez MQTT.
 * Automatycznie zapisuje dane do karty SD (backup lub kolejka).
 * 
 * parametr: pakiet Wskaźnik do struktury Pakiet_Danych do wysłania
 */
void WyslijPakiet(Pakiet_Danych* pakiet);
/*
 * Funkcja testowa - wypełnia tablicę pakietów sinusoidalnymi danymi.
 * Używana do testów bez fizycznych czujników.
 * 
 * parametr: pakiet Wskaźnik do tablicy pakietów
 * parametr: wielkosc Ilość pakietów do wygenerowania
 */
void TEST_zapelnij_pakiet(Pakiet_Danych* pakiet, int wielkosc);

void TEST_pakiet(Pakiet_Danych* pakiet);

#endif
