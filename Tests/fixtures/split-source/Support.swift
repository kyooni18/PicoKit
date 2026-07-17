import PicoKit

enum SplitSourceSupport {
  @inline(__always)
  static func announce() {
    Serial.println("split-source")
  }
}
