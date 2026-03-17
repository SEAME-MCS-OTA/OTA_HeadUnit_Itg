// library import
#include "TimerOne.h"
#define pin 2
#include <mcp_can.h>
#include <SPI.h>

MCP_CAN CAN0(10);     // Set CS to pin 10

// needed variables
int wheel, counter;
float interval;
unsigned long previousMicros, usInterval, calc;
byte data[8] = {0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07};

void setup()
{
 counter = 0; // setting counter to 0
 interval = 0.5; // 1 second interval
 wheel = 20; // number of encoder disc holes

 calc = 60 / interval; // calculate interval to one minute
 usInterval = interval * 1000000; // convert interval to micro
 // seconds
 wheel = wheel * 2; // number of encoder disc wholes times 2
 pinMode(pin, INPUT_PULLUP); // setting pin 2 as input
 Timer1.initialize(usInterval); // initialize timer with interval time
 attachInterrupt(digitalPinToInterrupt(pin), count, CHANGE);// executes count, if the level on pin 2 changes
 Timer1.attachInterrupt(output); // executes output after interval time
 Serial.begin(115200);

  // Initialize MCP2515 running at 16MHz with a baudrate of 500kb/s and the masks and filters disabled.
  if(CAN0.begin(MCP_ANY, CAN_500KBPS, MCP_16MHZ) == CAN_OK) Serial.println("MCP2515 Initialized Successfully!");
  else Serial.println("Error Initializing MCP2515...");

  CAN0.setMode(MCP_NORMAL);   // Change to normal mode to allow messages to be transmitted
}

// counts holes on disc (with filter)
void count(){
 if (micros() - previousMicros >= 700) {
 counter++;
 previousMicros = micros();
 }
}

// output to serial
void output(){
 Timer1.detachInterrupt(); // interrupts the timer

 Serial.print("Drehzahl pro Minute: ");
 int speed = ((counter)*calc) / wheel; // calculate round per minute
 Serial.println(speed);

 //Convert speed in byte form
 data[0] = highByte(speed);
 data[1] = lowByte(speed);
 
 counter = 0; // resetting the counter
 Timer1.attachInterrupt(output); // restarts the timer for output
}

void loop(){

  byte sndStat = CAN0.sendMsgBuf(0x10, 0, 2, data); // Sending CAN Message with ID 0x10 with a Data Size of 2 Bytes

  if(sndStat != CAN_OK){
  Serial.println("Error Sending Message...");
  }

  //delay(100);   // send data per 100ms

}