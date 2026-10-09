#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>

namespace godot {

// Stateless; does not retain live entities or publications.
class RoRReadModelKernel : public RefCounted {
    GDCLASS(RoRReadModelKernel, RefCounted)

public:
    Dictionary project_render(const Dictionary &source, const Dictionary &previous, const Array &fields, const Array &nested_fields, int64_t schema) const;
    Dictionary capture_frozen(const Variant &source, const Array &trusted) const;

protected:
    static void _bind_methods();
};

} // namespace godot
