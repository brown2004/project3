#include <Wire.h>
#include <Keypad.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>
#include <SPI.h>
#include <MFRC522.h>
#include <freertos/FreeRTOS.h>
#include <freertos/task.h>
#include <freertos/semphr.h>
#include <WiFi.h>
#include <PubSubClient.h>
#include <ArduinoJson.h>
#include <Preferences.h>

#define SCREEN_WIDTH 128
#define SCREEN_HEIGHT 64
#define OLED_RESET -1
Adafruit_SSD1306 display(SCREEN_WIDTH, SCREEN_HEIGHT, &Wire, OLED_RESET);

Preferences preferences;

// Keypad
const byte ROWS = 4;
const byte COLS = 4;
const int MAX_PASS_SIZE = 8;
String inputString = "";
String correct_password = "123456";
int offset = 0;
boolean lockState = true;

char keys[ROWS][COLS] = {
  {'1', '2', '3', 'A'},
  {'4', '5', '6', 'B'},
  {'7', '8', '9', 'C'},
  {'*', '0', '#', 'D'}
};
byte rowPins[ROWS] = {14, 27, 26, 25};  
byte colPins[COLS] = {33, 32, 13, 12}; 
Keypad keypad = Keypad(makeKeymap(keys), rowPins, colPins, ROWS, COLS);

// MFRC522 pins
#define SS_PIN 5
#define RST_PIN 4
#define SCK_PIN 18
#define MOSI_PIN 23
#define MISO_PIN 19

MFRC522 mfrc522(SS_PIN, RST_PIN);

// FreeRTOS
SemaphoreHandle_t displayMutex;
SemaphoreHandle_t inputMutex;

volatile bool rfidDisplayActive = false;
volatile uint32_t rfidDisplayEnd = 0;
volatile bool scanMode = false;

String validUIDs[10] = {"47:60:3E:05"};
int validUIDCount = 1;

// WiFi & MQTT
const char* ssid = "Duong"; // Thay đổi nếu cần
const char* password = "00000000"; // Thay đổi nếu cần
const char* mqttServer = "172.20.10.5"; // IP Broker
const int mqttPort = 1883;
const char* mqttClientId = "ESP32_SmartLock";

const char* TOPIC_COMMAND = "smartlock/command";
const char* TOPIC_LOG = "smartlock/log";
const char* TOPIC_RFID = "smartlock/rfid";
const char* TOPIC_STATUS = "smartlock/status";

WiFiClient espClient;
PubSubClient client(espClient);

// ==========================
// HELPER FUNCTIONS
// ==========================
void safePrintCenter(const String &s, int textSize = 1) {
  if (xSemaphoreTake(displayMutex, (TickType_t)10) == pdTRUE) {
    display.clearDisplay();
    display.setTextSize(textSize);
    display.setTextColor(WHITE);

    int16_t x1, y1;
    uint16_t w, h;
    display.getTextBounds(s, 0, 0, &x1, &y1, &w, &h);

    display.setCursor((SCREEN_WIDTH - w) / 2, (SCREEN_HEIGHT - h) / 2);
    display.print(s);
    display.display();
    xSemaphoreGive(displayMutex);
  }
}

void displayKeypadScreen() {
  if (xSemaphoreTake(displayMutex, (TickType_t)10) == pdTRUE) {
    display.clearDisplay();
    display.setTextSize(1);
    display.setTextColor(WHITE);
    display.setCursor(5, 5);
    display.print("Nhap ma khoa:");

    if (offset < 0) offset = 0;

    int16_t x1, y1;
    uint16_t w, h;
    display.getTextBounds(inputString, 0, 0, &x1, &y1, &w, &h);
    display.setCursor((SCREEN_WIDTH - w - offset * 5) / 2, (SCREEN_HEIGHT - h) / 2);
    display.setTextSize(2);
    display.print(inputString);
    display.display();
    xSemaphoreGive(displayMutex);
  }
}

