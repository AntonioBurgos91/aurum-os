set(CMAKE_AUTOMOC ON)

find_package(Qt6 COMPONENTS Core Gui Test REQUIRED)

# The pure helpers under test live in display_manager.cpp (part of the
# aurum-settings executable, not a shared lib), so we compile that TU directly
# into the test. AUTOMOC picks up the QObject in display_manager.h.
add_executable(test_display_manager
    test_display_manager.cpp
    ../display_manager.cpp
)
target_link_libraries(test_display_manager PRIVATE Qt6::Core Qt6::Gui Qt6::Test)
target_include_directories(test_display_manager PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/..)
add_test(NAME settings::display_manager COMMAND test_display_manager)
