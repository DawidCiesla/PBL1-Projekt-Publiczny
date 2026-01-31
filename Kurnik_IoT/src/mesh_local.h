#ifndef MESH_LOCAL
#define MESH_LOCAL

#include <painlessMesh.h>

// Dynamiczna nazwa mesh z adresem MAC (generowana w InicjalizacjaMesh)
extern String MESH_PREFIX;
#define MESH_PASSWORD   "CHANGEME" // Zastąp bezpiecznym hasłem w konfiguracji (min. 8 znaków)
#define MESH_PORT       5555

// Główne obiekty mesh
extern painlessMesh mesh;
extern Scheduler userScheduler;

// === TASKI SCHEDULERA ===
// Task raportujący stan sieci mesh
extern Task taskRaport;
// Task synchronizacji czasu w sieci mesh
extern Task syncMeshDataTime;
// Task wysyłania danych z czujników (co 5 sekund)
extern Task taskWyslijDaneCzujnikow;
// Task przełączania ekranu OLED (co 5 sekund)
extern Task taskOLEDSwitch;
// Task odświeżania ekranu OLED dla statycznego widoku czujników (co 10 sekund)
extern Task taskOLEDRefresh;
// Task monitorowania połączeń WiFi/MQTT (co 10 sekund)
extern Task taskMonitorPolaczen;
// Task synchronizacji NTP (co 1 godzinę)
extern Task taskSyncNTP;

// === FUNKCJE ===
// Inicjalizacja i setup mesha
void InicjalizacjaMesh();

// Callback callbacki tasków (do wywołania zewnętrznego)
void wyslijDaneCzujnikowCallback();
void oledSwitchCallback();
void oledRefreshCallback();
void monitorPolaczenCallback();
void syncNTPCallback();

// Manual OLED control (used by external code to force a screen)
void oledShowSensors();
void oledShowStatus();
void oledShowMeshStatus();

#endif