// ==========================
// FLASH STORAGE
// ==========================
void loadUserData() {
  preferences.begin("smartlock", false);
  correct_password = preferences.getString("pin", "123456"); 
  Serial.println("🔑 Loaded PIN: " + correct_password);

  validUIDCount = preferences.getInt("uid_count", 1);
  if (validUIDCount > 10) validUIDCount = 10;
  if (validUIDCount < 1) validUIDCount = 1;

  Serial.print("📂 Loaded UIDs: ");
  Serial.println(validUIDCount);

  for (int i = 0; i < validUIDCount; i++) {
    String key = "uid_" + String(i); 
    validUIDs[i] = preferences.getString(key.c_str(), "");
    Serial.println("  - " + validUIDs[i]);
  }
  preferences.end();
}

void saveUIDsToFlash() {
  preferences.begin("smartlock", false);
  preferences.putInt("uid_count", validUIDCount);
  for (int i = 0; i < validUIDCount; i++) {
    String key = "uid_" + String(i);
    preferences.putString(key.c_str(), validUIDs[i]);
  }
  preferences.end();
  Serial.println("💾 Đã lưu danh sách thẻ vào Flash!");
}

void savePinToFlash(String newPin) {
  preferences.begin("smartlock", false);
  preferences.putString("pin", newPin);
  preferences.end();
  Serial.println("💾 Đã lưu PIN mới vào Flash!");
}

// ==========================
// MQTT FUNCTIONS
// ==========================
void sendCommandFeedback(const String &command, bool success, const String &message = "") {
  if (!client.connected()) return;
  StaticJsonDocument<256> doc;
  doc["action"] = command;
  doc["success"] = success;
  doc["message"] = message;
  doc["timestamp"] = millis();
  char buffer[256];
  serializeJson(doc, buffer);
  client.publish(TOPIC_LOG, buffer);
  Serial.println("📤 Feedback: " + String(buffer));
}

void sendLogMQTT(const String &user, const String &action, bool success) {
  if (!client.connected()) return;
  StaticJsonDocument<256> doc; // Tăng size buffer
  doc["user"] = user;
  doc["action"] = action;
  doc["success"] = success;
  doc["timestamp"] = millis();
  char buffer[256];
  serializeJson(doc, buffer);
  client.publish(TOPIC_LOG, buffer);
  Serial.println("📤 Log: " + String(buffer));
}

void sendRfidMQTT(const String &rfidCode) {
  if (!client.connected()) return;
  StaticJsonDocument<128> doc;
  doc["rfid"] = rfidCode;
  doc["code"] = rfidCode;
  char buffer[128];
  serializeJson(doc, buffer);
  client.publish(TOPIC_RFID, buffer);
  Serial.println("📤 RFID: " + String(buffer));
}

void sendStatusMQTT() {
  if (!client.connected()) return;
  StaticJsonDocument<128> doc;
  doc["locked"] = lockState;
  char buffer[128];
  serializeJson(doc, buffer);
  client.publish(TOPIC_STATUS, buffer);
  Serial.println("📤 Status: " + String(buffer));
}

void sendSyncCards() {
  if (!client.connected()) return;
  StaticJsonDocument<1024> doc; // Buffer lớn cho danh sách thẻ
  doc["type"] = "SYNC_CARDS";
  doc["count"] = validUIDCount;
  JsonArray cards = doc.createNestedArray("cards");
  for (int i = 0; i < validUIDCount; i++) {
    cards.add(validUIDs[i]);
  }
  char buffer[1024];
  serializeJson(doc, buffer);
  // Quan trọng: Kiểm tra xem gói tin có quá lớn so với buffer MQTT không
  if (strlen(buffer) < 512) { 
      client.publish(TOPIC_LOG, buffer);
      Serial.println("📤 Sync Cards Sent");
  } else {
      Serial.println("❌ Sync Cards too large!");
  }
}

void sendSyncPin() {
  if (!client.connected()) return;
  StaticJsonDocument<128> doc;
  doc["type"] = "SYNC_PIN";
  doc["pin_length"] = correct_password.length();
  char buffer[128];
  serializeJson(doc, buffer);
  client.publish(TOPIC_LOG, buffer);
  Serial.println("📤 Sync PIN length: " + String(buffer));
}

bool isValidUID(const String &uid) {
  for (int i = 0; i < validUIDCount; i++) {
    if (uid == validUIDs[i]) return true;
  }
  return false;
}

