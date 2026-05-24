set(CMAKE_AUTOMOC ON)

find_package(Qt6 COMPONENTS Core Test REQUIRED)

# One executable per test class — Qt's QTest convention. Each one is added
# via add_test() so `ctest` finds them.
add_executable(test_desktop_entry  test_desktop_entry.cpp)
target_link_libraries(test_desktop_entry PRIVATE Qt6::Core Qt6::Test core-services)
add_test(NAME core_services::desktop_entry COMMAND test_desktop_entry)

add_executable(test_field_codes    test_field_codes.cpp)
target_link_libraries(test_field_codes PRIVATE Qt6::Core Qt6::Test core-services)
add_test(NAME core_services::field_codes COMMAND test_field_codes)

add_executable(test_resolve_path   test_resolve_path.cpp)
target_link_libraries(test_resolve_path PRIVATE Qt6::Core Qt6::Test core-services)
add_test(NAME core_services::resolve_path COMMAND test_resolve_path)

add_executable(test_dedup_mutex    test_dedup_mutex.cpp)
target_link_libraries(test_dedup_mutex PRIVATE Qt6::Core Qt6::Test core-services)
add_test(NAME core_services::dedup_mutex COMMAND test_dedup_mutex)
