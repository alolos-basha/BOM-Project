import android.bluetooth.BluetoothAdapter;
import android.bluetooth.BluetoothDevice;
import android.bluetooth.BluetoothSocket;
import android.media.MediaPlayer;
import android.content.res.AssetFileDescriptor;
import android.content.Context;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.UUID;
import java.util.Set;

//  Bluetooth & Stream Variables 
BluetoothSocket btSocket = null;
OutputStream outStream = null;
InputStream inStream = null;
volatile boolean connected = false;
volatile boolean isReconnecting = false;
int disconnectTime = 0;
volatile String status = ""; 
int lastAppHeartbeat = 0;

//  Audio 
MediaPlayer correctSound;
MediaPlayer wrongSound;

//  Main variables
volatile int currentPosition = -1;
float[] sysX = new float[3];
float[] sysY = new float[3];
String[] sysNames = {"SORTER STATION", "SHOOTER SYSTEM", "LIFTER ELEVATOR"};

//  Images
PImage imgSorter, imgShooter, imgLifter;
PImage imgLargeBall, imgSmallBall;
PImage imgCatWipe, imgStartBg, imgGameBgLower;
boolean usePNGs = false;
PFont customArcadeFont;

//  Game Logic & State 
boolean awaitingChoice = false;
String targetBallType = "Large";    
String feedbackMessage = "";   
int flashTimer = 0;
color flashColor;
int shakeTimer = 0;
boolean needsNewBall = true;
int feedbackTimer = 0;

//  Animation variables
float ballVisualX = 0;
float ballVisualY = 0;
boolean ballInitialized = false;
float popupScale = 0.0;

//  Transition Variables (for correct answers)
boolean isCatWiping = false;
int catWipeTimer = 0;
int catWipeDuration = 30; 
float maxCatH; 
float centerX; 
float[] keyPosProgress = {0.0, 0.45, 0.45, 0.90, 1.0}; 
float[] keyX; 
float[] keyScale = { 0, 1.5, 1.5, 0, 0.0 }; 
float[] keyOpacity = { 255, 255, 255, 255, 255 }; 

void setup() {
  fullScreen();
  orientation(PORTRAIT);
  
  // Font Initialization 
  try {
    customArcadeFont = loadFont("custom_font.vlw");
    if (customArcadeFont == null) throw new Exception();
  } catch (Exception e) {
    customArcadeFont = createFont("SansSerif-Bold", 48, true);
  }
  textFont(customArcadeFont);
  
  // Android Permissions
  requestPermission("android.permission.ACCESS_FINE_LOCATION");
  requestPermission("android.permission.BLUETOOTH_CONNECT");
  requestPermission("android.permission.BLUETOOTH_SCAN");
  
  // Audio init
  try {
    Context ctx = getActivity(); 
    correctSound = new MediaPlayer();
    AssetFileDescriptor afd1 = ctx.getAssets().openFd("correct.mp3");
    correctSound.setDataSource(afd1.getFileDescriptor(), afd1.getStartOffset(), afd1.getLength());
    correctSound.prepare();
    
    wrongSound = new MediaPlayer();
    AssetFileDescriptor afd2 = ctx.getAssets().openFd("wrong.mp3");
    wrongSound.setDataSource(afd2.getFileDescriptor(), afd2.getStartOffset(), afd2.getLength());
    wrongSound.prepare();
  } catch (Exception e) {}
  
  // Coordinates
  sysX[0] = width * 0.50;  sysY[0] = height * 0.23; 
  sysX[1] = width * 0.78;  sysY[1] = height * 0.48; 
  sysX[2] = width * 0.22;  sysY[2] = height * 0.48; 
  
  // Loading pics
  try {
    imgSorter = loadImage("sorter.png");
    imgShooter = loadImage("shooter.png");
    imgLifter = loadImage("lifter.png");
    imgLargeBall = loadImage("large_ball.png");
    imgSmallBall = loadImage("small_ball.png");
    imgCatWipe = loadImage("cat_wipe.png"); 
    imgStartBg = loadImage("start_bg.png"); 
    imgGameBgLower = loadImage("game_bg_lower.png"); 

    if (imgSorter != null) usePNGs = true;
    
    // Setup Wipe Animation Limits
    maxCatH = height * 0.8; 
    centerX = width / 2;
    keyX = new float[] { -width * 0.6, centerX, centerX, width * 1.6, width * 1.6 };
  } catch (Exception e) {}
}

