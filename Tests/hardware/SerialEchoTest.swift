import Foundation
import Darwin

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: SerialEchoTest.swift /dev/cu.usbmodem…\n".utf8))
    exit(2)
}

let path = CommandLine.arguments[1]
let descriptor = open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)
guard descriptor >= 0 else {
    perror("open")
    exit(1)
}
defer { close(descriptor) }

var settings = termios()
guard tcgetattr(descriptor, &settings) == 0 else {
    perror("tcgetattr")
    exit(1)
}
cfmakeraw(&settings)
cfsetspeed(&settings, speed_t(B115200))
guard tcsetattr(descriptor, TCSANOW, &settings) == 0 else {
    perror("tcsetattr")
    exit(1)
}
tcflush(descriptor, TCIOFLUSH)

let expected: [UInt8] = [0x50, 0x69, 0x63, 0x6F, 0x00, 0x7F, 0xFF, 0x0A]
let written = expected.withUnsafeBytes { write(descriptor, $0.baseAddress, $0.count) }
guard written == expected.count else {
    perror("write")
    exit(1)
}

var received: [UInt8] = []
let deadline = Date().addingTimeInterval(5)
while received.count < expected.count && Date() < deadline {
    var buffer = [UInt8](repeating: 0, count: expected.count - received.count)
    let count = buffer.withUnsafeMutableBytes { read(descriptor, $0.baseAddress, $0.count) }
    if count > 0 {
        received.append(contentsOf: buffer.prefix(count))
    } else if count < 0 && errno != EAGAIN && errno != EWOULDBLOCK {
        perror("read")
        exit(1)
    }
    usleep(10_000)
}

guard received == expected else {
    FileHandle.standardError.write(Data("echo mismatch: expected \(expected), received \(received)\n".utf8))
    exit(1)
}

print("Serial byte echo verified")
