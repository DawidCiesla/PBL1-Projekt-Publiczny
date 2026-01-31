#include "painlessMesh.h"

#define MESH_PREFIX     "" // Musi być takie samo wszędzie
#define MESH_PASSWORD   "pbl_haslo123" // Musi być takie samo (min. 8 znaków)
#define MESH_PORT       5555

painlessMesh  mesh;
Scheduler     userScheduler;

// Funkcja wywoływana, gdy Root dostanie wiadomość
void receivedCallback( uint32_t from, String &msg ) {
  Serial.printf("ROOT: Odebrano od Node [%u]: %s\n", from, msg.c_str());
}

void mesh_setup() {
  mesh.init( MESH_PREFIX, MESH_PASSWORD, &userScheduler, MESH_PORT );
  
  // Ustawienie tego urządzenia jako ROOTA
  mesh.setContainsRoot(true); 

  // Rejestracja funkcji odbioru
  mesh.onReceive(&receivedCallback);

  Serial.println(">>> ROZPOCZĘTO PRACĘ JAKO ROOT <<<");
  Serial.printf("Mój NodeID: %u\n", mesh.getNodeId());
}

void setup() {
  Serial.begin(115200);
  mesh_setup();
  // Inicjalizacja mesh
  
}

void loop() {
  mesh.update(); // Obowiązkowe zamiast delay()
}