void draw() {
  background(30, 50, 90); 
  
  // Error Shake Effect
  pushMatrix();
  if (shakeTimer > 0) {
    translate(random(-10, 10), random(-10, 10)); 
    shakeTimer--;
  }

  // View Router
  if (!connected && !isReconnecting) drawStartScreen();
  else drawGameScreen();
  
  popMatrix();

  // Screen Flash Overlay
  if (flashTimer > 0) {
    rectMode(CORNER);
    noStroke();
    fill(red(flashColor), green(flashColor), blue(flashColor), map(flashTimer, 0, 30, 0, 120));
    rect(0, 0, width, height);
    flashTimer--;
  }
  
  // Cat Wipe Transition
  if (isCatWiping && imgCatWipe != null) {
    catWipeTimer++;
    if (catWipeTimer >= catWipeDuration) {
      isCatWiping = false; 
    } else {
      float progress = map(catWipeTimer, 0, catWipeDuration, 0, 1);
      int k = 0;
      for (int i = 0; i < keyPosProgress.length - 1; i++) {
        if (progress >= keyPosProgress[i] && progress <= keyPosProgress[i+1]) { k = i; break; }
      }
      
      float subProgress = map(progress, keyPosProgress[k], keyPosProgress[k+1], 0, 1);
      float currentX = lerp(keyX[k], keyX[k+1], subProgress);
      float currentScale = lerp(keyScale[k], keyScale[k+1], subProgress);
      float currentOpacity = lerp(keyOpacity[k], keyOpacity[k+1], subProgress);
      
      float catH = maxCatH * currentScale; 
      float catW = (float)imgCatWipe.width / imgCatWipe.height * catH;
      
      imageMode(CENTER);
      tint(255, currentOpacity); 
      image(imgCatWipe, currentX, height / 2, catW, catH);
      noTint(); 
    }
  }
  
  // Reconnection Warning Overlay
  if (isReconnecting && (millis() - disconnectTime > 3000)) {
    rectMode(CORNER);
    fill(20, 35, 70, 230);
    rect(0, 0, width, height);
    
    textSize(54); 
    textAlign(CENTER, CENTER);
    drawOutlinedText("Connection Lost!", width/2, height/2 - 80, color(225, 135, 45));
    
    int timeRemaining = 20 - ((millis() - disconnectTime) / 1000);
    if (timeRemaining <= 0) {
      timeRemaining = 0;
      closeConnection(); 
    }
    
    textSize(38); 
    drawOutlinedText("Reconnecting... " + timeRemaining + "s", width/2, height/2 + 60, color(225, 135, 45));
  }
}

//  Text Utility 
void drawOutlinedText(String str, float x, float y, color textColor) {
  fill(0); 
  float off1 = 2.0; 
  float off2 = 4.0; 
  
  // Inner Stroke
  text(str, x - off1, y - off1); text(str, x, y - off1); text(str, x + off1, y - off1);
  text(str, x - off1, y);                                text(str, x + off1, y);
  text(str, x - off1, y + off1); text(str, x, y + off1); text(str, x + off1, y + off1);
  
  // Outer Stroke
  text(str, x - off2, y - off2); text(str, x, y - off2); text(str, x + off2, y - off2);
  text(str, x - off2, y);                                text(str, x + off2, y);
  text(str, x - off2, y + off2); text(str, x, y + off2); text(str, x + off2, y + off2);
  
  fill(textColor);
  text(str, x, y);
}

//  Image Utility 
void drawProportionalImage(PImage img, float x, float y, float maxDim) {
  if (img == null) return;
  float w = img.width;
  float h = img.height;
  float scaleFactor = maxDim / max(w, h);
  imageMode(CENTER);
  image(img, x, y, w * scaleFactor, h * scaleFactor);
}

