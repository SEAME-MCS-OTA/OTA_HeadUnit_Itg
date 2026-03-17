// sen-speed Demo
// The code measures the revolutions of the encoder disk over a period of
// time (5 seconds by default), then converts it to revolutions per minute
// and outputs it via the serial interface.

// library import
#include "TimerOne.h"
#define pin 2

// needed variables
int interval, wheel, counter;
unsigned long previousMicros, usInterval, calc;

void setup()
{
 counter = 0; // setting counter to 0
 interval = 1; // 5 second interval
 wheel = 20; // number of encoder disc holes

 calc = 60 / interval; // calculate interval to one minute
 usInterval = interval * 1000000; // convert interval to micro
 // seconds
 wheel = wheel * 2; // number of encoder disc wholes times 2
 pinMode(pin, INPUT_PULLUP); // setting pin 2 as input
 Timer1.initialize(usInterval); // initialize timer with interval time
 attachInterrupt(digitalPinToInterrupt(pin), count, CHANGE);
 // executes count, if the level on pin 2 changes

 Timer1.attachInterrupt(output); // executes output after interval time
 Serial.begin(9600); // starts serial interface with 9600 Baud
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
 int speed = ((counter)*calc) / wheel;
 // calculate round per minute

 Serial.println(speed);
 counter = 0; // resetting the counter
 Timer1.attachInterrupt(output); // restarts the timer for output
}

void loop(){
// no loop needed
}