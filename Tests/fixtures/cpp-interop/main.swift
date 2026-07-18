import CppInterop

@main
struct CppInteropProbe {
  static func main() {
    let result = picokit_cpp_add(19, 23)
    if result != 42 {
      while true {}
    }

    while true {}
  }
}