//  Screens 
void drawStartScreen() {
  if (imgStartBg != null) {
    float scale = max((float) width / imgStartBg.width, (float) height / imgStartBg.height);
    imageMode(CENTER);
    image(imgStartBg, width / 2, height / 2, imgStartBg.width * scale, imgStartBg.height * scale);
  }

  textAlign(CENTER, CENTER);
  textSize(85); 
  drawOutlinedText("BALL\nPURRFECTION", width / 2, height * 0.32, color(225, 135, 45)); 
  
  if (status.length() > 0) {
    textSize(32); 
    drawOutlinedText(status, width / 2, height * 0.55, color(225, 135, 45));
  }

  rectMode(CENTER);
  boolean overConnect = checkRectBounds(width/2, height * 0.62, 440, 110);
  fill(overConnect && mousePressed ? color(10, 25, 60) : color(20, 45, 90));
  stroke(255);
  strokeWeight(4);
  rect(width/2, height * 0.62, overConnect && mousePressed ? 420 : 440, overConnect && mousePressed ? 100 : 110, 25);
  
  fill(255); 
  textSize(38); 
  text("START GAME", width / 2, height * 0.62); 
}

void drawGameScreen() {
  if (imgGameBgLower != null) {
    float lowerH = height * 0.85f;
    float scale = max((float) width / imgGameBgLower.width, lowerH / imgGameBgLower.height);
    pushMatrix();
    translate(width / 2, height * 0.15f + lowerH / 2);
    imageMode(CENTER);
    image(imgGameBgLower, 0, 0, imgGameBgLower.width * scale, imgGameBgLower.height * scale);
    popMatrix();
  }

  // App Header
  noStroke();
  fill(10, 15, 30);
  rectMode(CORNER);
  rect(0, 0, width, height * 0.15); 
  
  textAlign(CENTER, CENTER);
  textSize(55); 
  drawOutlinedText("BALL PURRFECTION", width / 2, height * 0.05, color(225, 135, 45));

  // "take a Break" Button
  boolean overDisc = checkRectBounds(width/2, height * 0.115, 280, 60);
  fill(overDisc && mousePressed ? color(10, 25, 60) : color(20, 45, 90));
  stroke(255);
  strokeWeight(4); 
  rectMode(CENTER);
  rect(width/2, height * 0.115, 280, 60, 20);
  fill(255); 
  textSize(22); 
  text("Take a Break", width/2, height * 0.115);

  // Ball Target Vector Math
  float targetX = sysX[0];
  float targetY = sysY[0];
  
  if (currentPosition == 0 || currentPosition == 3) {
    targetX = sysX[currentPosition == 0 ? 0 : 2]; targetY = sysY[currentPosition == 0 ? 0 : 2];
  } else if (currentPosition == 1 || currentPosition == 2) {
    int startIdx = currentPosition - 1;
    float[] bPos = getAnimatedPathPos(sysX[startIdx], sysY[startIdx], sysX[startIdx+1], sysY[startIdx+1]);
    targetX = bPos[0]; targetY = bPos[1];
  }
  
  // Ball Movement Engine god bless purrfection
  if (!ballInitialized) {
    ballVisualX = targetX; ballVisualY = targetY; ballInitialized = true;
  } else {
    if (currentPosition == 1 || currentPosition == 2) {
      ballVisualX = targetX; ballVisualY = targetY;
    } else {
      float distance = dist(ballVisualX, ballVisualY, targetX, targetY);
      float travelSpeed = 45.0f; 
      if (distance > travelSpeed) {
        ballVisualX += ((targetX - ballVisualX) / distance) * travelSpeed;
        ballVisualY += ((targetY - ballVisualY) / distance) * travelSpeed;
      } else {
        ballVisualX = targetX; ballVisualY = targetY;
      }
    }
  }

  // Draw Static Paths
  stroke(15, 30, 65);
  strokeWeight(12);
  line(sysX[0], sysY[0], sysX[1], sysY[1]);
  line(sysX[1], sysY[1], sysX[2], sysY[2]);
  line(sysX[2], sysY[2], sysX[0], sysY[0]); 

  // Draw Animated arrows
  if (currentPosition == 1) drawAnimatedArrowOnly(sysX[0], sysY[0], sysX[1], sysY[1]);
  else if (currentPosition == 2) drawAnimatedArrowOnly(sysX[1], sysY[1], sysX[2], sysY[2]);

  // drawimg images
  for (int i = 0; i < 3; i++) {
    if (usePNGs) {
      if (i == 0) drawProportionalImage(imgSorter, sysX[i], sysY[i], 180);
      else if (i == 1) drawProportionalImage(imgShooter, sysX[i], sysY[i], 180);
      else if (i == 2) drawProportionalImage(imgLifter, sysX[i], sysY[i], 180);
    } else {
      noStroke(); fill(20, 45, 90); ellipse(sysX[i], sysY[i], 160, 160);
      fill(255); textSize(18); text(sysNames[i], sysX[i], sysY[i]); 
    }
  }

  drawBallAt(ballVisualX, ballVisualY);
  // feedback message handler
  float feedbackY = height * 0.86;
  if (feedbackTimer > 0) {
    feedbackTimer--;
    textSize(44);
    drawOutlinedText(feedbackMessage, width / 2, feedbackY, color(225, 135, 45));
    
    if (feedbackTimer == 0 && currentPosition == 0) {
      awaitingChoice = true;
      feedbackMessage = "";
    }
  } else if (awaitingChoice) {
    popupScale = lerp(popupScale, 1.0f, 0.16f);
    if (popupScale > 0.05) {
       pushMatrix();
       translate(width/2, feedbackY);
       scale(popupScale);
       rectMode(CENTER);
       
       fill(10, 15, 30); 
       stroke(30, 45, 80);
       strokeWeight(4); 
       rect(0, 0, width - 40, height * 0.28f, 40);
       
       fill(255); textSize(34);
       text("Choose the " + targetBallType + " ball!", 0, -height * 0.09f);
       
       // Large Button Overlay
       float btnLargeX = -width * 0.20f; float btnLargeY = height * 0.02f;
       fill(255, 193, 7); noStroke(); ellipse(btnLargeX, btnLargeY, 140, 140);
       fill(255, 230, 150); ellipse(btnLargeX - 20, btnLargeY - 20, 35, 35);
       fill(255); textSize(28); text("LARGE", btnLargeX, btnLargeY + 105);
       
       // Small Button Overlay
       float btnSmallX = width * 0.20f; float btnSmallY = height * 0.02f;
       fill(255); stroke(140); strokeWeight(2); 
       ellipse(btnSmallX, btnSmallY, 95, 95);
       fill(255); textSize(28); text("SMALL", btnSmallX, btnSmallY + 105);
       popMatrix();
    }
  } else {
    popupScale = lerp(popupScale, 0.0f, 0.16f);
    textSize(44); 
    if (currentPosition == 1 || currentPosition == 2) drawOutlinedText("Ball on its way!", width / 2, feedbackY, color(225, 135, 45));
    else if (currentPosition == 3) drawOutlinedText("Lifting ball...", width / 2, feedbackY, color(225, 135, 45));
  }

  // Socket Keep-Alive Ping
  if (connected && !isReconnecting && (millis() - lastAppHeartbeat > 3000)) {
    lastAppHeartbeat = millis();
    sendStringCommand("P1"); 
  }
}

