#include <DHT.h> 
#include <Wire.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SH110X.h>
#include <Arduino.h>

#define I2C_SDA 8
#define I2C_SCL 9

#define PIN_DHT22 4 
#define PIN_NTC 5
#define PIN_LDR 6
#define PIN_MQ135 7
#define PIN_MQ3 15

Adafruit_SH1106G display = Adafruit_SH1106G(128, 64, &Wire, -1);
DHT dht22(PIN_DHT22, DHT22);

const float BETA = 3950;
const int MQ_MAX_ADC = 2060; 


float measureDHT22_Temp(){
  float t = dht22.readTemperature();
  if (isnan(t)) return 0.0; //potem można zrobić obłsugę błędów
  return t;
}

float measureDHT22_Hum(){
  float h = dht22.readHumidity();
  if (isnan(h)) return 0.0; 
  return h;
}

float measureNTC() {
  int raw = analogRead(PIN_NTC);
  raw = constrain(raw, 1, 4094); // sprowadza do tych wartośći raw
  return 1 / (log(1 / (4095. / raw - 1)) / BETA + 1.0 / 298.15) - 273.15; //mocne to
}

int measureLDR(){
  int raw = analogRead(PIN_LDR);
  raw = constrain(raw, 500, 3800);
  return map(raw, 3800, 500, 0, 100);
}

int measureMQ135(int pin) {
  //dzielnik napięć dla 2k,1k, potem mogę zroibć że się wprowadza opór
  const int maxEffectiveADC = (5.0 / 3.3) * (1.0 / 3.0) * 4095;
  int rawValue = analogRead(PIN_MQ135);
  return map(rawValue, 0, maxEffectiveADC, 0, 100);
}

int measureMQ3(int pin) {
  //dzielnik napięć dla 2k,1k, potem mogę zroibć że się wprowadza opór
  const int maxEffectiveADC = (5.0 / 3.3) * (1.0 / 3.0) * 4095;
  int raw = analogRead(PIN_MQ3);
  return map(raw, 0, maxEffectiveADC, 0, 100);
}

void setup() {
  Serial.begin(115200);
  
  analogReadResolution(12);       
  analogSetAttenuation(ADC_11db); 
  pinMode(PIN_LDR, INPUT); 
  pinMode(PIN_NTC, INPUT);
  pinMode(PIN_MQ135, INPUT);
  pinMode(PIN_MQ3, INPUT);
  dht22.begin(); 
  Wire.begin(I2C_SDA, I2C_SCL);
  
  if(!display.begin(0x3C, true)) {
    Serial.println("Bbrak OLED bruh");
    
  }
  display.setTextColor(SH110X_WHITE);
  display.clearDisplay();
  
  delay(5000); 
}

void loop() {

  float dht_temp = measureDHT22_Temp();
  float dht_hum  = measureDHT22_Hum();
  float ntc_temp = measureNTC();
  int ldr_light  = measureLDR();
  int mq135_air = measureMQ135(PIN_MQ135);
  int mq3_alc = measureMQ3(PIN_MQ3);

  display.clearDisplay(); 
  display.setTextSize(1); 
  display.setCursor(0, 0);
  display.printf("Temp DHT: %.1f C\n", dht_temp);
  display.printf("Wilg DHT: %.1f %%\n", dht_hum);
  display.printf("Temp NTC: %.1f C\n", ntc_temp);
  display.printf("Swiatlo:  %d %%\n", ldr_light);
  display.printf("Gaz/dym:  %d %%\n", mq135_air);
  display.printf("Alkohol:  %d %%\n", mq3_alc);

  Serial.printf("raw MQ135: %4d, raw MQ3: %4d\n", analogRead(PIN_MQ135), analogRead(PIN_MQ3));
  display.display();
  delay(1000); 
}