/*
 * Mã nguồn tích hợp Keypad và RFID trên ESP32
 * Sử dụng FreeRTOS để chạy đồng thời hai tác vụ
 * và Mutex để bảo vệ tài nguyên màn hình OLED.
 */

// --- THƯ VIỆN ---
#include <Wire.h>
#include <Keypad.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>
#include <SPI.h>
#include <MFRC522.h>
// FreeRTOS đã được tích hợp sẵn trong ESP32 Core

// --- CẤU HÌNH OLED ---
#define SCREEN_WIDTH 128
#define SCREEN_HEIGHT 64
#define OLED_RESET -1
Adafruit_SSD1306 display(SCREEN_WIDTH, SCREEN_HEIGHT, &Wire, OLED_RESET);

// --- CẤU HÌNH KEYPAD (Giữ nguyên) ---
const byte ROWS = 4;
const byte COLS = 4;
const int MAX_PASS_SIZE = 8;
String inputString = "";
String correct_password = "123456";
int offset = 0;
boolean lock = true;

char keys[ROWS][COLS] = {
  {'1', '2', '3', 'A'},
  {'4', '5', '6', 'B'},
  {'7', '8', '9', 'C'},
  {'*', '0', '#', 'D'}
};
byte rowPins[ROWS] = {14, 27, 26, 25};
byte colPins[COLS] = {33, 32, 18, 19};
Keypad keypad = Keypad(makeKeymap(keys), rowPins, colPins, ROWS, COLS);

// --- CẤU HÌNH RFID (Theo yêu cầu) ---
#define RST_PIN     4   // D4
#define SS_PIN      5   // D5

// Chân SPI tùy chỉnh
#define SCK_PIN     15  // D15
#define MISO_PIN    2   // D2 (Cẩn thận với chân này!)
#define MOSI_PIN    23  // D23

// Khởi tạo đối tượng MFRC522
MFRC522 mfrc522(SS_PIN, RST_PIN);  
// Khởi tạo đối tượng SPI tùy chỉnh
SPIClass rfidSPI(HSPI); // Sử dụng HSPI (bus SPI thứ 2) để tránh xung đột

// --- BIẾN TOÀN CỤC CHO FreeRTOS ---
SemaphoreHandle_t displayMutex; // Khóa (mutex) để bảo vệ màn hình

// --- CÁC HÀM XỬ LÝ (TỪ CODE CŨ) ---
// Hàm này giờ sẽ cần được bảo vệ bởi Mutex
void print_center(String string) {
  display.clearDisplay();
  int16_t x1, y1;
  uint16_t w, h;
  display.getTextBounds(string, 0, 0, &x1, &y1, &w, &h);
  int centerX = (SCREEN_WIDTH - w) / 2 ;
  int centerY = (SCREEN_HEIGHT - h) / 2;

  display.setCursor(centerX, centerY);
  display.setTextSize(1);
  display.print(string);
  display.display();
}

void unlock() {
  lock = false;
  // Báo cho Task Keypad biết là đã mở khóa
  // Việc hiển thị sẽ do chính Task Keypad thực hiện
  // (Hoặc chúng ta có thể bảo vệ print_center bằng Mutex)
  
  // Lấy Mutex trước khi dùng màn hình
  if (xSemaphoreTake(displayMutex, portMAX_DELAY) == pdTRUE) {
    print_center("Mo khoa thanh cong!");
    // Giữ Mutex trong 3 giây
    vTaskDelay(3000 / portTICK_PERIOD_MS); // Dùng vTaskDelay thay cho delay()
    // Nhả Mutex
    xSemaphoreGive(displayMutex);
  }

  // Tự động khóa lại
  lock = true;
  inputString = "";
  offset = 0;
}

// --- TÁC VỤ 1: XỬ LÝ BÀN PHÍM ---
void taskKeypad(void *pvParameters) {
  Serial.println("Task Keypad da khoi dong.");
  // Hiển thị màn hình chờ ban đầu
  if (xSemaphoreTake(displayMutex, portMAX_DELAY) == pdTRUE) {
    display.clearDisplay();
    display.setTextSize(1);
    display.setTextColor(WHITE);
    display.setCursor(5, 5);
    display.print("Nhap ma khoa:");
    display.display();
    xSemaphoreGive(displayMutex);
  }
  
  for (;;) { // Vòng lặp vĩnh viễn của Task
    char key = keypad.getKey();

    if (key) {
      Serial.print("Phim nhan: ");
      Serial.println(key);
      if (inputString.length() < MAX_PASS_SIZE)
        offset++;
      switch (key) {
        case '#':
          inputString = ""; // Xóa toàn bộ
          offset = 0;
          break;
        case '*':
          if (inputString.length() > 0) {
            inputString.remove(inputString.length() - 1); // Xóa 1 ký tự cuối
            offset--;
          }
          break;
        default:
          if (inputString.length() < MAX_PASS_SIZE)
            inputString += key;
          if (inputString == correct_password) {
            unlock(); // Hàm unlock() đã được sửa để dùng Mutex
          }
          break;
      }

      // Cập nhật hiển thị NẾU cửa BỊ KHÓA
      if (lock) {
        // Yêu cầu quyền sử dụng màn hình
        if (xSemaphoreTake(displayMutex, portMAX_DELAY) == pdTRUE) {
          display.clearDisplay(); // Xóa toàn bộ màn hình trước khi vẽ mới
          display.setTextSize(1);
          display.setTextColor(WHITE);
          display.setCursor(5, 5);
          display.print("Nhap ma khoa:");
          if (offset < 0)  offset = 0;

          int16_t x1, y1;
          uint16_t w, h;
          display.getTextBounds(inputString, 0, 0, &x1, &y1, &w, &h);
          int centerX = (SCREEN_WIDTH - w - offset * 5) / 2 ;
          int centerY = (SCREEN_HEIGHT - h) / 2 ; // +10 để tránh đè dòng tiêu đề

          display.setCursor(centerX, centerY);
          display.setTextSize(2);
          display.print(inputString);
          display.display();

          // Nhả quyền sử dụng màn hình
          xSemaphoreGive(displayMutex);
        }
      }
    }
    
    vTaskDelay(20 / portTICK_PERIOD_MS); // Quan trọng: Tạm nghỉ để Task khác chạy
  }
}

