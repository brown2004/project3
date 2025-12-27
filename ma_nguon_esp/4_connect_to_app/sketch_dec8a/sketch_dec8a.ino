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

#define SCREEN_WIDTH 128
#define SCREEN_HEIGHT 64
#define OLED_RESET -1
Adafruit_SSD1306 display(SCREEN_WIDTH, SCREEN_HEIGHT, &Wire, OLED_RESET);

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
byte rowPins[ROWS] = {14, 27, 26, 25};  // Giữ nguyên
byte colPins[COLS] = {33, 32, 13, 12};  // ĐỔI: 18→13, 19→12
Keypad keypad = Keypad(makeKeymap(keys), rowPins, colPins, ROWS, COLS);

// MFRC522 pins - VSPI CHUẨN ESP32
#define SS_PIN 5      // D5 - Giữ nguyên
#define RST_PIN 4     // D4 - Giữ nguyên  
#define SCK_PIN 18    // D18 - ĐỔI từ D15 (giờ được dùng vì keypad đã đổi)
#define MOSI_PIN 23   // D23 - Giữ nguyên
#define MISO_PIN 19   // D19 - ĐỔI từ D35 (giờ được dùng vì keypad đã đổi)

MFRC522 mfrc522(SS_PIN, RST_PIN);

// FreeRTOS sync
SemaphoreHandle_t displayMutex;
SemaphoreHandle_t inputMutex;

// RFID display control
volatile bool rfidDisplayActive = false;
volatile uint32_t rfidDisplayEnd = 0;

// Chế độ quét thẻ mới
volatile bool scanMode = false;

// Danh sách UID hợp lệ (tối đa 10 thẻ)
String validUIDs[10] = {
  "47:60:3E:05"
};
int validUIDCount = 1;

// WiFi
const char* ssid = "Duong";
const char* password = "00000000";

// MQTT
const char* mqttServer = "broker.hivemq.com";
const int mqttPort = 1883;
const char* mqttClientId = "ESP32_SmartLock";

// Topics
const char* TOPIC_COMMAND = "smartlock/command";
const char* TOPIC_LOG = "smartlock/log";
const char* TOPIC_RFID = "smartlock/rfid";
const char* TOPIC_STATUS = "smartlock/status";

WiFiClient espClient;
PubSubClient client(espClient);

// ==========================
// HELPER FUNCTIONS (ĐẶT TRƯỚC)
// ==========================
void safePrintCenter(const String &s, int textSize = 1) {
  if (xSemaphoreTake(displayMutex, (TickType_t)10) == pdTRUE) {
    display.clearDisplay();
    display.setTextSize(textSize);
    display.setTextColor(WHITE);

    int16_t x1, y1;
    uint16_t w, h;
    display.getTextBounds(s, 0, 0, &x1, &y1, &w, &h);

    int centerX = (SCREEN_WIDTH - w) / 2;
    int centerY = (SCREEN_HEIGHT - h) / 2;

    display.setCursor(centerX, centerY);
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
    String masked = inputString;
    display.getTextBounds(masked, 0, 0, &x1, &y1, &w, &h);
    int centerX = (SCREEN_WIDTH - w - offset * 5) / 2;
    int centerY = (SCREEN_HEIGHT - h) / 2;
    display.setCursor(centerX, centerY);
    display.setTextSize(2);
    display.print(masked);
    display.display();
    xSemaphoreGive(displayMutex);
  }
}

// ==========================
// MQTT FUNCTIONS
// ==========================
void sendLogMQTT(const String &user, const String &action, bool success) {
  if (!client.connected()) return;

  StaticJsonDocument<200> doc;
  doc["user"] = user;
  doc["action"] = action;
  doc["success"] = success;
  doc["timestamp"] = millis();

  char buffer[200];
  serializeJson(doc, buffer);
  
  client.publish(TOPIC_LOG, buffer);
  Serial.println("📤 Log: " + String(buffer));
}

void sendRfidMQTT(const String &rfidCode) {
  if (!client.connected()) return;

  StaticJsonDocument<100> doc;
  doc["rfid"] = rfidCode;
  doc["code"] = rfidCode;
  
  char buffer[100];
  serializeJson(doc, buffer);
  
  client.publish(TOPIC_RFID, buffer);
  Serial.println("📤 RFID: " + String(buffer));
}

void sendStatusMQTT() {
  if (!client.connected()) return;

  StaticJsonDocument<100> doc;
  doc["locked"] = lockState;
  
  char buffer[100];
  serializeJson(doc, buffer);
  
  client.publish(TOPIC_STATUS, buffer);
  Serial.println("📤 Status: " + String(buffer));
}

void showUnlockMessage() {
  lockState = false;
  safePrintCenter("Mo khoa thanh cong!", 1);
  sendStatusMQTT();
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
    int centerX = (SCREEN_WIDTH - w) / 2;
    int centerY = (SCREEN_HEIGHT - h) / 2;

    display.setCursor(centerX, centerY);
    display.print(msg);
    display.display();
    xSemaphoreGive(displayMutex);

    if (valid) {
      lockState = false;
      sendLogMQTT("RFID:" + uid, "Mo khoa bang the", true);
      sendStatusMQTT();
    } else {
      sendLogMQTT("RFID:" + uid, "The khong hop le", false);
    }
  }
}

