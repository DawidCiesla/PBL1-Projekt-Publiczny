#include "painlessMesh.h"
#include "czujniki.h"
#include "mesh_local.h"
#include "pamiec.h"

void setup() {
  Serial.begin(115200);
  delay(2000);
  
  Serial.println("\n\n=== URUCHAMIANIE WĘZŁA SLAVE ===");
  
  InicjalizacjaCzujnikow();
  InicjalizacjaMesh();
  
  Serial.println("=== SETUP ZAKOŃCZONY ===\n");
}

void loop() {
  static unsigned long lastDebug = 0;
  if (Serial.available()) {
    String komenda = Serial.readStringUntil('\n');
    komenda.trim();
    
    if (komenda.equalsIgnoreCase("reset")) {
      Serial.println("\n>>> RESET - Czyszczenie pamięci EEPROM...");
      wyczyscEEPROM();
      Serial.println(">>> Restart urządzenia za 2 sekundy...");
      delay(2000);
      ESP.restart();
    } else if (komenda.equalsIgnoreCase("help") || komenda == "?") {
      Serial.println("\n=== DOSTĘPNE KOMENDY ===");
      Serial.println("reset  - Wyczyść EEPROM i zrestartuj");
      Serial.println("help   - Pokaż tę pomoc");
      Serial.println("========================\n");
    } else if (komenda.length() > 0) {
      Serial.printf(">>> Nieznana komenda: %s (wpisz 'help' aby zobaczyć dostępne komendy)\n", komenda.c_str());
    }
  }
  
  // 
  // Zawsze wywołuj mesh.update()
  mesh.update();
  
  // Co 10 sekund wyświetl status
  if (millis() - lastDebug > 10000) {
    lastDebug = millis();
    Serial.println("\n--- STATUS WĘZŁA ---");
    Serial.printf("Mój ID: %u\n", mesh.getNodeId());
    Serial.printf("Liczba węzłów: %d\n", mesh.getNodeList().size());
    Serial.printf("Czy ma czas: %s\n", czy_ma_czas ? "TAK" : "NIE");
    Serial.printf("Root ID: %u\n", root_id);
    Serial.println("-------------------\n");
  }
}
