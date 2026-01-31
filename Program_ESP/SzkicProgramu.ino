#include <Arduino.h>
#include <WiFiS3.h>
#include <ArduinoBLE.h>
#include <PubSubClient.h>
#include <string.h>
#include <EEPROM.h>
#include <math.h>

// ================== WiFi & MQTT ==================

// Bufory na dane dostępowe z BLE
char wifi_ssid[33] = "";
char wifi_password[65] = "";

bool wifiConfigured = false;   // Czy odebrano dane z BLE i zatwierdzono APPLY
bool wifiConnected  = false;   // Czy jesteśmy połączeni z WiFi


// EEPROM ustawienia
#define SSID_MAX 32
#define PASS_MAX 64
#define EEPROM_SIZE 256
#define SSID_LEN_ADDR 0
#define SSID_ADDR 1
#define PASS_LEN_ADDR (SSID_ADDR + SSID_MAX)
#define PASS_ADDR (PASS_LEN_ADDR + 1)


// MQTT
WiFiClient espClient;
PubSubClient mqtt_client(espClient);

char topic[30] = "kurnik/";   // Bazowy topic, potem + MAC
bool topicInitialized = false;

const int mqtt_port = 1883;                  // zwykły MQTT (bez TLS)
const char *mqtt_broker   = "57.128.237.128"; // adres serwera MQTT
const char *mqtt_username = "esp8266"; // nazwa użytkownika MQTT
const char *mqtt_password = "esp8266"; // hasło użytkownika MQTT

// ================== BLE – konfiguracja WiFi ==================
// 128-bitowe UUID 
BLEService wifiService("00000001-0000-0000-0000-000000000001");

BLEStringCharacteristic ssidCharacteristic(
  "00000001-0000-0000-0000-000000000002",
  BLERead | BLEWrite,
  32
);

BLEStringCharacteristic passCharacteristic(
  "00000001-0000-0000-0000-000000000003",
  BLERead | BLEWrite,
  64
);

// 0 = nic, 1 = zastosuj konfigurację
BLEByteCharacteristic applyCharacteristic(
  "00000001-0000-0000-0000-000000000004",
  BLERead | BLEWrite
);

// STATUS: 0=disconnected/error, 1=connected OK
BLEByteCharacteristic statusCharacteristic(
  "00000001-0000-0000-0000-000000000005",
  BLERead | BLENotify
);

// ================== Dane pomiarowe ==================

typedef struct {
    int   ID_urzadzenia;
    float temperatura;
    float wilgotnosc;
    int   poziom_co2;
    int   poziom_amoniaku;
    int   naslonecznienie;
} Pakiet_Danych;


// ================== Deklaracje funkcji ==================

void connectToWiFi();
void connectToMQTT();
void mqttCallback(char *topic, byte *payload, unsigned int length);
void wyslijPakiet(Pakiet_Danych* pakiet);
void TEST_zapelnij_pakiet(Pakiet_Danych* pakiet, int wielkosc);
void initTopicFromMAC();
bool loadCredentialsFromEEPROM();
void saveCredentialsToEEPROM();

// ================== Setup ==================

void setup() {
    Serial.begin(115200);
    while (!Serial) { }


    // ----- BLE start -----
    if (!BLE.begin()) {
        Serial.println("Błąd startu BLE!");
        while (1);
    }

    defaultBluetooth();

    // Initialize EEPROM and try to load saved credentials.
    // Different cores expose different EEPROM APIs: ESP32/ESP8266 require begin(size),
    // while some cores (Renesas) provide begin() without args.
#if defined(ESP32) || defined(ESP8266)
    EEPROM.begin(EEPROM_SIZE);
#else
    EEPROM.begin();
#endif

    bool had = loadCredentialsFromEEPROM();

    if (!had) {
        BLE.advertise();
        Serial.println("BLE uruchomione - skonfiguruj WiFi z telefonu (SSID, PASS, APPLY=1)");
        Serial.println(BLE.address());
        provisionViaBle();
    } else {
        Serial.println("Wczytano dane WiFi z EEPROM - pomijam BLE provisioning");
    }

    // ----- MQTT konfiguracja (bez łączenia) -----
    mqtt_client.setServer(mqtt_broker, mqtt_port);
    mqtt_client.setCallback(mqttCallback);

    // Jeśli mieliśmy zapisane dane WiFi, łączymy się teraz
    if (had) {
        connectToWiFi();
        if (WiFi.status() == WL_CONNECTED) {
            initTopicFromMAC();
            connectToMQTT();
        }
    }
}

