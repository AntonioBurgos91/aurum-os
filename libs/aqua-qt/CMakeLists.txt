# aqua-qt: visual tokens, Qt palette, Fusion base style, QML primitives.
find_package(Qt6 COMPONENTS Core Gui Widgets REQUIRED)

add_library(aqua-qt SHARED style_engine.cpp)
target_link_libraries(aqua-qt PUBLIC Qt6::Core Qt6::Gui Qt6::Widgets)
target_include_directories(aqua-qt PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})

install(TARGETS aqua-qt
        LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR})

# Public header for downstream apps. Installs to <prefix>/include/aurum/.
install(FILES style_engine.h DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}/aurum)

# Install the QML module (Aurum.Aqua) alongside the system Qt6 QML modules so
# any AurumOS QML can `import Aurum.Aqua 1.0` without QML2_IMPORT_PATH hacks.
install(DIRECTORY qml/Aurum
        DESTINATION ${CMAKE_INSTALL_LIBDIR}/qt6/qml
        FILES_MATCHING
        PATTERN "*.qml"
        PATTERN "qmldir")
