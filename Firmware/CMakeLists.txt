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
target_link_libraries(PicoKitSDKBridge PUBLIC pico_stdlib pico_status_led hardware_adc hardware_dma hardware_i2c hardware_pwm hardware_spi hardware_watchdog)

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

add_executable(${PICOKIT_PRODUCT} ${PICOKIT_SOURCES})
set_target_properties(${PICOKIT_PRODUCT} PROPERTIES LINKER_LANGUAGE CXX)
target_compile_definitions(${PICOKIT_PRODUCT} PRIVATE
    PICO_ENABLE_USB_RESET_VIA_BAUD_RATE=1
    PICO_ENABLE_USB_RESET_VIA_VENDOR_INTERFACE=1
)
target_compile_options(${PICOKIT_PRODUCT} PRIVATE "$<$<COMPILE_LANGUAGE:Swift>:SHELL:
    -target ${SWIFT_TARGET}
    -enable-experimental-feature Embedded
    -parse-as-library
    -I ${PICOKIT_SWIFT_MODULE_DIRECTORY}
>")
target_link_libraries(${PICOKIT_PRODUCT} PRIVATE PicoKit)

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
pico_enable_stdio_usb(${PICOKIT_PRODUCT} 1)
pico_enable_stdio_uart(${PICOKIT_PRODUCT} 0)
pico_add_extra_outputs(${PICOKIT_PRODUCT})

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
