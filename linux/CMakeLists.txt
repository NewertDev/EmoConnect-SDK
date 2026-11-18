cmake_minimum_required(VERSION 3.10)

set(PROJECT_NAME "emoconnect_sdk")
project(${PROJECT_NAME} LANGUAGES NONE)

# The prebuilt core, bundled next to the app (lib/ of the bundle).
set(emoconnect_sdk_bundled_libraries
  "${CMAKE_CURRENT_SOURCE_DIR}/lib/libemoconnect_core.so"
  PARENT_SCOPE
)