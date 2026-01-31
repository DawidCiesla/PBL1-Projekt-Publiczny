#include "main.h"
#include "bluetooth.h"
#include "pamiec_lokalna.h"
#include "kurnikwifi.h"
#include "mqtt.h"
#include "pamiec_SD.h"
#include "czujniki.h"
#include "mesh_local.h"
#include "oled.h"

// Bufor komend z Serial
String serialCommandBuffer = "";

// Przyciski
static const int BUTTON_SCREEN_PIN = 2; 
static const int BUTTON_RESET_PIN = 4;  


static int lastScreenReading = HIGH;
static int screenState = HIGH;
static unsigned long screenLastDebounceTime = 0;
static const unsigned long DEBOUNCE_DELAY = 50;

static int lastResetReading = HIGH;
static int resetState = HIGH;
static unsigned long resetLastDebounceTime = 0;
static unsigned long resetPressStart = 0;
static bool resetTriggered = false;
static const unsigned long RESET_HOLD_MS = 5000;
static unsigned long lastResetOledUpdate = 0;
static int currentScreen = 0;

void setup() {
    Serial.begin(115200);

    // Inicjalizacja OLED
    if (!oled.begin()) {
        Serial.println("OLED init failed");
    } else {
        oled.showBootScreen("KURNIK", "Uruchamianie...", 10);
    }

    // Inicjalizacja modułu Bluetooth do konfiguracji WiFi
    InicjalizacjaBluetooth();

    // Inicjalizacja czujników
    InicjalizacjaCzujnikow();
    // Krótkie wyświetlenie animowanego ekranu ładowania podczas stabilizacji czujników
    unsigned long _start = millis();
    while (millis() - _start < 2000) {
        oled.showLoadingAnimated();
        delay(100);
    }

    // Inicjalizacja pamięci EEPROM i karty SD
    InicjalizacjaPamieci();
    InicjalizacjaSD();

    oled.showBootScreen("KURNIK", "Inicjalizacja pamieci", 30);

    // Próba wczytania zapisanych danych WiFi z EEPROM
    bool had = WczytanieDanychEEPROM();

    if (had == false) {
        // ŚCIEŻKA 1: Brak zapisanych danych WiFi - uruchom provisioning przez BLE
        if (pAdvertising) pAdvertising->start();
        Serial.println("BLE uruchomione - skonfiguruj WiFi z telefonu (SSID, PASS, APPLY=1)");
            Serial.println(BLEDevice::getAddress().toString().c_str());

            // Pokaż na OLED ekran provisioningowy z adresem urządzenia
            oled.showProvisioningScreen(BLEDevice::getAddress().toString().c_str());

            // Czekaj na konfigurację WiFi przez BLE (blokuje wykonanie)
            NadawaniePrzezBLE();
 
        // Po udanej konfiguracji WiFi, synchronizuj czas i połącz z MQTT        oled.showConnectionSuccess(wifi_ssid);
        delay(2000); // Pokaż ekran sukcesu przez 2 sekundy

        oled.showNTPSync(70);
        UstawCzasZWiFi();
        delay(1000);

		oled.showMQTTInit(85);
		InicjalizacjaMQTT();
			
		Serial.println("WiFi połączone - publikowanie wiadomości inicjującej MQTT");
		InicjalizacjaTopicuZ_MAC();
		PolaczDoMQTT();
		delay(1000);

        // Aktualizuj OLED, aby pokazać zakończenie inicjalizacji
        oled.showBootScreen("KURNIK", "Gotowe", 100);
		if (asyncMqttClient.connected()) {
			asyncMqttClient.publish(topic, 0, false, "Wiadomosc inicjujaca");
            // Wyślij dane oczekujące w kolejce na karcie SD
			PonowWyslijZKolejki();
		}

    } else {
        // ŚCIEŻKA 2: Wczytano dane WiFi z EEPROM - pomiń provisioning BLE
        Serial.println("Wczytano dane WiFi z EEPROM - pomijam BLE provisioning");
        
        // Połącz z WiFi używając zapisanych danych
        oled.showWiFiInit(50);
        PolaczZWiFi();
        if (WiFi.status() == WL_CONNECTED) {
            delay(1000);
            // Synchronizuj czas z serwera NTP
            oled.showNTPSync(70);
            UstawCzasZWiFi();
            delay(1000);
            // Inicjalizuj i połącz z MQTT
            oled.showMQTTInit(85);
            InicjalizacjaMQTT();
            InicjalizacjaTopicuZ_MAC();
            PolaczDoMQTT();
            delay(1000);
            // Wyślij dane oczekujące w kolejce
            if (asyncMqttClient.connected()) {
                PonowWyslijZKolejki();
            }
        }
        
    }

    // Inicjalizacja sieci mesh, rozpoczęcie pracy jako root
    InicjalizacjaMesh();

    // Konfiguracja przycisków
    pinMode(BUTTON_SCREEN_PIN, INPUT_PULLUP);
    pinMode(BUTTON_RESET_PIN, INPUT_PULLUP);

    // Upewnij się, że początkowy ekran OLED to czujniki
    currentScreen = 0;
    oledShowSensors();
}

