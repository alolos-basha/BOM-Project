#include <esp_now.h>
#include <esp_wifi.h>

uint8_t ESP2_ADRESS[] = {0x80, 0xF3, 0xDA, 0x62, 0x42, 0x34}; //80:F3:DA:62:42:34
esp_now_peer_info_t esp2_peer_info;

struct Timestamps {
    unsigned long lifter_start_time = 0;
    unsigned long lifter_stop_time = 0;
    unsigned long shooter_time = 0;
};

Timestamps detection_times;

// Ultrasonic 1 (start lifter)
const int LIFTER_START_TRIG_PIN = 32;
const int LIFTER_START_ECHO_PIN = 33;

// Ultrasonic 2 (stop lifter)
const int LIFTER_STOP_TRIG_PIN = 18;
const int LIFTER_STOP_ECHO_PIN = 19;

// Ultrasonic 3 (shooter trigger)
const int SHOOTER_TRIG_PIN = 13;
const int SHOOTER_ECHO_PIN = 14;
bool is_shooter_triggered = false;

// Output pulse pin
const int SHOOTER_PIN = 23;

// Motor

const int ENA = 25;
const int IN1 = 26;
const int IN2 = 27;

const int PWM_FREQ = 20000;
const int PWM_RESOLUTION = 8;

bool is_motor_running = false;
bool is_send_message = false;



float read_distance(int trig, int echo)
{
    digitalWrite(trig, LOW);
    delayMicroseconds(2);
    digitalWrite(trig, HIGH);
    delayMicroseconds(10);
    digitalWrite(trig, LOW);

    long duration = pulseIn(echo, HIGH, 3000);
    float distance = duration * 0.034 / 2;
    return distance;
}

void turn_motor_on()
{
    digitalWrite(IN1, HIGH);
    digitalWrite(IN2, LOW);
    ledcWrite(ENA, 153);
}

void turn_motor_off()
{
    ledcWrite(ENA, 0);
}

void activate_shooter()
{
    digitalWrite(SHOOTER_PIN, HIGH);
    delay(50);              // short pulse
    digitalWrite(SHOOTER_PIN, LOW);
}

void setup()
{
    Serial.begin(115200);
    pinMode(IN1, OUTPUT);
    pinMode(IN2, OUTPUT);


    pinMode(LIFTER_START_TRIG_PIN, OUTPUT);
    pinMode(LIFTER_START_ECHO_PIN, INPUT);

    pinMode(LIFTER_STOP_TRIG_PIN, OUTPUT);
    pinMode(LIFTER_STOP_ECHO_PIN, INPUT);

    pinMode(SHOOTER_TRIG_PIN, OUTPUT);
    pinMode(SHOOTER_ECHO_PIN, INPUT);

    pinMode(SHOOTER_PIN, OUTPUT);
    digitalWrite(SHOOTER_PIN, LOW);

    ledcAttach(ENA, PWM_FREQ, PWM_RESOLUTION);

    turn_motor_off();

    // ESP-NOW & WiFi Setup
    esp_netif_init();
    esp_event_loop_create_default();
    wifi_init_config_t cfg = WIFI_INIT_CONFIG_DEFAULT();
    esp_wifi_init(&cfg);
    esp_wifi_set_mode(WIFI_MODE_STA);
    esp_wifi_start();

    // Force the channel to 1
    esp_wifi_set_channel(1, WIFI_SECOND_CHAN_NONE);

    if (esp_now_init() != ESP_OK) {
        Serial.println("Error initializing ESP-NOW");
        return;
    }

    memcpy(esp2_peer_info.peer_addr, ESP2_ADRESS, 6);
    esp2_peer_info.channel = 1;
    esp2_peer_info.encrypt = false;

    if (esp_now_add_peer(&esp2_peer_info) != ESP_OK) {
        Serial.println("Failed to add peer");
    }
}


void loop()
{
    float lifter_start_dist = read_distance(LIFTER_START_TRIG_PIN, LIFTER_START_ECHO_PIN);
    float lifter_stop_dist  = read_distance(LIFTER_STOP_TRIG_PIN, LIFTER_STOP_ECHO_PIN);

    float shooter_dist = read_distance(SHOOTER_TRIG_PIN, SHOOTER_ECHO_PIN);


    if (!is_motor_running && lifter_start_dist > 0 && lifter_start_dist < 10)
    {
        turn_motor_on();
        is_motor_running = true;
        detection_times.lifter_start_time = millis();
        is_send_message = true;
    }

    if (is_motor_running && lifter_stop_dist > 0 && lifter_stop_dist < 10)
    {
        turn_motor_off();
        is_motor_running = false;
        detection_times.lifter_stop_time = millis();
        is_send_message = true;
    }


    if (!is_shooter_triggered && shooter_dist > 0 && shooter_dist < 10)
    {
        is_shooter_triggered = true;
        detection_times.shooter_time = millis();
        is_send_message = true;
        is_motor_running = false;
    }
    if (is_shooter_triggered){
        if ((millis() - detection_times.shooter_time) >= 3000){
            activate_shooter();
            is_shooter_triggered = false;
        }
    }
    if (is_send_message){
        is_send_message = false;

        for (int i = 0 ; i < 3; i++){
            esp_now_send(ESP2_ADRESS, (uint8_t *)&detection_times, sizeof(detection_times));
            delay(3);
        }
    }
    delay(50);
}