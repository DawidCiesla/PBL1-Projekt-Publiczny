#include "mesh_local.h"
#include "painlessMesh.h"
#include "czujniki.h"
#include "main.h"
#include "mqtt.h"
#include "kurnikwifi.h"
#include "pamiec_SD.h"
#include "oled.h"

// Dynamiczna nazwa mesh z adresem MAC
String MESH_PREFIX = "";

painlessMesh mesh;
Scheduler userScheduler;

// === DEKLARACJE FORWARD DLA CALLBACKÓW ===
void raportujSiec();
void broadcastEpoch();
void wyslijDaneCzujnikowCallback();
void oledSwitchCallback();
void monitorPolaczenCallback();
void syncNTPCallback();

// === DEFINICJE TASKÓW ===
// Task raportujący stan sieci mesh co 10 sekund
Task taskRaport(TASK_SECOND * 10, TASK_FOREVER, &raportujSiec);
// Task synchronizacji czasu w sieci mesh co 20 sekund
Task syncMeshDataTime(TASK_SECOND * 20, TASK_FOREVER, &broadcastEpoch);
// Task wysyłania danych z czujników co 5 sekund
Task taskWyslijDaneCzujnikow(TASK_SECOND * 5, TASK_FOREVER, &wyslijDaneCzujnikowCallback);
// Task przełączania ekranu OLED co 5 sekund
Task taskOLEDSwitch(TASK_SECOND * 5, TASK_FOREVER, &oledSwitchCallback);
// Task odświeżania ekranu OLED co 10 sekund (tylko gdy pokazuje czujniki)
Task taskOLEDRefresh(TASK_SECOND * 10, TASK_FOREVER, &oledRefreshCallback);
// Task monitorowania połączeń WiFi/MQTT co 10 sekund
Task taskMonitorPolaczen(TASK_SECOND * 10, TASK_FOREVER, &monitorPolaczenCallback);
// Task synchronizacji NTP co 1 godzinę (3600 sekund)
Task taskSyncNTP(TASK_SECOND * 3600, TASK_FOREVER, &syncNTPCallback);

// === ZMIENNE STANU DLA TASKÓW ===
static bool _showSensors = true;
// 0 = sensors, 1 = connection status, 2 = mesh status
static int _currentScreen = 0;
static float _dhtTemp = 0, _dhtHum = 0, _ntcTemp = 0;
static int _ldr = 0, _eCO2 = 0, _tvoc = 0;
static bool mqttByloPolaczone = false;


void receivedCallback( uint32_t from, String &msg ) {
	Serial.printf("[Mesh] Odebrano wiadomość od węzła %u: %s\n", from, msg.c_str());
	
	String prefix = msg.substring(0, 4);
    if (prefix == "DANE") {
		// Usuń prefiks "DANE;" (5 znaków) z pakietu
		String dane_str = msg.substring(5);  // Było: substring(4), teraz: substring(5)
		
		Serial.printf("[Mesh] Pakiet danych po usunięciu prefiksu: %s\n", dane_str.c_str());
		
		// Utwórz pakiet i wypełnij danymi z CSV
		Pakiet_Danych pakiet;
		// Format CSV: ID;temp;hum;co2;nh3;sun;timestamp
		int parseCount = sscanf(dane_str.c_str(), "%d;%f;%f;%d;%d;%d",
			&pakiet.ID_urzadzenia,
			&pakiet.temperatura,
			&pakiet.wilgotnosc,
			&pakiet.poziom_co2,
			&pakiet.poziom_amoniaku,
			&pakiet.naslonecznienie
		);
		
		// Wyodrębnij timestamp (po ostatnim średniku)
		int lastSemicolon = dane_str.lastIndexOf(';');
		if (lastSemicolon != -1) {
			pakiet.data_i_czas = dane_str.substring(lastSemicolon + 1);
		}
		
		Serial.printf("[Mesh] Sparsowano %d pól z pakietu\n", parseCount);
		
		// Wyślij pakiet przez MQTT i zapisz na SD
		if (parseCount >= 6) {
			Serial.println("[Mesh] Przekazuję pakiet do WyslijPakiet()");
			WyslijPakiet(&pakiet);
		} else {
			Serial.printf("[Mesh] BŁĄD: Nieprawidłowy format pakietu (sparsowano tylko %d/6 pól)\n", parseCount);
		}
	}
	else if (prefix == "KURA") {
		// Format: KURA;id_urządzenia;id_kury;waga;data
		// Przykład: KURA;692641124;F7474A39;-0.37;23:44:15 Wed, Jan 28 2026
		String kura_str = msg.substring(5);  // Usuń "KURA;"
		
		Serial.printf("[Mesh] Pakiet kury po usunięciu prefiksu: %s\n", kura_str.c_str());
		
		char id_kury[16];
		int id_urzadzenia;
		float waga;
		
		// Parsuj pierwsze 3 pola: id_urządzenia;id_kury;waga
		int parseCount = sscanf(kura_str.c_str(), "%d;%15[^;];%f",
			&id_urzadzenia,
			id_kury,
			&waga
		);
		
		// Wyodrębnij timestamp (po 3 średnikach)
		String timestamp = "";
		int count = 0;
		for (int i = 0; i < kura_str.length(); i++) {
			if (kura_str[i] == ';') {
				count++;
				if (count == 3) {
					timestamp = kura_str.substring(i + 1);
					break;
				}
			}
		}
		
		Serial.printf("[Mesh] Sparsowano %d pól z pakietu kury\n", parseCount);
		
		if (parseCount >= 3) {
			Serial.printf("[Mesh] ID urządzenia: %d, ID kury: %s, Waga: %.2f, Data: %s\n",
				id_urzadzenia, id_kury, waga, timestamp.c_str());
			WyslijPakietKura(id_urzadzenia, id_kury, waga, timestamp);
		} else {
			Serial.printf("[Mesh] BŁĄD: Nieprawidłowy format pakietu kury (sparsowano tylko %d/3 pól)\n", parseCount);
		}
	}
	else if (prefix == "TIME") {
		Serial.println("[Mesh] Otrzymano żądanie synchronizacji czasu");
		broadcastEpoch();
	}
	else {
		Serial.printf("[Mesh] UWAGA: Nieznany typ wiadomości (prefix: %s)\n", prefix.c_str());
	}
}

