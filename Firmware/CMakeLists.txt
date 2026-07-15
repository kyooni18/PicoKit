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
set(PICOKIT_USB_STDOUT_TIMEOUT_US "10000" CACHE STRING
    "Maximum time USB CDC output may block when the host stops consuming data")
if(NOT PICOKIT_USB_STDOUT_TIMEOUT_US MATCHES "^[0-9]+$")
    message(FATAL_ERROR "PICOKIT_USB_STDOUT_TIMEOUT_US must be a non-negative integer")
endif()
option(PICOKIT_ENABLE_USB
    "Initialize and link the USB CDC/reset interface for the firmware target" ON)
# PICOKIT_SOURCE remains the backwards-compatible entry-point hint used by
# SwiftPico. Compile every Swift file in that application's directory so a
# sketch can be split into ordinary source files and subdirectories. Callers
# that need a different selection can pass PICOKIT_SOURCES explicitly.
if(NOT DEFINED PICOKIT_SOURCES)
    get_filename_component(PICOKIT_SOURCE_DIRECTORY "${PICOKIT_SOURCE}" DIRECTORY)
    file(GLOB_RECURSE PICOKIT_SOURCES CONFIGURE_DEPENDS "${PICOKIT_SOURCE_DIRECTORY}/*.swift")
endif()
if(NOT PICOKIT_SOURCES)
    message(FATAL_ERROR "No Swift sources found for PICOKIT_SOURCE: ${PICOKIT_SOURCE}")
endif()

if(NOT DEFINED PICOKIT_SDK_IMPORTED)
    include(${PICO_SDK_PATH}/external/pico_sdk_import.cmake)
    set(PICOKIT_SDK_IMPORTED YES)
endif()
if(NOT DEFINED PICOKIT_PROJECT_INITIALIZED)
    project(PicoKitFirmware)
endif()
pico_sdk_init()

set(CMAKE_Swift_COMPILATION_MODE wholemodule)
set(PICOKIT_SWIFT_MODULE_DIRECTORY "${CMAKE_BINARY_DIR}/picokit-swift-modules")
file(MAKE_DIRECTORY "${PICOKIT_SWIFT_MODULE_DIRECTORY}")
# CMake's Swift compiler probe links a host macOS executable. That probe is
# incompatible with the Embedded Swift toolchain: it can compile an object,
# but it must not try to link against the host `System` library. Mark the
# compiler as usable before enable_language(Swift), where CMake performs the
# probe. The actual firmware targets below still compile with the embedded
# target and are checked by the real build.
set(CMAKE_Swift_COMPILER_WORKS YES CACHE INTERNAL "Embedded Swift compiler is usable")
enable_language(Swift)

set(SWIFT_TARGET "armv6m-none-none-eabi")
set(CLANG_ARCH_ABI_FLAGS "")
if(PICO_PLATFORM STREQUAL "rp2350-arm-s")
    set(SWIFT_TARGET "armv7em-none-none-eabi")
    string(APPEND CLANG_ARCH_ABI_FLAGS " -Xcc -mfloat-abi=soft")
elseif(PICO_PLATFORM STREQUAL "rp2350-riscv")
    set(SWIFT_TARGET "riscv32-none-none-eabi")
    string(APPEND CLANG_ARCH_ABI_FLAGS
        " -Xcc -march=rv32imac_zicsr_zifencei_zba_zbb_zbs_zbkb"
        " -Xcc -mabi=ilp32")
else()
    string(APPEND CLANG_ARCH_ABI_FLAGS " -Xcc -mfloat-abi=soft")
endif()

# Keep BoardLED's runtime declaration tied to the exact board selected by the
# generated project. Chip-family checks alone cannot distinguish Pico from
# Pico W, or Pico 2 from Pico 2 W.
set(PICOKIT_COMPILED_BOARD 255)
if(PICO_BOARD STREQUAL "pico")
    set(PICOKIT_COMPILED_BOARD 0)
elseif(PICO_BOARD STREQUAL "pico_w")
    set(PICOKIT_COMPILED_BOARD 1)
elseif(PICO_BOARD STREQUAL "pico2")
    set(PICOKIT_COMPILED_BOARD 2)
elseif(PICO_BOARD STREQUAL "pico2_w")
    set(PICOKIT_COMPILED_BOARD 3)
