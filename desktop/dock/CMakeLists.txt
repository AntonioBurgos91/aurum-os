set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)

find_package(Qt6 COMPONENTS Core Gui Quick QuickControls2 Widgets DBus REQUIRED)

add_executable(aurum-dock
    main.cpp
    dock_model.cpp
    dock_model.h
)
target_link_libraries(aurum-dock PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Quick
    Qt6::QuickControls2
    Qt6::Widgets
    Qt6::DBus
    core-services
    aqua-qt
)
target_include_directories(aurum-dock PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})

install(TARGETS aurum-dock RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
install(FILES Dock.qml DESTINATION ${CMAKE_INSTALL_DATADIR}/aurum-os/qml)
