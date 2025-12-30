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

// Keymap
char keys[ROWS][COLS] = {
  {'1', '2', '3', 'A'},
  {'4', '5', '6', 'B'},
  {'7', '8', '9', 'C'},
  {'*', '0', '#', 'D'}
};
byte rowPins[ROWS] = {14, 27, 26, 25};
byte colPins[COLS] = {33, 32, 18, 19};
Keypad keypad = Keypad(makeKeymap(keys), rowPins, colPins, ROWS, COLS);

// MFRC522 pins 
#define SS_PIN 5
#define RST_PIN 4
#define SCK_PIN 15
#define MOSI_PIN 23
#define MISO_PIN 35

MFRC522 mfrc522(SS_PIN, RST_PIN);

// FreeRTOS sync
SemaphoreHandle_t displayMutex;
SemaphoreHandle_t inputMutex;

// RFID display control
volatile bool rfidDisplayActive = false;
volatile uint32_t rfidDisplayEnd = 0;

// Danh sách UID hợp lệ
String validUIDs[] = {
  "47:60:3E:05",
  "11:22:33:44"
};

const int validUIDCount = sizeof(validUIDs) / sizeof(validUIDs[0]);

// WiFi
const char* ssid = "Duong";
const char* password = "00000000";

// MQTT
const char* mqttServer = "broker.hivemq.com";
const int mqttPort = 1883;
const char* mqttUser = "USERNAME"; // nếu có
const char* mqttPassword = "PASSWORD"; // nếu có
const char* mqttTopic = "home/door/status";

WiFiClient espClient;
PubSubClient client(espClient);

void setupWiFi() {
  WiFi.begin(ssid, password);
  Serial.print("Connecting to WiFi");
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }
  Serial.println("Connected!");
}

void reconnectMQTT() {
  while (!client.connected()) {
    Serial.print("Connecting to MQTT...");
    if (client.connect("ESP32_Client", mqttUser, mqttPassword)) {
      Serial.println("connected");
    } else {
      Serial.print("failed, rc=");
      Serial.print(client.state());
      Serial.println(" try again in 2s");
      delay(2000);
    }
  }
}
// MQTT
void sendMQTT(const String &status, const String &method, const String &uidOrPass="") {
  if (!client.connected()) return;

  String payload = "{";
  payload += "\"status\":\"" + status + "\",";
  payload += "\"method\":\"" + method + "\""; // "RFID" hoặc "PASSWORD"
  if (uidOrPass != "") payload += ",\"value\":\"" + uidOrPass + "\"";
  payload += "}";

  client.publish(mqttTopic, payload.c_str());
  Serial.print("MQTT sent: ");
  Serial.println(payload);
}

// Helper functions
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

void showUnlockMessage() {
  lockState = false;
  safePrintCenter("Mo khoa thanh cong!", 1);
}



// Kiem tra Rfid hop le
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
      sendMQTT("unlock", "RFID", uid); // gửi JSON mở khóa
    } else {
      sendMQTT("failed", "RFID", uid); // gửi JSON thất bại
    }

  }
}

// Hàm hiển thị màn hình nhập mật khẩu
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



// ---- Tasks ----
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
        } else if (key == '#') {      // Xóa tất cả
          inputString = "";
          offset = 0;
        } else if (key == '*') {      // Xóa ký tự cuối
          if (inputString.length() > 0) {
            inputString.remove(inputString.length() - 1);
            offset--;
          }
        } else if (key == 'D') {      // Xác nhận mật khẩu
          if (inputString == correct_password) {
            showUnlockMessage();
            sendMQTT("unlock", "PASSWORD"); // gửi JSON mở khóa
            vTaskDelay(pdMS_TO_TICKS(3000));
            lockState = true;
          } else {
            safePrintCenter("Mat khau khong dung!", 1);
            sendMQTT("failed", "PASSWORD"); // gửi JSON thất bại
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
  for (;;) {
    if (mfrc522.PICC_IsNewCardPresent() && mfrc522.PICC_ReadCardSerial()) {
      String uidStr = "";
      for (byte i = 0; i < mfrc522.uid.size; i++) {
        if (mfrc522.uid.uidByte[i] < 0x10) uidStr += "0";
        uidStr += String(mfrc522.uid.uidByte[i], HEX);
        if (i != mfrc522.uid.size - 1) uidStr += ":";
      }
      uidStr.toUpperCase();
      Serial.print("Detected UID: ");
      Serial.println(uidStr);

      bool valid = isValidUID(uidStr);
      showRFIDStatus(uidStr, valid);

      mfrc522.PICC_HaltA();
      mfrc522.PCD_StopCrypto1();
    }
    vTaskDelay(pdMS_TO_TICKS(100));
  }
}



// ---- Setup & Loop ----
void setup() {
  Serial.begin(115200);
  Wire.begin(21, 22); // SDA=21, SCL=22
  
  client.setServer(mqttServer, mqttPort);

  if (!display.begin(SSD1306_SWITCHCAPVCC, 0x3C)) {
    Serial.println("Không tìm thấy màn hình OLED!");
    for (;;) ;
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

  displayMutex = xSemaphoreCreateMutex();
  inputMutex = xSemaphoreCreateMutex();
  if (displayMutex == NULL || inputMutex == NULL) {
    Serial.println("Failed to create semaphores!");
    for (;;) ;
  }

  xTaskCreatePinnedToCore(keypadTask, "KeypadTask", 4096, NULL, 1, NULL, 1);
  xTaskCreatePinnedToCore(rfidTask, "RFIDTask", 4096, NULL, 1, NULL, 1);
  setupWiFi();
}

void loop() {
  if (!client.connected()) reconnectMQTT();
  client.loop();
  vTaskDelay(pdMS_TO_TICKS(1000));
}
