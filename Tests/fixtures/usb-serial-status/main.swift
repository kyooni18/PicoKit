import PicoKit

/// Proves the throwing USB API rejects writes before DTR, then becomes usable
/// after a monitor opens the CDC device.
@main
struct USBSerialStatusProbe {
  static func main() {
    let serial = try! USBSerial()
    var rejectedAsDisconnected = false
    var readRejectedAsDisconnected = false

    do {
      try serial.write("must-not-be-delivered")
    } catch PicoKitError.unavailable(_) {
      rejectedAsDisconnected = true
    } catch {
    }
    do {
      _ = try serial.read()
    } catch PicoKitError.unavailable(_) {
      readRejectedAsDisconnected = true
    } catch {
    }

    while !serial.isConnected { sleep(10) }
    if rejectedAsDisconnected {
      try! serial.write("disconnected_write,pass\r\n")
    } else {
      try! serial.write("disconnected_write,fail\r\n")
    }
    if readRejectedAsDisconnected {
      try! serial.write("disconnected_read,pass\r\n")
    } else {
      try! serial.write("disconnected_read,fail\r\n")
    }
    try! serial.write("connected_write,pass\r\n")

    while true {
      if let byte = try! serial.read() {
        if byte == 0x54 { // T: arm a timed-read disconnect test.
          try! serial.write("timed_read,armed\r\n")
          var timedReadRejectedAsDisconnected = false
          do {
            _ = try serial.read(timeout: .seconds(30))
          } catch PicoKitError.unavailable(_) {
            timedReadRejectedAsDisconnected = true
          } catch {
          }
          while !serial.isConnected { sleep(10) }
          if timedReadRejectedAsDisconnected {
            try! serial.write("timed_disconnect,pass\r\n")
          } else {
            try! serial.write("timed_disconnect,fail\r\n")
          }
        } else {
          try! serial.write(byte)
        }
      } else {
        sleepMicroseconds(100)
      }
    }
  }
}
