/*
 * mqtt.cpp
 * 
 * Moduł komunikacji MQTT odpowiedzialny za:
 * - Łączenie z brokerem MQTT
 * - Wysyłanie pakietów danych z czujników w formacie CSV
 * - Automatyczne zapisywanie danych na kartę SD (backup lub kolejka)
 * - Generowanie unikalnego topic'a na podstawie adresu MAC urządzenia
 * - Obsługę callbacków onConnect, onDisconnect, onMessage
 * 
 * Format danych MQTT (CSV): ID;temp;hum;co2;nh3;sun;timestamp
 * Przykład: 2;22.32;61.65;1220;15;51;15:55:06 Wed, Jan 07 2026
 */

#include "mqtt.h"
#include "main.h"
#include "pamiec_SD.h"
#include "czujniki.h"

// Klienci WiFi i MQTT
WiFiClient espClient;              // Klient WiFi 
AsyncMqttClient asyncMqttClient;   // Asynchroniczny klient MQTT

// Globalny zegar RTC (zadeklarowany jako extern w main.h)
ESP32Time rtc;

/**
 * Funkcja pomocnicza konwertująca kod stanu MQTT na nazwę tekstową.
 * Używana do debugowania i logowania stanów połączenia.
 * 
 * parametr: s Kod stanu MQTT (int8_t)
 * return: Tekstowa reprezentacja stanu
 */
const char* mqttStateName(int8_t s){
    switch(s){
        case -4: return "MQTT_CONNECTION_TIMEOUT";       // Timeout połączenia
        case -3: return "MQTT_CONNECTION_LOST";          // Utracono połączenie
        case -2: return "MQTT_CONNECT_FAILED";           // Połączenie nie powiodło się
        case  0: return "MQTT_DISCONNECTED";             // Rozłączony
        case  1: return "MQTT_CONNECTED";                // Połączony
        case  2: return "MQTT_CONNECT_BAD_PROTOCOL";     // Zła wersja protokołu
        case  3: return "MQTT_CONNECT_BAD_CLIENT_ID";    // Nieprawidłowy Client ID
        case  4: return "MQTT_CONNECT_UNAVAILABLE";      // Serwer niedostępny
        case  5: return "MQTT_CONNECT_BAD_CREDENTIALS";  // Złe dane logowania
        case  6: return "MQTT_CONNECT_UNAUTHORIZED";     // Brak autoryzacji
        default: return "MQTT_UNKNOWN";                  // Nieznany stan
    }
}

// Topic MQTT - format: "kurnik/" + adres MAC BLE urządzenia
// Make topic larger to avoid accidental overflow when appending MAC
char topic[48] = "kurnik/";   
bool topicInitialized = false;  // Czy topic został już zainicjalizowany

// Konfiguracja serwera MQTT
const int mqtt_port = 1883;                  // Port MQTT (bez TLS)
const char *mqtt_broker   = ""; // Adres IP brokera MQTT
const char *mqtt_username = "";        // Nazwa użytkownika
const char *mqtt_password = "";        // Hasło użytkownika

/**
 * Inicjalizuje klienta MQTT i rejestruje callback'i.
 * Konfiguruje:
 * - Adres serwera i port
 * - Dane logowania (username, password)
 * - Callback onConnect - wywoływany po nawiązaniu połączenia
 * - Callback onDisconnect - wywoływany po utracie połączenia
 * - Callback onMessage - wywoływany po otrzymaniu wiadomości MQTT
 * 
 * Wywoływana w setup() przed próbą połączenia.
 */