// ==========================
// WIFI
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

// ==========================
// CALLBACK MQTT
// ==========================
void mqttCallback(char* topic, byte* payload, unsigned int length) {
  String message = "";
  for (unsigned int i = 0; i < length; i++) {
    message += (char)payload[i];
  }
  
  Serial.print("📩 MQTT nhận: [");
  Serial.print(topic);
  Serial.print("] ");
  Serial.println(message);

  // Xử lý lệnh
  if (String(topic) == TOPIC_COMMAND) {
    if (message == "SCAN_NEW_RFID") {
      Serial.println("✅ Vào chế độ quét thẻ mới");
      scanMode = true;
      safePrintCenter("Che do them the!", 1);
      
    } else if (message == "CANCEL_SCAN") {
      Serial.println("❌ Hủy quét thẻ");
      scanMode = false;
      displayKeypadScreen();
      
    } else if (message == "LOCK") {
      lockState = true;
      safePrintCenter("Da khoa!", 1);
      sendStatusMQTT();
      
    } else if (message == "UNLOCK") {
      lockState = false;
      safePrintCenter("Da mo!", 1);
      sendStatusMQTT();
      
    } else if (message.startsWith("SAVE_CARD:")) {
      int firstColon = message.indexOf(':');
      int lastColon = message.lastIndexOf(':');
      String uid = message.substring(firstColon + 1, lastColon);
      
      if (validUIDCount < 10) {
        validUIDs[validUIDCount++] = uid;
        Serial.println("✅ Đã lưu thẻ: " + uid);
      }
      
    } else if (message.startsWith("DELETE:")) {
      String uid = message.substring(7);
      for (int i = 0; i < validUIDCount; i++) {
        if (validUIDs[i] == uid) {
          for (int j = i; j < validUIDCount - 1; j++) {
            validUIDs[j] = validUIDs[j + 1];
          }
          validUIDCount--;
          Serial.println("🗑️ Đã xóa thẻ: " + uid);
          break;
        }
      }
      
    } else if (message.startsWith("CHANGE_PIN:")) {
      String newPin = message.substring(11);
      correct_password = newPin;
      Serial.println("🔑 Đã đổi PIN thành: " + newPin);
    }
  }
}

// ==========================
// KẾT NỐI MQTT
// ==========================
void reconnectMQTT() {
  int attempts = 0;
  while (!client.connected() && attempts < 5) {
    attempts++;
    Serial.print("🔄 Connecting to MQTT... (Attempt ");
    Serial.print(attempts);
    Serial.println("/5)");
    
    Serial.print("   Broker: ");
    Serial.println(mqttServer);
    Serial.print("   Port: ");
    Serial.println(mqttPort);
    Serial.print("   ClientID: ");
    Serial.println(mqttClientId);
    
    if (client.connect(mqttClientId)) {
      Serial.println("✅ Connected!");
      
      bool subSuccess = client.subscribe(TOPIC_COMMAND);
      if (subSuccess) {
        Serial.println("📡 Subscribed to: " + String(TOPIC_COMMAND));
      } else {
        Serial.println("❌ Subscribe failed!");
      }
      
      client.publish(TOPIC_STATUS, "{\"locked\":true,\"online\":true}");
      Serial.println("📤 Test message sent");
      
      return;
      
    } else {
      Serial.print("❌ Failed, rc=");
      Serial.print(client.state());
      Serial.print(" - ");
      
      switch(client.state()) {
        case -4: Serial.println("TIMEOUT"); break;
        case -3: Serial.println("CONNECTION_LOST"); break;
        case -2: Serial.println("CONNECT_FAILED"); break;
        case -1: Serial.println("DISCONNECTED"); break;
        case 1: Serial.println("BAD_PROTOCOL"); break;
        case 2: Serial.println("BAD_CLIENT_ID"); break;
        case 3: Serial.println("UNAVAILABLE"); break;
        case 4: Serial.println("BAD_CREDENTIALS"); break;
        case 5: Serial.println("UNAUTHORIZED"); break;
        default: Serial.println("UNKNOWN"); break;
      }
      
      delay(3000);
    }
  }
  
  if (!client.connected()) {
    Serial.println("❌ Không thể kết nối sau 5 lần thử!");
  }
}

