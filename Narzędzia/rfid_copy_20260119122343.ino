#include <SPI.h>
#include <MFRC522.h>

// Piny (zgodne z Twoim schematem)
#define RST_PIN 9
#define SS_PIN 10

MFRC522 rfid(SS_PIN, RST_PIN);

// --- BAZA DANYCH KURNIKA ---

struct Kura {
  String uid;               // ID kury
  String imie;              // Imię kury
  bool czyNaDworze;         // Status: false = w kurniku, true = na dworze
  unsigned long czasWyjscia; // Moment (millis), w którym kura wyszła
  unsigned long lacznyCzasNaDworze; // Suma czasu na dworze (w sekundach)
};

// Tablica na 10 kur
Kura stado[10];
int liczbaKur = 0;

void setup() {
  Serial.begin(9600);
  SPI.begin();
  rfid.PCD_Init();
  
  Serial.println(F("--- SYSTEM MONITORINGU KURNIKA ---"));
  Serial.println(F("Zasada dzialania:"));
  Serial.println(F("1. Odbicie = WYJSCIE na dwor."));
  Serial.println(F("2. Kolejne odbicie = POWROT (podsumowanie czasu)."));
  Serial.println(F("---------------------------------------------"));
}

void loop() {
  // 1. Sprawdź czy jest kura przy czytniku
  if (!rfid.PICC_IsNewCardPresent() || !rfid.PICC_ReadCardSerial()) {
    return;
  }

  String aktualnyUID = pobierzUID();
  int indeksKury = znajdzKure(aktualnyUID);

  // --- SCENARIUSZ A: KURA ZNANA ---
  if (indeksKury != -1) {
    Kura &k = stado[indeksKury]; // Skrót do konkretnej kury
    
    if (k.czyNaDworze == false) {
      // --- WYJŚCIE Z KURNIKA ---
      k.czyNaDworze = true;
      k.czasWyjscia = millis(); // Zapamiętaj moment wyjścia
      
      Serial.print(F(">>> WYJSCIE: "));
      Serial.println(k.imie);
      Serial.println(F("Kura udala sie na spacer."));
      
    } else {
      // --- POWRÓT DO KURNIKA ---
      unsigned long czasTeraz = millis();
      // Oblicz ile sekund trwalo to konkretne wyjscie
      unsigned long czasTegoSpaceru = (czasTeraz - k.czasWyjscia) / 1000;
      
      k.lacznyCzasNaDworze += czasTegoSpaceru;
      k.czyNaDworze = false; // Zmien status na "w srodku"

      Serial.print(F("<<< POWROT: "));
      Serial.println(k.imie);
      Serial.print(F("Czas tego spaceru: "));
      wypiszCzas(czasTegoSpaceru);
      
      Serial.print(F("Laczny czas na dworze dzisiaj: "));
      wypiszCzas(k.lacznyCzasNaDworze);
    }

  } 
  // --- SCENARIUSZ B: NOWA KURA (REJESTRACJA) ---
  else {
    rejestrujNowaKure(aktualnyUID);
  }

  Serial.println(F("---------------------------------------------"));

  // Zatrzymaj kartę
  rfid.PICC_HaltA();
  rfid.PCD_StopCrypto1();
  
  // Ważne: Blokada na 2 sekundy, żeby kura przechodząca przez drzwiczki
  // nie "odbiła się" 5 razy pod rząd (wyjście-wejście-wyjście...).
  delay(2000); 
}

// --- FUNKCJE POMOCNICZE ---

void rejestrujNowaKure(String uid) {
    if (liczbaKur >= 10) {
      Serial.println(F("Kurnik pelny! (limit pamieci)"));
      return;
    }

    Serial.print(F("Wykryto nowa kure! UID: "));
    Serial.println(uid);
    Serial.println(F("Wpisz imie kury w konsoli i wcisnij ENTER..."));

    // Czekaj na wpisanie imienia
    while(Serial.available()) Serial.read(); 
    while (!Serial.available()) {}

    String imie = Serial.readStringUntil('\n');
    imie.trim();

    // Zapisz dane domyślne (zakładamy że nowa kura jest W SRODKU)
    stado[liczbaKur].uid = uid;
    stado[liczbaKur].imie = imie;
    stado[liczbaKur].czyNaDworze = false;
    stado[liczbaKur].lacznyCzasNaDworze = 0;
    
    Serial.print(F("Zarejestrowano kure: "));
    Serial.println(imie);
    liczbaKur++;
}

String pobierzUID() {
  String uidString = "";
  for (byte i = 0; i < rfid.uid.size; i++) {
    if (rfid.uid.uidByte[i] < 0x10) uidString += "0";
    uidString += String(rfid.uid.uidByte[i], HEX);
    uidString += " ";
  }
  uidString.toUpperCase();
  uidString.trim();
  return uidString;
}

int znajdzKure(String szukanyUID) {
  for (int i = 0; i < liczbaKur; i++) {
    if (stado[i].uid == szukanyUID) return i;
  }
  return -1;
}

// Funkcja ładnie formatująca czas (np. 65s -> 1m 5s)
void wypiszCzas(unsigned long sekundy) {
  unsigned long m = sekundy / 60;
  unsigned long s = sekundy % 60;
  unsigned long h = m / 60;
  m = m % 60;

  if (h > 0) { Serial.print(h); Serial.print("h "); }
  if (m > 0) { Serial.print(m); Serial.print("m "); }
  Serial.print(s); Serial.println("s");
}