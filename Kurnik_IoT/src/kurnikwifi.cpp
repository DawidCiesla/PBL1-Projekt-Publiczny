/*
 * kurnikwifi.cpp
 * 
 * Moduł zarządzania połączeniem WiFi i synchronizacji czasu z serwerów NTP.
 * Odpowiada za:
 * - Łączenie z siecią WiFi używając zapisanych danych z EEPROM lub BLE
 * - Synchronizację czasu RTC z serwerów NTP pool.ntp.org i time.nist.gov
 * - Obsługę utraty połączenia WiFi podczas synchronizacji czasu
 */

#include "main.h"
#include "kurnikwifi.h"

// Bufory na dane dostępowe WiFi (eksportowane z pamiec_lokalna.cpp)
char wifi_ssid[33] = "";      // SSID sieci WiFi (max 32 znaki + null terminator)
char wifi_password[65] = "";  // Hasło WiFi (max 64 znaki + null terminator)

// Flagi stanu WiFi
bool wifiConfigured = false;  // Czy konfiguracja WiFi została załadowana z EEPROM
bool wifiConnected = false;   // Czy WiFi jest aktualnie połączone

/**
 * Łączy się z siecią WiFi używając danych z buforów wifi_ssid i wifi_password.
 * Funkcja próbuje połączyć się przez ~30 sekund, po czym kończy próbę.
 * 
 * Timeout: 30 sekund (30 prób z 1 sekundowym opóźnieniem)
 * 
 * Po pomyślnym połączeniu wyświetla adres IP urządzenia.
 */
void PolaczZWiFi() {
	Serial.print("Łączenie z WiFi: ");
	Serial.println(wifi_ssid);

	// Rozpocznij połączenie z siecią WiFi
	WiFi.begin(wifi_ssid, wifi_password);

	// Czekaj maksymalnie 30 sekund na połączenie
	int attempts = 0;
	while (WiFi.status() != WL_CONNECTED && attempts < 30) {
		// Sprawdź komendy Serial podczas oczekiwania
		extern void checkAndHandleSerialCommands();
		checkAndHandleSerialCommands();
		delay(1000);  
		Serial.print(".");  
		attempts++;
	}

	// Sprawdź czy połączenie się udało
	if (WiFi.status() != WL_CONNECTED) {
		Serial.println("\nBłąd połączenia WiFi!");
		return;  // Przerwij próbę połączenia
	}

	// Połączenie udane - wyświetl informacje
	Serial.println("\nPołączono z WiFi");
	Serial.print("IP: ");
	Serial.println(WiFi.localIP());
}

/**
 * Synchronizuje czas wewnętrznego zegara RTC z serwerami NTP.
 * Funkcja próbuje w nieskończoność aż do pomyślnej synchronizacji.
 * 
 * Używane serwery NTP:
 * - pool.ntp.org (podstawowy)
 * - time.nist.gov (zapasowy)
 * 
 * Warunek zakończenia: now >= 8 * 3600 * 2 (timestamp > ~44 godziny od epoch)
 * Oznacza to że otrzymano prawidłowy czas z serwera NTP.
 * 
 * Obsługuje utratę WiFi podczas synchronizacji - czeka na ponowne połączenie
 * i kontynuuje próby synchronizacji.
 */
void UstawCzasZWiFi() {
	// Sprawdź czy WiFi jest połączone
	if (WiFi.status() != WL_CONNECTED) {
		Serial.println("Brak połączenia WiFi - nie można ustawić czasu z NTP");
		return;
	}

	// Skonfiguruj połączenie z serwerami NTP
	// Polska: UTC+1 (CET) + 1h DST (CEST w lecie) = UTC+2 latem
	configTime(3600, 3600, "pool.ntp.org", "time.nist.gov");

	Serial.println("Synchronizacja czasu z NTP...");
	time_t now = time(nullptr);
	
	// Próbuj w nieskończoność dopóki nie otrzymamy prawidłowego czasu
	// now < 8*3600*2 oznacza że czas nie został jeszcze zsynchronizowany
	while (now < 8 * 3600 * 2) {
		// Sprawdź komendy Serial podczas synchronizacji
		extern void checkAndHandleSerialCommands();
		checkAndHandleSerialCommands();
		delay(2000);  
		Serial.print(".");  
		now = time(nullptr);  // Pobierz aktualny czas
		
		// Sprawdź czy WiFi nadal jest połączone podczas synchronizacji
		if (WiFi.status() != WL_CONNECTED) {
			Serial.println("\nUtracono połączenie WiFi podczas synchronizacji NTP");
			Serial.println("Czekam na ponowne połączenie...");
			
			// Czekaj aż WiFi ponownie się połączy
			while (WiFi.status() != WL_CONNECTED) {
				// Sprawdź komendy Serial podczas ponownego łączenia
				extern void checkAndHandleSerialCommands();
				checkAndHandleSerialCommands();
				delay(1000);
			}
			
			Serial.println("WiFi ponownie połączone, kontynuuję synchronizację NTP");
			// Zrestartuj konfigurację NTP po ponownym połączeniu WiFi
			configTime(3600, 3600, "pool.ntp.org", "time.nist.gov");
		}
	}
	Serial.println();

	// Konwertuj otrzymany timestamp na strukturę tm
	struct tm timeinfo;
	localtime_r(&now, &timeinfo);
	
	// Ustaw zegar RTC używając zsynchronizowanego czasu
	rtc.setTimeStruct(timeinfo);
	
	Serial.print("Czas ustawiony: ");
	Serial.println(rtc.getDateTime());
}


