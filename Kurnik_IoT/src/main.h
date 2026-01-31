/*
 * PLIK NAGŁÓWKOWY GŁÓWNY - main.h
 * 
 * Zawiera wszystkie niezbędne biblioteki oraz definicje struktur danych
 * używanych w całym projekcie systemu monitorowania kurnika IoT.
 */

#ifndef MAIN_H
#define MAIN_H

// Biblioteki Arduino i ESP32
#include <Arduino.h>
#include <freertos/FreeRTOS.h>
#include <freertos/ringbuf.h>
#include <WiFi.h>
#include <NimBLEDevice.h>
#include <AsyncMqttClient.h>
#include <PubSubClient.h>
#include <string.h>
#include <EEPROM.h>
#include <math.h>
#include <ESP32Time.h>

/*
 * Struktura przechowująca pojedynczy pakiet danych z czujników
 * Zawiera wszystkie pomiary oraz timestamp
 */
typedef struct {
    int   ID_urzadzenia;      // Identyfikator urządzenia
    float temperatura;        // Temperatura w stopniach Celsjusza
    float wilgotnosc;         // Wilgotność względna w procentach
    int   poziom_co2;         // Stężenie CO2 w ppm
    int   poziom_amoniaku;    // Stężenie amoniaku w ppm
    int   naslonecznienie;    // Natężenie światła w luksach
    String data_i_czas;       // Timestamp pomiaru (format: "HH:MM:SS Www, Mmm DD YYYY")
} Pakiet_Danych;

// Globalny obiekt RTC (Real Time Clock) do zarządzania czasem
extern ESP32Time rtc;

// Funkcje obsługi komend Serial (dostępne globalnie)
void checkAndHandleSerialCommands();
void resetKurnik();
void wyswietlStatusSystemu();

#endif 