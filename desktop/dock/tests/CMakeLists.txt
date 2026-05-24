set(CMAKE_AUTOMOC ON)
find_package(Qt6 COMPONENTS Core Test REQUIRED)

add_executable(test_dock_model
    test_dock_model.cpp
    ../dock_model.cpp
    ../dock_model.h
)
target_link_libraries(test_dock_model PRIVATE
    Qt6::Core Qt6::Test
    aqua-qt
    core-services
)
target_include_directories(test_dock_model PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/..)
add_test(NAME dock::model COMMAND test_dock_model)
