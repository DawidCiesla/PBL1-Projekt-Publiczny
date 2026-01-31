/*
 * MODUŁ PAMIĘCI LOKALNEJ (EEPROM) - pamiec_lokalna.h
 * 
 * Zarządza trwałym przechowywaniem danych WiFi w pamięci EEPROM.
 * Umożliwia zapisanie konfiguracji WiFi między restartami urządzenia.
 */

#ifndef PAMIEC_LOKALNA_H
#define PAMIEC_LOKALNA_H

#include "main.h"

/*
 * Inicjalizuje pamięć EEPROM.
 * Dla ESP32/ESP8266 ustawia rozmiar bufora EEPROM na 256 bajtów.
 */
void InicjalizacjaPamieci();

/*
 * Wczytuje dane WiFi (SSID i hasło) z pamięci EEPROM.
 * 
 * return: true jeśli dane zostały pomyślnie wczytane, false jeśli EEPROM jest pusta
 */
bool WczytanieDanychEEPROM();

/*
 * Zapisuje aktualne dane WiFi (SSID i hasło) do pamięci EEPROM.
 * Wykonuje commit() aby zapewnić trwałość zapisu.
 */
void ZapiszDaneDoEEPROM();

/*
 * Czyści całą pamięć EEPROM (resetuje dane WiFi).
 * Używane podczas pełnego resetu urządzenia.
 */
void ResetPamiec();

#endif
