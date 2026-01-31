#include <czujniki.h>
#include "mesh_local.h" 

HX711 scale1;
HX711 scale2;

// RFID MFRC522v2 - nowa biblioteka
MFRC522DriverPinSimple ss_pin(SS_PIN);
MFRC522DriverSPI driver{ss_pin};
MFRC522 mfrc522{driver};

// Inicjalizacja czujnika SGP30
void InicjalizacjaCzujnikow() {
    
    // Inicjalizacja czujników wagi HX711
    Serial.println("Inicjalizacja HX711...");
    yield();
    scale1.begin(LOADCELL_DOUT_PIN_1, LOADCELL_SCK_PIN_1);
    yield();
    // TYMCZASOWO WYŁĄCZONE - scale2.begin(LOADCELL_DOUT_PIN_2, LOADCELL_SCK_PIN_2);
    yield();
    scale1.set_scale(430.0);   // Współczynnik kalibracji dla pierwszej wagi
    // TYMCZASOWO WYŁĄCZONE - scale2.set_scale(1750.0);  // Współczynnik kalibracji dla drugiej wagi
    yield();
    delay(100);
    Serial.println("Tarowanie wagi 1...");
    scale1.tare(5);            // Zerowanie wagi 1 (5 próbek zamiast 10)
    yield();
    delay(500);                // Daj watchdogowi czas na reset
    // TYMCZASOWO WYŁĄCZONE - Serial.println("Tarowanie wagi 2...");
    // TYMCZASOWO WYŁĄCZONE - scale2.tare(5);            // Zerowanie wagi 2 (5 próbek zamiast 10)
    yield();
    delay(100);
    Serial.println("Czujniki wagi HX711 zainicjalizowane pomyślnie");
    
    // Inicjalizacja czytnika RFID MFRC522v2
    mfrc522.PCD_Init();
    MFRC522Debug::PCD_DumpVersionToSerial(mfrc522, Serial);
    Serial.println("Czytnik RFID MFRC522v2 zainicjalizowany pomyślnie");
}

// Funkcja mierząca wagę z dwóch czujników HX711
float zmierz_wage() {
    yield(); // Pozwól watchdogowi na reset
    double waga1 = scale1.get_units(5);  // Średnia z 5 pomiarów (szybsze)
    yield(); // Pozwól watchdogowi na reset
    // TYMCZASOWO WYŁĄCZONE - double waga2 = scale2.get_units(5);  // Średnia z 5 pomiarów (szybsze)
    yield(); // Pozwól watchdogowi na reset
    return waga1;  // TYMCZASOWO tylko waga1 (było: waga1 + waga2)
}

// Funkcja tarująca wagę (zerowanie)
void taruj_wage() {
    Serial.println("Tarowanie wagi...");
    yield();
    scale1.tare(5);
    yield();
    delay(500);
    // TYMCZASOWO WYŁĄCZONE - scale2.tare(5);
    yield();
    delay(100);
    Serial.println("Waga wyzerowana");
}

// --- FUNKCJE RFID ---

// Sprawdza czy wykryto nową kartę RFID
bool sprawdz_karte_rfid() {
    return mfrc522.PICC_IsNewCardPresent() && mfrc522.PICC_ReadCardSerial();
}

// Pobiera UID karty RFID jako String w formacie HEX
String pobierz_uid_rfid() {
    String uidString = "";
    for (byte i = 0; i < mfrc522.uid.size; i++) {
        if (mfrc522.uid.uidByte[i] < 0x10) uidString += "0";
        uidString += String(mfrc522.uid.uidByte[i], HEX);
    }
    uidString.toUpperCase();
    return uidString;
}

// Kończy komunikację z kartą RFID
void zakoncz_komunikacje_rfid() {
    mfrc522.PICC_HaltA();
    mfrc522.PCD_StopCrypto1();
}


void pakietToCSV(const Pakiet_Danych* pakiet, char* buffer, size_t bufferSize) {
    snprintf(buffer, bufferSize, "%d;%s;%.2f;%s",
        pakiet->ID_urzadzenia,      // ID urządzenia (int)
        pakiet->uid_rfid.c_str(),   // UID karty RFID (String)
        pakiet->waga,               // Waga (float)
        pakiet->data_i_czas.c_str()); // Data i czas (String)
}
Pakiet_Danych odczytCzujniki() {
    Pakiet_Danych odczyt;
    odczyt.ID_urzadzenia   = mesh.getNodeId();
    odczyt.uid_rfid        = pobierz_uid_rfid();
    odczyt.waga            = zmierz_wage();
    odczyt.data_i_czas     = rtc.getTimeDate();
    return odczyt;
}

