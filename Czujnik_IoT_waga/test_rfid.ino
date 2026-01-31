/*
 * Test czytnika RFID MFRC522 dla ESP8266
 * 
 * Podłączenie według schematu NodeMCU:
 * RST  -> D3 (GPIO0)
 * SS   -> D2 (GPIO4)
 * MOSI -> D7 (GPIO13) - standardowy pin SPI
 * MISO -> D6 (GPIO12) - standardowy pin SPI
 * SCK  -> D5 (GPIO14) - standardowy pin SPI
 * VCC  -> 3.3V
 * GND  -> GND
 */

#include <SPI.h>
#include <MFRC522.h>

#define RST_PIN 0    // D3 (GPIO0)
#define SS_PIN 4     // D2 (GPIO4)

MFRC522 rfid(SS_PIN, RST_PIN);

void setup() {
  Serial.begin(115200);
  delay(1000);
  
  Serial.println("\n\n=== TEST CZYTNIKA RFID MFRC522 ===");
  
  // Inicjalizacja SPI
  SPI.begin();
  Serial.println("SPI zainicjalizowane");
  
  // Inicjalizacja RFID
  rfid.PCD_Init();
  Serial.println("RFID MFRC522 zainicjalizowany");
  
  // Wyświetl wersję oprogramowania czytnika
  rfid.PCD_DumpVersionToSerial();
  
  Serial.println("\n=== GOTOWY DO SKANOWANIA ===");
  Serial.println("Przyłóż kartę RFID do czytnika...\n");
}

void loop() {
  // Sprawdź czy wykryto nową kartę
  if (!rfid.PICC_IsNewCardPresent()) {
    delay(50);
    return;
  }
  
  // Sprawdź czy udało się odczytać kartę
  if (!rfid.PICC_ReadCardSerial()) {
    delay(50);
    return;
  }
  
  Serial.println("\n==========================");
  Serial.println(">>> WYKRYTO KARTĘ RFID!");
  Serial.println("==========================");
  
  // Wyświetl UID w formacie HEX
  Serial.print("UID (HEX): ");
  String uidHex = "";
  for (byte i = 0; i < rfid.uid.size; i++) {
    if (rfid.uid.uidByte[i] < 0x10) {
      Serial.print("0");
      uidHex += "0";
    }
    Serial.print(rfid.uid.uidByte[i], HEX);
    uidHex += String(rfid.uid.uidByte[i], HEX);
    if (i < rfid.uid.size - 1) {
      Serial.print(" ");
      uidHex += " ";
    }
  }
  Serial.println();
  uidHex.toUpperCase();
  Serial.println("UID (String): " + uidHex);
  
  // Wyświetl typ karty
  Serial.print("Typ karty: ");
  MFRC522::PICC_Type piccType = rfid.PICC_GetType(rfid.uid.sak);
  Serial.println(rfid.PICC_GetTypeName(piccType));
  
  // Wyświetl rozmiar UID
  Serial.print("Rozmiar UID: ");
  Serial.print(rfid.uid.size);
  Serial.println(" bajtów");
  
  Serial.println("==========================\n");
  
  // Zakończ komunikację z kartą
  rfid.PICC_HaltA();
  rfid.PCD_StopCrypto1();
  
  // Opóźnienie aby uniknąć wielokrotnego odczytu
  delay(2000);
  
  Serial.println("Gotowy na następną kartę...\n");
}
