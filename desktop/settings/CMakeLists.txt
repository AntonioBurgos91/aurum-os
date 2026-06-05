set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)

find_package(Qt6 COMPONENTS Core Gui Quick QuickControls2 Widgets DBus REQUIRED)

add_executable(aurum-settings
    main.cpp
    cuda_manager.cpp
    cuda_manager.h
    display_manager.cpp
    display_manager.h
    venv_manager.cpp
    venv_manager.h
    mlops_config.cpp
    mlops_config.h
    model_packs_model.cpp
    model_packs_model.h
)
target_link_libraries(aurum-settings PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Quick
    Qt6::QuickControls2
    Qt6::Widgets
    Qt6::DBus
    core-services
    aqua-qt
)
target_include_directories(aurum-settings PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})

install(TARGETS aurum-settings RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})
install(FILES Settings.qml HardwarePanel.qml ModelPacksPanel.qml
        DESTINATION ${CMAKE_INSTALL_DATADIR}/aurum-os/qml)
install(DIRECTORY sections/
        DESTINATION ${CMAKE_INSTALL_DATADIR}/aurum-os/qml/sections
        FILES_MATCHING PATTERN "*.qml")

# Privileged helper for CUDA toolkit switching (pkexec target).
install(PROGRAMS helpers/aurum-cuda-switch
        DESTINATION ${CMAKE_INSTALL_PREFIX}/libexec)

# Polkit action policy.
install(FILES polkit/org.aurumos.settings.policy
        DESTINATION ${CMAKE_INSTALL_DATADIR}/polkit-1/actions)
