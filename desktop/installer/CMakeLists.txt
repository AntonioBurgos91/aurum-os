set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)

find_package(Qt6 COMPONENTS Core Gui Quick QuickControls2 Widgets REQUIRED)

add_executable(aurum-installer
    main.cpp
    disk_lister.cpp
    disk_lister.h
    installer_backend.cpp
    installer_backend.h
)
target_link_libraries(aurum-installer PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Quick
    Qt6::QuickControls2
    Qt6::Widgets
    core-services
    aqua-qt
)
target_include_directories(aurum-installer PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})

install(TARGETS aurum-installer RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
install(FILES Installer.qml DESTINATION ${CMAKE_INSTALL_DATADIR}/aurum-os/qml)
install(DIRECTORY pages/
        DESTINATION ${CMAKE_INSTALL_DATADIR}/aurum-os/qml/pages
        FILES_MATCHING PATTERN "*.qml")
install(FILES polkit/org.aurumos.installer.policy
        DESTINATION ${CMAKE_INSTALL_DATADIR}/polkit-1/actions)
