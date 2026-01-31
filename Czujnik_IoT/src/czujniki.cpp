#include <czujniki.h>
#include "mesh_local.h" 

DHT dht22(PIN_DHT22, DHTTYPE);
Adafruit_SGP30 sgp;

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
    // approximation formula from Sensirion SGP30 Driver Integration chapter 3.15
    const float absoluteHumidity = 216.7f * ((humidity / 100.0f) * 6.112f * exp((17.62f * temperature) / (243.12f + temperature)) / (273.15f + temperature)); // [g/m^3]
    const uint32_t absoluteHumidityScaled = static_cast<uint32_t>(1000.0f * absoluteHumidity); // [mg/m^3]
    return absoluteHumidityScaled;
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

int odczytCO2(float temperature, float humidity) {
    if (!sgp.IAQmeasure()) {
        Serial.println("Błąd odczytu czujnika SGP30");
        return -1; 
    }
    sgp.setHumidity(getAbsoluteHumidity(temperature, humidity));
    int eCO2 = sgp.eCO2;
    return eCO2;
}

int odczytTVOC(float temperature, float humidity) {
    // IAQmeasure już wywołany w odczytCO2, więc używamy ostatniej wartości
    sgp.setHumidity(getAbsoluteHumidity(temperature, humidity));
    int TVOC = sgp.TVOC;
    return TVOC;
}
void pakietToCSV(const Pakiet_Danych* pakiet, char* buffer, size_t bufferSize) {
    snprintf(buffer, bufferSize, "%d;%.2f;%.2f;%d;%d;%d;%s",
        pakiet->ID_urzadzenia,      // ID urządzenia (int)
        pakiet->temperatura,        // Temperatura w °C (float, 2 miejsca po przecinku)
        pakiet->wilgotnosc,         // Wilgotność w % (float, 2 miejsca po przecinku)
        pakiet->poziom_co2,         // CO2 w ppm (int)
        pakiet->poziom_amoniaku,    // Amoniak w ppm (int)
        pakiet->naslonecznienie,    // Nasłonecznienie w lux (int)
        pakiet->data_i_czas.c_str()); // Data i czas (String)
}
Pakiet_Danych odczytCzujniki() {
    Pakiet_Danych odczyt;
    odczyt.ID_urzadzenia   = mesh.getNodeId();
    odczyt.temperatura     = measureDHT22_Temp();        
    odczyt.wilgotnosc      = measureDHT22_Hum();
    odczyt.poziom_co2      = 10;
    odczyt.poziom_amoniaku = 10;
    odczyt.naslonecznienie = 2137; 
    odczyt.data_i_czas     = rtc.getTimeDate();
    return odczyt;
}

void TEST_zapelnijPakiet(Pakiet_Danych* pakiet, int wielkosc) {
    for (int i = 0; i < wielkosc; i++) {
        // Oblicz kąt od 0 do 2π (pełny cykl sinusoidy)
        float t = (float)i / (wielkosc - 1) * 2 * M_PI;

        pakiet[i].ID_urzadzenia   = mesh.getNodeId();  // ID urządzenia jako mesh id
        
        // Generuj sinusoidalne wartości z różnymi częstotliwościami
        pakiet[i].temperatura     = 22.0 + 5.0  * sin(t);        // 17-27°C
        pakiet[i].wilgotnosc      = 60.0 + 20.0 * sin(t * 1.3);  // 40-80%
        pakiet[i].poziom_co2      = 1200 + 400 * sin(t * 0.8);   // 800-1600 ppm
        pakiet[i].poziom_amoniaku = 15 + 8   * sin(t * 1.7);     // 7-23 ppm
        pakiet[i].naslonecznienie = 50 + 45  * sin(t * 0.5);     // 5-95 lux
        
        // Timestamp jest ustawiany przez roota
    }
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