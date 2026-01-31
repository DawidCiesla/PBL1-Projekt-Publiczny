#ifndef PAMIEC_H
#define PAMIEC_H

#include <Arduino.h>

// Zapisz SSID sieci mesh do EEPROM
void zapiszSSIDDoEEPROM(const String& ssid);

// Odczytaj SSID sieci mesh z EEPROM
// Zwraca pusty String jeśli EEPROM jest pusty (pierwsze uruchomienie)
String odczytajSSIDzEEPROM();

// Wyczyść EEPROM (resetuje zapisany SSID)
void wyczyscEEPROM();

#endif
