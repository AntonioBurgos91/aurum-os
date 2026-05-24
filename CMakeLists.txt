cmake_minimum_required(VERSION 3.28)
project(AurumOS LANGUAGES CXX)

# Require C++23
set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# Build configuration options
option(BUILD_DESKTOP "Build the AurumOS Desktop Environment" ON)
option(BUILD_LIBS "Build AurumOS core libraries" ON)
option(BUILD_TESTS "Build verification tests" ON)

# Define installation paths (consistent with standard Linux hierarchies)
include(GNUInstallDirs)

# Locate dependencies
find_package(PkgConfig REQUIRED)

# Find Qt6
find_package(Qt6 COMPONENTS Core Quick Qml Widgets REQUIRED)

# Find Vulkan SDK
find_package(Vulkan REQUIRED)

# Find Wayland & wlroots via pkg-config
pkg_check_modules(WAYLAND_CLIENT REQUIRED wayland-client)
pkg_check_modules(WLROOTS REQUIRED wlroots>=0.17.0)
pkg_check_modules(XKBCOMMON REQUIRED xkbcommon)

# Common compilation flags
add_compile_options(-Wall -Wextra -Wpedantic -Werror=return-type)

if(BUILD_LIBS)
    message(STATUS "Configuring AurumOS Core Libraries...")
    add_subdirectory(libs/aqua-qt)
    add_subdirectory(libs/core-services)
    add_subdirectory(libs/ml-integrations)
endif()

if(BUILD_DESKTOP)
    message(STATUS "Configuring AurumOS Desktop Components...")
    add_subdirectory(desktop/dock)
    add_subdirectory(desktop/menubar)
    add_subdirectory(desktop/finder)
    add_subdirectory(desktop/spotlight)
    add_subdirectory(desktop/mission-control)
    add_subdirectory(desktop/notifications)
    add_subdirectory(desktop/settings)
    add_subdirectory(desktop/installer)
    add_subdirectory(desktop/coming-soon)
endif()

if(BUILD_TESTS)
    message(STATUS "Configuring AurumOS Tests...")
    enable_testing()
    add_subdirectory(tests)
    if(BUILD_LIBS)
        add_subdirectory(libs/core-services/tests)
    endif()
    if(BUILD_DESKTOP)
        add_subdirectory(desktop/finder/tests)
        add_subdirectory(desktop/dock/tests)
    endif()
endif()

# Print Configuration Summary
message(STATUS "--------------------------------------------------------")
message(STATUS "AurumOS Build Configuration Summary:")
message(STATUS "  C++ Standard:        ${CMAKE_CXX_STANDARD}")
message(STATUS "  Build Desktop DE:    ${BUILD_DESKTOP}")
message(STATUS "  Build Libraries:     ${BUILD_LIBS}")
message(STATUS "  Build Tests:         ${BUILD_TESTS}")
message(STATUS "  Qt6 Version:         ${Qt6_VERSION}")
message(STATUS "  Vulkan Found:        ${Vulkan_FOUND} (${Vulkan_LIBRARY})")
message(STATUS "  wlroots Version:     ${WLROOTS_VERSION}")
message(STATUS "--------------------------------------------------------")
