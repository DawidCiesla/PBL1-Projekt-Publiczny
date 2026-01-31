/*
 * pamiec_SD.cpp
 * 
 * Moduł obsługi karty SD przez interfejs SPI.
 * Odpowiada za:
 * - Inicjalizację karty SD 
 * - Operacje na plikach (tworzenie, odczyt, zapis, usuwanie)
 * - System kolejkowania danych offline:
 *   * backup_data.txt - archiwum pomyślnie wysłanych danych
 *   * transfer_waitlist.txt - kolejka danych do ponownego wysłania
 * - Automatyczne ponowne wysyłanie danych po odzyskaniu połączenia MQTT
 * 
 * Konfiguracja sprzętowa SPI (VSPI):
 * - SCK (Serial Clock):  GPIO 18
 * - MISO (Master In):    GPIO 19  
 * - MOSI (Master Out):   GPIO 23
 * - CS (Chip Select):    GPIO 5
 * - Prędkość: 4 MHz - Przy próbach wyższych prędkości występowały błędy komunikacji
 */

#include "pamiec_SD.h"
#include "mqtt.h"

// Instancja SPI dla karty SD (VSPI)
SPIClass spi = SPIClass(VSPI);

/**
 * Wypisuje zawartość katalogu na karcie SD.
 * Funkcja pomocnicza do debugowania - wyświetla listę plików i podkatalogów.
 * 
 * parametr: fs Referencja do systemu plików SD
 * parametr: dirname Ścieżka do katalogu do wylistowania
 * parametr: levels Głębokość rekurencji (ilość poziomów podkatalogów do wyświetlenia)
 * 
 * Wypisuje:
 * - DIR : nazwa_katalogu (dla katalogów)
 * - FILE: nazwa_pliku  SIZE: rozmiar_w_bajtach (dla plików)
 */
void listDir(fs::FS &fs, const char * dirname, uint8_t levels){
  Serial.printf("Listing directory: %s\n", dirname);

  // Otwórz katalog
  File root = fs.open(dirname);
  if(!root){
    Serial.println("Failed to open directory");
    return;
  }
  if(!root.isDirectory()){
    Serial.println("Not a directory");
    return;
  }

  // Iteruj przez wszystkie pliki w katalogu
  File file = root.openNextFile();
  while(file){
    if(file.isDirectory()){
      // Jeśli to katalog
      Serial.print("  DIR : ");
      Serial.println(file.name());
      if(levels){
        // Rekurencyjnie wylistuj podkatalogi
        listDir(fs, file.name(), levels -1);
      }
    } else {
      // Jeśli to plik
      Serial.print("  FILE: ");
      Serial.print(file.name());
      Serial.print("  SIZE: ");
      Serial.println(file.size());
    }
    file = root.openNextFile();
  }
}

/**
 * Usuwa katalog z karty SD.
 * 
 * parametr: fs Referencja do systemu plików SD
 * parametr: path Ścieżka katalogu do usunięcia
 */
void removeDir(fs::FS &fs, const char * path){
  Serial.printf("Removing Dir: %s\n", path);
  if(fs.rmdir(path)){
    Serial.println("Dir removed");
  } else {
    Serial.println("rmdir failed");
  }
}

/**
 * Odczytuje i wyświetla zawartość pliku z karty SD.
 * Funkcja pomocnicza do debugowania - wypisuje całą zawartość pliku na Serial.
 * 
 * parametr: fs Referencja do systemu plików SD
 * parametr: path Ścieżka do pliku do odczytania
 */
void readFile(fs::FS &fs, const char * path){
  Serial.printf("Reading file: %s\n", path);

  // Otwórz plik w trybie odczytu
  File file = fs.open(path);
  if(!file){
    Serial.println("Failed to open file for reading");
    return;
  }

  Serial.print("Read from file: ");
  // Odczytaj i wyświetl całą zawartość pliku
  while(file.available()){
    Serial.write(file.read());
  }
  file.close();
}

/**
 * Zapisuje tekst do pliku na karcie SD.
 * 
 * parametr: fs Referencja do systemu plików SD
 * parametr: path Ścieżka do pliku do utworzenia/nadpisania
 * parametr: message Tekst do zapisania w pliku
 */
void writeFile(fs::FS &fs, const char * path, const char * message){
  Serial.printf("Writing file: %s\n", path);

  // Otwórz plik w trybie zapisu (FILE_WRITE nadpisuje istniejący plik)
  File file = fs.open(path, FILE_WRITE);
  if(!file){
    Serial.println("Failed to open file for writing");
    return;
  }
  
  // Zapisz tekst do pliku
  if(file.print(message)){
    Serial.println("File written");
  } else {
    Serial.println("Write failed");
  }
  file.close();
}

