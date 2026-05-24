# CMakeLists.txt for tests
add_executable(aurum-tests main.cpp)
target_link_libraries(aurum-tests PRIVATE 
    Qt6::Core 
    core-services
)
target_include_directories(aurum-tests PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})

add_test(NAME CoreServicesTest COMMAND aurum-tests)

# Quick Look preview pipeline driver. Linked against libml-integrations + Qt6
# Core. Not registered as a ctest because it requires an input file argument;
# tests/run_preview_tests.sh is what calls it.
add_executable(aurum-test-preview test_preview.cpp)
target_link_libraries(aurum-test-preview PRIVATE
    Qt6::Core
    ml-integrations
)
target_include_directories(aurum-test-preview PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
