# PicoKit typed API and errors

PicoKit's portable core is the contract between application configuration and
hardware operations. It validates values before the SDK bridge is called,
keeps units explicit, and gives the application enough information to choose a
failure policy. The core does not access registers or require the Pico SDK, so
these rules are suitable for host tests and configuration parsing.

## Board and chip identity

`PicoBoard` describes the four supported board identifiers and derives their
chip family:

| Board | `cmakeName` | Chip | `isWireless` | `onboardLEDPin` |
| --- | --- | --- | --- | --- |
| `.pico` | `pico` | `.rp2040` | `false` | GPIO25 |
| `.picoW` | `pico_w` | `.rp2040` | `true` | `nil` |
| `.pico2` | `pico2` | `.rp2350` | `false` | GPIO25 |
| `.pico2W` | `pico2_w` | `.rp2350` | `true` | `nil` |

Use `configurationName` when a board comes from a manifest or command line:

```swift
guard let board = PicoBoard(configurationName: userValue) else {
    throw PicoKitError.unavailable("unsupported Pico board")
}

Serial.println("board=\(board.cmakeName) chip=\(board.chip)")
```

Parsing trims surrounding whitespace, ignores case, and accepts `pico-w` and
`pico2-w` as compatibility spellings. It does not accept arbitrary board names.
`PicoBoard.compiled` reports the exact recognized board selected by firmware;
it is `nil` for a custom board outside PicoKit's four-board mapping. Host builds
use `.pico` as their validation default.

Do not use `onboardLEDPin` as a universal LED rule. Wireless boards use the
SDK status-LED path, so `BoardLED()` is the board-aware operation. Keep the
board selected by CMake, SwiftPico project metadata, and any explicit
`PicoBoard`/`PicoChip` declaration aligned.

## Validated pins

`PicoPin` represents a GPIO accepted by PicoKit's public surface:

```swift
let pin = try PicoPin(15)
let named = PicoPin.gpio15

print(pin.rawValue)     // UInt32(15)
print(pin.description)  // GPIO15
```

The valid range is GPIO0 through GPIO29. `PicoPin(_:)` throws
`PicoKitError.invalidPin` for an invalid `Int`; `PicoPin(rawValue:)` returns
`nil` for an invalid `UInt32` without throwing. The named `.gpio0` through
`.gpio29` constants are already validated.

`PicoPin` is `Hashable`, `Comparable`, and `Sendable`, which makes it useful in
a checked application pin map:

```swift
let reserved: Set<PicoPin> = [.gpio4, .gpio5, .gpio17]
precondition(!reserved.contains(.gpio18))
```

A valid GPIO is not automatically a valid peripheral signal. UART, I2C, and
SPI constructors apply their instance/chip-specific alternate-function maps
after the generic pin range check. A pin can therefore pass `PicoPin` creation
and still throw `invalidPeripheralPin` for a selected peripheral role.

## Explicit units

`Duration` stores positive microseconds and `Frequency` stores positive hertz.
Use the named factories rather than unannotated integer literals:

```swift
let poll = try Duration.milliseconds(20)
let timeout = try Duration.seconds(2)
let uart = try Frequency.hertz(115_200)
let spi = try Frequency.megahertz(8)
```

The conversion factories detect multiplication overflow:

```swift
do {
    let impossible = try Frequency.megahertz(UInt32.max)
    _ = impossible
} catch PicoKitError.invalidFrequency(let value) {
    Serial.println("frequency overflow: \(value)")
}
```

Zero is rejected by `Duration` factories as `invalidTimeout` and by
`Frequency` factories as `invalidFrequency`. The standalone `delay(0)`,
`delayMicroseconds(0)`, and facade sleep helpers deliberately treat zero as a
valid no-op because they are convenience operations rather than timeout
constructors.

The units are still subject to the narrower hardware API receiving them. For
example, I2C and some other SDK calls pass microseconds through a `UInt32`
boundary; a valid `Duration` can therefore be rejected as `invalidTimeout` by
that peripheral if it exceeds the bridge's representable range.

## Typed errors

`PicoKitError` is `Equatable`, `Sendable`, and `CustomStringConvertible`. Its
cases separate configuration, availability, timing, transfer, and ownership
failures:

