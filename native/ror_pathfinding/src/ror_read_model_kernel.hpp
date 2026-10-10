#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>

namespace godot {

// Stateless; does not retain live entities or publications.
class RoRReadModelKernel : public RefCounted {
    GDCLASS(RoRReadModelKernel, RefCounted)

public:
    PackedInt32Array advance_idle_animation(const Array &entities, double delta) const;
    Dictionary project_render(const Dictionary &source, const Dictionary &previous, const Array &fields, const Array &nested_fields, int64_t schema) const;
    Dictionary project_ai(const Dictionary &source, const Dictionary &previous, int64_t observer_team, const Array &fields, const Array &array_fields, const Array &private_trade_fields) const;
    Dictionary encode_replay_variant(const Variant &source, bool quantize_numbers = true) const;
    Dictionary capture_frozen(const Variant &source, const Array &trusted) const;

protected:
    static void _bind_methods();
};

} // namespace godot
