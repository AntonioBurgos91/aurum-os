set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)

find_package(Qt6 COMPONENTS Core Gui Quick QuickControls2 Widgets REQUIRED)

add_executable(aurum-notifications main.cpp)
target_link_libraries(aurum-notifications PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Quick
    Qt6::QuickControls2
    Qt6::Widgets
    core-services
    aqua-qt
)
target_include_directories(aurum-notifications PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})

install(TARGETS aurum-notifications RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
install(FILES Notifications.qml DESTINATION ${CMAKE_INSTALL_DATADIR}/aurum-os/qml)
