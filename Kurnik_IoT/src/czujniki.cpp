#include <cstdint>
#include <cmath>
#include "czujniki.h"

Adafruit_SGP30 sgp;

DHT dht22(PIN_DHT22, DHTTYPE);

// Stałe dla termistora NTC
const float REFERENCE_RESISTANCE = 10000.0;   // Rezystancja referencyjna (10kΩ)
const float NOMINAL_RESISTANCE = 10000.0;    // Rezystancja NTC w 25°C (10kΩ)
const float NOMINAL_TEMPERATURE = 25.0;      // Temperatura referencyjna (°C)
const float B_VALUE = 3950.0;                // Współczynnik Beta

// Inicjalizacja czujnika SGP30
void InicjalizacjaCzujnikow() {
    if (!sgp.begin()) {
        Serial.println("Nie znaleziono czujnika SGP30!");
        // Kontynuuj mimo braku czujnika - użyj wartości domyślnych
    } else {
        Serial.println("Czujnik SGP30 zainicjalizowany pomyślnie");
        // Czujnik wymaga ok. 15 sekund na inicjalizację
    }
}

// CO2 Sensor - Oblicza bezwzględną wilgotność na podstawie temperatury i wilgotności względnej
uint32_t getAbsoluteHumidity(float temperature, float humidity) {
    // Przybliżony wzór z dokumentacji Sensirion SGP30 (rozdział 3.15)
    const float absoluteHumidity = 216.7f * ((humidity / 100.0f) * 6.112f * exp((17.62f * temperature) / (243.12f + temperature)) / (273.15f + temperature)); // [g/m^3]
    const uint32_t absoluteHumidityScaled = static_cast<uint32_t>(1000.0f * absoluteHumidity); // [mg/m^3]
    return absoluteHumidityScaled;
}


int odczytCO2(float temperature, float humidity) {
  // Ustaw wilgotność kompensacyjną przed pomiarem zgodnie z dokumentacją Sensirion
  sgp.setHumidity(getAbsoluteHumidity(temperature, humidity));
  if (!sgp.IAQmeasure()) {
    Serial.println("Błąd odczytu czujnika SGP30");
    return -1;
  }
  int eCO2 = sgp.eCO2;
  return eCO2;
}

int odczytTVOC(float temperature, float humidity) {
  // Ustaw wilgotność kompensacyjną przed pomiarem i wykonaj pomiar IAQ
  sgp.setHumidity(getAbsoluteHumidity(temperature, humidity));
  if (!sgp.IAQmeasure()) {
    Serial.println("Błąd odczytu czujnika SGP30");
    return -1;
  }
  int TVOC = sgp.TVOC;
  return TVOC;
}

float measureDHT22_Temp(){
  float t = dht22.readTemperature();
  if (isnan(t)) return 0.0; 
  return t;
}

float measureDHT22_Hum(){
  float h = dht22.readHumidity();
  if (isnan(h)) return 0.0; 
  return h;
}

float measureNTC() {
  int raw = analogRead(PIN_NTC);
  
  if (raw <= 0 || raw >= 4095) {
    Serial.println("NTC: Błędny odczyt ADC");
    return NAN;
  }
  
  // Oblicz rezystancję NTC z dzielnika napięciowego
  // Konfiguracja: VCC --- R_REF(9.55k) --- ADC_PIN --- NTC(10k) --- GND
  float resistance = REFERENCE_RESISTANCE * raw / (4095.0 - raw);
  
  // Wzór Steinharta-Harta (uproszczony z parametrem Beta)
  // T = 1 / (1/T0 + (1/B) * ln(R/R0))
  float steinhart = resistance / NOMINAL_RESISTANCE;    // (R/R0)
  steinhart = log(steinhart);                           // ln(R/R0)
  steinhart /= B_VALUE;                                 // (1/B) * ln(R/R0)
  steinhart += 1.0 / (NOMINAL_TEMPERATURE + 273.15);    // 1/T0 + (1/B)*ln(R/R0)
  steinhart = 1.0 / steinhart;                          // Temperatura w Kelvinach
  float celsius = steinhart - 273.15;                   // Konwersja na °C
  
  return celsius;
}

int measureLDR(){
  int raw = analogRead(PIN_LDR);
  // zabezpieczenia przed skrajnymi wartościami ADC
  raw = constrain(raw, 1, 4094);

  // Referencyjny rezystor w dzielniku (dopasuj jeśli inny)
  const float LDR_REF_R = 10000.0f;

  // Domyślne współczynniki kalibracyjne (A,B) dla modelu R = A * lux^-B
  // Po kalibracji można je dopasować; wartości poniżej są przybliżone.
  const float LDR_A = 150000.0f;
  const float LDR_B = 0.7f;

  // Oblicz rezystancję LDR z dzielnika: Vnode = raw/4095*Vcc
  // Rldr = Rref * Vnode / (Vcc - Vnode) => Rref * raw / (4095 - raw)
  float Rldr = LDR_REF_R * (float)raw / (4095.0f - (float)raw);

  // Oblicz lux z odwróconego modelu: lux = (A / R)^(1/B)
  float lux = powf(LDR_A / Rldr, 1.0f / LDR_B);
  if (!isfinite(lux) || lux < 0) lux = 0.0f;

  int ilux = (int)roundf(lux);
  // --- Calibration to match reference meter ---
  // Measured pairs from reference device -> device produced a linear mapping
  // Solve for phone = a*device + b. Default values computed from samples:
  const float CAL_A = 0.587444f; // slope
  const float CAL_B = 22.2009f;  // offset
  float corrected = CAL_A * (float)ilux + CAL_B;
  if (!isfinite(corrected) || corrected < 0) corrected = 0.0f;
  return (int)roundf(corrected);
}

/*
sgp.setHumidity(getAbsoluteHumidity(temperature, humidity)) - Ustawia wilgotność dla sensora SGP30
 - temperature: temperatura w stopniach Celsjusza
 - humidity: wilgotność względna w procentach

 sgp.TVOC - odczytuje wartość TVOC w ppb
 sgp.eCO2 - odczytuje wartość eCO2 w ppm
 sgp.rawH2 - odczytuje surową wartość H2
 sgp.rawEthanol - odczytuje surową wartość etanolu

*/