# ml-integrations: Quick Look previews (ipynb, safetensors, parquet) + future
# MLflow/W&B hooks.
find_package(Qt6 COMPONENTS Core REQUIRED)

add_library(ml-integrations SHARED ml_integrations.cpp)
target_link_libraries(ml-integrations PUBLIC Qt6::Core)
target_include_directories(ml-integrations PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})

install(TARGETS ml-integrations LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR})

# Public header for downstream apps. Installs to <prefix>/include/aurum/.
install(FILES ml_integrations.h DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}/aurum)