// ==========================
// TASKS
// ==========================
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
          if (inputString == correct_password) {
            showUnlockMessage();
            sendLogMQTT("Password", "Mo khoa bang PIN", true);
            vTaskDelay(pdMS_TO_TICKS(3000));
            lockState = true;
            sendStatusMQTT();
          } else {
            safePrintCenter("Mat khau khong dung!", 1);
            sendLogMQTT("Password", "Sai PIN", false);
            vTaskDelay(pdMS_TO_TICKS(2000));
          }
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
  Serial.println("🎫 RFID Task started!");
  
  for (;;) {
    // Debug: In ra mỗi 5 giây để biết task đang chạy
    static unsigned long lastDebug = 0;
    if (millis() - lastDebug > 5000) {
      Serial.println("🔄 RFID task running... (Quét thẻ nào!)");
      lastDebug = millis();
    }
    
    if (mfrc522.PICC_IsNewCardPresent()) {
      Serial.println("👀 Phát hiện thẻ!");
      
      if (mfrc522.PICC_ReadCardSerial()) {
        String uidStr = "";
        for (byte i = 0; i < mfrc522.uid.size; i++) {
          if (mfrc522.uid.uidByte[i] < 0x10) uidStr += "0";
          uidStr += String(mfrc522.uid.uidByte[i], HEX);
          if (i != mfrc522.uid.size - 1) uidStr += ":";
        }
        uidStr.toUpperCase();
        Serial.print("✅ Detected UID: ");
        Serial.println(uidStr);

        if (scanMode) {
          Serial.println("🆕 Gửi mã thẻ mới về App...");
          sendRfidMQTT(uidStr);
          scanMode = false;
          displayKeypadScreen();
        } else {
          bool valid = isValidUID(uidStr);
          Serial.print("Kiểm tra thẻ: ");
          Serial.println(valid ? "HỢP LỆ ✅" : "KHÔNG HỢP LỆ ❌");
          showRFIDStatus(uidStr, valid);
        }

        mfrc522.PICC_HaltA();
        mfrc522.PCD_StopCrypto1();
      } else {
        Serial.println("⚠️ Không đọc được serial thẻ!");
      }
    }
    vTaskDelay(pdMS_TO_TICKS(100));
  }
}

// ==========================
// SETUP
// ==========================
void setup() {
  Serial.begin(115200);
  Wire.begin(21, 22);

  if (!display.begin(SSD1306_SWITCHCAPVCC, 0x3C)) {
    Serial.println("Không tìm thấy màn hình OLED!");
    for (;;);
  }
  display.clearDisplay();
  display.setTextSize(1);
  display.setTextColor(WHITE);
  display.setCursor(5, 5);
  display.print("Nhap ma khoa:");
  display.display();

  SPI.begin(SCK_PIN, MISO_PIN, MOSI_PIN, SS_PIN);
  mfrc522.PCD_Init();
  Serial.println("RFID reader initialized.");
  
  // Test RFID
  Serial.println("\n=== TEST RFID MODULE ===");
  Serial.println("Pins:");
  Serial.println("  SS: " + String(SS_PIN));
  Serial.println("  RST: " + String(RST_PIN));
  Serial.println("  SCK: " + String(SCK_PIN));
  Serial.println("  MOSI: " + String(MOSI_PIN));
  Serial.println("  MISO: " + String(MISO_PIN));
  
  delay(100);
  byte version = mfrc522.PCD_ReadRegister(mfrc522.VersionReg);
  Serial.print("MFRC522 Version: 0x");
  Serial.println(version, HEX);
  
  if (version == 0x00 || version == 0xFF) {
    Serial.println("\n❌❌❌ LỖI NGHIÊM TRỌNG ❌❌❌");
    Serial.println("KHÔNG TÌM THẤY MODULE RFID!");
    Serial.println("\nKiểm tra:");
    Serial.println("  1. Dây kết nối đúng chưa?");
    Serial.println("  2. Module có nguồn 3.3V?");
    Serial.println("  3. Dây SPI có bị nhầm không?");
    Serial.println("  4. Module có bị hỏng?");
    Serial.println("\n⚠️ RFID SẼ KHÔNG HOẠT ĐỘNG!");
  } else if (version == 0x91 || version == 0x92) {
    Serial.println("✅✅✅ Module RFID OK!");
    Serial.println("Có thể quét thẻ bình thường.");
  } else {
    Serial.println("⚠️ Version lạ, có thể vẫn hoạt động.");
  }
  
  // Test self-check
  Serial.println("\nChạy self-test...");
  bool testResult = mfrc522.PCD_PerformSelfTest();
  if (testResult) {
    Serial.println("✅ Self-test PASSED!");
  } else {
    Serial.println("❌ Self-test FAILED!");
  }
  mfrc522.PCD_Init(); // Khởi tạo lại sau self-test
  
  Serial.println("========================\n");

  displayMutex = xSemaphoreCreateMutex();
  inputMutex = xSemaphoreCreateMutex();
  if (displayMutex == NULL || inputMutex == NULL) {
    Serial.println("Failed to create semaphores!");
    for (;;);
  }

  xTaskCreatePinnedToCore(keypadTask, "KeypadTask", 4096, NULL, 1, NULL, 1);
  xTaskCreatePinnedToCore(rfidTask, "RFIDTask", 4096, NULL, 1, NULL, 1);

  setupWiFi();
  
  client.setServer(mqttServer, mqttPort);
  client.setCallback(mqttCallback);
  
  Serial.println("✅ ESP32 Ready!");
}

// ==========================
// LOOP
// ==========================
void loop() {
  if (!client.connected()) {
    reconnectMQTT();
  }
  client.loop();
  vTaskDelay(pdMS_TO_TICKS(100));
}