set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)

find_package(Qt6 COMPONENTS Core Gui Quick QuickControls2 Widgets REQUIRED)

add_executable(aurum-finder
    main.cpp
    finder_model.cpp
    finder_model.h
    sidebar_model.cpp
    sidebar_model.h
)
target_link_libraries(aurum-finder PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Quick
    Qt6::QuickControls2
    Qt6::Widgets
    core-services
    aqua-qt
    ml-integrations
)
target_include_directories(aurum-finder PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})

install(TARGETS aurum-finder RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
install(FILES Finder.qml DESTINATION ${CMAKE_INSTALL_DATADIR}/aurum-os/qml)
