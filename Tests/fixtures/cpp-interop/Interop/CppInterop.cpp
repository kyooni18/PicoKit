#include "CppInterop.h"

class Accumulator {
public:
  explicit Accumulator(int32_t initial) : value(initial) {}

  int32_t add(int32_t amount) {
    value += amount;
    return value;
  }

private:
  int32_t value;
};

extern "C" int32_t picokit_cpp_add(int32_t left, int32_t right) {
  Accumulator accumulator(left);
  return accumulator.add(right);
}
