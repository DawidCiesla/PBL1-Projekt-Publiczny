#include <ESP32Time.h>
#include <painlessMesh.h>
#include <ESP8266WiFi.h>
#include "mesh_local.h"
#include "czujniki.h"
#include "pamiec.h"

painlessMesh mesh;
Scheduler userScheduler;
ESP32Time rtc;
uint32_t root_id = 0;
bool czy_ma_czas = false;
bool polaczony_z_mesh = false;
int mesh_channel = 0;  // Znaleziony kanał sieci mesh
String mesh_ssid = "";  // Pełna nazwa znalezionej sieci mesh

// Deklaracje forward
void wyslijOdczyt();
void zapytajOCzas();


// Task wysyłania odczytów co 5 sekund
Task taskWyslijOdczyt(TASK_SECOND * 5, TASK_FOREVER, &wyslijOdczyt);
// Task żądania czasu co 10 sekund (aktywne dopóki nie ma czasu)
Task taskZapytajCzas(TASK_SECOND * 10, TASK_FOREVER, &zapytajOCzas);

void receivedCallback(uint32_t from, String &msg) {
    Serial.printf(">>> ODEBRANO od %u: %s\n", from, msg.c_str());
    
    String prefix = msg.substring(0,4);
    Serial.printf(">>> Prefix: '%s'\n", prefix.c_str());
    
    if(prefix == "SYNC") {
        root_id = from;
        String time = msg.substring(4);
        Serial.printf(">>> Time string: '%s'\n", time.c_str());
        
        // Użyj strtoul zamiast toInt() dla uint32_t
        unsigned long time_int = strtoul(time.c_str(), NULL, 10);
        Serial.printf(">>> Parsed time: %lu\n", time_int);
        time_int += 3600;
        rtc.setTime(time_int);
        czy_ma_czas = true;
        // Wyłącz żądanie czasu - mamy już czas
        taskZapytajCzas.disable();
        Serial.printf(">>> ZSYNCHRONIZOWANO CZAS z ROOT (ID: %u)\n", root_id);
        Serial.printf(">>> Aktualny czas RTC: %s\n", rtc.getTimeDate().c_str());
    } else {
        Serial.printf(">>> Nieznany prefix: %s\n", prefix.c_str());
    }
}

void changedConnectionCallback() {
    Serial.println(">>> ZMIANA POŁĄCZEŃ w sieci mesh");
    SimpleList<uint32_t> nodes = mesh.getNodeList();
    Serial.printf(">>> Węzłów w sieci: %d\n", nodes.size());
    
    if (nodes.size() > 0 && !czy_ma_czas) {
        // Jesteśmy połączeni ale nie mamy czasu - włącz żądanie
        taskZapytajCzas.enable();
    }
}

void zapytajOCzas() {
    if (!czy_ma_czas) {
        Serial.println(">>> Wysyłam żądanie czasu (TIME)...");
        mesh.sendBroadcast("TIME");
    }
}

void wyslijOdczyt() {
    if (!czy_ma_czas) {
        Serial.println("Brak zsynchronizowanego czasu - pomijam wysyłkę");
        return;
    }
    
    if (root_id == 0) {
        Serial.println("Brak root_id - pomijam wysyłkę");
        return;
    }
    
    // Odczytaj dane z czujników
    Pakiet_Danych odczyt = odczytCzujniki();
    
    char dane[150];
    pakietToCSV(&odczyt, dane, 150);
    
    String msg = "DANE;";
    msg += String(dane);
    
    mesh.sendSingle(root_id, msg);
    
    Serial.printf(">>> Wysłano odczyt z czujników do ROOT (ID: %u)\n", root_id);
}

// Skanuj sieci WiFi
// Jeśli mesh_ssid jest pusty - szuka najlepszej sieci KurnikMesh_* i ustawia mesh_ssid
// Jeśli mesh_ssid jest ustawiony - szuka konkretnie tego SSID
int skanujSiecMesh() {
    bool szukaj_dowolnej = (mesh_ssid.length() == 0);
    
    if (szukaj_dowolnej) {
        Serial.println(">>> Skanowanie w poszukiwaniu sieci KurnikMesh_*");
    } else {
        Serial.printf(">>> Skanowanie sieci w poszukiwaniu: %s\n", mesh_ssid.c_str());
    }
    
    int liczba_sieci = WiFi.scanNetworks();
    Serial.printf(">>> Znaleziono %d sieci WiFi\n", liczba_sieci);
    
    int znaleziony_kanal = 0;
    String najlepsza_siec = "";
    int najsilniejszy_rssi = -100;
    
    for (int i = 0; i < liczba_sieci; i++) {
        String ssid = WiFi.SSID(i);
        int rssi = WiFi.RSSI(i);
        int kanal = WiFi.channel(i);
        
        Serial.printf("  %d: %s (Kanał %d, RSSI: %d dBm)\n", i + 1, ssid.c_str(), kanal, rssi);
        
        if (szukaj_dowolnej) {
            // Szukaj najlepszej sieci KurnikMesh_*
            if (ssid.startsWith("KurnikMesh_")) {
                Serial.printf("    >>> ZNALEZIONO SIEĆ MESH: %s (RSSI: %d dBm)\n", ssid.c_str(), rssi);
                if (rssi > najsilniejszy_rssi) {
                    najsilniejszy_rssi = rssi;
                    znaleziony_kanal = kanal;
                    najlepsza_siec = ssid;
                }
            }
        } else {
            // Szukaj konkretnego SSID
            if (ssid == mesh_ssid) {
                znaleziony_kanal = kanal;
                Serial.printf("    >>> ZNALEZIONO SIEĆ: %s na kanale %d (RSSI: %d dBm)\n", 
                             ssid.c_str(), kanal, rssi);
                break;
            }
        }
    }
    
    WiFi.scanDelete();
    
    if (szukaj_dowolnej) {
        if (znaleziony_kanal > 0) {
            mesh_ssid = najlepsza_siec;
            mesh_channel = znaleziony_kanal;
            Serial.printf(">>> WYBRANO SIEĆ: %s, KANAŁ: %d, RSSI: %d dBm\n", 
                         najlepsza_siec.c_str(), znaleziony_kanal, najsilniejszy_rssi);
        } else {
            Serial.println(">>> BŁĄD: Nie znaleziono żadnej sieci KurnikMesh_*");
            mesh_channel = 0;
        }
    } else {
        if (znaleziony_kanal > 0) {
            mesh_channel = znaleziony_kanal;
        } else {
            Serial.printf(">>> BŁĄD: Nie znaleziono sieci %s\n", mesh_ssid.c_str());
            mesh_channel = 0;
        }
    }
    
    return znaleziony_kanal;
}

