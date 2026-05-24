set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)

find_package(Qt6 COMPONENTS Core Gui Quick QuickControls2 Widgets DBus REQUIRED)

add_executable(aurum-menubar main.cpp)
target_link_libraries(aurum-menubar PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Quick
    Qt6::QuickControls2
    Qt6::Widgets
    Qt6::DBus
    core-services
    aqua-qt
    ml-integrations
)
target_include_directories(aurum-menubar PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})

install(TARGETS aurum-menubar RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
install(FILES MenuBar.qml DESTINATION ${CMAKE_INSTALL_DATADIR}/aurum-os/qml)
