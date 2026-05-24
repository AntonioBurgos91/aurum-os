set(CMAKE_AUTOMOC ON)
find_package(Qt6 COMPONENTS Core Test REQUIRED)

add_executable(test_finder_model
    test_finder_model.cpp
    ../finder_model.cpp
    ../finder_model.h
)
target_link_libraries(test_finder_model PRIVATE
    Qt6::Core Qt6::Test
    aqua-qt
    core-services
    ml-integrations
)
target_include_directories(test_finder_model PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/..)
add_test(NAME finder::model COMMAND test_finder_model)

add_executable(test_sidebar_model
    test_sidebar_model.cpp
    ../sidebar_model.cpp
    ../sidebar_model.h
)
target_link_libraries(test_sidebar_model PRIVATE
    Qt6::Core Qt6::Test
    aqua-qt
)
target_include_directories(test_sidebar_model PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/..)
add_test(NAME finder::sidebar COMMAND test_sidebar_model)
