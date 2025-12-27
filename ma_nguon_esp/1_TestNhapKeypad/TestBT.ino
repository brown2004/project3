#include <Wire.h>
#include <Keypad.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>
#include <WiFi.h>
#include <PubSubClient.h>

#define SCREEN_WIDTH 128
#define SCREEN_HEIGHT 64
#define OLED_RESET -1
Adafruit_SSD1306 display(SCREEN_WIDTH, SCREEN_HEIGHT, &Wire, OLED_RESET);


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

void print_center(String string){
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

void unlock(){
  lock = false;
  print_center("Mo khoa thanh cong!");
}

void setup() {
  Serial.begin(115200);
  Wire.begin(21, 22); // SDA=21, SCL=22

  if(!display.begin(SSD1306_SWITCHCAPVCC, 0x3C)) {
    Serial.println("Không tìm thấy màn hình OLED!");
    for(;;); // Dừng lại
  }

  display.clearDisplay();
  display.setTextSize(1);
  display.setTextColor(WHITE);
  display.setCursor(5, 5);
  display.print("Nhap ma khoa:");
  display.display(); 
}

void loop() {
  char key = keypad.getKey();
  
  if (key) {
    Serial.print("Phim nhan: ");
    Serial.println(key);
    if(inputString.length() < MAX_PASS_SIZE) 
      offset++;
    switch (key) {
      case '#':
        inputString = ""; // Xóa toàn bộ
        offset = 0;
        break;
      case '*':
        if (inputString.length() > 0){
          inputString.remove(inputString.length() - 1); // Xóa 1 ký tự cuối
          offset--;
        }
          
        break;
      default:
        if (inputString.length() < MAX_PASS_SIZE)
          inputString += key;
        if(inputString == correct_password){
          unlock();
          delay(3000);
          lock = true;
          inputString = "";
          offset = 0;
        }
        break;
    }

    // cap nhat hien thi neu cua bi khoa
    if(lock){
      display.clearDisplay(); // Xóa toàn bộ màn hình trước khi vẽ mới
      display.setTextSize(1);
      display.setTextColor(WHITE);
      display.setCursor(5, 5);
      display.print("Nhap ma khoa:");
      if(offset < 0)  offset = 0;
     
      int16_t x1, y1;
      uint16_t w, h;
      display.getTextBounds(inputString, 0, 0, &x1, &y1, &w, &h);
      int centerX = (SCREEN_WIDTH - w - offset * 5) / 2 ;
      int centerY = (SCREEN_HEIGHT - h) / 2 ; // +10 để tránh đè dòng tiêu đề

      display.setCursor(centerX, centerY);
      display.setTextSize(2);
      display.print(inputString);
      display.display(); 
    }
    
  }
}