void showRFIDStatus(const String &uid, bool valid) {
  rfidDisplayActive = true;
  rfidDisplayEnd = millis() + 2000;

  if (xSemaphoreTake(displayMutex, (TickType_t)10) == pdTRUE) {
    display.clearDisplay();
    display.setTextSize(1);
    display.setTextColor(WHITE);

    String msg = valid ? "Mo khoa thanh cong!" : "RFID khong hop le!";
    int16_t x1, y1;
    uint16_t w, h;
    display.getTextBounds(msg, 0, 0, &x1, &y1, &w, &h);
    display.setCursor((SCREEN_WIDTH - w) / 2, (SCREEN_HEIGHT - h) / 2);
    display.print(msg);
    display.display();
    xSemaphoreGive(displayMutex);

    if (valid) {
      lockState = false;
      // SỬA: Gửi Log trước, Status sau
      sendLogMQTT("RFID:" + uid, "Mo khoa bang the", true);
      vTaskDelay(pdMS_TO_TICKS(100)); 
      sendStatusMQTT();
    } else {
      sendLogMQTT("RFID:" + uid, "The khong hop le", false);
    }
  }
}

// ==========================
// WIFI & MQTT SETUP
// ==========================
void setupWiFi() {
  WiFi.begin(ssid, password);
  Serial.print("Connecting to WiFi");
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }
  Serial.println("\nWiFi Connected!");
  Serial.print("IP: ");
  Serial.println(WiFi.localIP());
}

void mqttCallback(char* topic, byte* payload, unsigned int length) {
  String message = "";
  for (unsigned int i = 0; i < length; i++) {
    message += (char)payload[i];
  }
  
  Serial.print("📩 MQTT nhận: [");
  Serial.print(topic);
  Serial.print("] ");
  Serial.println(message);

  if (String(topic) == TOPIC_COMMAND) {
    if (message == "SYNC_REQ") {
      sendStatusMQTT();
      delay(50);
      sendSyncCards();
      delay(50);
      sendSyncPin();
      sendCommandFeedback("SYNC_REQ", true, "Dong bo thanh cong");
      
    } else if (message == "SCAN_NEW_RFID") {
      scanMode = true;
      safePrintCenter("Che do them the!", 1);
      sendCommandFeedback("SCAN_NEW_RFID", true, "Che do quet the");
      
    } else if (message == "CANCEL_SCAN") {
      scanMode = false;
      displayKeypadScreen();
      sendCommandFeedback("CANCEL_SCAN", true, "Da huy");
      
    } else if (message == "LOCK") {
      lockState = true;
      safePrintCenter("Da khoa!", 1);
      
      // Remote Log
      sendLogMQTT("Remote", "Khoa tu xa", true);
      vTaskDelay(pdMS_TO_TICKS(100));
      sendStatusMQTT();
      sendCommandFeedback("LOCK", true, "Da khoa tu xa"); // Feedback cho nút bấm
      
      vTaskDelay(pdMS_TO_TICKS(1500));
      displayKeypadScreen();
      
    } else if (message == "UNLOCK") {
      lockState = false;
      safePrintCenter("Da mo!", 1);
      
      // Remote Log
      sendLogMQTT("Remote", "Mo khoa tu xa", true);
      vTaskDelay(pdMS_TO_TICKS(100));
      sendStatusMQTT();
      sendCommandFeedback("UNLOCK", true, "Da mo tu xa"); // Feedback cho nút bấm
      
      vTaskDelay(pdMS_TO_TICKS(1500));
      displayKeypadScreen();
      
    } else if (message.startsWith("SAVE_CARD:")) {
      int firstColon = message.indexOf(':');
      int lastColon = message.lastIndexOf(':');
      String uid = message.substring(firstColon + 1, lastColon);
      
      bool alreadyExists = false;
      for (int i = 0; i < validUIDCount; i++) {
        if (validUIDs[i] == uid) {
          alreadyExists = true;
          break;
        }
      }
      
      if (alreadyExists) {
        safePrintCenter("The da ton tai!", 1);
        sendCommandFeedback("SAVE_CARD", false, "The da ton tai");
        vTaskDelay(pdMS_TO_TICKS(2000));
        displayKeypadScreen();
      } else if (validUIDCount < 10) {
        validUIDs[validUIDCount++] = uid;
        saveUIDsToFlash();
        safePrintCenter("Da luu the!", 1);
        sendCommandFeedback("SAVE_CARD", true, "Da luu: " + uid);
        vTaskDelay(pdMS_TO_TICKS(1500));
        displayKeypadScreen();
      } else {
        safePrintCenter("Day! Khong the them", 1);
        sendCommandFeedback("SAVE_CARD", false, "Da du 10 the");
        vTaskDelay(pdMS_TO_TICKS(2000));
        displayKeypadScreen();
      }
      
    } else if (message.startsWith("DELETE:")) {
      String uid = message.substring(7);
      bool found = false;
      for (int i = 0; i < validUIDCount; i++) {
        if (validUIDs[i] == uid) {
          for (int j = i; j < validUIDCount - 1; j++) {
            validUIDs[j] = validUIDs[j + 1];
          }
          validUIDCount--;
          saveUIDsToFlash();
          safePrintCenter("Da xoa the!", 1);
          sendCommandFeedback("DELETE", true, "Da xoa: " + uid);
          found = true;
          vTaskDelay(pdMS_TO_TICKS(1500));
          displayKeypadScreen();
          break;
        }
      }
      if (!found) {
        safePrintCenter("Khong tim thay!", 1);
        sendCommandFeedback("DELETE", false, "Khong tim thay the");
        vTaskDelay(pdMS_TO_TICKS(1500));
        displayKeypadScreen();
      }
      
    } else if (message.startsWith("CHANGE_PIN:")) {
      String newPin = message.substring(11);
      if (newPin.length() >= 4 && newPin.length() <= 8) {
        bool validPin = true;
        for (int i = 0; i < newPin.length(); i++) {
          if (!isDigit(newPin[i])) {
            validPin = false;
            break;
          }
        }
        if (validPin) {
          correct_password = newPin;
          savePinToFlash(newPin);
          safePrintCenter("Da doi PIN!", 1);
          sendCommandFeedback("CHANGE_PIN", true, "Da doi PIN");
          vTaskDelay(pdMS_TO_TICKS(1500));
          displayKeypadScreen();
        } else {
          safePrintCenter("PIN khong hop le!", 1);
          sendCommandFeedback("CHANGE_PIN", false, "PIN phai toan so");
          vTaskDelay(pdMS_TO_TICKS(2000));
          displayKeypadScreen();
        }
      } else {
        safePrintCenter("PIN 4-8 chu so!", 1);
        sendCommandFeedback("CHANGE_PIN", false, "PIN phai 4-8 chu so");
        vTaskDelay(pdMS_TO_TICKS(2000));
        displayKeypadScreen();
      }
    }
  }
}

