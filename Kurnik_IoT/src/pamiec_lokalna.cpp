/*
 * pamiec_lokalna.cpp
 * 
 * Moduł zarządzania pamięcią EEPROM dla trwałego przechowywania danych WiFi.
 * Obsługuje:
 * - Zapisywanie SSID i hasła WiFi do EEPROM
 * - Odczytywanie zapisanych danych przy starcie
 * - Reset pamięci (usunięcie danych WiFi)
 * 
 */

#include "pamiec_lokalna.h"
#include "kurnikwifi.h"

// Stałe definiujące układ pamięci EEPROM
static constexpr int SSID_MAX = 32;        // Maksymalna długość SSID (32 znaki)
static constexpr int PASS_MAX = 64;        // Maksymalna długość hasła (64 znaki)
static constexpr int EEPROM_SIZE = 256;    // Całkowity rozmiar EEPROM (256 bajtów)

// Adresy w pamięci EEPROM
static constexpr int SSID_LEN_ADDR = 0;                      // Adres długości SSID
static constexpr int SSID_ADDR = 1;                          // Początek SSID (adres 1)
static constexpr int PASS_LEN_ADDR = (SSID_ADDR + SSID_MAX); // Adres długości hasła (33)
static constexpr int PASS_ADDR = (PASS_LEN_ADDR + 1);        // Początek hasła (adres 34)

/**
 * Inicjalizuje pamięć EEPROM.
 * Dla ESP32/ESP8266 wymagane jest wywołanie EEPROM.begin() przed użyciem.
 * 
 * Alokuje 256 bajtów pamięci EEPROM.
 * Wywoływana w setup() przed próbą odczytu danych.
 */
void InicjalizacjaPamieci() {
#if defined(ESP32) || defined(ESP8266)
    // ESP32/ESP8266 wymagają inicjalizacji EEPROM z podanym rozmiarem
    EEPROM.begin(EEPROM_SIZE);
#else
    // Inne platformy (np. Arduino) używają prostego begin()
    EEPROM.begin();
#endif
}

/**
 * Wczytuje dane WiFi (SSID i hasło) z pamięci EEPROM.
 * 
 * return: true jeśli dane WiFi są prawidłowe i wczytano je pomyślnie
 * return: false jeśli EEPROM jest pusta lub dane są nieprawidłowe
 * 
 * Walidacja:
 * - Długość SSID nie może być 0xFF (pusta EEPROM), 0, ani > 32
 * - Długość hasła nie może być > 64
 * 
 * Dane są wczytywane do globalnych buforów: wifi_ssid i wifi_password
 */
bool WczytanieDanychEEPROM() {
    // Odczytaj długość SSID z adresu 0
    byte ssid_len = EEPROM.read(SSID_LEN_ADDR);
    
    // Walidacja długości SSID
    // 0xFF = pusta EEPROM, 0 = brak danych, > SSID_MAX = błąd
    if (ssid_len == 0xFF || ssid_len == 0 || ssid_len > SSID_MAX) return false;

    // Wczytaj SSID znak po znaku
    for (int i = 0; i < ssid_len && i < SSID_MAX; i++) {
        wifi_ssid[i] = (char)EEPROM.read(SSID_ADDR + i);
    }
    wifi_ssid[ssid_len] = '\0';  // Dodaj null terminator

    // Odczytaj długość hasła
    byte pass_len = EEPROM.read(PASS_LEN_ADDR);
    
    // Walidacja długości hasła (0xFF = pusta EEPROM, > 64 = błąd)
    if (pass_len == 0xFF || pass_len > PASS_MAX) pass_len = 0;
    
    // Wczytaj hasło znak po znaku
    for (int i = 0; i < pass_len && i < PASS_MAX; i++) {
        wifi_password[i] = (char)EEPROM.read(PASS_ADDR + i);
    }
    wifi_password[pass_len] = '\0';  // Dodaj null terminator

    // Ustaw flagę wifiConfigured na true
    wifiConfigured = true;
    return true;  // Dane wczytane pomyślnie
}

/**
 * Zapisuje dane WiFi (SSID i hasło) do pamięci EEPROM.
 * Dane są pobierane z globalnych buforów: wifi_ssid i wifi_password.
 * 
 * Format zapisu:
 * 1. Długość SSID (1 bajt)
 * 2. SSID (max 32 bajty)
 * 3. Długość hasła (1 bajt)
 * 4. Hasło (max 64 bajty)
 * 
 * KRYTYCZNE: Na ESP32/ESP8266 wymagane jest EEPROM.commit() 
 * aby zapisać zmiany do flash! Bez tego dane zostaną utracone przy restarcie.
 */
void ZapiszDaneDoEEPROM() {
    // Oblicz długość SSID i ogranicz do maksymalnej (32)
    byte ssid_len = strlen(wifi_ssid);
    if (ssid_len > SSID_MAX) ssid_len = SSID_MAX;
    
    // Zapisz długość SSID
    EEPROM.write(SSID_LEN_ADDR, ssid_len);
    
    // Zapisz SSID znak po znaku
    for (int i = 0; i < ssid_len; i++) {
        EEPROM.write(SSID_ADDR + i, wifi_ssid[i]);
    }

    // Oblicz długość hasła i ogranicz do maksymalnej (64)
    byte pass_len = strlen(wifi_password);
    if (pass_len > PASS_MAX) pass_len = PASS_MAX;
    
    // Zapisz długość hasła
    EEPROM.write(PASS_LEN_ADDR, pass_len);
    
    // Zapisz hasło znak po znaku
    for (int i = 0; i < pass_len; i++) {
        EEPROM.write(PASS_ADDR + i, wifi_password[i]);
    }

#if defined(ESP32) || defined(ESP8266)
    // KRYTYCZNE: commit() zapisuje zmiany do flash na ESP32/ESP8266
    EEPROM.commit();
    Serial.println("Zapisano dane do EEPROM");
#else
    // Na innych platformach zapis jest automatyczny
    Serial.println("Zapisano dane do EEPROM");
#endif
}

/**
 * Resetuje pamięć EEPROM - usuwa zapisane dane WiFi.
 * Wywoływana podczas komendy "reset" z Serial Monitor.
 * 
 * Proces:
 * 1. Ustawia długości SSID i hasła na 0xFF (pusta EEPROM)
 * 2. Zeruje wszystkie bajty SSID i hasła
 * 3. Commituje zmiany (ESP32/ESP8266)
 * 
 * Po resecie urządzenie uruchomi się w trybie BLE provisioning.
 */
void ResetPamiec() {
    // Ustaw długości na 0xFF (znacznik pustej EEPROM)
    EEPROM.write(SSID_LEN_ADDR, 0xFF);
    EEPROM.write(PASS_LEN_ADDR, 0xFF);

    // Wyzeruj wszystkie bajty SSID
    for (int i = 0; i < SSID_MAX; i++) {
        EEPROM.write(SSID_ADDR + i, 0);
    }
    
    // Wyzeruj wszystkie bajty hasła
    for (int i = 0; i < PASS_MAX; i++) {
        EEPROM.write(PASS_ADDR + i, 0);
    }

#if defined(ESP32) || defined(ESP8266)
    // Zapisz zmiany do flash
    EEPROM.commit();
#endif
}
