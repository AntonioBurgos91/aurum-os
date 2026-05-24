set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)

find_package(Qt6 COMPONENTS Core Gui Quick QuickControls2 Widgets REQUIRED)

add_executable(aurum-mission-control
    main.cpp
    hypr_client.cpp
    hypr_client.h
)
target_link_libraries(aurum-mission-control PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Quick
    Qt6::QuickControls2
    Qt6::Widgets
    core-services
    aqua-qt
)
target_include_directories(aurum-mission-control PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})

install(TARGETS aurum-mission-control RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
install(FILES MissionControl.qml DESTINATION ${CMAKE_INSTALL_DATADIR}/aurum-os/qml)
