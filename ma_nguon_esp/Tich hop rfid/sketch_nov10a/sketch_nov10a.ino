#include <Wire.h>
#include <Keypad.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>
#include <SPI.h>
#include <MFRC522.h>
#include <freertos/FreeRTOS.h>
#include <freertos/task.h>
#include <freertos/semphr.h>

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
#define SS_PIN 5   // SDA -> D5
#define RST_PIN 4  // RST -> D4
#define SCK_PIN 15 // D15
#define MOSI_PIN 23 // D23
#define MISO_PIN 35 // D35

MFRC522 mfrc522(SS_PIN, RST_PIN);

// FreeRTOS sync
SemaphoreHandle_t displayMutex;
SemaphoreHandle_t inputMutex;

// RFID display control
volatile bool rfidDisplayActive = false;
volatile uint32_t rfidDisplayEnd = 0;

// Helper functions
void safePrintCenter(const String &s, int textSize = 1) {
  if (xSemaphoreTake(displayMutex, (TickType_t)10) == pdTRUE) {
    display.clearDisplay();
    display.setTextSize(textSize);   // set size trước
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

// Hiển thị UID 
void showRFIDUID(const String &uidStr) {
  rfidDisplayActive = true;
  rfidDisplayEnd = millis() + 2000;

  if (xSemaphoreTake(displayMutex, (TickType_t)10) == pdTRUE) {
    display.clearDisplay();
    display.setTextSize(1);

    // Vẽ dòng tiêu đề
    String title = "RFID UID:";
    int16_t x1, y1;
    uint16_t w, h;
    display.getTextBounds(title, 0, 0, &x1, &y1, &w, &h);
    int centerX = (SCREEN_WIDTH - w) / 2;
    int centerY = (SCREEN_HEIGHT - h) / 2 - 8;
    display.setCursor(centerX, centerY);
    display.print(title);

    // Vẽ UID ở dòng dưới
    int uidWidth = uidStr.length() * 6; // mỗi ký tự ~6 pixel
    int uidX = (SCREEN_WIDTH - uidWidth) / 2;
    display.setCursor(uidX, centerY + 12);
    display.print(uidStr);

    display.display();
    xSemaphoreGive(displayMutex);
  }
}


// Hàm hiển thị màn hình nhập mật khẩu (khi không bị ghi đè bởi RFID)
void displayKeypadScreen() {
  if (xSemaphoreTake(displayMutex, (TickType_t)10) == pdTRUE) {
    display.clearDisplay();
    display.setTextSize(1);
    display.setCursor(5, 5);
    display.print("Nhap ma khoa:");
    if (offset < 0) offset = 0;
    // Tính vị trí để hiển thị input
    int16_t x1, y1;
    uint16_t w, h;
    String masked = inputString; //có thể thay bằng **** nếu muốn ẩn
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
    // Nếu đang hiển thị RFID, kiểm tra thời gian để tắt chế độ đó
    if (rfidDisplayActive) {
      if ((int32_t)(millis() - rfidDisplayEnd) >= 0) {
        rfidDisplayActive = false;
        // reset màn hình keypad khi RFID kết thúc
        displayKeypadScreen();
      }
      vTaskDelay(pdMS_TO_TICKS(50));
      continue;
    }

    char key = keypad.getKey();
    if (key) {
      Serial.print("Phim nhan: ");
      Serial.println(key);
      // thao tác trên inputString cần mutex
      if (xSemaphoreTake(inputMutex, (TickType_t)10) == pdTRUE) {
        if (key != '#' && key != '*') {
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
        }
        // kiểm tra mật khẩu
        if (inputString == correct_password) {
          showUnlockMessage();
          vTaskDelay(pdMS_TO_TICKS(3000));
          // quay về trạng thái khóa
          lockState = true;
          inputString = "";
          offset = 0;
        }
        xSemaphoreGive(inputMutex);
      }
      // update màn hình (nếu không bị RFID chiếm)
      if (!rfidDisplayActive) displayKeypadScreen();
    }
    vTaskDelay(pdMS_TO_TICKS(50));
  }
}

void rfidTask(void *pvParameters) {
  (void) pvParameters;
  for (;;) {
    // Kiểm tra thẻ
    if (mfrc522.PICC_IsNewCardPresent() && mfrc522.PICC_ReadCardSerial()) {
      // build UID string
      String uidStr = "";
      for (byte i = 0; i < mfrc522.uid.size; i++) {
        if (mfrc522.uid.uidByte[i] < 0x10) uidStr += "0";
        uidStr += String(mfrc522.uid.uidByte[i], HEX);
        if (i != mfrc522.uid.size - 1) uidStr += ":";
      }
      uidStr.toUpperCase();
      Serial.print("Detected UID: ");
      Serial.println(uidStr);

      // show UID for 2 seconds
      showRFIDUID(uidStr);

      // Halt PICC để chuẩn bị lần scan kế tiếp
      mfrc522.PICC_HaltA();
      mfrc522.PCD_StopCrypto1();
    }
    vTaskDelay(pdMS_TO_TICKS(100));
  }
}

// ---- Setup & Loop ----
void setup() {
  Serial.begin(115200);
  // I2C cho OLED
  Wire.begin(21, 22); // SDA=21, SCL=22

  // init display
  if (!display.begin(SSD1306_SWITCHCAPVCC, 0x3C)) {
    Serial.println("Không tìm thấy màn hình OLED!");
    for (;;) ; // dừng
  }
  display.clearDisplay();
  display.setTextSize(1);
  display.setTextColor(WHITE);
  display.setCursor(5, 5);
  display.print("Nhap ma khoa:");
  display.display();

  // init SPI cho RC522 theo pins đã cung cấp
  // SPI.begin(SCK, MISO, MOSI, SS) trên ESP32
  SPI.begin(SCK_PIN, MISO_PIN, MOSI_PIN, SS_PIN);
  mfrc522.PCD_Init();
  Serial.println("RFID reader initialized.");

  // tạo semaphore
  displayMutex = xSemaphoreCreateMutex();
  inputMutex = xSemaphoreCreateMutex();
  if (displayMutex == NULL || inputMutex == NULL) {
    Serial.println("Failed to create semaphores!");
    for (;;) ;
  }

  // Tạo các task FreeRTOS
  xTaskCreatePinnedToCore(keypadTask, "KeypadTask", 4096, NULL, 1, NULL, 1);
  xTaskCreatePinnedToCore(rfidTask, "RFIDTask", 4096, NULL, 1, NULL, 1);
}

void loop() {
  // Không dùng loop() để logic chính, đã chuyển qua FreeRTOS tasks.
  vTaskDelay(pdMS_TO_TICKS(1000));
}
