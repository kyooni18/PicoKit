import PicoKit

/// Release-mode, USB-CDC timing fixture for the connected supported Pico.
/// Each record is `metric,iterations,elapsed_us,check` so host tools can
/// collect medians without parsing prose.
@main
struct Performance {
  private static let iterations: UInt32 = 100_000

  static func main() {
    // Initialize USB CDC, then wait for one host byte. This makes capture
    // readiness explicit and permits repeat runs without reflashing.
    _ = Serial.available
    while true {
      while !Serial.connected { sleep(10) }
      emit("# ready=send-one-byte")
      while Serial.connected {
        if Serial.read() != nil {
          runOnce()
          break
        }
        sleep(10)
      }
    }
  }

  private static func runOnce() {
    emit("# format=picokit-performance-v1")
    emit("# chip=" + PicoChip.compiled.rawValue)
    emit("# board=" + (PicoBoard.compiled?.rawValue ?? "custom"))
    emit("# iterations=" + String(iterations))
    emit("metric,iterations,elapsed_us,check")
    cpuBenchmarks()
    peripheralBenchmarks()
    emit("complete,0,0,0")
  }

  private static func emit(_ line: String) {
    Serial.println(line)
  }

  @discardableResult
  private static func report(_ metric: String, _ startedAt: UInt64, _ check: UInt32) -> UInt64 {
    let elapsed = Clock.now() - startedAt
    emit(metric + "," + String(iterations) + "," + String(elapsed) + "," + String(check))
    return elapsed
  }

  private static func cpuBenchmarks() {
    var value: UInt32 = 1
    var index: UInt32 = 0
    var start = Clock.now()
    while index < iterations {
      value &+= index
      index &+= 1
    }
    report("cpu.add", start, value)

    value = 3
    index = 0
    start = Clock.now()
    while index < iterations {
      value &*= 1_664_525
      value &+= 1_013_904_223
      index &+= 1
    }
    report("cpu.multiply", start, value)

    value = 0x1357_9bdf
    index = 0
    start = Clock.now()
    while index < iterations {
      value = (value << 5) | (value >> 27)
      index &+= 1
    }
    report("cpu.shift", start, value)

    value = 0
    index = 0
    start = Clock.now()
    while index < iterations {
      if index & 1 == 0 { value &+= index } else { value &-= index }
      index &+= 1
    }
    report("cpu.branch", start, value)

    value = 0x2468_ace1
    index = 0
    start = Clock.now()
    while index < iterations {
      value ^= value << 13
      value ^= value >> 17
      value ^= value << 5
      index &+= 1
    }
    report("cpu.xorshift", start, value)

    value = 65_536
    index = 0
    start = Clock.now()
    while index < iterations {
      value = (value &* 65_470) >> 16
      index &+= 1
    }
    report("cpu.fixedpoint", start, value)

    value = 0
    index = 0
    start = Clock.now()
    while index < iterations {
      value &+= (index &* 17) ^ (index >> 3)
      index &+= 1
    }
    report("cpu.mix", start, value)

    value = 0xffff_ffff
    index = 0
    start = Clock.now()
    while index < iterations {
      value = (value >> 1) ^ (0xedb8_8320 & (0 &- (value & 1)))
      index &+= 1
    }
    report("cpu.crcstep", start, value)
  }

  private static func peripheralBenchmarks() {
    do {
      let gpio = PicoGPIO.compiled
      try gpio.configure(.gpio14, mode: .output)
      try gpio.configure(.gpio15, mode: .output)
      let mask: UInt32 = (1 << 14) | (1 << 15)
      var index: UInt32 = 0
      let singleStart = Clock.now()
      while index < iterations {
        try gpio.toggle(.gpio14)
        index &+= 1
      }
      let singleElapsed = report("gpio.single_toggle", singleStart, 0)

      index = 0
      let maskStart = Clock.now()
      while index < iterations {
        try gpio.toggle(mask: mask)
        index &+= 1
      }
      let maskElapsed = report("gpio.mask_toggle", maskStart, 0)

      // Counterbalance a second pair to expose ordering, cache, or thermal
      // effects instead of attributing them to the API from one ordering.
      index = 0
      let maskSecondStart = Clock.now()
      while index < iterations {
        try gpio.toggle(mask: mask)
        index &+= 1
      }
      let maskSecondElapsed = report("gpio.mask_toggle.second_pass", maskSecondStart, 0)

      index = 0
      let singleSecondStart = Clock.now()
      while index < iterations {
        try gpio.toggle(.gpio14)
        index &+= 1
      }
      let singleSecondElapsed = report("gpio.single_toggle.second_pass", singleSecondStart, 0)
      emit(
        "gpio.counterbalanced," + String(singleElapsed) + "," + String(maskElapsed) + ","
          + String(maskSecondElapsed) + "," + String(singleSecondElapsed)
      )

      let pwm = try PicoPWM(pin: .gpio0, frequency: .kilohertz(1))
      index = 0
      let pwmStart = Clock.now()
      while index < iterations {
        try pwm.setDutyCycle(UInt16(truncatingIfNeeded: index))
        index &+= 1
      }
      report("pwm.update", pwmStart, 0)

      index = 0
      let rawPWMStart = Clock.now()
      while index < iterations {
        try pwm.setCounterLevel(UInt16(truncatingIfNeeded: index))
        index &+= 1
      }
      report("pwm.counter_update", rawPWMStart, 0)

      let adc = try PicoADC()
      index = 0
      var sample: UInt16 = 0
      let adcStart = Clock.now()
      while index < iterations {
        sample = try adc.read(.gpio26)
        index &+= 1
      }
      report("adc.same_channel", adcStart, UInt32(sample))
    } catch {
      emit("error,0,0,1")
    }
  }
}