void broadcastEpoch(){
	String reply = "SYNC";
	// Użyj getLocalEpoch() zamiast getEpoch() bo RTC przechowuje czas lokalny (UTC+1)
	// getEpoch() zwracałby timestamp o godzinę wcześniej
	unsigned long akt_czas = rtc.getLocalEpoch();
	reply += String(akt_czas);
	mesh.sendBroadcast(reply);
	Serial.printf("Wysłano broadcast czasu: %s (epoch: %lu)\n", reply.c_str(), akt_czas);
}

void newConnectionCallback(uint32_t nodeId) {
	Serial.printf("\n>>> NOWE POŁĄCZENIE! Węzeł ID: %u\n", nodeId);
	Serial.printf(">>> Łącznie węzłów w sieci: %d\n\n", mesh.getNodeList().size());
}

void changedConnectionCallback() {
	Serial.println("\n>>> ZMIANA TOPOLOGII SIECI");
	Serial.printf(">>> Liczba węzłów: %d\n\n", mesh.getNodeList().size());
}

void raportujSiec() {
	Serial.println("\n--- RAPORT MESH ROOT ---");
	Serial.printf("Mój ID: %u\n", mesh.getNodeId());
	Serial.printf("Liczba połączeń: %d\n", mesh.getNodeList().size());
	
	// Wylistuj wszystkie połączone węzły
	SimpleList<uint32_t> nodes = mesh.getNodeList();
	if (nodes.size() > 0) {
		Serial.println("Połączone węzły:");
		for (auto &&id : nodes) {
			Serial.printf("  - Węzeł ID: %u\n", id);
		}
	} else {
		Serial.println("  (brak połączonych węzłów)");
	}
	
	// Pobierz topologię mesh w formacie JSON
	String topologyJson = mesh.subConnectionJson();
	Serial.print("Topologia JSON: ");
	Serial.println(topologyJson); 
	
	// Wyślij topologię przez MQTT (jeśli połączone)
	if (asyncMqttClient.connected() && topicInitialized) {
		String meshTopic = String(topic) + "/mesh/topology";
		asyncMqttClient.publish(meshTopic.c_str(), 0, false, topologyJson.c_str());
		Serial.printf("Wysłano topologię mesh przez MQTT do: %s\n", meshTopic.c_str());
	} else {
		Serial.println("MQTT niedostępny - pomijam wysyłkę topologii");
	}
	
	Serial.println("------------------------\n");
}


