set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)

find_package(Qt6 COMPONENTS
    Core Gui Quick QuickControls2 Widgets Qml
    Network DBus Qml REQUIRED)

add_executable(aurum-spotlight
    main.cpp
    search_aggregator.cpp
    search_aggregator.h
    plugins/plugin.h
    plugins/apps_plugin.cpp
    plugins/apps_plugin.h
    plugins/files_plugin.cpp
    plugins/files_plugin.h
    plugins/calculator_plugin.cpp
    plugins/calculator_plugin.h
    plugins/huggingface_plugin.cpp
    plugins/huggingface_plugin.h
    plugins/arxiv_plugin.cpp
    plugins/arxiv_plugin.h
)
target_link_libraries(aurum-spotlight PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Quick
    Qt6::QuickControls2
    Qt6::Widgets
    Qt6::Qml
    Qt6::Network
    Qt6::DBus
    core-services
    aqua-qt
    ml-integrations
)
target_include_directories(aurum-spotlight PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})

install(TARGETS aurum-spotlight RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
install(FILES Spotlight.qml DESTINATION ${CMAKE_INSTALL_DATADIR}/aurum-os/qml)