void InicjalizacjaMQTT() {
    // Ustaw adres serwera MQTT i port
    // Convert IP string to IPAddress to avoid potential null pointer issues
    IPAddress brokerIP;
    brokerIP.fromString(mqtt_broker);
    asyncMqttClient.setServer(brokerIP, mqtt_port);
    // Ustaw dane logowania
    asyncMqttClient.setCredentials(mqtt_username, mqtt_password);

    // Callback wywoływany po pomyślnym połączeniu z brokerem
    asyncMqttClient.onConnect([](bool sessionPresent){
        Serial.println("Async MQTT connected");
        // Upewnij się, że topic jest zainicjalizowany
        if (!topicInitialized) {
            InicjalizacjaTopicuZ_MAC();
        }
        // Subskrybuj własny topic (odbieraj wiadomości wysłane na ten topic)
        asyncMqttClient.subscribe(topic, 0);
        // Opublikuj wiadomość inicjującą po połączeniu
        asyncMqttClient.publish(topic, 0, false, "Wiadomosc inicjujaca");
    });

    // Callback wywoływany po utracie połączenia
    asyncMqttClient.onDisconnect([](AsyncMqttClientDisconnectReason reason){
        Serial.println("Async MQTT disconnected");
    });

    // Callback wywoływany po otrzymaniu wiadomości MQTT
    asyncMqttClient.onMessage([](char* t, char* p, AsyncMqttClientMessageProperties props, size_t len, size_t index, size_t total){
        // Przekieruj do funkcji obsługującej wiadomości
        OdpowiedzMQTT(t, (byte*)p, (unsigned int)len);
    });
}

/**
 * Tworzy unikalny topic MQTT na podstawie adresu MAC urządzenia BLE.
 * Format topic'a: "kurnik/" + adres_MAC (np. "kurnik/b0:cb:d8:03:f9:62")
 * 
 * Topic jest używany do:
 * - Publikowania danych z czujników
 * - Subskrypcji (odbierania komend)
 * 
 * Wywoływana tylko raz - flaga topicInitialized zapobiega wielokrotnej inicjalizacji.
 */
void InicjalizacjaTopicuZ_MAC() {
    if (topicInitialized) return;  // Jeśli już zainicjalizowany, wyjść

    // Pobierz adres MAC urządzenia BLE jako string
    char macStr[18] = "";
    String mac = String(BLEDevice::getAddress().toString().c_str());
    if (mac.length() > 0) mac.toCharArray(macStr, sizeof(macStr));

    // Safely append address to base topic
    strncat(topic, macStr, sizeof(topic) - strlen(topic) - 1);
    topicInitialized = true;

    Serial.print("MQTT topic: ");
    Serial.println(topic);
}

/**
 * Nieblokująca funkcja łącząca się z brokerem MQTT.
 * Wykonuje pojedynczą próbę połączenia - nie zawiesza programu.
 * 
 * Wymagania:
 * - Aktywne połączenie WiFi
 * - Zainicjalizowany klient MQTT (InicjalizacjaMQTT)
 * 
 * Client ID: "Kurnik_IoT_" + MAC bez dwukropków (np. "Kurnik_IoT_b0cbd803f962")
 * 
 * Jeśli MQTT jest już połączony, funkcja kończy się natychmiast.
 */
void PolaczDoMQTT() {
    // Sprawdź czy już jesteśmy połączeni
    if (asyncMqttClient.connected()) {
        return; // Już podłączony - brak akcji
    }
    
    // Pobierz adres MAC BLE urządzenia
    char macStr[64] = "";
    String mac = BLEDevice::getAddress().toString().c_str();
    if (mac.length() > 0) mac.toCharArray(macStr, sizeof(macStr));

    // Sprawdź czy WiFi jest połączone
    if (WiFi.status() != WL_CONNECTED) {
        Serial.println("MQTT: brak połączenia WiFi");
        return;  // Brak WiFi - nie można połączyć MQTT
    }
    
    // Utwórz bezpieczny Client ID usuwając dwukropki z adresu MAC
    char macSafe[64] = "";
    int si = 0;
    for (int i = 0; macStr[i] != '\0' && si < (int)sizeof(macSafe)-1; ++i) {
        if (macStr[i] == ':') continue;  // Pomiń dwukropki
        macSafe[si++] = macStr[i];
    }
    macSafe[si] = '\0';

    // Zbuduj Client ID: "Kurnik_IoT_" + MAC
    static char client_id_buf[64];
    snprintf(client_id_buf, sizeof(client_id_buf), "Kurnik_IoT_%s", macSafe);
    Serial.print("Łączenie do brokera MQTT jako ");
    Serial.println(client_id_buf);

    // Ustaw Client ID (persistent buffer) i spróbuj połączyć (nieblokujące)
    asyncMqttClient.setClientId(client_id_buf);
    asyncMqttClient.connect();  // Asynchroniczne - nie czeka na wynik
}

