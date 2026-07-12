# PicoKit Documentation

## Chapter 13: Error model


The low-level API uses `PicoKitError`:

```swift
public enum PicoKitError: Error {
    case invalidPin(Int)
    case invalidFrequency(UInt32)
    case invalidTimeout(UInt64)
    case invalidAddress(UInt8)
    case unavailable(String)
    case timedOut(operation: String)
    case ioFailure(operation: String, status: Int32)
    case ownershipConflict(String)
}
```

Typical meanings:

| Error | Meaning |
|---|---|
| `invalidPin` | GPIO is outside `0...29` |
| `invalidFrequency` | Frequency is zero or overflowed |
| `invalidTimeout` | Duration is zero, overflowed, or unsupported |
| `invalidAddress` | I2C address is outside `0x08...0x77` |
| `unavailable` | Hardware bridge or board feature is unavailable |
| `timedOut` | A bounded peripheral operation exceeded its timeout |
| `ioFailure` | Pico SDK operation returned an error status |
| `ownershipConflict` | An operation was attempted with the wrong peripheral owner |

`PicoKitError.description` provides a human-readable diagnostic string.