// ================== Funkcje pomocnicze ==================

void defaultBluetooth(){

    BLE.setLocalName("Kurnik IoT");
    BLE.setAdvertisedService(wifiService);

    wifiService.addCharacteristic(ssidCharacteristic);
    wifiService.addCharacteristic(passCharacteristic);
    wifiService.addCharacteristic(applyCharacteristic);
    wifiService.addCharacteristic(statusCharacteristic);

    BLE.addService(wifiService);

    ssidCharacteristic.writeValue("");
    passCharacteristic.writeValue("");
    applyCharacteristic.writeValue((byte)0);
    statusCharacteristic.writeValue((byte)0);  // domyślnie rozłączone

}

void connectToWiFi() {
    Serial.print("Łączenie z WiFi: ");
    Serial.println(wifi_ssid);

    WiFi.begin(wifi_ssid, wifi_password);
    
    int attempts = 0;
    while (WiFi.status() != WL_CONNECTED && attempts < 30) { // 30 sekund timeout
        // trzymać BLE aktywne podczas oczekiwania
        for (int i = 0; i < 10; i++) {
            BLE.poll();
            delay(100);
        }
        Serial.print(".");
        attempts++;
    }
    
    if (WiFi.status() != WL_CONNECTED) {
        Serial.println("\nBłąd połączenia WiFi!");
        statusCharacteristic.writeValue((byte)0);  // FAIL
        return;
    }
    
    Serial.println("\nPołączono z WiFi");
    Serial.print("IP: ");
    Serial.println(WiFi.localIP());
    statusCharacteristic.writeValue((byte)1); // OK
}


void provisionViaBle() {
    Serial.println("Starting BLE provisioning. Waiting for central...");
    BLE.advertise();

    while (!wifiConfigured) {
        BLEDevice central = BLE.central();
        if (!central) {
            // no central connected yet
            BLE.poll();
            delay(200);
            continue;
        }

        Serial.print("BLE central connected: "); Serial.println(central.address());

        while (central.connected() && !wifiConnected) {
            BLE.poll();
            if (ssidCharacteristic.written() || passCharacteristic.written() || applyCharacteristic.written()) {
                String ssid = ssidCharacteristic.value();
                String pass = passCharacteristic.value();
                byte apply = applyCharacteristic.value();
                if (apply == 1 && ssid.length() > 0) {
                    ssid.toCharArray(wifi_ssid, sizeof(wifi_ssid));
                    pass.toCharArray(wifi_password, sizeof(wifi_password));

                    Serial.print("Otrzymano SSID: "); Serial.println(wifi_ssid);

                    statusCharacteristic.writeValue((byte)0);
                    connectToWiFi();

                    if (WiFi.status() == WL_CONNECTED) {
                        wifiConfigured = true;
                        wifiConnected = true;
                        saveCredentialsToEEPROM();

                        Serial.println("WiFi połączone - publikowanie wiadomości inicjującej MQTT");
                        initTopicFromMAC();
                        connectToMQTT();
                        if (mqtt_client.connected()) {
                            mqtt_client.publish(topic, "Wiadomosc inicjujaca");
                            mqtt_client.loop();
                        }

                        // powiadom klienta BLE na krótko
                        for (int i = 0; i < 10 && central.connected(); i++) {
                            statusCharacteristic.writeValue((byte)1);
                            BLE.poll();
                            delay(100);
                        }

                        BLE.stopAdvertise();
                        break; // exit central.connected() loop
                    } else {
                        Serial.println("Nie udało się połączyć z WiFi");
                        statusCharacteristic.writeValue((byte)0);
                        applyCharacteristic.writeValue((byte)0);
                    }
                }
            }
        }

        Serial.println("BLE central disconnected");
    }

    // stopowanie reklamy BLE
    BLE.stopAdvertise();
}


