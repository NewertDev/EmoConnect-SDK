cmake_minimum_required(VERSION 3.14)

set(PROJECT_NAME "emoconnect_sdk")
project(${PROJECT_NAME} LANGUAGES NONE)

# The prebuilt core, copied next to the app's executable.
set(emoconnect_sdk_bundled_libraries
  "${CMAKE_CURRENT_SOURCE_DIR}/lib/emoconnect_core.dll"
  PARENT_SCOPE
)