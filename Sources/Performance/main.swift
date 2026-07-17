import PicoKit

/// Release-mode, USB-CDC timing fixture for the connected Pico 2 W.
/// Each record is `metric,iterations,elapsed_us,check` so host tools can
/// collect medians without parsing prose.
@main
struct Performance {
  private static let iterations: UInt32 = 100_000

  static func main() {
    // Initialize USB CDC before waiting, otherwise a monitor cannot open
    // the port until after the one-shot report has already begun.
    _ = Serial.available
    // Give a monitor time to reopen USB CDC after a reset or flash.
    sleep(2_000)
    Serial.println("metric,iterations,elapsed_us,check")
    cpuBenchmarks()
    peripheralBenchmarks()
    Serial.println("complete,0,0,0")
    while true { sleep(1_000) }
  }

  private static func report(_ metric: String, _ startedAt: UInt64, _ check: UInt32) {
    let elapsed = Clock.now() - startedAt
    Serial.println(metric + "," + String(iterations) + "," + String(elapsed) + "," + String(check))
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
      let gpio = PicoGPIO.rp2350
      try gpio.configure(.gpio14, mode: .output)
      try gpio.configure(.gpio15, mode: .output)
      let mask: UInt32 = (1 << 14) | (1 << 15)
      var index: UInt32 = 0
      let singleStart = Clock.now()
      while index < iterations {
        try gpio.toggle(.gpio14)
        index &+= 1
      }
      report("gpio.single_toggle", singleStart, 0)

      index = 0
      let maskStart = Clock.now()
      while index < iterations {
        try gpio.toggle(mask: mask)
        index &+= 1
      }
      report("gpio.mask_toggle", maskStart, 0)

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
      Serial.println("error,0,0,1")
    }
  }
}