endif()

# Layer 4: the only C target that includes Pico SDK headers. All SDK access is
# behind fixed-width C functions so embedded Swift never imports SDK inlines.
set(PICOKIT_BRIDGE_DIR "${PICOKIT_ROOT}/Firmware")
set(PICOKIT_BRIDGE_MODULE_MAP "${PICOKIT_BRIDGE_DIR}/PicoKitSDKBridge.modulemap")
add_library(PicoKitSDKBridge STATIC "${PICOKIT_BRIDGE_DIR}/PicoKitSDKBridge.c")
target_include_directories(PicoKitSDKBridge PUBLIC "${PICOKIT_BRIDGE_DIR}")
target_compile_definitions(PicoKitSDKBridge PRIVATE
    PICOKIT_COMPILED_BOARD=${PICOKIT_COMPILED_BOARD}
)
option(PICOKIT_BRIDGE_WARNINGS
    "Enable strict warnings for PicoKitSDKBridge.c" OFF)
if(PICOKIT_BRIDGE_WARNINGS)
    set(PICOKIT_BRIDGE_WARNING_FLAGS
        -Wall -Wextra -Wconversion -Wshadow
        -Wstrict-prototypes -Wmissing-prototypes
        -Wcast-align -Wcast-qual -Wpointer-arith -Wformat=2
        -fanalyzer -Werror
    )
    set_source_files_properties("${PICOKIT_BRIDGE_DIR}/PicoKitSDKBridge.c"
        PROPERTIES COMPILE_OPTIONS
        "${PICOKIT_BRIDGE_WARNING_FLAGS}"
    )
else()
    # Clear source properties when an existing build directory is reconfigured
    # from ON to OFF; CMake does not remove them automatically.
    set_source_files_properties("${PICOKIT_BRIDGE_DIR}/PicoKitSDKBridge.c"
        PROPERTIES COMPILE_OPTIONS "")
endif()
set(PICOKIT_SDK_LIBRARIES
    pico_stdlib pico_status_led hardware_adc hardware_dma hardware_i2c
    hardware_pwm hardware_spi hardware_watchdog
)
# Keep the SDK implementation closure private to the C bridge. PUBLIC linkage
# causes CMake to attach the same INTERFACE sources and definitions to every
# Swift consumer, compiling large portions of the SDK two or three times.
target_link_libraries(PicoKitSDKBridge PRIVATE ${PICOKIT_SDK_LIBRARIES})
if(PICOKIT_ENABLE_USB)
    target_compile_definitions(PicoKitSDKBridge PRIVATE
        PICOKIT_ENABLE_USB=1
        PICO_STDIO_USB_STDOUT_TIMEOUT_US=${PICOKIT_USB_STDOUT_TIMEOUT_US}
        PICO_ENABLE_USB_RESET_VIA_BAUD_RATE=1
        PICO_ENABLE_USB_RESET_VIA_VENDOR_INTERFACE=1
    )
    pico_enable_stdio_usb(PicoKitSDKBridge 1)
else()
    target_compile_definitions(PicoKitSDKBridge PRIVATE PICOKIT_ENABLE_USB=0)
    pico_enable_stdio_usb(PicoKitSDKBridge 0)
endif()
pico_enable_stdio_uart(PicoKitSDKBridge 0)

# Layers 2, 1, and public facade. This is a real Swift library; firmware
# sources import PicoKit and link it instead of calling a project-local shim.
file(GLOB PICOKIT_CORE_SOURCES CONFIGURE_DEPENDS "${PICOKIT_ROOT}/Sources/PicoKitCore/*.swift")
file(GLOB PICOKIT_HAL_SOURCES CONFIGURE_DEPENDS "${PICOKIT_ROOT}/Sources/PicoKitHAL/*.swift")
file(GLOB PICOKIT_FACADE_SOURCES CONFIGURE_DEPENDS "${PICOKIT_ROOT}/Sources/PicoKitFacade/*.swift")
add_library(PicoKit STATIC ${PICOKIT_CORE_SOURCES} ${PICOKIT_HAL_SOURCES} ${PICOKIT_FACADE_SOURCES})
set_target_properties(PicoKit PROPERTIES LINKER_LANGUAGE CXX Swift_MODULE_NAME PicoKit)
# Keep the bridge's SDK interface private to PicoKit. Static-library
# dependencies still need to be listed on the final firmware target, but
# exposing the bridge publicly makes CMake forward every valued Pico SDK
# definition into the application's Swift compile command.
target_link_libraries(PicoKit PRIVATE PicoKitSDKBridge)