void InicjalizacjaMesh() {
	// Sprawdź czy WiFi jest połączone - ROOT wymaga połączenia WiFi
	if (WiFi.status() != WL_CONNECTED) {
		Serial.println("BŁĄD: Nie można zainicjalizować mesh - WiFi nie jest połączone!");
		Serial.println("ROOT musi być połączony z routerem WiFi przed inicjalizacją mesh.");
		return;
	}
	
	// Pobierz adres MAC i wygeneruj unikalną nazwę mesh
	String macAddr = WiFi.macAddress();
	macAddr.replace(":", ""); // Usuń dwukropki z MAC
	MESH_PREFIX = "KurnikMesh_" + macAddr;
	Serial.printf("Nazwa sieci mesh: %s\n", MESH_PREFIX.c_str());
	
	// Pobierz kanał WiFi routera - ROOT używa TYLKO kanału routera
	uint8_t wifiChannel = WiFi.channel();
	Serial.printf("WiFi połączone na kanale %d - mesh użyje tego samego kanału\n", wifiChannel);
	
	// Włącz debug messages dla mesh (pomaga w diagnozowaniu połączeń)
	mesh.setDebugMsgTypes( ERROR | STARTUP | CONNECTION );
	
	// Inicjalizacja mesh na kanale WiFi routera
	mesh.init( MESH_PREFIX, MESH_PASSWORD, &userScheduler, MESH_PORT, WIFI_AP_STA, wifiChannel);

	// Podłącz mesh do zewnętrznej sieci WiFi (ROOT)
	mesh.stationManual(WiFi.SSID(), WiFi.psk());
	Serial.printf("Mesh ROOT połączony z WiFi: %s\n", WiFi.SSID().c_str());
	// Ustawienie tego urządzenia jako ROOTA
	mesh.setContainsRoot(true); 
	mesh.setRoot(true);
	
	// Rejestracja funkcji odbioru
	mesh.onReceive(&receivedCallback);
	
	// Rejestracja callbacków połączeń
	mesh.onNewConnection(&newConnectionCallback);
	mesh.onChangedConnections(&changedConnectionCallback);

	// === DODANIE TASKÓW DO SCHEDULERA ===
	// Taski związane z mesh
	userScheduler.addTask(taskRaport);
	userScheduler.addTask(syncMeshDataTime);
	
	// Taski związane z czujnikami i MQTT
	userScheduler.addTask(taskWyslijDaneCzujnikow);
	
	// Taski związane z OLED
	// OLED will be controlled manually via buttons; do not auto-schedule switching
	// Add periodic refresh for sensor screen
	userScheduler.addTask(taskOLEDRefresh);
	
	// Taski związane z monitoringiem połączeń
	userScheduler.addTask(taskMonitorPolaczen);
	
	// Task synchronizacji NTP
	userScheduler.addTask(taskSyncNTP);
	
	// === AKTYWACJA TASKÓW ===
	taskRaport.enable();
	syncMeshDataTime.enable();
	taskWyslijDaneCzujnikow.enable();
	taskMonitorPolaczen.enable();
	taskOLEDRefresh.enable();
	taskSyncNTP.enable();

	Serial.println(">>> ROZPOCZĘTO PRACĘ JAKO ROOT <<<");
	Serial.printf(">>> Mój NodeID: %u\n", mesh.getNodeId());
	Serial.printf(">>> Kanał mesh: %d\n", wifiChannel);
	Serial.printf(">>> SSID mesh AP: %s (WIDOCZNY)\n", MESH_PREFIX);
	Serial.printf(">>> Scheduler: wszystkie taski aktywowane\n");
	Serial.println(">>> ROOT czeka na połączenia od węzłów SLAVE...\n");
	
	// Sprawdź czy AP jest włączony
	delay(1000); // Poczekaj chwilę na inicjalizację AP
	wifi_mode_t mode = WiFi.getMode();
	Serial.printf(">>> Tryb WiFi: %s\n", 
		mode == WIFI_AP ? "AP" : 
		mode == WIFI_STA ? "STA" : 
		mode == WIFI_AP_STA ? "AP+STA" : "UNKNOWN");
	
	if (mode == WIFI_AP_STA || mode == WIFI_AP) {
		Serial.printf(">>> AP SSID dla mesh: %s (kanał %d)\n", WiFi.softAPSSID().c_str(), wifiChannel);
		Serial.printf(">>> AP IP: %s\n", WiFi.softAPIP().toString().c_str());
		Serial.println(">>> Mesh AP aktywny - węzły mogą się łączyć!");
	} else {
		Serial.println(">>> UWAGA: AP nie jest włączony! Węzły nie będą mogły się połączyć!");
	}
	Serial.println();
}

// === CALLBACK: WYSYŁANIE DANYCH Z CZUJNIKÓW ===
void wyslijDaneCzujnikowCallback() {
	Pakiet_Danych pakiet;
	TEST_pakiet(&pakiet);
	WyslijPakiet(&pakiet);
	Serial.println("[Scheduler] Wysłano pakiet danych z czujników");
}