/**
 * Dopisuje tekst na końcu pliku (append).
 * Jeśli plik nie istnieje, zostanie utworzony.
 * 
 * parametr: fs Referencja do systemu plików SD
 * parametr: path Ścieżka do pliku
 * parametr: message Tekst do dopisania na końcu pliku
 * 
 * Używana głównie do zapisywania danych pomiarowych do:
 * - /backup_data.txt (archiwum)
 * - /transfer_waitlist.txt (kolejka)
 */
void appendFile(fs::FS &fs, const char * path, const char * message){
  Serial.printf("Dopisuję do pliku: %s\n", path);

  // Otwórz plik w trybie dopisywania (FILE_APPEND)
  File file = fs.open(path, FILE_APPEND);
  if(!file){
    Serial.println("Nie udało się otworzyć pliku do dopisania");
    return;
  }
  
  // Dopisz tekst na końcu pliku
  if(file.print(message)){
    Serial.println("Wiadomosc dopisana");
  } else {
    Serial.println("Wiadomosc nie dopisana, blad zapisu");
  }
  file.close();
}

/**
 * Zmienia nazwę pliku lub przenosi plik.
 * 
 * parametr: fs Referencja do systemu plików SD
 * parametr: path1 Aktualna ścieżka pliku
 * parametr: path2 Nowa ścieżka pliku
 */
void renameFile(fs::FS &fs, const char * path1, const char * path2){
  Serial.printf("Renaming file %s to %s\n", path1, path2);
  if (fs.rename(path1, path2)) {
    Serial.println("File renamed");
  } else {
    Serial.println("Rename failed");
  }
}

/**
 * Usuwa plik z karty SD.
 * 
 * parametr: fs Referencja do systemu plików SD
 * parametr: path Ścieżka do pliku do usunięcia
 * 
 * UWAGA: Przed usunięciem pliku należy zamknąć wszystkie handle do tego pliku!
 * W przeciwnym razie może wystąpić błąd "bad arguments".
 */
void deleteFile(fs::FS &fs, const char * path){
  Serial.printf("Deleting file: %s\n", path);
  if(fs.remove(path)){
    Serial.println("File deleted");
  } else {
    Serial.println("Delete failed");
  }
}


/**
 * Inicjalizuje kartę SD i przygotowuje system plików.
 * 
 * Proces inicjalizacji:
 * 1. Konfiguruje piny SPI 
 * 2. Montuje kartę SD z prędkością 4 MHz
 * 3. Sprawdza typ karty (MMC, SD, SDHC)
 * 4. Wyświetla rozmiar karty
 * 5. Czyści niepotrzebne pliki (zachowuje tylko backup_data.txt i transfer_waitlist.txt)
 * 6. Tworzy pliki systemowe jeśli nie istnieją
 * 
 */