void reconnectMQTT() {
  int attempts = 0;
  while (!client.connected() && attempts < 5) {
    attempts++;
    Serial.print("🔄 Connecting to MQTT... (");
    Serial.print(attempts);
    Serial.println("/5)");
    
    if (client.connect(mqttClientId)) {
      Serial.println("✅ Connected!");
      client.subscribe(TOPIC_COMMAND);
      
      // Sửa lỗi Buffer: Tăng buffer size để gửi được gói tin dài
      client.setBufferSize(512); 
      
      client.publish(TOPIC_STATUS, "{\"locked\":true,\"online\":true}");
      delay(500);
      sendStatusMQTT();
      Serial.println("📤 Đã gửi trạng thái ban đầu");
      return;
    } else {
      Serial.print("❌ Failed, rc=");
      Serial.println(client.state());
      delay(3000);
    }
  }
}

void keypadTask(void *pvParameters) {
  (void) pvParameters;
  for (;;) {
    if (rfidDisplayActive) {
      if ((int32_t)(millis() - rfidDisplayEnd) >= 0) {
        rfidDisplayActive = false;
        displayKeypadScreen();
      }
      vTaskDelay(pdMS_TO_TICKS(50));
      continue;
    }

    char key = keypad.getKey();
    if (key) {
      Serial.print("Phim nhan: ");
      Serial.println(key);

      if (xSemaphoreTake(inputMutex, (TickType_t)10) == pdTRUE) {
        if (key >= '0' && key <= '9') {
          if (inputString.length() < MAX_PASS_SIZE) {
            inputString += key;
            offset++;
          }
        } else if (key == '#') {
          inputString = "";
          offset = 0;
        } else if (key == '*') {
          if (inputString.length() > 0) {
            inputString.remove(inputString.length() - 1);
            offset--;
          }
        } else if (key == 'D') {
          // --- XÁC NHẬN MẬT KHẨU ---
          if (inputString == correct_password) {
            lockState = false;
            safePrintCenter("Mo khoa thanh cong!", 1);
            
            // QUAN TRỌNG: Gửi Log TRƯỚC, Status SAU
            sendLogMQTT("Keypad", "Mo khoa bang PIN", true);
            vTaskDelay(pdMS_TO_TICKS(100)); 
            sendStatusMQTT();
            
            vTaskDelay(pdMS_TO_TICKS(2000));
            displayKeypadScreen();
          } else {
            safePrintCenter("Mat khau khong dung!", 1);
            sendLogMQTT("Keypad", "Sai PIN", false);
            vTaskDelay(pdMS_TO_TICKS(2000));
          }
          inputString = "";
          offset = 0;
        } else if (key == 'C') {
          // --- NÚT KHÓA/MỞ NHANH ---
          lockState = !lockState;
          
          String msg = lockState ? "Da khoa bang phim C" : "Da mo bang phim C";
          String statusMsg = lockState ? "Da khoa!" : "Da mo!";
          
          safePrintCenter(statusMsg, 1);
          
          // QUAN TRỌNG: Gửi Log TRƯỚC, Status SAU
          sendLogMQTT("Keypad", msg, true);
          vTaskDelay(pdMS_TO_TICKS(100));
          sendStatusMQTT();
          
          vTaskDelay(pdMS_TO_TICKS(1500));
          inputString = "";
          offset = 0;
        }
        xSemaphoreGive(inputMutex);
      }
      if (!rfidDisplayActive) displayKeypadScreen();
    }
    vTaskDelay(pdMS_TO_TICKS(50));
  }
}

