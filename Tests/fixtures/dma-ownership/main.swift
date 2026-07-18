import PicoKit

@main
struct DMAOwnershipFixture {
  static func main() throws {
    let uartA = try PicoUART(
      .uart0, baudRate: .hertz(115_200), tx: .gpio0, rx: .gpio1)
    let uartB = try PicoUART(
      .uart0, baudRate: .hertz(115_200), tx: .gpio0, rx: .gpio1)

    // An empty transfer still claims the bridge owner, but does not touch the
    // UART FIFO. The second object must be rejected, then succeeds after the
    // first object explicitly releases its claim.
    try uartA.writeDMA([])
    var uartRejected = false
    do {
      try uartB.writeDMA([])
    } catch { uartRejected = true }
    precondition(uartRejected)
    uartA.releaseDMAChannel()
    try uartB.writeDMA([])

    let spiA = try PicoSPI(
      .spi0, frequency: .megahertz(1), sck: .gpio2, mosi: .gpio3)
    let spiB = try PicoSPI(
      .spi0, frequency: .megahertz(1), sck: .gpio2, mosi: .gpio3)
    try spiA.writeDMA([UInt8]())
    var spiRejected = false
    do {
      try spiB.writeDMA([UInt8]())
    } catch { spiRejected = true }
    precondition(spiRejected)
    spiA.releaseDMAChannels()
    try spiB.writeDMA([UInt8]())
  }
}