void InicjalizacjaSD(){
  
  // Konfiguracja pinu CS (Chip Select) z pull-up
  pinMode(CS, INPUT_PULLUP);
  
  // Inicjalizacja magistrali SPI z właściwymi pinami
  spi.begin(SCK, MISO, MOSI, CS);

  // Montowanie karty SD z prędkością 4 MHz
  if (!SD.begin(CS,spi,4000000)) {
    Serial.println("Card Mount Failed");
    return;  // Przerwij jeśli montowanie nie powiodło się
  }
  
  // Odczytaj typ karty SD
  uint8_t cardType = SD.cardType();

  if(cardType == CARD_NONE){
    Serial.println("No SD card attached");
    return;
  }

  // Wyświetl typ karty
  Serial.print("SD Card Type: ");
  if(cardType == CARD_MMC){
    Serial.println("MMC");  // MultiMediaCard
  } else if(cardType == CARD_SD){
    Serial.println("SDSC"); // SD Standard Capacity
  } else if(cardType == CARD_SDHC){
    Serial.println("SDHC"); // SD High Capacity
  } else {
    Serial.println("UNKNOWN");
  }

  // Oblicz i wyświetl rozmiar karty w MB
  uint64_t cardSize = SD.cardSize() / (1024 * 1024);
  Serial.printf("SD Card Size: %lluMB\n", cardSize);

  // ===== CZYŚCCENIE KARTY SD =====
  // Usuń wszystkie pliki oprócz backup_data.txt i transfer_waitlist.txt
  Serial.println("Czyszczenie karty SD z niepotrzebnych plików...");
  
  // Najpierw zbierz nazwy plików do usunięcia (maksymalnie 50)
  String plikiDoUsuniecia[50];
  int iloscPlikow = 0;
  
  File root = SD.open("/");
  if (root) {
    File file = root.openNextFile();
    
    // Iteruj przez wszystkie pliki w katalogu głównym
    while (file && iloscPlikow < 50) {
      if (!file.isDirectory()) {
        String fileName = String(file.name());
        
        // Dodaj "/" na początku ścieżki jeśli nie ma
        if (!fileName.startsWith("/")) {
          fileName = "/" + fileName;
        }
        
        // Sprawdź czy plik NIE JEST jednym z naszych plików systemowych
        if (fileName != "/backup_data.txt" && fileName != "/transfer_waitlist.txt") {
          // Dodaj do listy plików do usunięcia
          plikiDoUsuniecia[iloscPlikow++] = fileName;
        }
      }
      file.close();
      file = root.openNextFile();
    }
    root.close();
    
    // Teraz usuń zebrane pliki (wszystkie handle są już zamknięte)
    for (int i = 0; i < iloscPlikow; i++) {
      deleteFile(SD, plikiDoUsuniecia[i].c_str());
    }
    
    Serial.println("Czyszczenie karty SD zakończone");
  } else {
    Serial.println("Nie można otworzyć katalogu głównego SD");
  }

  // ===== TWORZENIE PLIKÓW SYSTEMOWYCH =====
  // Utwórz backup_data.txt jeśli nie istnieje
  if (!SD.exists("/backup_data.txt")) {
    Serial.println("Tworzenie pliku backup_data.txt");
    File backupFile = SD.open("/backup_data.txt", FILE_WRITE);
    if (backupFile) {
      backupFile.close();
      Serial.println("Utworzono backup_data.txt");
    } else {
      Serial.println("Nie udało się utworzyć backup_data.txt");
    }
  } else {
    Serial.println("Plik backup_data.txt już istnieje");
  }

  // Utwórz transfer_waitlist.txt jeśli nie istnieje
  if (!SD.exists("/transfer_waitlist.txt")) {
    Serial.println("Tworzenie pliku transfer_waitlist.txt");
    File waitlistFile = SD.open("/transfer_waitlist.txt", FILE_WRITE);
    if (waitlistFile) {
      waitlistFile.close();
      Serial.println("Utworzono transfer_waitlist.txt");
    } else {
      Serial.println("Nie udało się utworzyć transfer_waitlist.txt");
    }
  } else {
    Serial.println("Plik transfer_waitlist.txt już istnieje");
  }

}

/**
 * Zapisuje pakiet danych do odpowiedniego pliku na karcie SD.
 * 
 * parametr: data Dane w formacie CSV (np. "2;22.32;61.65;1220;15;51;15:55:06 Wed, Jan 07 2026")
 * parametr: mqttSuccess Czy wysyłanie przez MQTT się udało
 * 
 * Decyzja o pliku docelowym:
 * - mqttSuccess = true  → zapisz do /backup_data.txt (archiwum)
 * - mqttSuccess = false → zapisz do /transfer_waitlist.txt (kolejka do ponownego wysłania)
 * 
 * Dane są zapisywane z nową linią na końcu (\n).
 */
void ZapiszDanePakiet(const char* data, bool mqttSuccess) {
  const char* filepath;
  
  // Wybierz plik docelowy w zależności od statusu MQTT
  if (mqttSuccess) {
    filepath = "/backup_data.txt";
    Serial.println("Zapisuję dane do backup_data.txt (MQTT wysłano)");
  } else {
    filepath = "/transfer_waitlist.txt";
    Serial.println("Zapisuję dane do transfer_waitlist.txt (MQTT nieudane)");
  }
  
  // Połącz dane z nową linią w jeden string
  String dataWithNewline = String(data) + "\n";
  
  // Dopisz dane na końcu pliku
  appendFile(SD, filepath, dataWithNewline.c_str());
}

/**
 * Ponownie wysyła dane z kolejki po odzyskaniu połączenia MQTT.
 * 
 * Proces:
 * 1. Sprawdza czy MQTT jest połączony - jeśli nie, kończy działanie
 * 2. Otwiera plik /transfer_waitlist.txt
 * 3. Czyta linia po linii
 * 4. Próbuje wysłać każdą linię przez MQTT
 * 5. Jeśli wysyłanie się uda, przenosi dane do /backup_data.txt
 * 6. Jeśli wszystkie dane zostały wysłane, czyści plik transfer_waitlist.txt
 * 
 * Wywoływana automatycznie:
 * - W setup() po nawiązaniu połączenia MQTT
 * - W loop() po wykryciu odnowienia połączenia MQTT (flaga mqttByloPolaczone)
 * 
 * Delay: 100ms między wysyłkami aby nie przeciążyć brokera MQTT
 */
