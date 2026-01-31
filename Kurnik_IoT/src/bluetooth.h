/*
 * MODUŁ BLUETOOTH - bluetooth.h
 * 
 * Odpowiada za konfigurację WiFi przez BLE (Bluetooth Low Energy).
 * Umożliwia użytkownikowi ustawienie SSID i hasła WiFi przez aplikację mobilną.
 */

#ifndef BLUETOOTH_H
#define BLUETOOTH_H

#include "main.h"

// Globalne obiekty NimBLE współdzielone między modułami
extern NimBLEServer* pServer;                      // Serwer BLE
extern NimBLEService* wifiService;                 // Serwis WiFi provisioning
extern NimBLECharacteristic* ssidCharacteristic;   // Charakterystyka do przekazania SSID
extern NimBLECharacteristic* passCharacteristic;   // Charakterystyka do przekazania hasła
extern NimBLECharacteristic* applyCharacteristic;  // Charakterystyka do zatwierdzenia ustawień
extern NimBLEAdvertising* pAdvertising;            // Obiekt reklamowania BLE

/*
 * Inicjalizuje moduł Bluetooth i konfiguruje wszystkie charakterystyki BLE.
 * Tworzy serwis WiFi provisioning z UUID i ustawia callbacki.
 */
void InicjalizacjaBluetooth();

/*
 * Rozpoczyna nadawanie BLE i czeka na konfigurację WiFi od użytkownika.
 * Blokuje wykonanie do momentu otrzymania i zatwierdzenia danych WiFi.
 */
void NadawaniePrzezBLE();

#endif
