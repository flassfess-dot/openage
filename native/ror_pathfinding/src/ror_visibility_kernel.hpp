#pragma once

#include <cstdint>

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/vector2.hpp>

namespace godot {

class RoRVisibilityKernel : public RefCounted {
    GDCLASS(RoRVisibilityKernel, RefCounted)

public:
    void configure(int32_t width, int32_t height);
    PackedInt32Array vision_cells(const Vector2 &center, double radius) const;
    bool is_configured() const;

protected:
    static void _bind_methods();

private:
    int32_t width_ = 0;
    int32_t height_ = 0;
};

} // namespace godot