void PonowWyslijZKolejki() {
  const char* waitlist_path = "/transfer_waitlist.txt";
  const char* backup_path = "/backup_data.txt";
  
  // Sprawdź czy MQTT jest połączony
  if (!asyncMqttClient.connected()) {
    Serial.println("MQTT niepodłączony - pomijam ponowne wysyłanie z kolejki");
    return;  // Nie ma sensu próbować bez MQTT
  }
  
  // Otwórz plik z kolejką
  File waitlistFile = SD.open(waitlist_path);
  if (!waitlistFile) {
    Serial.println("Brak pliku transfer_waitlist.txt lub jest pusty");
    return;
  }
  
  Serial.println("Rozpoczynam ponowne wysyłanie danych z kolejki...");
  int wyslanoDanych = 0;      // Licznik pomyślnie wysłanych pakietów
  int nieudanychDanych = 0;   // Licznik nieudanych wysyłek
  
  // Czytaj plik linia po linii
  while (waitlistFile.available()) {
    String linia = waitlistFile.readStringUntil('\n');
    linia.trim(); // Usuń białe znaki (spacje, \r, \n)
    
    if (linia.length() == 0) continue; // Pomiń puste linie
    
    // Spróbuj wysłać przez MQTT
    uint16_t packetId = asyncMqttClient.publish(topic, 0, false, linia.c_str());
    
    if (packetId != 0 && asyncMqttClient.connected()) {
      // Udane wysłanie - dopisz do backup_data.txt
      appendFile(SD, backup_path, linia.c_str());
      appendFile(SD, backup_path, "\n");
      wyslanoDanych++;
      Serial.printf("Ponownie wysłano: %s\n", linia.c_str());
    } else {
      // Nieudane - zostaw w kolejce (nie robimy nic)
      nieudanychDanych++;
      Serial.printf("Nie udało się ponownie wysłać: %s\n", linia.c_str());
    }
    
    delay(100); // Krótka przerwa między wysyłkami (nie przeciążaj brokera)
  }
  
  waitlistFile.close();
  
  // Jeśli wysłano wszystkie dane, wyczyść plik transfer_waitlist
  if (wyslanoDanych > 0 && nieudanychDanych == 0) {
    Serial.println("Wszystkie dane wysłano - czyszczenie transfer_waitlist.txt");
    deleteFile(SD, waitlist_path);
  } else if (wyslanoDanych > 0) {
    // Jeśli wysłano część, trzeba by było przepisać plik bez wysłanych danych
    // To jest bardziej skomplikowane - na razie zostawiamy wszystko w pliku
    Serial.printf("Wysłano %d pakietów, %d pozostało w kolejce\n", wyslanoDanych, nieudanychDanych);
  }
  
  Serial.printf("Zakończono ponowne wysyłanie: %d udanych, %d nieudanych\n", wyslanoDanych, nieudanychDanych);
}

/**
 * Czyści całą kartę SD - usuwa WSZYSTKIE pliki.
 * Używana podczas komendy "reset" z Serial Monitor.
 * 
 * Proces:
 * 1. Otwiera katalog główny karty SD
 * 2. Zbiera nazwy wszystkich plików (maksymalnie 50)
 * 3. Zamyka wszystkie handle plików
 * 4. Usuwa wszystkie zebrane pliki
 * 
 * UWAGA: Funkcja usuwa RÓWNIEź pliki systemowe (backup_data.txt, transfer_waitlist.txt)!
 * Po wyczyszczeniu należy wywołać InicjalizacjaSD() aby odtworzyć strukturę plików.
 */
void WyczyscKarteSD() {
  Serial.println("Czyszczenie całej karty SD...");
  
  // Otwórz katalog główny
  File root = SD.open("/");
  if (!root) {
    Serial.println("Nie można otworzyć katalogu głównego SD");
    return;
  }
  
  // Najpierw zbierz nazwy wszystkich plików do usunięcia
  String plikiDoUsuniecia[50]; // Maksymalnie 50 plików
  int iloscPlikow = 0;
  
  File file = root.openNextFile();
  while (file && iloscPlikow < 50) {
    if (!file.isDirectory()) {
      String fileName = String(file.name());
      
      // Upewnij się, że ścieżka zaczyna się od "/"
      if (!fileName.startsWith("/")) {
        fileName = "/" + fileName;
      }
      
      // Dodaj do listy plików do usunięcia
      plikiDoUsuniecia[iloscPlikow++] = fileName;
    }
    file.close();
    file = root.openNextFile();
  }
  root.close();
  
  // Teraz usuń wszystkie zebrane pliki (wszystkie handle są zamknięte)
  for (int i = 0; i < iloscPlikow; i++) {
    deleteFile(SD, plikiDoUsuniecia[i].c_str());
  }
  
  Serial.println("Karta SD wyczyszczona");
}

