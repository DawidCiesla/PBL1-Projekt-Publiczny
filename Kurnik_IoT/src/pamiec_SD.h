/*
 * MODUŁ KARTY SD - pamiec_SD.h
 * 
 * Zarządza zapisem i odczytem danych na karcie SD.
 * Implementuje system kolejkowania danych w przypadku braku połączenia MQTT.
 */

#ifndef PAMIEC_SD_H
#define PAMIEC_SD_H

#include "main.h"
#include "FS.h"
#include "SD.h"
#include "SPI.h"

// === FUNKCJE POMOCNICZE DO OPERACJI NA PLIKACH I KATALOGACH ===

/* Wyświetla zawartość katalogu na karcie SD */
void listDir(fs::FS &fs, const char * dirname, uint8_t levels);

/* Usuwa katalog */
void removeDir(fs::FS &fs, const char * path);

/* Odczytuje i wyświetla zawartość pliku */
void readFile(fs::FS &fs, const char * path);

/* Tworzy nowy plik i zapisuje wiadomość */
void writeFile(fs::FS &fs, const char * path, const char * message);

/* Dopisuje wiadomość na końcu pliku */
void appendFile(fs::FS &fs, const char * path, const char * message);

/* Zmienia nazwę pliku */
void renameFile(fs::FS &fs, const char * path1, const char * path2);

/* Usuwa plik */
void deleteFile(fs::FS &fs, const char * path);


// === FUNKCJE GŁÓWNE MODUŁU ===

/*
 * Inicjalizuje kartę SD i przygotowuje pliki systemowe.
 * - Montuje kartę SD przez interfejs SPI
 * - Usuwa niepotrzebne pliki (zachowuje backup_data.txt i transfer_waitlist.txt)
 * - Tworzy pliki systemowe jeśli nie istnieją
 */
void InicjalizacjaSD();

/*
 * Zapisuje pakiet danych do odpowiedniego pliku na karcie SD.
 * - Jeśli MQTT zadziałało -> backup_data.txt (kopia zapasowa)
 * - Jeśli MQTT nie zadziałało -> transfer_waitlist.txt (kolejka do ponownej wysyłki)
 * 
 * parametr: data String z danymi do zapisania (format CSV)
 * parametr: mqttSuccess Status wysyłki MQTT (true = sukces, false = błąd)
 */
void ZapiszDanePakiet(const char* data, bool mqttSuccess);

/*
 * Ponownie wysyła wszystkie dane z kolejki przez MQTT.
 * - Odczytuje transfer_waitlist.txt
 * - Próbuje wysłać każdą linię przez MQTT
 * - Przenosi wysłane dane do backup_data.txt
 * - Czyści kolejkę jeśli wszystko wysłano
 * 
 * Wywoływana automatycznie po nawiązaniu połączenia MQTT.
 */
void PonowWyslijZKolejki();

/*
 * Czyści całą kartę SD ze wszystkich plików.
 * Używana podczas pełnego resetu systemu.
 */
void WyczyscKarteSD();

// === KONFIGURACJA SPRZĘTOWA ===

extern SPIClass spi;  // Obiekt SPI do komunikacji z kartą SD

// Piny interfejsu SPI dla modułu karty SD (VSPI)
#define SCK  18   // Pin zegara SPI (Serial Clock)
#define MISO 19   // Pin wejścia danych (Master In Slave Out)
#define MOSI 23   // Pin wyjścia danych (Master Out Slave In)
#define CS   5    // Pin wyboru urządzenia (Chip Select)

#endif