void rfidTask(void *pvParameters) {
  (void) pvParameters;
  for (;;) {
    if (mfrc522.PICC_IsNewCardPresent()) {
      if (mfrc522.PICC_ReadCardSerial()) {
        String uidStr = "";
        for (byte i = 0; i < mfrc522.uid.size; i++) {
          if (mfrc522.uid.uidByte[i] < 0x10) uidStr += "0";
          uidStr += String(mfrc522.uid.uidByte[i], HEX);
          if (i != mfrc522.uid.size - 1) uidStr += ":";
        }
        uidStr.toUpperCase();
        
        if (scanMode) {
          sendRfidMQTT(uidStr);
          scanMode = false;
          displayKeypadScreen();
        } else {
          bool valid = isValidUID(uidStr);
          showRFIDStatus(uidStr, valid);
        }
        mfrc522.PICC_HaltA();
        mfrc522.PCD_StopCrypto1();
      }
    }
    vTaskDelay(pdMS_TO_TICKS(100));
  }
}

void setup() {
  Serial.begin(115200);
  Wire.begin(21, 22);

  if (!display.begin(SSD1306_SWITCHCAPVCC, 0x3C)) {
    Serial.println("OLED failed");
    for (;;);
  }
  display.clearDisplay();
  display.setTextSize(1);
  display.setTextColor(WHITE);
  display.setCursor(5, 5);
  display.print("Khoi dong...");
  display.display();

  loadUserData();

  SPI.begin(SCK_PIN, MISO_PIN, MOSI_PIN, SS_PIN);
  mfrc522.PCD_Init();

  displayMutex = xSemaphoreCreateMutex();
  inputMutex = xSemaphoreCreateMutex();

  xTaskCreatePinnedToCore(keypadTask, "KeypadTask", 4096, NULL, 1, NULL, 1);
  xTaskCreatePinnedToCore(rfidTask, "RFIDTask", 4096, NULL, 1, NULL, 1);

  setupWiFi();
  client.setServer(mqttServer, mqttPort);
  client.setCallback(mqttCallback);
  
  Serial.println("✅ Ready");
  displayKeypadScreen();
}

void loop() {
  if (!client.connected()) {
    reconnectMQTT();
  }
  client.loop();
  vTaskDelay(pdMS_TO_TICKS(100));
}