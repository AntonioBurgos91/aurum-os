# core-services: XDG desktop file parser, app launcher, future IPC helpers.
# AUTOMOC is on because profile_client.h defines a QObject (ProfileClient) and
# would otherwise miss the generated moc_*.cpp.
set(CMAKE_AUTOMOC ON)
find_package(Qt6 COMPONENTS Core REQUIRED)

add_library(core-services SHARED
    core_services.cpp
    profile_client.cpp
    profile_client.h
)
target_link_libraries(core-services PUBLIC Qt6::Core)
target_include_directories(core-services PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})

install(TARGETS core-services
        LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR})

# Public headers for downstream apps. Install to <prefix>/include/aurum/.
install(FILES core_services.h profile_client.h
        DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}/aurum)
