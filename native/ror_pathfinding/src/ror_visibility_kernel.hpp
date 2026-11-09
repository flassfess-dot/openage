#pragma once

#include <cstdint>
#include <vector>

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/vector2.hpp>

namespace godot {

class RoRVisibilityKernel : public RefCounted {
    GDCLASS(RoRVisibilityKernel, RefCounted)

public:
    void configure(int32_t width, int32_t height);
    PackedInt32Array vision_cells(const Vector2 &center, double radius) const;
    bool is_configured() const;
    Dictionary apply_source_deltas(const Dictionary &input) const;
    Dictionary apply_owned_source_deltas(Dictionary states_by_player, Dictionary counts_by_player, int64_t observer, const Dictionary &input) const;
    Dictionary apply_observer_source_deltas(Dictionary states_by_player, Dictionary counts_by_player, const Dictionary &input) const;
    Dictionary collect_source_deltas(const Dictionary &input) const;

protected:
    static void _bind_methods();

private:
    void publish_observer_visibility(const Dictionary &publication, const std::vector<int32_t> &visible,
        const std::vector<int32_t> &explored, const std::vector<int32_t> &newly_visible) const;
    Dictionary apply_source_deltas_internal(const Dictionary &input, PackedByteArray &states, PackedInt32Array &counts) const;
    int32_t width_ = 0;
    int32_t height_ = 0;
};

} // namespace godot
