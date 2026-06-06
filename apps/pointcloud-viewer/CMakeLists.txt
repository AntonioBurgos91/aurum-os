cmake_minimum_required(VERSION 3.16)
project(aurum-pointcloud-viewer LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(Qt6 COMPONENTS Core Gui OpenGL OpenGLWidgets Widgets REQUIRED)

# Shared core: point cloud + GL renderer.
add_library(pcv-core STATIC src/point_cloud.cpp src/gl_renderer.cpp)
target_link_libraries(pcv-core PUBLIC Qt6::Core Qt6::Gui Qt6::OpenGL)
target_include_directories(pcv-core PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/src)

# Interactive native viewer.
add_executable(aurum-pointcloud-viewer src/main.cpp)
target_link_libraries(aurum-pointcloud-viewer PRIVATE pcv-core Qt6::Widgets Qt6::OpenGLWidgets)

# Headless renderer (CI / servers without a display).
add_executable(pcv-render-offscreen src/render_offscreen.cpp)
target_link_libraries(pcv-render-offscreen PRIVATE pcv-core Qt6::Gui)

# Install the viewer + headless renderer into the system (used by the ISO build,
# which runs `cmake --install`). CMAKE_INSTALL_PREFIX is /usr/local there.
include(GNUInstallDirs)
install(TARGETS aurum-pointcloud-viewer pcv-render-offscreen
        RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})

if(BUILD_TESTS)
    enable_testing()
    find_package(Qt6 COMPONENTS Test REQUIRED)
    add_executable(test_point_cloud tests/test_point_cloud.cpp)
    target_link_libraries(test_point_cloud PRIVATE pcv-core Qt6::Test)
    add_test(NAME pcv::point_cloud COMMAND test_point_cloud)
endif()