//  Geometry Helpers 
float[] getAnimatedPathPos(float x1, float y1, float x2, float y2) {
  float d = dist(x1, y1, x2, y2);
  float animLength = (frameCount * 6.0) % d;
  float angle = atan2(y2 - y1, x2 - x1);
  return new float[]{ x1 + cos(angle) * animLength, y1 + sin(angle) * animLength };
}

void drawAnimatedArrowOnly(float x1, float y1, float x2, float y2) {
  float[] pos = getAnimatedPathPos(x1, y1, x2, y2);
  float angle = atan2(y2 - y1, x2 - x1);
  
  stroke(225, 135, 45);
  strokeWeight(12);
  line(x1, y1, pos[0], pos[1]);
  
  pushMatrix();
  translate(pos[0], pos[1]);
  rotate(angle);
  fill(225, 135, 45);
  noStroke();
  triangle(0, 0, -25, -15, -25, 15);
  popMatrix();
}

void drawBallAt(float x, float y) {
  if (usePNGs) {
    if (targetBallType.equals("Small")) drawProportionalImage(imgSmallBall, x, y, 75);
    else drawProportionalImage(imgLargeBall, x, y, 110);
  } else {
    if (targetBallType.equals("Small")) {
      fill(255); stroke(150); strokeWeight(4); ellipse(x, y, 70, 70); 
    } else {
      fill(255, 193, 7); noStroke(); ellipse(x, y, 100, 100); 
    }
  }
}

