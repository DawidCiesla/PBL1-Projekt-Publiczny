#include <ESP8266WiFi.h>
#include <PubSubClient.h>
#include <string.h>
#include <math.h>

// Dane dostępowe WiFi
const char *ssid = "NaszaSiec.NET_C8C831"; // Enter your WiFi name
const char *password = "4JXGF4EM73";  // Enter WiFi password

char topic[20];

// Zwykły klient TCP
WiFiClient espClient;
PubSubClient mqtt_client(espClient);

// Definicje funkcji
void connectToWiFi();
void connectToMQTT();
void mqttCallback(char *topic, byte *payload, unsigned int length);

typedef struct{
    int ID_urzadzenia;
    float temperatura;
    float wilgotnosc;
    int poziom_co2;
    int poziom_amoniaku;
    int naslonecznienie;
}Pakiet_Danych;

const int mqtt_port = 1883;                // zwykły MQTT (bez TLS)
const char *mqtt_broker = "57.128.237.128"; // IP VPS z mosquitto
const char *mqtt_username = "esp8266";    
const char *mqtt_password = "esp8266";    

// Czas konfiguracji - 1 cykl = 1 godzina = 3600 sekund
const unsigned long PAKIEL_NA_GODZINE = 100;
const unsigned long INTERWAL_MIEDZY_PAKIETAMI = 3600000UL / PAKIEL_NA_GODZINE; // 36 sekund między pakietami

void setup() {
    Serial.begin(115200);
    connectToWiFi();
    mqtt_client.setServer(mqtt_broker, mqtt_port);
    mqtt_client.setCallback(mqttCallback);
    connectToMQTT();

    strcpy(topic, "kurnik/");
    strcat(topic, "48:E7:29:6D:8E:8C");
    
    Serial.printf("Rozpoczynam wysyłanie: %lu pakietów/godz. co %lu ms\n", 
                  PAKIEL_NA_GODZINE, INTERWAL_MIEDZY_PAKIETAMI);
}

const char *mqtt_topic = topic;          

void connectToWiFi() {
    WiFi.begin(ssid, password);
    while (WiFi.status() != WL_CONNECTED) {
        delay(1000);
        Serial.println("Connecting to WiFi...");
    }
    Serial.println("Connected to WiFi");
    Serial.print("IP: ");
    Serial.println(WiFi.localIP());
}

void connectToMQTT() {
    while (!mqtt_client.connected()) {
        String client_id = "esp8266-client-" + String(WiFi.macAddress());
        Serial.printf("Łączenie się do brokera MQTT jako %s...\n", client_id.c_str());
        if (mqtt_client.connect(client_id.c_str(), mqtt_username, mqtt_password)) {
            Serial.println("Połączono z brokerem MQTT");
            mqtt_client.subscribe(mqtt_topic);
            mqtt_client.publish(mqtt_topic, "Hi, I'm ESP8266 - Sinusoidal Data Generator");
        } else {
            Serial.print("Błąd połączenia MQTT, kod stanu: ");
            Serial.println(mqtt_client.state());
            delay(5000);
        }
    }
}

void mqttCallback(char *topic, byte *payload, unsigned int length) {
    Serial.print("Otrzymano wiadomość na topicu [");
    Serial.print(topic);
    Serial.print("]: ");
    for (unsigned int i = 0; i < length; i++) {
        Serial.print((char)payload[i]);
    }
    Serial.println();
}

void wyslijPakiet(Pakiet_Danych* pakiet) {
    char message[100];
    snprintf(message, sizeof(message), "%d,%.2f,%.2f,%d,%d,%d",
             pakiet->ID_urzadzenia,
             pakiet->temperatura,
             pakiet->wilgotnosc,
             pakiet->poziom_co2,
             pakiet->poziom_amoniaku,
             pakiet->naslonecznienie);
    mqtt_client.publish(mqtt_topic, message);
}

void TEST_zapelnij_pakiet(Pakiet_Danych* pakiet, int wielkosc) {
    for (int i = 0; i < wielkosc; i++) {
        float t = (float)i / (wielkosc - 1) * 2 * M_PI; // 0 do 2π
        
        pakiet[i].ID_urzadzenia = 2;
        
        // Sinusoidy o różnych amplitudach, offsetach i częstotliwościach
        pakiet[i].temperatura = 22.0 + 5.0 * sin(t);           // 17-27°C
        pakiet[i].wilgotnosc = 60.0 + 20.0 * sin(t * 1.3);    // 40-80%
        pakiet[i].poziom_co2 = 1200 + 400 * sin(t * 0.8);     // 800-1600 ppm
        pakiet[i].poziom_amoniaku = 15 + 8 * sin(t * 1.7);    // 7-23 ppm
        pakiet[i].naslonecznienie = 50 + 45 * sin(t * 0.5);   // 5-95 lux
    }
}

void loop() {
    if (!mqtt_client.connected()) {
        connectToMQTT();
    }

    // Wypełnij bufor danymi na całą godzinę
    static Pakiet_Danych Dane[100];
    static int index_pakietu = 0;
    static unsigned long ostatni_czas = 0;
    
    // Na początku godziny wygeneruj nowe dane
    if (index_pakietu == 0) {
        TEST_zapelnij_pakiet(Dane, PAKIEL_NA_GODZINE);
        Serial.println("Nowa godzina - wygenerowano 100 pakietów sinusoidalnych");
    }
    
    // Wyślij jeden pakiet z bufora
    wyslijPakiet(&Dane[index_pakietu]);
    Serial.printf("Pakiet %d/%d wysłany (pozostały czas do końca godziny: %lu s)\n", 
                  index_pakietu + 1, PAKIEL_NA_GODZINE, 
                  (3600 - ((millis() - ostatni_czas) / 1000)));
    
    index_pakietu++;
    
    // Jeśli koniec bufora - zresetuj licznik i czekaj godzinę
    if (index_pakietu >= PAKIEL_NA_GODZINE) {
        index_pakietu = 0;
        Serial.println("Koniec godziny - czekam 1h na następny cykl...");
        delay(3600000UL - (PAKIEL_NA_GODZINE * INTERWAL_MIEDZY_PAKIETAMI)); // Dokładnie 1h minus czasy wysyłki
        ostatni_czas = millis();
        return;
    }
    
    mqtt_client.loop();
    
    // Precyzyjne opóźnienie między pakietami
    unsigned long teraz = millis();
    if (INTERWAL_MIEDZY_PAKIETAMI > (teraz - ostatni_czas)) {
        delay(INTERWAL_MIEDZY_PAKIETAMI - (teraz - ostatni_czas));
    }
    ostatni_czas = millis();
}
