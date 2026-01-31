#include "painlessMesh.h"

#define   MESH_PREFIX     "KurnikMesh"
#define   MESH_PASSWORD   "pbl_haslo123"
#define   MESH_PORT       5555

painlessMesh  mesh;
Scheduler     userScheduler;

// Zadanie do wysyłania wiadomości co 5 sekund
void sendMessage(); 
Task taskSendMessage(TASK_SECOND * 5, TASK_FOREVER, &sendMessage);

void sendMessage() {
  String msg = "Wiadomosc od Node: ";
  msg += "Elo zelo";
  mesh.sendBroadcast(msg); // Wysyła do wszystkich (w tym do Roota)
  Serial.println("NODE: Wysłano dane do sieci");
}

void setup() {
  Serial.begin(115200);
  mesh.init( MESH_PREFIX, MESH_PASSWORD, &userScheduler, MESH_PORT );

  // Dodanie zadania do harmonogramu
  userScheduler.addTask(taskSendMessage);
  taskSendMessage.enable();

  Serial.println(">>> ROZPOCZĘTO PRACĘ JAKO NODE <<<");
}

void loop() {
  mesh.update();
}
