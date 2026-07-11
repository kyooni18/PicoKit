cmake_minimum_required(VERSION 3.29)

# The Pico SDK is vendored with PicoKit by default. An environment or CMake
# value still wins, so projects can share a centrally installed SDK.
if(NOT DEFINED PICO_SDK_PATH)
    set(PICO_SDK_PATH "${CMAKE_CURRENT_LIST_DIR}/../Vendor/pico-sdk")
endif()
include(${PICO_SDK_PATH}/external/pico_sdk_import.cmake)

set(CMAKE_Swift_COMPILATION_MODE wholemodule)
set(CMAKE_Swift_COMPILER_WORKS YES)

project(picokit_blink)
pico_sdk_init()
enable_language(Swift)

# Pico uses ARMv6-M; Pico 2 uses the RP2350's ARMv8-M-compatible ARMv7E-M
# Swift target. CMake's PICO_BOARD=pico2 selects rp2350-arm-s by default.
set(SWIFT_TARGET "armv6m-none-none-eabi")
if(PICO_PLATFORM STREQUAL "rp2350-arm-s")
    set(SWIFT_TARGET "armv7em-none-none-eabi")
    list(APPEND CLANG_ARCH_ABI_FLAGS "-Xcc -mfloat-abi=soft")
elseif(PICO_PLATFORM STREQUAL "rp2350-riscv")
    set(SWIFT_TARGET "riscv32-none-none-eabi")
    list(APPEND CLANG_ARCH_ABI_FLAGS "-Xcc -march=rv32imac_zicsr_zifencei_zba_zbb_zbs_zbkb" "-Xcc -mabi=ilp32")
else()
    list(APPEND CLANG_ARCH_ABI_FLAGS "-Xcc -mfloat-abi=soft")
endif()

add_executable(picokit-blink ../Sources/Blink/main.swift PicoKitShim.c)
set_target_properties(picokit-blink PROPERTIES LINKER_LANGUAGE CXX)
target_link_libraries(picokit-blink pico_stdlib pico_status_led)
pico_enable_stdio_usb(picokit-blink 1)
pico_enable_stdio_uart(picokit-blink 0)

# Pico SDK interface targets carry C-only flags. Re-express them so Swift's
# bridging-header import sees the same definitions and include directories.
set_target_properties(pico_standard_link PROPERTIES INTERFACE_COMPILE_OPTIONS "")
target_compile_options(pico_standard_link INTERFACE "$<$<COMPILE_LANGUAGE:C>:SHELL: -ffunction-sections -fdata-sections>")
# RP2350's VFP support exports a C-only `-fno-math-errno` option. CMake passes
# interface flags to Swift too, but current Embedded Swift rejects that raw C
# flag. The library itself keeps its own C compile options; only the exported
# consumer option is cleared here.
set_target_properties(pico_float_pico_vfp PROPERTIES INTERFACE_COMPILE_OPTIONS "")

set_property(GLOBAL PROPERTY picokit_visited_targets "")
set_property(GLOBAL PROPERTY picokit_compile_definitions "")
function(picokit_collect_definitions target)
    get_property(visited GLOBAL PROPERTY picokit_visited_targets)
    if(${target} MATCHES "\\$<" OR ${target} MATCHES "::@" OR ${target} IN_LIST visited)
        return()
    endif()
    list(APPEND visited ${target})
    set_property(GLOBAL PROPERTY picokit_visited_targets "${visited}")

    get_target_property(definitions ${target} INTERFACE_COMPILE_DEFINITIONS)
    if(definitions)
        get_property(collected GLOBAL PROPERTY picokit_compile_definitions)
        list(APPEND collected ${definitions})
        set_property(GLOBAL PROPERTY picokit_compile_definitions "${collected}")
    endif()

    get_target_property(libraries ${target} INTERFACE_LINK_LIBRARIES)
    if(libraries)
        foreach(library ${libraries})
            picokit_collect_definitions(${library})
        endforeach()
    endif()
endfunction()

picokit_collect_definitions(picokit-blink)
get_property(COMPILE_DEFINITIONS GLOBAL PROPERTY picokit_compile_definitions)
list(REMOVE_DUPLICATES COMPILE_DEFINITIONS)
list(PREPEND COMPILE_DEFINITIONS "")
string(REPLACE "$<TARGET_PROPERTY:PICO_TARGET_BINARY_TYPE>" "$<TARGET_PROPERTY:picokit-blink,PICO_TARGET_BINARY_TYPE>" COMPILE_DEFINITIONS "${COMPILE_DEFINITIONS}")
string(REPLACE ";" " -Xcc -D" COMPILE_DEFINITIONS "${COMPILE_DEFINITIONS}")

set(IMPLICIT_INCLUDES)
foreach(directory ${CMAKE_C_IMPLICIT_INCLUDE_DIRECTORIES} ${CMAKE_CXX_IMPLICIT_INCLUDE_DIRECTORIES})
    string(CONCAT IMPLICIT_INCLUDES ${IMPLICIT_INCLUDES} "-Xcc -I${directory} ")
endforeach()

target_compile_options(picokit-blink PUBLIC "$<$<COMPILE_LANGUAGE:Swift>:SHELL:
    -target ${SWIFT_TARGET}
    -enable-experimental-feature Embedded
    -parse-as-library
    -module-name PicoKitFirmware
    ${CLANG_ARCH_ABI_FLAGS}
    -Xcc -fshort-enums
    -Xfrontend -function-sections
    -import-bridging-header ${CMAKE_CURRENT_LIST_DIR}/BridgingHeader.h
    ${COMPILE_DEFINITIONS}
    ${IMPLICIT_INCLUDES}
>")

pico_add_extra_outputs(picokit-blink)