// === CALLBACK: PRZEŁĄCZANIE EKRANU OLED ===
void oledSwitchCallback() {
	_showSensors = !_showSensors;
	
	bool wifiOk = (WiFi.status() == WL_CONNECTED);
	bool mqttOk = asyncMqttClient.connected();
	
	if (_showSensors) {
		// Odczytaj czujniki tylko przy przełączeniu na ekran czujników
		_dhtTemp = measureDHT22_Temp();
		_dhtHum = measureDHT22_Hum();
		_ntcTemp = measureNTC();
		_ldr = measureLDR();
		_eCO2 = odczytCO2(_dhtTemp, _dhtHum);
		_tvoc = odczytTVOC(_dhtTemp, _dhtHum);
		oled.showSensorReadings(_dhtTemp, _dhtHum, _ntcTemp, _ldr, _eCO2, _tvoc);
	} else {
		oled.showConnectionStatus(wifiOk, mqttOk);
	}
}

// Callback: odświeżenie aktywnego ekranu OLED (wywoływane okresowo)
void oledRefreshCallback() {
	// Odśwież aktywny ekran: 0=sensors,1=status,2=mesh
	if (_currentScreen == 0) {
		// sensors
		_showSensors = true;
		_dhtTemp = measureDHT22_Temp();
		_dhtHum = measureDHT22_Hum();
		_ntcTemp = measureNTC();
		_ldr = measureLDR();
		_eCO2 = odczytCO2(_dhtTemp, _dhtHum);
		_tvoc = odczytTVOC(_dhtTemp, _dhtHum);
		oled.showSensorReadings(_dhtTemp, _dhtHum, _ntcTemp, _ldr, _eCO2, _tvoc);
	} else if (_currentScreen == 1) {
		// connection status
		_showSensors = false;
		bool wifiOk = (WiFi.status() == WL_CONNECTED);
		bool mqttOk = asyncMqttClient.connected();
		oled.showConnectionStatus(wifiOk, mqttOk);
	} else if (_currentScreen == 2) {
		// mesh status
		_showSensors = false;
		SimpleList<uint32_t> nodes = mesh.getNodeList();
		int n = nodes.size();
		oled.showMeshStatus(n);
	}
}

// Manual functions to request specific OLED screens from other modules (e.g., main)
void oledShowSensors() {
	_showSensors = true;
	_currentScreen = 0;
	_dhtTemp = measureDHT22_Temp();
	_dhtHum = measureDHT22_Hum();
	_ntcTemp = measureNTC();
	_ldr = measureLDR();
	_eCO2 = odczytCO2(_dhtTemp, _dhtHum);
	_tvoc = odczytTVOC(_dhtTemp, _dhtHum);
	oled.showSensorReadings(_dhtTemp, _dhtHum, _ntcTemp, _ldr, _eCO2, _tvoc);
}

void oledShowStatus() {
	_showSensors = false;
	_currentScreen = 1;
	bool wifiOk = (WiFi.status() == WL_CONNECTED);
	bool mqttOk = asyncMqttClient.connected();
	oled.showConnectionStatus(wifiOk, mqttOk);
}

void oledShowMeshStatus() {
	// count connected nodes in mesh
	_showSensors = false;
	_currentScreen = 2;
	SimpleList<uint32_t> nodes = mesh.getNodeList();
	int n = nodes.size();
	oled.showMeshStatus(n);
}

// === CALLBACK: MONITORING POŁĄCZEŃ WIFI/MQTT ===
void monitorPolaczenCallback() {
	// Sprawdź połączenie WiFi
	if (WiFi.status() != WL_CONNECTED) {
		Serial.println("[Scheduler] Utracono WiFi - próba ponownego połączenia");
		PolaczZWiFi();
	}
	
	// Sprawdź połączenie MQTT
	if (!asyncMqttClient.connected()) {
		if (mqttByloPolaczone) {
			Serial.println("[Scheduler] Utracono MQTT - próba ponownego połączenia");
			mqttByloPolaczone = false;
		}
		PolaczDoMQTT();
	} else {
		// MQTT dopiero co się połączył - wyślij dane z kolejki
		if (!mqttByloPolaczone) {
			mqttByloPolaczone = true;
			Serial.println("[Scheduler] MQTT połączony - wysyłam dane z kolejki");
			PonowWyslijZKolejki();
		}
	}
}

// === CALLBACK: SYNCHRONIZACJA NTP ===
void syncNTPCallback() {
	if (WiFi.status() == WL_CONNECTED) {
		Serial.println("[Scheduler] Cykliczna synchronizacja czasu z NTP");
		UstawCzasZWiFi();
	} else {
		Serial.println("[Scheduler] Brak WiFi - pomijam synchronizację NTP");
	}
}