bool loadCredentialsFromEEPROM() {
    // wczytujemy SSID
    byte ssid_len = EEPROM.read(SSID_LEN_ADDR);
    if (ssid_len == 0xFF || ssid_len == 0 || ssid_len > SSID_MAX) return false;

    for (int i = 0; i < ssid_len && i < SSID_MAX; i++) {
        wifi_ssid[i] = (char)EEPROM.read(SSID_ADDR + i);
    }
    wifi_ssid[ssid_len] = '\0';

    // wczytujemy hasło
    byte pass_len = EEPROM.read(PASS_LEN_ADDR);
    if (pass_len == 0xFF || pass_len > PASS_MAX) pass_len = 0;
    for (int i = 0; i < pass_len && i < PASS_MAX; i++) {
        wifi_password[i] = (char)EEPROM.read(PASS_ADDR + i);
    }
    wifi_password[pass_len] = '\0';

    
    wifiConfigured = true;
    return true;
}

void saveCredentialsToEEPROM() {
    byte ssid_len = strlen(wifi_ssid);
    if (ssid_len > SSID_MAX) ssid_len = SSID_MAX;
    EEPROM.write(SSID_LEN_ADDR, ssid_len);
    for (int i = 0; i < ssid_len; i++) {
        EEPROM.write(SSID_ADDR + i, wifi_ssid[i]);
    }

    byte pass_len = strlen(wifi_password);
    if (pass_len > PASS_MAX) pass_len = PASS_MAX;
    EEPROM.write(PASS_LEN_ADDR, pass_len);
    for (int i = 0; i < pass_len; i++) {
        EEPROM.write(PASS_ADDR + i, wifi_password[i]);
    }

    // Some cores require commit; guard with weak symbol
#if defined(EEPROM_commit)
    EEPROM.commit();
#elif defined(EEPROM) && defined(ARDUINO_ARCH_ESP32)
    EEPROM.commit();
#endif
}

// Reset EEPROM i przejście w tryb provisioningu
void resetKurnik() {
    Serial.println("RESET EEPROM: czyszczenie...");

    // Ustawiamy długości na 0xFF (brak zapisanych danych)
    EEPROM.write(SSID_LEN_ADDR, 0xFF);
    EEPROM.write(PASS_LEN_ADDR, 0xFF);

    // (opcjonalnie) nadpisz zawartość buforów zerami dla przejrzystości
    for (int i = 0; i < SSID_MAX; i++) {
        EEPROM.write(SSID_ADDR + i, 0);
    }
    for (int i = 0; i < PASS_MAX; i++) {
        EEPROM.write(PASS_ADDR + i, 0);
    }

    // Commit jeśli wymagany przez core
#if defined(EEPROM_commit)
    EEPROM.commit();
#elif defined(EEPROM) && defined(ARDUINO_ARCH_ESP32)
    EEPROM.commit();
#endif

    // Zerowanie lokalnych zmiennych i połączeń
    wifiConfigured = false;
    wifiConnected = false;
    memset(wifi_ssid, 0, sizeof(wifi_ssid));
    memset(wifi_password, 0, sizeof(wifi_password));
    topicInitialized = false;
    topic[0] = 'k'; topic[1] = 'u'; topic[2] = 'r'; topic[3] = 'n'; topic[4] = 'i'; topic[5] = 'k'; topic[6] = '/'; topic[7] = '\0';

    // Rozłącz MQTT i WiFi jeśli były połączone
    if (mqtt_client.connected()) {
        mqtt_client.disconnect();
    }
#if defined(ESP8266) || defined(ESP32)
    WiFi.disconnect(true);
#else
    WiFi.disconnect();
#endif

    // Ustaw status BLE i wznow reklamę aby można było provisionować z telefonu
    statusCharacteristic.writeValue((byte)0);
    BLE.advertise();

    Serial.println("EEPROM wyczyszczony. Urządzenie uruchomione w trybie BLE provisioning.");
    Serial.println("Proszę skonfigurować SSID i PASS z aplikacji mobilnej.");

    // Opcjonalnie spróbuj zrestartować urządzenie jeśli core to wspiera,
    // aby mieć czysty start; w przeciwnym razie urządzenie już reklamuje BLE.
#if defined(ESP8266) || defined(ESP32)
    delay(200);
    ESP.restart();
#endif
}