# Pico SDK interface targets contain C-only options. Keep them on C targets;
# Swift receives only the architecture, module, and bridge header it needs.
# SDK definitions remain available to the explicit third-party Swift extension
# helper below, whose sources may intentionally import SDK-backed C modules.
set_target_properties(pico_standard_link PROPERTIES INTERFACE_COMPILE_OPTIONS "")
target_compile_options(pico_standard_link INTERFACE "$<$<COMPILE_LANGUAGE:C>:SHELL: -ffunction-sections -fdata-sections>")
if(TARGET pico_float_pico_vfp)
    set_target_properties(pico_float_pico_vfp PROPERTIES INTERFACE_COMPILE_OPTIONS "")
endif()

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

foreach(library ${PICOKIT_SDK_LIBRARIES})
    picokit_collect_definitions(${library})
endforeach()
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
    -Xcc -fmodule-map-file=${PICOKIT_BRIDGE_MODULE_MAP}
    -Xcc -I${PICOKIT_BRIDGE_DIR}
    ${IMPLICIT_INCLUDES}
>")

add_executable(${PICOKIT_PRODUCT} ${PICOKIT_SOURCES})
set_target_properties(${PICOKIT_PRODUCT} PROPERTIES LINKER_LANGUAGE CXX)
# Embedded Swift's runtime archives carry fixed-width enum ABI metadata while
# the GNU linker defaults to variable-size enums. The C and Swift sides already
# use the required -fshort-enums ABI; suppress only these known, safe linker
# diagnostics. Embedded firmware never needs an executable process stack.
target_link_options(${PICOKIT_PRODUCT} PRIVATE
    "-Wl,-z,noexecstack"
    # The SDK runtime initializers are registered through linker sections, so
    # they have no ordinary undefined reference that would pull their object
    # files out of PicoKitSDKBridge's static archive. Force one symbol from
    # each registration object into the final image; this restores the SDK's
    # clock/reset/vector initialization before USB CDC starts.
    "LINKER:-u,runtime_init_spin_locks_reset"
    "LINKER:-u,runtime_init_clocks"
)
# The ARM GNU linker emits enum-size ABI diagnostics for Embedded Swift's
# runtime archives and supports this suppression. The RISC-V linker shipped
# with the Pico SDK toolchain does not recognize the option, and its ABI does
# not produce the same diagnostic, so keep it ARM-only.
if(NOT PICO_PLATFORM STREQUAL "rp2350-riscv")
    target_link_options(${PICOKIT_PRODUCT} PRIVATE "-Wl,--no-enum-size-warning")
endif()
if(PICOKIT_ENABLE_USB)
    target_compile_options(${PICOKIT_PRODUCT} PRIVATE
        "$<$<COMPILE_LANGUAGE:C>:-DPICO_ENABLE_USB_RESET_VIA_BAUD_RATE=1>"
        "$<$<COMPILE_LANGUAGE:CXX>:-DPICO_ENABLE_USB_RESET_VIA_BAUD_RATE=1>"
        "$<$<COMPILE_LANGUAGE:C>:-DPICO_ENABLE_USB_RESET_VIA_VENDOR_INTERFACE=1>"
        "$<$<COMPILE_LANGUAGE:CXX>:-DPICO_ENABLE_USB_RESET_VIA_VENDOR_INTERFACE=1>"
    )
