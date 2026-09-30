#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/rect2i.hpp>

namespace godot {

// Builds the same continuous terrain surface as environment_terrain.gd.
// Only immutable numeric inputs cross the boundary; no scene or texture access.
class RoRTerrainKernel : public RefCounted {
    GDCLASS(RoRTerrainKernel, RefCounted)
public:
    Dictionary build_mesh(const Rect2i &bounds, const PackedInt32Array &cells,
        const PackedFloat32Array &heights, const PackedInt32Array &frames,
        const PackedFloat32Array &materials, int64_t seed, int32_t maximum_subdivisions = 16) const;
protected:
    static void _bind_methods();
};

} // namespace godot