/** 
 * Callback wywoływany po otrzymaniu wiadomości MQTT.
 * Obsługuje wiadomości przychodzące na zasubskrybowany topic.
 * 
 * parametr: topic Topic na którym otrzymano wiadomość
 * parametr: payload Treść wiadomości (bajty)
 * parametr: length Długość wiadomości w bajtach
 * 
 */
void OdpowiedzMQTT(char *topic, byte *payload, unsigned int length) {
    Serial.print("Otrzymano wiadomość na topicu [");
    Serial.print(topic);
    Serial.print("]: ");
    
    // Wyświetl treść wiadomości
    for (unsigned int i = 0; i < length; i++) {
        Serial.print((char)payload[i]);
    }
    Serial.println();
}

/**
 * Wysyła pakiet danych z czujników przez MQTT i zapisuje na kartę SD.
 * 
 * Format CSV: ID;temp;hum;co2;nh3;sun;timestamp
 * Przykład: 2;22.32;61.65;1220;15;51;15:55:06 Wed, Jan 07 2026
 * 
 * parametr: pakiet, Wskaźnik na strukturę Pakiet_Danych do wysłania
 * 
 * Proces:
 * 1. Aktualizuje timestamp z RTC (aktualny czas)
 * 2. Formatuje dane do CSV
 * 3. Próbuje wysłać przez MQTT
 * 4. Zapisuje na kartę SD:
 *    - backup_data.txt jeśli MQTT się udało (archiwum)
 *    - transfer_waitlist.txt jeśli MQTT nie działa (kolejka do ponownego wysłania)
 */
void WyslijPakiet(Pakiet_Danych* pakiet) {
    
    // Formatuj dane do CSV: ID;temp;hum;co2;nh3;sun;timestamp
    char message[150];
    snprintf(message, sizeof(message), "%d;%.2f;%.2f;%d;%d;%d;%s",
             pakiet->ID_urzadzenia,      // ID urządzenia (int)
             pakiet->temperatura,        // Temperatura w °C (float, 2 miejsca po przecinku)
             pakiet->wilgotnosc,         // Wilgotność w % (float, 2 miejsca po przecinku)
             pakiet->poziom_co2,         // CO2 w ppm (int)
             pakiet->poziom_amoniaku,    // Amoniak w ppm (int)
             pakiet->naslonecznienie,    // Nasłonecznienie w lux (int)
             pakiet->data_i_czas.c_str()); // Timestamp
    
    // Próbuj wysłać przez MQTT (zwraca packet ID lub 0 przy błędzie)
    uint16_t packetId = asyncMqttClient.publish(topic, 0, false, message);
    
    // Sprawdź czy wysyłanie MQTT się udało
    bool mqttSuccess = (packetId != 0 && asyncMqttClient.connected());
    
    // Zapisz dane do odpowiedniego pliku na karcie SD
    // - backup_data.txt jeśli MQTT działa (archiwum)
    // - transfer_waitlist.txt jeśli MQTT nie działa (kolejka)
    ZapiszDanePakiet(message, mqttSuccess);
}
/**
 * Funkcja testowa generująca 100 pakietów danych z sinusoidalnymi wartościami.
 * Używana do testów systemu bez fizycznych czujników.
 * 
 * parametr: pakiet Wskaźnik na tablicę Pakiet_Danych do wypełnienia
 * parametr: wielkosc Ilość pakietów do wygenerowania (zazwyczaj 100)
 * 
 * Generowane zakresy wartości:
 * - Temperatura: 17-27°C (sinusoida wokół 22°C ± 5°C)
 * - Wilgotność: 40-80% (sinusoida wokół 60% ± 20%)
 * - CO2: 800-1600 ppm (sinusoida wokół 1200 ppm ± 400 ppm)
 * - Amoniak: 7-23 ppm (sinusoida wokół 15 ppm ± 8 ppm)
 * - Nasłonecznienie: 5-95 lux (sinusoida wokół 50 lux ± 45 lux)
 * 
 * Każdy parametr ma inną częstotliwość (mnożniki 0.5-1.7) dla bardziej
 * realistycznych, niesynchronicznych zmian.
 */