/*
 * Funkcja resetująca urządzenie do ustawień fabrycznych
 * Czyści EEPROM, kartę SD i przechodzi w tryb konfiguracji BLE
 */
void resetKurnik() {
    Serial.println("RESET EEPROM: czyszczenie...");

    // Wyczyść pamięć EEPROM
    ResetPamiec();
    
    // Wyczyść całą kartę SD ze wszystkich plików
    WyczyscKarteSD();

    // Zerowanie zmiennych globalnych
    wifiConfigured = false;
    wifiConnected = false;
    memset(wifi_ssid, 0, sizeof(wifi_ssid));
    memset(wifi_password, 0, sizeof(wifi_password));
    topicInitialized = false;
    topic[0] = 'k'; topic[1] = 'u'; topic[2] = 'r'; topic[3] = 'n'; topic[4] = 'i'; topic[5] = 'k'; topic[6] = '/'; topic[7] = '\0';

    // Rozłącz MQTT i WiFi jeśli były połączone
    if (asyncMqttClient.connected()) {
        asyncMqttClient.disconnect();
    }
#if defined(ESP8266) || defined(ESP32)
    WiFi.disconnect(true);
#else
    WiFi.disconnect();
#endif

    // Uruchom reklamę BLE dla nowego provisioningu
    if (pAdvertising) pAdvertising->start();

    Serial.println("EEPROM wyczyszczony. Urządzenie uruchomione w trybie BLE provisioning.");
    Serial.println("Proszę skonfigurować SSID i PASS z aplikacji mobilnej.");

#if defined(ESP8266) || defined(ESP32)
    delay(200);
    ESP.restart();  // Restart ESP32
#endif
}

void wyswietlStatusSystemu() {
    Serial.println("\n=== STATUS SYSTEMU ===");
    
    // WiFi
    Serial.print("WiFi: ");
    if (WiFi.status() == WL_CONNECTED) {
        Serial.print("Połączone (");
        Serial.print(WiFi.RSSI());
        Serial.println(" dBm)");
        Serial.print("IP: ");
        Serial.println(WiFi.localIP());
    } else {
        Serial.println("Rozłączone");
    }
    
    // MQTT
    Serial.print("MQTT: ");
    Serial.println(asyncMqttClient.connected() ? "Połączone" : "Rozłączone");
    
    // Czas
    Serial.print("Czas: ");
    Serial.println(rtc.getTime("%Y-%m-%d %H:%M:%S"));
    
    // Synchronizacja NTP jest zarządzana przez scheduler (co 1 godzinę)
    
    // Pamięć
    Serial.print("Wolna RAM: ");
    Serial.print(ESP.getFreeHeap());
    Serial.println(" bajtów");
    
    // Uptime
    Serial.print("Uptime: ");
    Serial.print(millis() / 1000);
    Serial.println(" sekund");
    
    Serial.println("=======================\n");
}

// Funkcja do obsługi komend Serial (wywoływana w loop())
void checkAndHandleSerialCommands() {
    // Sprawdź czy są dostępne dane na Serial
    while (Serial.available() > 0) {
        char c = (char)Serial.read();
        
        // DEBUG: Pokaż co odbieramy
        Serial.printf("[DEBUG] Odebrano znak: '%c' (kod: %d)\n", c, (int)c);
        
        // Koniec komendy - wykonaj
        if (c == '\n' || c == '\r') {
            if (serialCommandBuffer.length() > 0) {
                String cmd = serialCommandBuffer;
                serialCommandBuffer = "";
                
                Serial.printf("[DEBUG] Przetwarzam komendę: '%s' (długość: %d)\n", 
                             cmd.c_str(), cmd.length());
                
                cmd.trim();
                cmd.toLowerCase();
                
                Serial.printf("[DEBUG] Po trim/lower: '%s'\n", cmd.c_str());
                
                if (cmd == "reset") {
                    resetKurnik();
                }
                else if (cmd == "status") {
                    wyswietlStatusSystemu();
                }
                else if (cmd.length() > 0) {
                    Serial.printf("Nieznana komenda: '%s'\n", cmd.c_str());
                    Serial.println("Dostępne komendy: reset, status");
                }
            } else {
                Serial.println("[DEBUG] Pusty bufor - ignoruję");
            }
        }
        // Dodaj znak do bufora
        else {
            serialCommandBuffer += c;
            Serial.printf("[DEBUG] Bufor: '%s'\n", serialCommandBuffer.c_str());
        }
    }
}

