cmake_minimum_required(VERSION 3.10)
set(PROJECT_NAME "llm_llamacpp")
project(${PROJECT_NAME} LANGUAGES CXX)

# This value is used when generating builds using this plugin, so it must
# not be changed
set(PLUGIN_NAME "llm_llamacpp_plugin")

add_library(${PLUGIN_NAME} SHARED
  "llm_llamacpp_plugin.cc"
)

apply_standard_settings(${PLUGIN_NAME})

set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)

target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")

target_link_libraries(${PLUGIN_NAME} PRIVATE flutter)
target_link_libraries(${PLUGIN_NAME} PRIVATE PkgConfig::GTK)

# Install the native library
install(FILES "${CMAKE_CURRENT_SOURCE_DIR}/libs/libllama.so"
  DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

set(llm_llamacpp_bundled_libraries
  "${CMAKE_CURRENT_SOURCE_DIR}/libs/libllama.so"
  PARENT_SCOPE
)

