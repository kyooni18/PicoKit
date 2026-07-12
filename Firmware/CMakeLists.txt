cmake_minimum_required(VERSION 3.29)

# `PICOKIT_ROOT` points at the reusable PicoKit checkout. Generated projects
# pass it from swiftpico.json; the in-tree example uses this default.
if(NOT DEFINED PICOKIT_ROOT)
    get_filename_component(PICOKIT_ROOT "${CMAKE_CURRENT_LIST_DIR}/.." ABSOLUTE)
endif()
if(NOT DEFINED PICO_SDK_PATH)
    set(PICO_SDK_PATH "${PICOKIT_ROOT}/Vendor/pico-sdk")
endif()
if(NOT DEFINED PICOKIT_PRODUCT)
    set(PICOKIT_PRODUCT "PicoKitFirmware")
endif()
if(NOT DEFINED PICOKIT_SOURCE)
    set(PICOKIT_SOURCE "${PICOKIT_ROOT}/Sources/Blink/main.swift")
endif()

include(${PICO_SDK_PATH}/external/pico_sdk_import.cmake)
project(PicoKitFirmware)
pico_sdk_init()

set(CMAKE_Swift_COMPILATION_MODE wholemodule)
# CMake's Swift compiler probe links a host macOS executable. That probe is
# incompatible with the Embedded Swift toolchain: it can compile an object,
# but it must not try to link against the host `System` library. Mark the
# compiler as usable before enable_language(Swift), where CMake performs the
# probe. The actual firmware targets below still compile with the embedded
# target and are checked by the real build.
set(CMAKE_Swift_COMPILER_WORKS YES CACHE INTERNAL "Embedded Swift compiler is usable")
enable_language(Swift)

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

# Layer 4: the only C target that includes Pico SDK headers. All SDK access is
# behind fixed-width C functions so embedded Swift never imports SDK inlines.
set(PICOKIT_BRIDGE_DIR "${PICOKIT_ROOT}/Firmware")
add_library(PicoKitSDKBridge STATIC "${PICOKIT_BRIDGE_DIR}/PicoKitSDKBridge.c")
target_include_directories(PicoKitSDKBridge PUBLIC "${PICOKIT_BRIDGE_DIR}")
target_link_libraries(PicoKitSDKBridge PUBLIC pico_stdlib pico_status_led hardware_adc hardware_i2c hardware_pwm hardware_spi hardware_watchdog)

# Layers 2, 1, and public facade. This is a real Swift library; firmware
# sources import PicoKit and link it instead of calling a project-local shim.
file(GLOB PICOKIT_CORE_SOURCES CONFIGURE_DEPENDS "${PICOKIT_ROOT}/Sources/PicoKitCore/*.swift")
file(GLOB PICOKIT_HAL_SOURCES CONFIGURE_DEPENDS "${PICOKIT_ROOT}/Sources/PicoKitHAL/*.swift")
file(GLOB PICOKIT_FACADE_SOURCES CONFIGURE_DEPENDS "${PICOKIT_ROOT}/Sources/PicoKitFacade/*.swift")
add_library(PicoKit STATIC ${PICOKIT_CORE_SOURCES} ${PICOKIT_HAL_SOURCES} ${PICOKIT_FACADE_SOURCES})
set_target_properties(PicoKit PROPERTIES LINKER_LANGUAGE CXX Swift_MODULE_NAME PicoKit)
target_link_libraries(PicoKit PUBLIC PicoKitSDKBridge)

# Pico SDK interface targets contain C-only options. Keep them on C targets;
# Swift receives the architecture, module, bridge header, and SDK definitions
# it needs, but never raw C compiler flags.
set_target_properties(pico_standard_link PROPERTIES INTERFACE_COMPILE_OPTIONS "")
target_compile_options(pico_standard_link INTERFACE "$<$<COMPILE_LANGUAGE:C>:SHELL: -ffunction-sections -fdata-sections>")
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

picokit_collect_definitions(PicoKit)
get_property(COMPILE_DEFINITIONS GLOBAL PROPERTY picokit_compile_definitions)
list(REMOVE_DUPLICATES COMPILE_DEFINITIONS)
list(PREPEND COMPILE_DEFINITIONS "")
string(REPLACE ";" " -Xcc -D" COMPILE_DEFINITIONS "${COMPILE_DEFINITIONS}")

set(IMPLICIT_INCLUDES)
foreach(directory ${CMAKE_C_IMPLICIT_INCLUDE_DIRECTORIES} ${CMAKE_CXX_IMPLICIT_INCLUDE_DIRECTORIES})
    string(CONCAT IMPLICIT_INCLUDES ${IMPLICIT_INCLUDES} "-Xcc -I${directory} ")
endforeach()

target_compile_options(PicoKit PRIVATE "$<$<COMPILE_LANGUAGE:Swift>:SHELL:
    -target ${SWIFT_TARGET}
    -enable-experimental-feature Embedded
    -parse-as-library
    -module-name PicoKit
    -D PICOKIT_PICO_SDK
    ${CLANG_ARCH_ABI_FLAGS}
    -Xcc -fshort-enums
    -Xfrontend -function-sections
    -import-bridging-header ${PICOKIT_BRIDGE_DIR}/BridgingHeader.h
    ${COMPILE_DEFINITIONS}
    ${IMPLICIT_INCLUDES}
>")

add_executable(${PICOKIT_PRODUCT} ${PICOKIT_SOURCE})
set_target_properties(${PICOKIT_PRODUCT} PROPERTIES LINKER_LANGUAGE CXX)
target_compile_definitions(${PICOKIT_PRODUCT} PRIVATE
    PICO_ENABLE_USB_RESET_VIA_BAUD_RATE=1
    PICO_ENABLE_USB_RESET_VIA_VENDOR_INTERFACE=1
)
target_compile_options(${PICOKIT_PRODUCT} PRIVATE "$<$<COMPILE_LANGUAGE:Swift>:SHELL:
    -target ${SWIFT_TARGET}
    -enable-experimental-feature Embedded
    -parse-as-library
>")
target_link_libraries(${PICOKIT_PRODUCT} PRIVATE PicoKit)
pico_enable_stdio_usb(${PICOKIT_PRODUCT} 1)
pico_enable_stdio_uart(${PICOKIT_PRODUCT} 0)
pico_add_extra_outputs(${PICOKIT_PRODUCT})