void loop() {
    // === AKTUALIZACJA MESH I SCHEDULERA ===
    // mesh.update() wewnętrznie wywołuje userScheduler.execute()
    // dzięki czemu wszystkie zadania są obsługiwane automatycznie:
    // - taskRaport (raport sieci mesh co 10s)
    // - syncMeshDataTime (synchronizacja czasu mesh co 20s)
    // - taskWyslijDaneCzujnikow (wysyłanie danych czujników co 5s)
    // - taskOLEDSwitch (przełączanie ekranu OLED co 5s)
    // - taskMonitorPolaczen (sprawdzanie WiFi/MQTT co 10s)
    // - taskSyncNTP (synchronizacja NTP co 1 godzinę)
    mesh.update();
    
    // === OBSŁUGA KOMEND SERIAL ===
    // Sprawdź czy użytkownik wysłał komendę "reset" lub "status" przez Serial Monitor
    checkAndHandleSerialCommands();

    // === OBSŁUGA PRZYCISKÓW ===
    // Przycisk ekranu (z eliminacją drgań, przełączanie po puszczeniu)
    int reading = digitalRead(BUTTON_SCREEN_PIN);
    if (reading != lastScreenReading) {
        screenLastDebounceTime = millis();
    }
    if ((millis() - screenLastDebounceTime) > DEBOUNCE_DELAY) {
        if (reading != screenState) {
            screenState = reading;
            // aktywny stan niski: przycisk wciśnięty, potem puszczony
            if (screenState == LOW) {
                // nic nie rób przy wciśnięciu, czekaj na puszczenie
            } else {
                // po puszczeniu -> przełącz ekrany: czujniki -> status -> mesh -> czujniki
                if (currentScreen == 0) {
                    oledShowStatus();
                    currentScreen = 1;
                } else if (currentScreen == 1) {
                    oledShowMeshStatus();
                    currentScreen = 2;
                } else {
                    oledShowSensors();
                    currentScreen = 0;
                }
            }
        }
    }
    lastScreenReading = reading;

    // Przycisk reset (z eliminacją drgań, wykrywanie długiego przytrzymania)
    int rreading = digitalRead(BUTTON_RESET_PIN);
    if (rreading != lastResetReading) {
        resetLastDebounceTime = millis();
    }
    if ((millis() - resetLastDebounceTime) > DEBOUNCE_DELAY) {
        if (rreading != resetState) {
            resetState = rreading;
            if (resetState == LOW) {
                // przycisk wciśnięty
                resetPressStart = millis();
                resetTriggered = false;
            } else {
                // przycisk puszczony - jeśli jeszcze nie zresetowano, sprawdź czas trzymania
                unsigned long held = millis() - resetPressStart;
                if (!resetTriggered && held >= RESET_HOLD_MS) {
                    Serial.println("[BUTTON] resetuje urządzenie...");
                    resetKurnik();
                } else if (!resetTriggered) {
                    // puszczony przed progiem -> przywróć ekran czujników
                    oledShowSensors();
                    currentScreen = 0;
                }
            }
        }
    }
    // Podczas trzymania, wywołaj reset po osiągnięciu progu czasu
    if (resetState == LOW && !resetTriggered) {
        unsigned long heldNow = millis() - resetPressStart;
        // aktualizuj licznik OLED okresowo
        if ((millis() - lastResetOledUpdate) > 200) {
            lastResetOledUpdate = millis();
            long remaining = (long)RESET_HOLD_MS - (long)heldNow;
            int secondsLeft = 0;
            if (remaining > 0) secondsLeft = (int)((remaining + 999) / 1000); // zaokrąglenie w górę do sekund
            char buf[32];
            snprintf(buf, sizeof(buf), "Reset za %d s", secondsLeft);
            // Pokaż postęp (jak blisko do resetu)
            uint8_t prog = 0;
            if (heldNow >= RESET_HOLD_MS) prog = 100; else prog = (uint8_t)((heldNow * 100) / RESET_HOLD_MS);
            oled.showBootScreen("RESET", buf, prog);
        }

        if (heldNow >= RESET_HOLD_MS) {
            resetTriggered = true;
            Serial.println("[BUTTON] resetuje urządzenie...");
            resetKurnik();
        }
    }
    lastResetReading = rreading;
}
