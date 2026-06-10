#include <BluetoothSerial.h>
#include <ESP32Servo.h>
#include <esp_now.h>
#include <WiFi.h>          
#include "esp_coexist.h"      

// I2C LCD Libraries
#include <Wire.h>
#include <LiquidCrystal_I2C.h>

LiquidCrystal_I2C lcd(0x27, 16, 2); 

// Bluetooth and Hardware
BluetoothSerial SerialBT;
const int LED_PIN = 2;
const int SMALL_SERVO_PIN = 13;
const int LARGE_SERVO_PIN = 14;

Servo small_servo;
Servo large_servo;

bool is_small_servo_upright = true;
bool is_large_servo_upright = true;
int score = 0;

struct Timestamps {
    unsigned long lifter_start_time = 0;
    unsigned long lifter_stop_time = 0;
    unsigned long shooter_time = 0;
};

volatile Timestamps received_times;
volatile unsigned long ball_deploy_time = 0;

enum Position { SORTER, LEFT_SORTER, LEFT_SHOOTER, LIFTER };
Position ball_position = SORTER;
volatile bool is_position_changed = false;

void updateLCDScore() {
    lcd.setCursor(7, 0);   
    lcd.print("         "); 
    lcd.setCursor(7, 0);   
    lcd.print(score);     
}

// called everytime data is recieved from esp1
void on_data_received(const esp_now_recv_info *esp_now_info, const uint8_t *incoming_data, int data_len) 
{
    memcpy((void*)&received_times, incoming_data, sizeof(received_times));
    is_position_changed = true;
}

void setup() 
{
    Serial.begin(115200);
    
    lcd.init();
    lcd.backlight();
    lcd.setCursor(0, 0);
    lcd.print("Score: 0"); 
    
    // Initialize Bluetooth 
    SerialBT.begin("ESP32_LED");
    
    pinMode(LED_PIN, OUTPUT);
    digitalWrite(LED_PIN, LOW);

    small_servo.attach(SMALL_SERVO_PIN);
    large_servo.attach(LARGE_SERVO_PIN);
    small_servo.write(0);
    large_servo.write(0);

    // Initialize Wi-Fi 
    WiFi.mode(WIFI_STA);
    WiFi.disconnect(); 
    
    // Prioritise Bluetooth
    esp_coex_preference_set(ESP_COEX_PREFER_BT);

    // Initialize ESP-NOW
    if (esp_now_init() != ESP_OK) {
        Serial.println("ESP-NOW Init Failed");
        return;
    }
    
    esp_now_peer_info_t peerInfo = {};
    uint8_t senderMac[] = {0x84, 0x1F, 0xE8, 0x1B, 0xBF, 0x00}; 
    memcpy(peerInfo.peer_addr, senderMac, 6);
    peerInfo.channel = 1;  
    peerInfo.encrypt = false;
    esp_now_add_peer(&peerInfo);

    esp_now_register_recv_cb(on_data_received);
}

void loop() 
{
    // Process incoming Bluetooth commands from the App
    if (SerialBT.available() >= 2) 
    {
        char cmd = SerialBT.read();
        bool is_correct = (SerialBT.read() == '1');
        Serial.println(cmd);
        
        if (is_correct) 
        {
            if (cmd == 'W') 
            {
                small_servo.write(is_small_servo_upright ? 180 : 0);
                is_small_servo_upright = !is_small_servo_upright;
                
                ball_deploy_time = millis();
                
                score++;
                updateLCDScore(); 
                
                is_position_changed = true;
            }
            else if (cmd == 'Y') 
            {
                large_servo.write(is_large_servo_upright ? 180 : 0);
                is_large_servo_upright = !is_large_servo_upright;
                
                ball_deploy_time = millis();
                
                score++;
                updateLCDScore(); 
                
                is_position_changed = true;
            }
            else if (cmd == 'P') 
            {
                SerialBT.println((String)"POS_" + ball_position);
            }
        } 
        else 
        {   
            if (score > 0){
                score--;
                updateLCDScore(); 
            }
        }
    }

    // Calculate Position
    if (is_position_changed)
    {
        is_position_changed = false;
        
        if (!(received_times.shooter_time || 
              received_times.lifter_start_time || 
              received_times.lifter_stop_time || 
              ball_deploy_time))
        {
            ball_position = SORTER; 
        } 
        else 
        {
            unsigned long max_time = max(received_times.lifter_start_time, 
                                     max(received_times.lifter_stop_time, 
                                     max(received_times.shooter_time, ball_deploy_time)));

            if (max_time == received_times.lifter_start_time) {
                ball_position = LIFTER;
            } else if (max_time == received_times.lifter_stop_time) {
                ball_position = SORTER;
            } else if (max_time == received_times.shooter_time) {
                ball_position = LEFT_SHOOTER;
            } else if (max_time == ball_deploy_time) {
                ball_position = LEFT_SORTER;
            }
        }
        Serial.println(ball_position);
        SerialBT.println((String)"POS_" + ball_position);
    }
}