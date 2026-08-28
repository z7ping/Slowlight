cmake_minimum_required(VERSION 3.14)
project(keyhook LANGUAGES CXX)

add_library(keyhook SHARED keyhook.cpp)
target_link_libraries(keyhook PRIVATE user32)

add_library(lock_overlay SHARED lock_overlay.cpp)
target_link_libraries(lock_overlay PRIVATE user32 gdi32)

# 输出到 runner 目录（与 exe 同目录，解决 DLL 找不到）
# 多配置生成器(VS)自动追加 /Debug/ 或 /Release/
set_target_properties(keyhook PROPERTIES
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/runner"
  LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/runner"
)
set_target_properties(lock_overlay PROPERTIES
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/runner"
  LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/runner"
)

# MSVC: treat source as UTF-8 (avoid code page 936 errors)
target_compile_options(lock_overlay PRIVATE /utf-8)
