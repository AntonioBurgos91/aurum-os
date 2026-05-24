set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)

find_package(Qt6 COMPONENTS Core Gui Quick QuickControls2 Widgets REQUIRED)

add_executable(aurum-coming-soon
    main.cpp
)
target_link_libraries(aurum-coming-soon PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Quick
    Qt6::QuickControls2
    Qt6::Widgets
    core-services
    aqua-qt
)
target_include_directories(aurum-coming-soon PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})

install(TARGETS aurum-coming-soon RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
install(FILES ComingSoon.qml DESTINATION ${CMAKE_INSTALL_DATADIR}/aurum-os/qml)