// --- TÁC VỤ 2: XỬ LÝ RFID ---
void taskRfid(void *pvParameters) {
  Serial.println("Task RFID da khoi dong.");
  for (;;) { // Vòng lặp vĩnh viễn của Task
    
    // 1. Kiểm tra xem có thẻ mới không
    if (mfrc522.PICC_IsNewCardPresent() && mfrc522.PICC_ReadCardSerial()) {
      
      String cardID = "";
      // 2. Lấy ID (UID) từ thẻ
      for (byte i = 0; i < mfrc522.uid.size; i++) {
        if (mfrc522.uid.uidByte[i] < 0x10) {
          cardID += "0";
        }
        cardID += String(mfrc522.uid.uidByte[i], HEX);
      }
      cardID.toUpperCase();
      Serial.print("Da quet the! ID: ");
      Serial.println(cardID);

      // 3. Hiển thị ID lên màn hình (YÊU CẦU MUTEX)
      if (xSemaphoreTake(displayMutex, portMAX_DELAY) == pdTRUE) {
        display.clearDisplay();
        display.setCursor(0, 0);
        display.setTextSize(2);
        display.println("ID THE:");
        display.setTextSize(1);
        display.println(cardID);
        display.display();
        
        // Giữ Mutex và hiển thị ID trong 2 giây
        vTaskDelay(2000 / portTICK_PERIOD_MS);
        
        // Nhả Mutex
        xSemaphoreGive(displayMutex);
        
        // Sau khi nhả Mutex, Task Keypad sẽ tự động vẽ lại màn hình "Nhap ma khoa"
      }
      
      // Yêu cầu thẻ dừng lại
      mfrc522.PICC_HaltA();
    }
    
    vTaskDelay(50 / portTICK_PERIOD_MS); // Tạm nghỉ 50ms giữa các lần quét
  }
}

// --- HÀM SETUP CHÍNH ---
void setup() {
  Serial.begin(115200);
  Wire.begin(21, 22); // SDA=21, SCL=22

  // Khởi động OLED
  if (!display.begin(SSD1306_SWITCHCAPVCC, 0x3C)) {
    Serial.println("Không tìm thấy màn hình OLED!");
    for (;;);
  }
  display.clearDisplay();
  display.setTextSize(1);
  display.setTextColor(WHITE);
  display.setCursor(0,0);
  display.println("He thong dang khoi dong...");
  display.display();
  delay(1000);

  // Khởi động SPI bus với các chân tùy chỉnh
  // SPI.begin(SCK, MISO, MOSI, SS);
  // Do bạn dùng chân non-standard, ta dùng bus HSPI
  rfidSPI.begin(SCK_PIN, MISO_PIN, MOSI_PIN, SS_PIN);
  
  // Khởi động MFRC522 với đối tượng SPI tùy chỉnh
  mfrc522.PCD_Init(SS_PIN, RST_PIN, &rfidSPI); 
  
  Serial.println("Da khoi dong RFID.");
  
  // Tạo Mutex để bảo vệ màn hình
  displayMutex = xSemaphoreCreateMutex();
  if (displayMutex == NULL) {
    Serial.println("Loi: Khong the tao Mutex!");
    for(;;);
  }

  // Tạo các Task
  // xTaskCreate( ten_ham_task, "Ten debug", kich_thuoc_stack, tham_so, do_uu_tien, NULL )
  xTaskCreate(
    taskKeypad,
    "Task Bàn phím",
    4096, // Kích thước Stack cho task này (cần khá lớn vì dùng thư viện GFX)
    NULL,
    1,    // Ưu tiên 1 (thấp)
    NULL);

  xTaskCreate(
    taskRfid,
    "Task RFID",
    4096, // Kích thước Stack
    NULL,
    1,    // Ưu tiên 1 (thấp)
    NULL);
    
  Serial.println("Da tao 2 Task. He thong san sang.");
}

void loop() {
  // HOÀN TOÀN KHÔNG DÙNG ĐẾN
  // FreeRTOS sẽ chạy các Task đã tạo, hàm loop() này sẽ bị bỏ qua.
  vTaskDelete(NULL); // Tự xóa task của `loop()`
}