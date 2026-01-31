#ifndef CZUJNIKI_H
#define CZUJNIKI_H

#include <Adafruit_SGP30.h>
#include <cstdint>
#include <cmath>
#include <DHT.h>

typedef struct {
    int   ID_urzadzenia;      // Identyfikator urządzenia
    float temperatura;        // Temperatura w stopniach Celsjusza
    float wilgotnosc;         // Wilgotność względna w procentach
    int   poziom_co2;         // Stężenie CO2 w ppm
    int   poziom_amoniaku;    // Stężenie amoniaku w ppm
    int   naslonecznienie;    // Natężenie światła w luksach
    String data_i_czas;       // Timestamp pomiaru (format: "HH:MM:SS Www, Mmm DD YYYY")
} Pakiet_Danych;


// CO2 Sensor - Oblicza bezwzględną wilgotność na podstawie temperatury i wilgotności względnej
extern Adafruit_SGP30 sgp;
extern DHT dht22;

#define PIN_DHT22 14
#define DHTTYPE DHT22

void InicjalizacjaCzujnikow();
uint32_t getAbsoluteHumidity(float temperature, float humidity);
int odczytCO2(float temperature, float humidity);
int odczytTVOC(float temperature, float humidity);
Pakiet_Danych odczytCzujniki(); 
void pakietToCSV(const Pakiet_Danych* pakiet, char* buffer, size_t bufferSize);
void TEST_zapelnijPakiet(Pakiet_Danych* pakiet, int wielkosc);
#endif