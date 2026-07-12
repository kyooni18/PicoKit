# PicoKit Documentation

## Chapter 17: USB serial


### Low-level USB serial

```swift
let serial = try USBSerial()
try serial.write("System started")
```

Creating `USBSerial` initializes Pico SDK stdio.

### High-level serial

The global `Serial` object initializes USB stdio lazily on its first write:

```swift
Serial.write("raw text")
Serial.print("value: ")
Serial.println(42)
Serial.println()
```

`print` does not append a newline. `println` does.

The default runtime exposes the same object:

```swift
pico.serial.println("hello")
```