void initTopicFromMAC() {
    if (topicInitialized) return;
    char macStr[18] = "";
    String bleAddr = BLE.address();
    if (bleAddr.length() > 0) {
        bleAddr.toCharArray(macStr, sizeof(macStr));
    } 

    strcat(topic, macStr);   // "kurnik/" + address
    topicInitialized = true;

    Serial.print("MQTT topic: ");
    Serial.println(topic);
}

void connectToMQTT() {
    while (!mqtt_client.connected()) {
        char macStr[64] = "";
        String bleAddr = BLE.address();
        if (bleAddr.length() > 0) {
            bleAddr.toCharArray(macStr, sizeof(macStr));
        }

        String client_id = "Kurnik_IoT" + String(macStr);
        Serial.print("Łączenie do brokera MQTT jako ");
        Serial.println(client_id.c_str());

        if (mqtt_client.connect(client_id.c_str(), mqtt_username, mqtt_password)) {
            Serial.println("Połączono z brokerem MQTT");
            mqtt_client.subscribe(topic);
            mqtt_client.publish(topic, "Wiadomość inicjująca");
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

    mqtt_client.publish(topic, message);
}

void TEST_zapelnij_pakiet(Pakiet_Danych* pakiet, int wielkosc) {
    for (int i = 0; i < wielkosc; i++) {
        float t = (float)i / (wielkosc - 1) * 2 * M_PI; // 0 -> 2π

        pakiet[i].ID_urzadzenia   = 2;
        pakiet[i].temperatura     = 22.0 + 5.0  * sin(t);        // 17-27°C
        pakiet[i].wilgotnosc      = 60.0 + 20.0 * sin(t * 1.3);  // 40-80%
        pakiet[i].poziom_co2      = 1200 + 400 * sin(t * 0.8);   // 800-1600 ppm
        pakiet[i].poziom_amoniaku = 15 + 8   * sin(t * 1.7);     // 7-23 ppm
        pakiet[i].naslonecznienie = 50 + 45  * sin(t * 0.5);     // 5-95 lux
    }
}

// ================== Loop ==================

void loop() {

    // Obsługa komend przez Serial: "rest" lub "reset" (case-insensitive)
    if (Serial.available() > 0) {
        String cmd = Serial.readStringUntil('\n');
        cmd.trim();
        cmd.toLowerCase();
        if (cmd == "rest" || cmd == "reset") {
            resetKurnik();
            // po resetowaniu restart (jeśli nie restartowano, to kontynuujemy)
            return;
        }
    }

    if (WiFi.status() != WL_CONNECTED) {
        Serial.println("Utracono WiFi - próba ponownego połączenia");
        connectToWiFi();
    }

    if (!mqtt_client.connected()) {
        connectToMQTT();
    }

    //Przykładowe wysyłanie pakietów danych co 10 sekund
    Pakiet_Danych Dane[100];
    TEST_zapelnij_pakiet(Dane, 100);

    int i=0;

    while(Serial.available()<=0){
        wyslijPakiet(&Dane[i]);
        delay(10000);
        Serial.println("Wyslano pakiet");
        i++;
        if(i=99) i=0;
    }

    mqtt_client.loop();

}
