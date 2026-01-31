/*
 * MODUŁ WIFI - kurnikwifi.h
 * 
 * Zarządza połączeniem WiFi oraz synchronizacją czasu przez NTP.
 * Przechowuje dane dostępowe i status połączenia.
 */

#ifndef KURNIKWIFI_H
#define KURNIKWIFI_H

#include "main.h"

// Bufory na dane dostępowe WiFi
extern char wifi_ssid[33];      // SSID sieci WiFi (max 32 znaki + \0)
extern char wifi_password[65];  // Hasło WiFi (max 64 znaki + \0)

// Flagi statusu WiFi
extern bool wifiConfigured;  // Czy odebrano i zatwierdzono dane WiFi przez BLE
extern bool wifiConnected;   // Czy udało się połączyć z siecią WiFi

/*
 * Łączy się z siecią WiFi używając zapisanych danych dostępowych.
 * Timeout: 30 sekund. Wyświetla status połączenia i adres IP.
 */
void PolaczZWiFi();

/*
 * Synchronizuje czas systemowy z serwerem NTP.
 * Próbuje nieskończenie długo aż do uzyskania prawidłowego czasu.
 * Ustawia zegar RTC po pomyślnej synchronizacji.
 */
void UstawCzasZWiFi();

#endif