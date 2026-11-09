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
    src/ror_visibility_observers.cpp
    src/ror_terrain_kernel.cpp
    src/ror_read_model_kernel.cpp
    src/ror_movement_pipeline.cpp
    src/ror_route_preparation.cpp
    src/ror_contact_frame.cpp
    src/ror_selection_mesh.cpp
    src/ror_actor_pipeline.cpp
    src/ror_gather_controller.cpp
    src/ror_combat_awareness.cpp
    src/ror_entity_read_index.cpp
    src/ror_entity_change_journal.cpp
    src/ror_read_model_queries.cpp
    src/ror_read_model_projection.cpp
    src/ror_save_file_kernel.cpp
)

target_include_directories(ror_pathfinding PRIVATE src)
target_link_libraries(ror_pathfinding PRIVATE godot-cpp)

# Math and Variant wrappers live in godot-cpp, outside the actor translation
# units. Optimize them together in Release while retaining the normal floating
# point rules; no fast-math or host-specific instruction set is required.
include(CheckIPOSupported)
check_ipo_supported(RESULT ROR_IPO_SUPPORTED OUTPUT ROR_IPO_ERROR LANGUAGES CXX)
if(ROR_IPO_SUPPORTED)
    set_property(TARGET ror_pathfinding godot-cpp PROPERTY INTERPROCEDURAL_OPTIMIZATION_RELEASE TRUE)
    if(MINGW AND CMAKE_CXX_COMPILER_AR AND CMAKE_CXX_COMPILER_RANLIB)
        # MinGW's shared-library object archive also contains LTO bytecode.
        set(CMAKE_AR "${CMAKE_CXX_COMPILER_AR}")
        set(CMAKE_RANLIB "${CMAKE_CXX_COMPILER_RANLIB}")
    endif()
else()
    message(STATUS "Release interprocedural optimization unavailable: ${ROR_IPO_ERROR}")
endif()
if(MINGW)
    # Keep address-to-function data for sampling the stripped Release DLL.
    target_link_options(ror_pathfinding PRIVATE "-Wl,-Map,${CMAKE_BINARY_DIR}/ror_pathfinding.map")
endif()

set_target_properties(ror_pathfinding PROPERTIES
    PREFIX ""
    OUTPUT_NAME "ror_pathfinding.windows.template_release.x86_64"
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
    LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
)
