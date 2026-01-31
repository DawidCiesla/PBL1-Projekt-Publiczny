#include "pamiec.h"
#include <EEPROM.h>

#define EEPROM_SIZE 512
#define EEPROM_SSID_ADDR 0
#define EEPROM_SSID_MAX_LEN 64
#define EEPROM_MAGIC_ADDR 100
#define EEPROM_MAGIC_VALUE 0xAB  // Wartość oznaczająca że EEPROM zawiera prawidłowe dane

// Zapisz SSID do EEPROM
void zapiszSSIDDoEEPROM(const String& ssid) {
    EEPROM.begin(EEPROM_SIZE);
    
    // Zapisz magic value
    EEPROM.write(EEPROM_MAGIC_ADDR, EEPROM_MAGIC_VALUE);
    
    // Zapisz SSID
    for (int i = 0; i < EEPROM_SSID_MAX_LEN; i++) {
        if (i < ssid.length()) {
            EEPROM.write(EEPROM_SSID_ADDR + i, ssid[i]);
        } else {
            EEPROM.write(EEPROM_SSID_ADDR + i, 0);  // Null terminator
        }
    }
    
    EEPROM.commit();
    EEPROM.end();
    Serial.printf(">>> Zapisano SSID do pamięci: %s\n", ssid.c_str());
}

// Odczytaj SSID z EEPROM
String odczytajSSIDzEEPROM() {
    EEPROM.begin(EEPROM_SIZE);
    
    // Sprawdź magic value
    if (EEPROM.read(EEPROM_MAGIC_ADDR) != EEPROM_MAGIC_VALUE) {
        EEPROM.end();
        Serial.println(">>> EEPROM pusty - pierwsze uruchomienie");
        return "";
    }
    
    // Odczytaj SSID
    char ssid_buf[EEPROM_SSID_MAX_LEN + 1];
    for (int i = 0; i < EEPROM_SSID_MAX_LEN; i++) {
        ssid_buf[i] = EEPROM.read(EEPROM_SSID_ADDR + i);
        if (ssid_buf[i] == 0) break;
    }
    ssid_buf[EEPROM_SSID_MAX_LEN] = 0;
    
    EEPROM.end();
    String result = String(ssid_buf);
    
    if (result.length() > 0) {
        Serial.printf(">>> Odczytano SSID z pamięci: %s\n", result.c_str());
    }
    
    return result;
}

// Wyczyść EEPROM (do debugowania)
void wyczyscEEPROM() {
    EEPROM.begin(EEPROM_SIZE);
    EEPROM.write(EEPROM_MAGIC_ADDR, 0);
    EEPROM.commit();
    EEPROM.end();
    Serial.println(">>> Wyczyszczono EEPROM");
}