//  Interaction Logic 
void triggerSortingChallenge() {
  if (needsNewBall) {
    targetBallType = (random(1.0) < 0.5) ? "Large" : "Small";
    needsNewBall = false;
  }
  awaitingChoice = true;
  feedbackMessage = "";
}

boolean checkRectBounds(float x, float y, float w, float h) {
  return (mouseX > x - w/2 && mouseX < x + w/2 && mouseY > y - h/2 && mouseY < y + h/2);
}

void mousePressed() {
  if (!connected) {
    if (checkRectBounds(width/2, height * 0.62, 440, 110)) {
      status = "Connecting...";
      thread("connectNativeBluetooth"); 
    }
    return;
  }
  
  if (isReconnecting) return;

  if (checkRectBounds(width/2, height * 0.115, 280, 60)) {
    closeConnection();
    return;
  }

  if (connected && awaitingChoice && popupScale > 0.90) {
    float feedbackY = height * 0.86;
    if (dist(mouseX, mouseY, width * 0.30f, feedbackY + height * 0.02f) < 75) {
      evaluateUserChoice("Large");
    } else if (dist(mouseX, mouseY, width * 0.70f, feedbackY + height * 0.02f) < 50) {
      evaluateUserChoice("Small");
    }
  }
}

void evaluateUserChoice(String chosenType) {
  awaitingChoice = false; 
  feedbackTimer = 120; 

  if (chosenType.equals(targetBallType)) {
    feedbackMessage = "Purrfect Job!";
    flashColor = color(225, 135, 45);
    flashTimer = 30;
    needsNewBall = true; 
    
    if (imgCatWipe != null) { isCatWiping = true; catWipeTimer = 0; }
    if (correctSound != null) { correctSound.seekTo(0); correctSound.start(); }
    sendStringCommand(chosenType.equals("Large") ? "Y1" : "W1");
  } else {
    feedbackMessage = "Try again, you got this!";
    flashColor = color(225, 135, 45); 
    flashTimer = 30;
    shakeTimer = 20;
    
    if (wrongSound != null) { wrongSound.seekTo(0); wrongSound.start(); }
    sendStringCommand(chosenType.equals("Large") ? "Y0" : "W0");
  }
}

//  Bluetooth Hardware Communications 
void connectNativeBluetooth() {
  try {
    BluetoothAdapter adapter = BluetoothAdapter.getDefaultAdapter();
    if (adapter == null) { status = "Bluetooth Missing"; return; }
    
    // Cancels discovery to free up hardware
    adapter.cancelDiscovery();

    Set<BluetoothDevice> pairedDevices = adapter.getBondedDevices();
    BluetoothDevice targetDevice = null;
    
    for (BluetoothDevice device : pairedDevices) {
      String name = device.getName();
      if (name != null && name.toUpperCase().contains("ESP32_LED")) {
        targetDevice = device;
        break;
      }
    }
    if (targetDevice == null) { status = "Device Not Paired"; return; }

    UUID sppUuid = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB");

    // Retry 
    int maxRetries = 3;
    boolean isConnected = false;
    
    for (int i = 0; i < maxRetries; i++) {
      try {
        btSocket = targetDevice.createInsecureRfcommSocketToServiceRecord(sppUuid);
        btSocket.connect(); 
        isConnected = true;
        break; 
      } catch (Exception e) {
        try { Thread.sleep(500); } catch (Exception ex) {} // Wait 500ms before retrying
      }
    }
    
    if (!isConnected) throw new Exception("Failed to connect after retries");

    outStream = btSocket.getOutputStream();
    inStream = btSocket.getInputStream();
    connected = true;
    isReconnecting = false;
    
    // Handshake Validation
    sendStringCommand("P1");
    thread("listenToESP32Stream");
  } catch (Exception e) {
    status = "Connection Failed";
    closeConnection();
  }
}

