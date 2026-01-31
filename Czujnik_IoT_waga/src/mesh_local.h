#ifndef MESH_LOCAL
#define MESH_LOCAL

#include <painlessMesh.h>
#include <ESP32Time.h>
#include "czujniki.h"

#define MESH_PASSWORD   "pbl_haslo123"
#define MESH_PORT       5555

extern painlessMesh mesh;
extern Scheduler userScheduler;
extern uint32_t root_id;
extern bool czy_ma_czas;
extern bool polaczony_z_mesh;
extern Pakiet_Danych pakiet[100];  // Tablica pakietów testowych

extern ESP32Time rtc;

void InicjalizacjaMesh();
void wyslij_pomiar_rfid(String uid, float waga);
#endif
