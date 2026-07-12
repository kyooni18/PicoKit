# PicoKit Documentation

## Chapter 31: API summary


### Core

```text
PicoChip
PicoBoard
PicoKitError
PicoPin
Duration
Frequency
PinMode
PinState
DigitalIO
pinMode(_:_:using:)
digitalWrite(_:_:using:)
digitalRead(_:using:)
```

### GPIO and facade

```text
PicoGPIO
BoardLED
Pico
pico
pinMode(_:_:)
digitalWrite(_:_:)
digitalRead(_:)
```

### Timing and serial

```text
Clock
delay(_:)
delayMicroseconds(_:)
millis()
micros()
sleep(_:)
sleepMicroseconds(_:)
USBSerial
PicoSerial
Serial
```

### Peripherals

```text
UARTInstance
PicoUART
PicoPWM
analogWrite(_:_:using:)
ADCChannel
PicoADC
analogRead(_:using:)
I2CInstance
PicoI2C
SPIInstance
PicoSPI
GPIOInterruptEdge
PicoInterrupts
PicoWatchdog
```