endif()
target_compile_options(${PICOKIT_PRODUCT} PRIVATE "$<$<COMPILE_LANGUAGE:Swift>:SHELL:
    -target ${SWIFT_TARGET}
    -enable-experimental-feature Embedded
    -parse-as-library
    -I ${PICOKIT_SWIFT_MODULE_DIRECTORY}
    -Xcc -fmodule-map-file=${PICOKIT_BRIDGE_MODULE_MAP}
    -Xcc -I${PICOKIT_BRIDGE_DIR}
>")
target_link_libraries(${PICOKIT_PRODUCT} PRIVATE PicoKit PicoKitSDKBridge)

# Application-owned interoperability stays outside PicoKit's bridge. C and
# C++ adapters in Firmware/Interop are compiled into the firmware target, while
# their umbrella header and module maps are imported only by application Swift.
if(NOT DEFINED PICOKIT_APP_INTEROP_DIR)
    set(PICOKIT_APP_INTEROP_DIR "${CMAKE_SOURCE_DIR}/Interop")
endif()
if(EXISTS "${PICOKIT_APP_INTEROP_DIR}")
    file(GLOB_RECURSE PICOKIT_APP_INTEROP_SOURCES CONFIGURE_DEPENDS
        "${PICOKIT_APP_INTEROP_DIR}/*.c"
        "${PICOKIT_APP_INTEROP_DIR}/*.cc"
        "${PICOKIT_APP_INTEROP_DIR}/*.cpp")
    if(PICOKIT_APP_INTEROP_SOURCES)
        target_sources(${PICOKIT_PRODUCT} PRIVATE ${PICOKIT_APP_INTEROP_SOURCES})
    endif()
    target_include_directories(${PICOKIT_PRODUCT} PRIVATE "${PICOKIT_APP_INTEROP_DIR}")
endif()
if(PICOKIT_ENABLE_USB)
    pico_enable_stdio_usb(${PICOKIT_PRODUCT} 1)
else()
    pico_enable_stdio_usb(${PICOKIT_PRODUCT} 0)
endif()
pico_enable_stdio_uart(${PICOKIT_PRODUCT} 0)
# pico_add_extra_outputs() normally adds PICO_TARGET_NAME through
# target_compile_definitions(), which would also be forwarded to Swift. Keep
# the C/C++ metadata definition without making it a Swift conditional flag.
set(PICO_NO_TARGET_NAME ON)
pico_add_extra_outputs(${PICOKIT_PRODUCT})
target_compile_definitions(${PICOKIT_PRODUCT} PRIVATE
    "$<$<COMPILE_LANGUAGE:C>:PICO_TARGET_NAME=\"${PICOKIT_PRODUCT}\">"
    "$<$<COMPILE_LANGUAGE:CXX>:PICO_TARGET_NAME=\"${PICOKIT_PRODUCT}\">"
)

# Add a small, explicit extension point for application dependencies.  A
# project's Firmware/Dependencies.cmake can use this helper after including
# this file to compile a Swift package target for the same embedded platform:
#
#   picokit_add_swift_library(Foo SOURCE_DIR ".../Sources/Foo")
#   target_link_libraries(${PICOKIT_PRODUCT} PRIVATE Foo)
#
# C/C++ packages do not need a wrapper: add them with FetchContent or
# add_subdirectory in Dependencies.cmake, then link their CMake target to the
# application in the same way.
function(picokit_add_swift_library target)
    cmake_parse_arguments(ARG "" "SOURCE_DIR" "SOURCES;LINK_LIBRARIES" ${ARGN})
    if(ARG_SOURCE_DIR AND ARG_SOURCES)
        message(FATAL_ERROR "picokit_add_swift_library accepts SOURCE_DIR or SOURCES, not both")
    endif()
    if(ARG_SOURCE_DIR)
        file(GLOB_RECURSE ARG_SOURCES CONFIGURE_DEPENDS "${ARG_SOURCE_DIR}/*.swift")
    endif()
    if(NOT ARG_SOURCES)
        message(FATAL_ERROR "picokit_add_swift_library(${target}) has no Swift sources")
    endif()

    add_library(${target} STATIC ${ARG_SOURCES})
    set_target_properties(${target} PROPERTIES
        LINKER_LANGUAGE CXX
        Swift_MODULE_NAME ${target}
        Swift_MODULE_DIRECTORY "${PICOKIT_SWIFT_MODULE_DIRECTORY}"
    )
    target_compile_options(${target} PRIVATE "$<$<COMPILE_LANGUAGE:Swift>:SHELL:
        -target ${SWIFT_TARGET}
        -enable-experimental-feature Embedded
        -parse-as-library
        -I ${PICOKIT_SWIFT_MODULE_DIRECTORY}
        ${CLANG_ARCH_ABI_FLAGS}
        -Xcc -fshort-enums
        -Xfrontend -function-sections
        ${COMPILE_DEFINITIONS}
        ${IMPLICIT_INCLUDES}
    >")
    if(ARG_LINK_LIBRARIES)
        target_link_libraries(${target} PUBLIC ${ARG_LINK_LIBRARIES})
    endif()
endfunction()

# Generated v0.2 dependencies are deterministic and read-only. Preserve the
# v0.1 Dependencies.cmake hook, then allow an intentionally untracked local
# extension file. A caller can still override PICOKIT_DEPENDENCIES_FILE.
if(NOT DEFINED PICOKIT_DEPENDENCIES_FILE)
    set(PICOKIT_DEPENDENCIES_FILE "${CMAKE_SOURCE_DIR}/Dependencies.cmake")
endif()
set(PICOKIT_GENERATED_DEPENDENCIES_FILE "${CMAKE_SOURCE_DIR}/Generated/Dependencies.cmake")
if(EXISTS "${PICOKIT_GENERATED_DEPENDENCIES_FILE}")
    include("${PICOKIT_GENERATED_DEPENDENCIES_FILE}")
endif()
if(EXISTS "${PICOKIT_DEPENDENCIES_FILE}")
    include("${PICOKIT_DEPENDENCIES_FILE}")
endif()
if(EXISTS "${CMAKE_SOURCE_DIR}/Dependencies.local.cmake")
    include("${CMAKE_SOURCE_DIR}/Dependencies.local.cmake")
endif()

# Discover application module maps after dependency CMake has run. Duplicate
# module names are rejected here so the Clang importer never silently chooses
# a header from the wrong library.
set(PICOKIT_APP_IMPORT_FLAGS ${PICOKIT_DEPENDENCY_CLANG_FLAGS})
set(PICOKIT_APP_MODULE_NAMES)
set(PICOKIT_APP_MODULE_MAPS ${PICOKIT_DEPENDENCY_MODULE_MAPS})
if(EXISTS "${PICOKIT_APP_INTEROP_DIR}")
    file(GLOB_RECURSE PICOKIT_LOCAL_MODULE_MAPS CONFIGURE_DEPENDS
        "${PICOKIT_APP_INTEROP_DIR}/*module.modulemap")
    list(APPEND PICOKIT_APP_MODULE_MAPS ${PICOKIT_LOCAL_MODULE_MAPS})
    foreach(module_map ${PICOKIT_APP_MODULE_MAPS})
        file(STRINGS "${module_map}" module_lines REGEX "^[ \t]*(explicit[ \t]+)?module[ \t]+[A-Za-z_][A-Za-z0-9_]*")
        foreach(module_line ${module_lines})
            string(REGEX REPLACE "^[ \t]*(explicit[ \t]+)?module[ \t]+([A-Za-z_][A-Za-z0-9_]*).*$" "\\2" module_name "${module_line}")
            if(module_name IN_LIST PICOKIT_APP_MODULE_NAMES)
                message(FATAL_ERROR "Duplicate application Clang module '${module_name}' in ${module_map}")
            endif()
            list(APPEND PICOKIT_APP_MODULE_NAMES "${module_name}")
        endforeach()
        get_filename_component(module_directory "${module_map}" DIRECTORY)
        list(APPEND PICOKIT_APP_IMPORT_FLAGS "-Xcc" "-fmodule-map-file=${module_map}" "-Xcc" "-I${module_directory}")
    endforeach()

    if(EXISTS "${PICOKIT_APP_INTEROP_DIR}/AppInterop.h")
        list(APPEND PICOKIT_APP_IMPORT_FLAGS
            "-import-bridging-header" "${PICOKIT_APP_INTEROP_DIR}/AppInterop.h")
    endif()
endif()
if(PICOKIT_APP_IMPORT_FLAGS)
    # Keep every -Xcc paired with its following Clang option. CMake otherwise
    # de-duplicates repeated -Xcc list elements and exposes later Clang flags
    # directly to swiftc.
    list(JOIN PICOKIT_APP_IMPORT_FLAGS " " PICOKIT_APP_IMPORT_FLAGS_SHELL)
    target_compile_options(${PICOKIT_PRODUCT} PRIVATE
        "$<$<COMPILE_LANGUAGE:Swift>:SHELL:${PICOKIT_APP_IMPORT_FLAGS_SHELL}>")
endif()
