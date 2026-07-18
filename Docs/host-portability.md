# PicoKit host portability

PicoKit deliberately supports a useful host build without pretending that a
host machine is a Pico. The host package validates values, errors, fakes,
buffering, API shape, and source compatibility; firmware builds select the
Pico SDK implementation through CMake. Keep those claims separate when adding
features or diagnosing a failure.

## Package layers

The Swift package has four relevant targets:

| Target | Host role |
| --- | --- |
| `PicoKitCore` | Foundation-free pins, units, errors, boards, and protocols |
| `PicoKitHAL` | hardware API with conditional SDK implementation and host fallback |
| `PicoKit` | umbrella module used by application code |
| `PicoKitHostTests` | Foundation-free executable validation target |

Applications import `PicoKit`; they do not import the SDK bridge directly. The
host target exists as an executable rather than an XCTest target because the
same Foundation-free validation style remains usable with Embedded Swift
toolchains that do not ship XCTest or Swift Testing.

## What conditional compilation means

Hardware files select their import and implementation by
`PICOKIT_PICO_SDK`:

```swift
#if !PICOKIT_PICO_SDK
import PicoKitCore
#else
import PicoKitSDKBridge
#endif
```

The host branch must still expose the same public API and validate arguments
that do not require hardware. A valid hardware operation then reports
`PicoKitError.unavailable("Pico SDK bridge")` on the host path. It must not
return a fabricated GPIO state, elapsed time, ADC sample, bus response, or
successful flash result.

The intentional host exceptions are documented behavior: host `Clock.now()`
and `micros()`/`millis()` return zero, watchdog updates are no-ops, interrupt
polling returns no event, and serial connection state is disconnected unless a
repository-internal test backend is being exercised through `@testable`.

## Build the host path

Run the debug and release executable checks from the package root:

```sh
swift build
swift run PicoKitHostTests
swift build -c release
swift run -c release PicoKitHostTests
```

The release target enables testing for `PicoKitHAL` so internal conversion
guards remain covered in the optimized configuration. A host build does not
need the Pico SDK submodule, CMake, Ninja, an Embedded Swift snapshot, or a
connected board.

## Keep new APIs portable

When adding a public declaration, keep its portable portion in `PicoKitCore`
when possible. For a HAL declaration:

1. define the same signature in the host and firmware branches;
2. validate pins, units, counts, addresses, and option combinations before the
   SDK call;
3. convert host-independent failures to the same typed `PicoKitError` case;
4. return unavailable rather than fake hardware success;
5. add a fake or backend seam only when it is a deliberate public protocol or
   an internal `@testable` repository seam;
6. add a compile-surface assignment and behavioral host assertion.

Avoid importing Foundation merely for formatting, sleeping, collections, or
test convenience. Use the Foundation-free standard-library surface supported
by the firmware toolchain, and keep host-only helpers behind the test target.

## Test with the right seam

Use values and protocols before trying to simulate hardware:

```swift
final class FakeGPIO: DigitalIO {
    var state: PinState = .low

    func setMode(_ pin: PicoPin, mode: PinMode) throws(PicoKitError) {}
    func write(_ pin: PicoPin, state: PinState) throws(PicoKitError) {
        self.state = state
    }
    func read(_ pin: PicoPin) throws(PicoKitError) -> PinState { state }
}

let gpio = FakeGPIO()
try digitalWrite(3, .high, using: gpio)
precondition(gpio.state == .high)
```

For serial buffering, use the repository's internal backend seam through
`@testable import PicoKitHAL`; external applications should test their own
abstraction above public `PicoSerial`. For a bus, test argument validation and
driver policy with a fake boundary, then use firmware integration or physical
equipment for electrical behavior.

## Architecture coverage

Host CI runs the same package checks on Apple Silicon and Intel. Do not use a
platform-specific path, integer width assumption, or host Foundation behavior
without testing both architectures. Prefer fixed-width values where the C ABI
requires them and validate conversions before entering the bridge.

Useful checks for a host-facing change are:

```sh
sh Tests/api-reference.sh
sh Tests/docs-consistency.sh
sh Tests/docs-links.sh
sh Tests/bridge-surface.sh
sh Tests/bridge-module.sh
swift build
swift run PicoKitHostTests
```

The API and bridge checks catch surface drift; the executable catches runtime
validation and error behavior. None of them proves a physical waveform or
device response.

## Host versus firmware evidence

| Result | Supports | Does not support |
| --- | --- | --- |
| host value/error test passes | portable validation and policy | SDK linkage or wiring |
| host hardware call throws unavailable | honest host boundary | firmware operation failure mode |
| host fake records expected GPIO | driver sequencing | voltage or current |
| firmware integration builds | compiler, SDK, bridge, and board target | boot or external device response |
| physical fixture succeeds | the selected image, board, wiring, and moment | every board or configuration |

When a host test fails, fix the portable contract first. When host tests pass
but firmware fails, inspect the SDK/compiler/CMake layer. When firmware builds
but the device is silent, continue to pin, power, timing, and protocol
evidence; do not weaken the host fallback to make the symptom disappear.

## Related documents

- [Driver testing](driver-testing.md) — fakes and host-only seams.
- [Runtime and testing](runtime-and-testing.md) — host behavior and evidence.
- [Firmware build and bridge](firmware-build-and-bridge.md) — SDK boundary.
- [CI validation](ci-validation.md) — architecture and job matrix.
- [Public API evolution](public-api-evolution.md) — cross-target API changes.
