import PicoKit

@main
struct BridgeContracts {
    static func main() {
        do {
            _ = try PicoPin(30)
            preconditionFailure()
        } catch {
        }

        do {
            _ = try PicoSPI(
                .spi0,
                frequency: .megahertz(1),
                sck: .gpio18,
                mosi: .gpio19,
                miso: .gpio16,
                mode: .mode0,
                bitOrder: .leastSignificantBitFirst
            )
            preconditionFailure()
        } catch {
        }

        let i2c = try! PicoI2C(
            .i2c0,
            frequency: .kilohertz(100),
            sda: .gpio4,
            scl: .gpio5
        )
        let timeout = try! Duration.milliseconds(1)
        _ = try! i2c.read(address: 0x50, count: 0, timeout: timeout)

        do {
            _ = try i2c.writeRead(address: 0x50, bytes: [0], count: 0, timeout: timeout)
            preconditionFailure()
        } catch {
        }
    }
}