void TEST_zapelnij_pakiet(Pakiet_Danych* pakiet, int wielkosc) {
    for (int i = 0; i < wielkosc; i++) {
        // Oblicz kąt od 0 do 2π (pełny cykl sinusoidy)
        float t = (float)i / (wielkosc - 1) * 2 * M_PI;

        pakiet[i].ID_urzadzenia   = 2;  // Stały ID = 2
        
        // Generuj sinusoidalne wartości z różnymi częstotliwościami
        pakiet[i].temperatura     = 22.0 + 5.0  * sin(t);        // 17-27°C
        pakiet[i].wilgotnosc      = 60.0 + 20.0 * sin(t * 1.3);  // 40-80%
        pakiet[i].poziom_co2      = 1200 + 400 * sin(t * 0.8);   // 800-1600 ppm
        pakiet[i].poziom_amoniaku = 15 + 8   * sin(t * 1.7);     // 7-23 ppm
        pakiet[i].naslonecznienie = 50 + 45  * sin(t * 0.5);     // 5-95 lux
        
        // Timestamp jest ustawiany w WyslijPakiet() z aktualnego RTC
    }
}

void TEST_pakiet(Pakiet_Danych* pakiet) {

    pakiet->ID_urzadzenia   = 1;  // Stały ID = 1
        
    pakiet->temperatura     = measureDHT22_Temp();        
    pakiet->wilgotnosc      = measureDHT22_Hum();
    pakiet->poziom_co2      = odczytCO2(pakiet->temperatura, pakiet->wilgotnosc);
    pakiet->poziom_amoniaku = odczytTVOC(pakiet->temperatura, pakiet->wilgotnosc);
    pakiet->naslonecznienie = measureLDR(); 
    pakiet->data_i_czas = rtc.getTimeDate();
        
    // Timestamp jest ustawiany w WyslijPakiet() z aktualnego RTC
    
}

/**
 * Wysyła pakiet danych z wagą kury przez MQTT.
 * 
 * Format: id_urządzenia;id_kury;waga;timestamp
 * Przykład: 692641124;F7474A39;-0.37;23:44:15 Wed, Jan 28 2026
 * 
 * parametr: id_urzadzenia ID urządzenia (wagi)
 * parametr: id_kury Identyfikator kury (hex string z RFID)
 * parametr: waga Zmierzona waga w kg
 * parametr: timestamp Czas pomiaru
 */
void WyslijPakietKura(int id_urzadzenia, const char* id_kury, float waga, String timestamp) {
    // Format: id_urządzenia;id_kury;waga;timestamp
    char message[150];
    snprintf(message, sizeof(message), "%d;%s;%.2f;%s",
             id_urzadzenia,
             id_kury,
             waga,
             timestamp.c_str());
    
    // Utwórz topic dla danych kur: kurnik/MAC/kury
    char kury_topic[64];
    snprintf(kury_topic, sizeof(kury_topic), "%s/kury", topic);
    
    Serial.printf("[MQTT] Wysyłam dane kury na topic %s: %s\n", kury_topic, message);
    
    // Wyślij przez MQTT
    uint16_t packetId = asyncMqttClient.publish(kury_topic, 0, false, message);
    
    if (packetId != 0 && asyncMqttClient.connected()) {
        Serial.println("[MQTT] Pomyślnie wysłano dane kury");
    } else {
        Serial.println("[MQTT] BŁĄD: Nie udało się wysłać danych kury");
    }
}