void InicjalizacjaMesh() {
    // Odczytaj SSID z EEPROM
    String zapisany_ssid = odczytajSSIDzEEPROM();
    
    if (zapisany_ssid.length() == 0) {
        // Brak SSID w pamięci - szukaj najlepszej sieci KurnikMesh_*
        Serial.println(">>> Brak SSID w pamięci - szukam najlepszej sieci mesh...");
        mesh_ssid = "";  // Wyczyść aby skanujSiecMesh szukała dowolnej
        mesh_channel = skanujSiecMesh();
        
        if (mesh_channel == 0 || mesh_ssid.length() == 0) {
            Serial.println(">>> BŁĄD: Nie znaleziono żadnej sieci mesh!");
            return;
        }
        
        // Zapisz znalezioną sieć do EEPROM
        Serial.printf(">>> Zapisuję sieć %s do pamięci...\n", mesh_ssid.c_str());
        zapiszSSIDDoEEPROM(mesh_ssid);
    } else {
        // Mamy SSID w pamięci - szukaj konkretnie tej sieci
        mesh_ssid = zapisany_ssid;
        Serial.printf(">>> Odczytano SSID z pamięci: %s\n", mesh_ssid.c_str());
        
        // Skanuj sieci aby znaleźć kanał dla zapisanego SSID
        Serial.println(">>> Skanowanie sieci WiFi...");
        mesh_channel = skanujSiecMesh();
        
        // Sprawdź czy znaleziono sieć
        if (mesh_channel == 0) {
            Serial.printf(">>> BŁĄD: Nie znaleziono sieci %s!\n", mesh_ssid.c_str());
            return;
        }
    }
    
    // Włącz debug messages
    mesh.setDebugMsgTypes(ERROR | STARTUP | CONNECTION);
    
    // Inicjalizacja mesh z konkretną nazwą sieci i kanałem
    Serial.printf(">>> ŁĄCZENIE DO SIECI: %s (kanał %d)...\n", mesh_ssid.c_str(), mesh_channel);
    mesh.init(mesh_ssid, MESH_PASSWORD, &userScheduler, MESH_PORT, WIFI_AP_STA, mesh_channel);
    
    // Informujemy że w sieci jest ROOT
    mesh.setContainsRoot(true);
    
    // Rejestracja callbacków
    mesh.onReceive(&receivedCallback);
    mesh.onChangedConnections(&changedConnectionCallback);
    
    // Czekaj na połączenie z innymi węzłami
    Serial.println(">>> Oczekiwanie na połączenie z siecią mesh...");
    unsigned long start = millis();
    
    while (millis() - start < 15000) {
        mesh.update();
        userScheduler.execute();
        
        if (mesh.getNodeList().size() > 0) {
            Serial.printf(">>> POŁĄCZONO! Wykryto %d węzłów w sieci\n", mesh.getNodeList().size());
            polaczony_z_mesh = true;
            break;
        }
        delay(100);
    }
    
    if (!polaczony_z_mesh) {
        Serial.println(">>> OSTRZEŻENIE: Nie wykryto innych węzłów w ciągu 15s");
        Serial.println(">>> Node będzie czekał na pojawienie się innych węzłów...");
    }
    
    // Dodanie tasków do schedulera
    userScheduler.addTask(taskWyslijOdczyt);
    userScheduler.addTask(taskZapytajCzas);
    
    // Włącz wysyłanie odczytów
    taskWyslijOdczyt.enable();
    
    Serial.println(">>> ROZPOCZĘTO PRACĘ JAKO NODE <<<");
    Serial.printf(">>> Node ID: %u\n", mesh.getNodeId());
    Serial.printf(">>> SSID: %s\n", mesh_ssid.c_str());
    Serial.printf(">>> Kanał WiFi: %d\n", mesh_channel);
}
    
   
