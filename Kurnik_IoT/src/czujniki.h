#ifndef CZUJNIKI_H
#define CZUJNIKI_H

#include "main.h"
#include <Adafruit_SGP30.h>
#include <DHT.h>
#include <NTC_Thermistor.h>
#include <cstdint>
#include <cmath>

#define PIN_DHT22 14
#define PIN_NTC 33
#define PIN_LDR 32
#define DHTTYPE DHT22

extern DHT dht22;
extern NTC_Thermistor* ntcThermistor;

// CO2 Sensor - Oblicza bezwzględną wilgotność na podstawie temperatury i wilgotności względnej
extern Adafruit_SGP30 sgp;

void InicjalizacjaCzujnikow();
uint32_t getAbsoluteHumidity(float temperature, float humidity);
int odczytCO2(float temperature, float humidity);
int odczytTVOC(float temperature, float humidity);

float measureDHT22_Temp();
float measureDHT22_Hum();
float measureNTC();
int measureLDR();
#endif