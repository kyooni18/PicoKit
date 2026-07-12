# PicoKit Documentation

## Chapter 17: USB serial


### Low-level USB serial

Use `USBSerial` when serial setup should participate in normal error handling:

```swift
let serial = try USBSerial()
try serial.write("System started")
```

Creating `USBSerial` initializes Pico SDK stdio. Keep the instance around and
reuse it rather than treating every line of output as a new setup operation.

### High-level serial

For a sketch, the global `Serial` object initializes USB stdio lazily on its
first write:

```swift
Serial.write("raw text")
Serial.print("value: ")
Serial.println(42)
Serial.println()
```

`print` does not append a newline. `println` does.

The default runtime exposes the same object if you prefer an explicit owner:

```swift
pico.serial.println("hello")
```
