/*
 * IMPLEMENTACJA MODUŁU BLUETOOTH
 * 
 * Ten moduł odpowiada za konfigurację WiFi przez Bluetooth Low Energy (BLE).
 * Umożliwia użytkownikowi wprowadzenie danych WiFi przez aplikację mobilną.
 */

#include "main.h"
#include "bluetooth.h"
#include "kurnikwifi.h"
#include "mqtt.h"
#include "pamiec_lokalna.h"

// === GLOBALNE OBIEKTY NimBLE ===
NimBLEServer* pServer = nullptr;
NimBLEService* wifiService = nullptr;
NimBLECharacteristic* ssidCharacteristic = nullptr;
NimBLECharacteristic* passCharacteristic = nullptr;
NimBLECharacteristic* applyCharacteristic = nullptr;
NimBLEAdvertising* pAdvertising = nullptr;

static bool bleClientConnected = false;
static bool pendingWifiConnection = false;  // Flaga oczekującego połączenia WiFi

// === UUID DLA SERWISU I CHARAKTERYSTYK BLE ===
// 128-bitowe identyfikatory unikalnego serwisu WiFi provisioning
static NimBLEUUID WIFI_SERVICE_UUID("00000001-0000-0000-0000-000000000001");
static NimBLEUUID SSID_CHAR_UUID("00000001-0000-0000-0000-000000000002");
static NimBLEUUID PASS_CHAR_UUID("00000001-0000-0000-0000-000000000003");
static NimBLEUUID APPLY_CHAR_UUID("00000001-0000-0000-0000-000000000004");

/*
 * Klasa obsługująca zdarzenia połączenia/rozłączenia serwera BLE
 */
class ServerCallbacks : public NimBLEServerCallbacks {
	void onConnect(NimBLEServer* /*server*/) override {
		bleClientConnected = true;
		Serial.println("Połączono z BLE");
	}
	void onDisconnect(NimBLEServer* /*server*/) override {
		bleClientConnected = false;
		Serial.println("Rozłączono z BLE");
	}
};

/*
 * Klasa obsługująca zatwierdzenie konfiguracji WiFi (przycisk APPLY w aplikacji)
 * Wywoływana gdy użytkownik zapisuje 1 do charakterystyki applyCharacteristic
 */
class ApplyCallback : public NimBLECharacteristicCallbacks {
	void onWrite(NimBLECharacteristic* pChar) override {
		// Odczytaj wartość charakterystyki APPLY
		std::string val = pChar->getValue().c_str();
		if (val.empty() || (uint8_t)val[0] != 1) return;  // Ignoruj jeśli nie jest to 1

		// Pobierz SSID i hasło z odpowiednich charakterystyk
		std::string ssid = ssidCharacteristic ? std::string(ssidCharacteristic->getValue().c_str()) : std::string();
		std::string pass = passCharacteristic ? std::string(passCharacteristic->getValue().c_str()) : std::string();

		// Skopiuj dane do globalnych buforów WiFi
		strncpy(wifi_ssid, ssid.c_str(), sizeof(wifi_ssid) - 1);
		wifi_ssid[sizeof(wifi_ssid) - 1] = '\0';
		strncpy(wifi_password, pass.c_str(), sizeof(wifi_password) - 1);
		wifi_password[sizeof(wifi_password) - 1] = '\0';

		Serial.print("Otrzymano SSID: ");
		Serial.println(wifi_ssid);

		// Zresetuj wartość APPLY do 0
		uint8_t zero = 0;
		pChar->setValue(&zero, 1);

		// Ustaw flagę - połączenie WiFi odbędzie się poza callbackiem
		pendingWifiConnection = true;
	}
};

/*
 * Inicjalizuje moduł Bluetooth i konfiguruje serwis WiFi provisioning
 */
void InicjalizacjaBluetooth() {

	// Inicjalizacja urządzenia BLE z nazwą "Kurnik IoT"
	NimBLEDevice::init("Kurnik IoT");

	// Utworzenie serwera BLE
	pServer = NimBLEDevice::createServer();
	pServer->setCallbacks(new ServerCallbacks());

	// Utworzenie serwisu WiFi provisioning
	wifiService = pServer->createService(WIFI_SERVICE_UUID);

	// Utworzenie charakterystyk (zmiennych BLE do komunikacji z aplikacją)
	
	// 1. SSID - do przesyłania nazwy sieci WiFi
	ssidCharacteristic = wifiService->createCharacteristic(
		SSID_CHAR_UUID,
		NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::WRITE
	);
	
	// 2. PASSWORD - do przesyłania hasła WiFi
	passCharacteristic = wifiService->createCharacteristic(
		PASS_CHAR_UUID,
		NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::WRITE
	);
	
	// 3. APPLY - przycisk zatwierdzenia konfiguracji (zapisanie 1 uruchamia callback)
	applyCharacteristic = wifiService->createCharacteristic(
		APPLY_CHAR_UUID,
		NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::WRITE
	);

	// Podpięcie callbacku do przycisku APPLY
	applyCharacteristic->setCallbacks(new ApplyCallback());

	// Uruchomienie serwisu BLE
	wifiService->start();

	// Konfiguracja reklamy BLE (aby urządzenie było widoczne)
	pAdvertising = NimBLEDevice::getAdvertising();
	pAdvertising->addServiceUUID(WIFI_SERVICE_UUID);

	// Ustawienie wartości początkowych wszystkich charakterystyk
	ssidCharacteristic->setValue("");
	passCharacteristic->setValue("");
	uint8_t zero = 0;
	applyCharacteristic->setValue(&zero, 1);
}

/*
 * Rozpoczyna nadawanie BLE i czeka na konfigurację WiFi
 * Funkcja blokująca - kończy się dopiero po udanej konfiguracji
 */
void NadawaniePrzezBLE() {
	Serial.println("Rozpoczęto nadawanie BLE");
	
	// Uruchom reklamę BLE (urządzenie staje się widoczne)
	if (pAdvertising) pAdvertising->start();

	// Pętla blokująca - czeka aż użytkownik skonfiguruje WiFi
	while (!wifiConfigured) {
		// Sprawdź komendy Serial ręcznie (serialEvent nie działa w setup)
		extern void checkAndHandleSerialCommands();
		checkAndHandleSerialCommands();
		
		// Sprawdź czy użytkownik wysłał dane WiFi przez BLE
		if (pendingWifiConnection) {
			pendingWifiConnection = false;
			
			Serial.println("Rozpoczynam łączenie z WiFi...");
			
			// Próba połączenia z WiFi (poza callbackiem BLE)
			PolaczZWiFi();
			
			if (WiFi.status() == WL_CONNECTED) {
				// SUKCES - połączono z WiFi
				wifiConfigured = true;
				wifiConnected = true;
				
				// Zapisz dane WiFi do EEPROM (trwałe przechowywanie)
				ZapiszDaneDoEEPROM();
				
				Serial.println("WiFi połączone - aplikacja sprawdzi status przez HTTP");
			} else {
				// BŁĄD - nie udało się połączyć z WiFi
				Serial.println("Nie udało się połączyć z WiFi");
			}
		}
		
		delay(200);
	}

	// Po konfiguracji - zatrzymaj reklamę BLE
	if (pAdvertising) pAdvertising->stop();
}