| Error | Meaning | Typical policy |
| --- | --- | --- |
| `invalidPin` | Value is outside GPIO0...GPIO29 | Fix configuration; do not retry unchanged |
| `invalidFrequency` | Zero, overflow, or unsupported requested frequency | Fix configuration |
| `invalidTimeout` | Zero, overflow, or hardware-bound timeout | Choose a valid bound |
| `invalidAddress` | I2C address outside `0x08...0x77` | Fix 7-bit device address |
| `invalidPeripheralPin` | Pin role is invalid for instance/chip | Recheck pin map |
| `unavailable` | Bridge, board feature, chip, or overload is unavailable | Change build/board/API or enter safe state |
| `timedOut` | Bounded operation reached its deadline | Retry or mark device degraded |
| `partialTransfer` | Only part of a requested transfer completed | Inspect progress, protocol, and retry policy |
| `ioFailure` | SDK or bridge returned another failure | Log operation/status and recover deliberately |
| `ownershipConflict` | Pin, instance, or helper ownership conflicts | Keep one owner or change the map |

The description is designed for bring-up logs and retains useful associated
values:

```swift
do {
    let address = UInt8(0x80) // deliberately invalid 7-bit address
    _ = try i2c.read(address: address, count: 1, timeout: .milliseconds(10))
} catch let error as PicoKitError {
    Serial.println("configuration/transfer error: \(error)")
}
```

Do not flatten every error into “device disconnected.” An invalid pin and a
timed-out I2C read require different fixes and different evidence.

## Choosing the API level

PicoKit exposes a short sketch facade and typed low-level objects:

```swift
// Fixed bring-up sketch: fail-fast convenience calls.
pinMode(25, .output)
digitalWrite(25, .high)
sleep(500)

// Reusable driver: explicit setup and recovery.
let gpio = PicoGPIO.compiled
let led = try BoardLED()
try gpio.configure(.gpio15, mode: .output, initialState: .low)
try led.toggle()
```

Use the facade when the configuration is a compile-time constant and there is
no meaningful recovery path. Its nonthrowing methods fail fast if a lower-level
operation would throw. Use typed objects when values come from configuration,
timeouts can be recovered, a fake is useful in a host test, or a resource needs
an explicit owner.

Mixing the levels is valid: `Serial.println` can report a failure while a
throwing `PicoI2C` or `PicoSPI` object owns the device transaction. The choice is
about failure policy, not a requirement to rewrite an entire application.

## Errors at the right boundary

Construct long-lived resources once, then catch errors where the application
can choose a policy:

```swift
func readRegister(_ bus: PicoI2C) -> [UInt8]? {
    do {
        return try bus.writeRead(
            address: 0x48,
            bytes: [0x00],
            count: 2,
            timeout: .milliseconds(20)
        )
    } catch PicoKitError.timedOut(let operation) {
        Serial.println("retryable timeout: \(operation)")
        return nil
    } catch let error as PicoKitError {
        Serial.println("sensor unavailable or misconfigured: \(error)")
        return nil
    } catch {
        Serial.println("unexpected error: \(error)")
        return nil
    }
}
```

An invalid fixed pin should normally stop setup rather than retry in a loop. A
device timeout may be retried with a limit. A safety output should enter an
explicit safe state before logging or retrying. Keep that policy in the
application driver, not in the portable value types.

## Test the contract on the host

The core types and errors need no board:

```swift
let p = try PicoPin(7)
precondition(p.description == "GPIO7")
precondition(try Frequency.kilohertz(400).hertz == 400_000)

do {
    _ = try PicoPin(30)
    fatalError("invalid pin was accepted")
} catch PicoKitError.invalidPin(let value) {
    precondition(value == 30)
}
```

Run the repository's executable host checks after changing a public contract:

```sh
swift build
swift run PicoKitHostTests
sh Tests/api-reference.sh
```

Host tests can prove value conversions, alias parsing, error equality, fake
GPIO behavior, and unavailable-bridge paths. They cannot prove board muxing,
voltage, timing, or a peripheral's response; use the [hardware validation](hardware-validation.md)
matrix for those claims.

## Related documents

- [Application design](application-design.md) — failure policy and resource
  ownership in a complete firmware loop.
- [Board and pin planning](board-and-pin-planning.md) — peripheral-specific
  pin maps and conflict planning.
- [Failure diagnosis](failure-diagnosis.md) — evidence-led error triage.
- [API reference](api-reference.md) — declaration-level surface and overloads.
- [Hardware guide](hardware-guide.md) — complete core and peripheral contract.
