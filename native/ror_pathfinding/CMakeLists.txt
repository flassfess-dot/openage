cmake_minimum_required(VERSION 3.19)

project(ror_pathfinding LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(GODOT_CPP_PATH "${CMAKE_CURRENT_SOURCE_DIR}/../../.tools/godot-cpp" CACHE PATH "Path to godot-cpp")
set(GODOTCPP_API_VERSION "4.7" CACHE STRING "Godot API version" FORCE)
set(GODOTCPP_BUILD_PROFILE "${CMAKE_CURRENT_SOURCE_DIR}/godot-cpp-profile.json" CACHE PATH "Minimal binding profile" FORCE)
set(GODOTCPP_ENABLE_TESTING OFF CACHE BOOL "Disable godot-cpp tests" FORCE)
set(GODOTCPP_TARGET "template_release" CACHE STRING "Godot target" FORCE)

add_subdirectory("${GODOT_CPP_PATH}" "${CMAKE_BINARY_DIR}/godot-cpp")

add_library(ror_pathfinding SHARED
    src/register_types.cpp
    src/ror_path_kernel.cpp
    src/ror_visibility_kernel.cpp
)

target_include_directories(ror_pathfinding PRIVATE src)
target_link_libraries(ror_pathfinding PRIVATE godot-cpp)

set_target_properties(ror_pathfinding PROPERTIES
    PREFIX ""
    OUTPUT_NAME "ror_pathfinding.windows.template_release.x86_64"
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/../../prototype/bin"
    LIBRARY_OUTPUT_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/../../prototype/bin"
)