void listenToESP32Stream() {
  byte[] buffer = new byte[256];
  int bytesRead;
  
  while (connected && !isReconnecting && inStream != null) {
    try {
      bytesRead = inStream.read(buffer);
      if (bytesRead > 0) {
        String incomingStr = new String(buffer, 0, bytesRead).trim().toUpperCase();
        
        if (incomingStr.contains("POS_0")) {
          if (currentPosition != 0) {
            currentPosition = 0;
            triggerSortingChallenge(); 
          }
        } else if (incomingStr.contains("POS_1")) {
          currentPosition = 1; 
          awaitingChoice = false;
          if (feedbackTimer == 0) feedbackMessage = ""; 
        } else if (incomingStr.contains("POS_2")) {
          currentPosition = 2; 
          awaitingChoice = false;
          if (feedbackTimer == 0) feedbackMessage = "";
        } else if (incomingStr.contains("POS_3")) {
          currentPosition = 3; 
          awaitingChoice = false;
          if (feedbackTimer == 0) feedbackMessage = "";
        }
      } else if (bytesRead == -1) { break; }
    } catch (Exception e) { break; } 
  }
  
  if (connected && !isReconnecting) handleDisconnection();
}

void handleDisconnection() {
  isReconnecting = true;
  disconnectTime = millis();
  
  try { if (outStream != null) outStream.close(); } catch(Exception e) {}
  try { if (inStream != null) inStream.close(); } catch(Exception e) {}
  try { if (btSocket != null) btSocket.close(); } catch(Exception e) {}
  outStream = null; inStream = null; btSocket = null;

  thread("reconnectLoop");
}

void reconnectLoop() {
  while (isReconnecting) {
    if (millis() - disconnectTime > 20000) { closeConnection(); break; }
    
    try {
      BluetoothAdapter adapter = BluetoothAdapter.getDefaultAdapter();
      Set<BluetoothDevice> pairedDevices = adapter.getBondedDevices();
      BluetoothDevice targetDevice = null;
      for (BluetoothDevice device : pairedDevices) {
        if (device.getName() != null && device.getName().toUpperCase().contains("ESP32_LED")) {
          targetDevice = device; break;
        }
      }
      
      if (targetDevice != null) {
        UUID sppUuid = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB");
        btSocket = targetDevice.createInsecureRfcommSocketToServiceRecord(sppUuid);
        btSocket.connect();
        
        outStream = btSocket.getOutputStream();
        inStream = btSocket.getInputStream();
        isReconnecting = false;
        
        sendStringCommand("P1");
        thread("listenToESP32Stream");
        break; 
      }
    } catch (Exception e) {
      try { Thread.sleep(300); } catch (Exception ex) {}
    }
  }
}

void sendStringCommand(String data) {
  if (connected && outStream != null) {
    try { outStream.write(data.getBytes()); } 
    catch (Exception e) { }
  }
}

void closeConnection() {
  connected = false;
  isReconnecting = false;
  awaitingChoice = false;
  popupScale = 0.0;
  status = "";
  currentPosition = -1;
  try { if (outStream != null) outStream.close(); } catch(Exception e) {}
  try { if (inStream != null) inStream.close(); } catch(Exception e) {}
  try { if (btSocket != null) btSocket.close(); } catch(Exception e) {}
  outStream = null;
  inStream = null;
  btSocket = null;
}
