#ifndef CZUJNIKI_H
#define CZUJNIKI_H

#include <cstdint>
#include <cmath>
#include <HX711.h>
#include <SPI.h>
#include <MFRC522v2.h>
#include <MFRC522DriverSPI.h>
#include <MFRC522DriverPinSimple.h>
#include <MFRC522Debug.h>

typedef struct {
    int   ID_urzadzenia;      // Identyfikator urządzenia
    String uid_rfid;        // UID karty RFID w formacie HEX
    float waga;               // Waga zmierzona przez czujniki HX711 (w gramach)
    String data_i_czas;       // Timestamp pomiaru (format: "HH:MM:SS Www, Mmm DD YYYY")
} Pakiet_Danych;


// Czujniki wagi HX711
extern HX711 scale1;
extern HX711 scale2;

// Czytnik RFID MFRC522v2
extern MFRC522DriverPinSimple ss_pin;
extern MFRC522DriverSPI driver;
extern MFRC522 mfrc522;

// Piny dla HX711 - dostosowane dla ESP8266
#define LOADCELL_DOUT_PIN_1 5  // D1
#define LOADCELL_SCK_PIN_1 4   // D2
#define LOADCELL_DOUT_PIN_2 10  // D0
#define LOADCELL_SCK_PIN_2 9    // D4

// Piny dla MFRC522 RFID - dostosowane dla ESP8266 (MFRC522v2)
// SPI: MOSI=D7(GPIO13), MISO=D6(GPIO12), SCK=D5(GPIO14)
#define SS_PIN 15   // D8 (GPIO15) - używany przez MFRC522DriverPinSimple

void InicjalizacjaCzujnikow();
uint32_t getAbsoluteHumidity(float temperature, float humidity);
float zmierz_wage();
void taruj_wage();
bool sprawdz_karte_rfid();
String pobierz_uid_rfid();
void zakoncz_komunikacje_rfid();
Pakiet_Danych odczytCzujniki(); 
void pakietToCSV(const Pakiet_Danych* pakiet, char* buffer, size_t bufferSize);
#endif