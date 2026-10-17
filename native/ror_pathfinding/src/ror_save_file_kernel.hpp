#pragma once
#include <godot_cpp/classes/ref_counted.hpp>

namespace godot {
class RoRSaveFileKernel : public RefCounted {
    GDCLASS(RoRSaveFileKernel, RefCounted)
protected:
    static void _bind_methods();
public:
    int64_t replace_atomic(const String &source, const String &destination) const;
};
}
