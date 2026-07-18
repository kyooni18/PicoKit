# Evolving the PicoKit public API

PicoKit's public surface is consumed by two different builds: ordinary host
SwiftPM validation and Embedded Swift firmware linked through the C bridge. A
public API change is complete only when both surfaces, the symbol reference,
and the generated firmware templates agree.

## Put the declaration in the right layer

Keep the smallest possible dependency direction:

| Change | Primary location | Constraint |
| --- | --- | --- |
| Board, pin, unit, error, or protocol value | `Sources/PicoKitCore` | Foundation-free and host-testable |
| GPIO, serial, timing, peripheral, or watchdog API | `Sources/PicoKitHAL` | host fallback plus firmware bridge behavior |
| Re-export or application-facing umbrella | `Sources/PicoKitFacade` | preserve the one-module `import PicoKit` surface |
| SDK call or status conversion | `Firmware/PicoKitSDKBridge.c/.h` | keep Pico SDK headers behind the bridge |
| Example or generated template | `Docs`, `Sources`, or `Tests/fixtures` | compile it against the actual public module |

Do not add a vendor header to the Swift targets or place application-specific
protocol policy in the reusable HAL. Keep the foundation thin and expose the
smallest upstream-compatible operation needed by the application.

## Preserve source compatibility deliberately

Before changing a declaration, classify the change:

- Adding a new type, overload, property, or defaulted option is usually
  additive.
- Changing a parameter label, argument type, throwing behavior, return type,
  or associated-value shape can break existing source.
- Removing a declaration or changing a default can alter firmware behavior even
  when existing source still compiles.
- Changing a `RawRepresentable` raw value can break the C bridge ABI or persisted
  configuration. Preserve values such as interrupt edge and SPI frame-width
  constants unless a coordinated migration is intentional.

Prefer an additive overload or a new explicit type when old call sites have a
valid meaning. If an old API must remain, keep its behavior and document the
new path rather than silently redirecting it to a different hardware policy.
For board and chip selection, make mismatches typed `PicoKitError.unavailable`
or validation errors; do not silently select another target.

## Keep typed errors stable

Throwing hardware APIs use `PicoKitError`, including invalid configuration,
timeouts, partial transfers, I/O status, unavailable features, and ownership
conflicts. When adding a failure path:

1. validate arguments before entering the SDK bridge;
2. preserve the associated operation, status, transferred count, or pin;
3. distinguish retryable runtime failure from configuration failure;
4. add a host assertion for the exact case and description when user-facing;
5. update the recovery and API guides if the policy changes.

Do not make callers parse `CustomStringConvertible.description` to recover
error policy. The case and associated values are the contract.

## Implement both build paths

Hardware types normally have a `#if PICOKIT_PICO_SDK` implementation and a host
fallback. The host fallback should validate what can be validated without
hardware, then report `PicoKitError.unavailable("Pico SDK bridge")` instead of
pretending a register or device was accessed.

For a new bridge operation, update all of these together:

```text
Firmware/PicoKitSDKBridge.h       declaration and status constants
Firmware/PicoKitSDKBridge.c       firmware implementation
Sources/PicoKitHAL/<feature>.swift  typed Swift wrapper and host path
Tests/bridge-surface.sh           declaration/definition coverage
Tests/bridge-module.sh            C/C++ module import coverage when relevant
Tests/HostTests/main.swift        host conversion and API behavior
Docs/api-reference.md             public declaration reference
```

Use `extern "C"` guards in headers that may be included by C++ callers. Keep
status values explicit and convert them once at the Swift boundary. Do not
expose SDK structs, C++ templates, exceptions, or ownership hidden in global
state through the public Swift API.

## Validate the public surface

Run the smallest checks while editing, then the full relevant sequence:

```sh
swift build
swift run PicoKitHostTests
sh Tests/api-reference.sh
sh Tests/docs-consistency.sh
sh Tests/docs-links.sh
sh Tests/bridge-surface.sh
sh Tests/bridge-module.sh
```

`Tests/api-reference.sh` derives public symbols from the Swift symbol graph and
checks both types and authored members. Do not satisfy it by adding a name to
the reference without documenting the declaration's actual behavior. Keep
overload-sensitive examples explicit, especially `UInt8` versus `UInt16` and
timed versus unbounded operations.

## Validate generated firmware compatibility

If the change touches `PicoKitHAL`, the bridge, a public overload used by
templates, or a CMake/module boundary, build the firmware-facing checks too:

```sh
sh Tests/integration/generated-templates.sh
sh Tests/integration/generated-blink.sh
sh Tests/integration/generated-project.sh
sh Tests/peripheral-pin-mux-validation.sh
sh Tests/bridge-validation.sh
```

The template gate checks the exact Embedded Swift module used by generated
projects. The generated-project gate checks CMake, linker, UF2, and fake-flash
arguments. These are stronger evidence than a host-only compile, but still do
not prove a physical board or external peripheral.

## Update documentation as part of the change

For every new public declaration:

1. add the declaration and semantics to [the API reference](api-reference.md);
2. add a runnable example or focused guide section when wiring, timing,
   ownership, or recovery matters;
3. add a source-backed assertion to `Tests/docs-consistency.sh` when the
   behavior is easy to regress;
4. link the guide from [the documentation index](README.md) and the root
   README when it is a new focused workflow;
5. run the link and fence checks before committing.

Keep examples aligned with the public overload labels and explicit unit types.
An example that looks plausible but does not compile is a documentation bug.

## Review checklist

Before merging an API change, confirm:

- the declaration is in the correct layer and remains Foundation-free where
  required;
- old source behavior and raw values are preserved or the migration is
  explicit;
- host and firmware branches have the same validation and error contract;
- C declarations, definitions, module maps, and Swift imports agree;
- host, bridge, API-reference, documentation, and generated-template gates
  pass;
- no claim exceeds the evidence level actually run.

## Related documents

- [API reference](api-reference.md) — complete declaration coverage.
- [Typed API and errors](typed-api-and-errors.md) — units, board identity, and
  typed failure categories.
- [Firmware build and bridge](firmware-build-and-bridge.md) — build-layer
  boundaries and CMake inputs.
- [Driver testing](driver-testing.md) — fakes and host seams.
- [CI validation](ci-validation.md) — repository job scopes and matrix gates.
