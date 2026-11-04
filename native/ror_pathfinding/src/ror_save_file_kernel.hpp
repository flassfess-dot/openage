#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>

namespace godot {
class RoRSaveFileKernel : public RefCounted {
    GDCLASS(RoRSaveFileKernel, RefCounted)
    void *background_process = nullptr;
    void *background_job = nullptr;
protected:
    static void _bind_methods();
public:
    ~RoRSaveFileKernel() override;
    bool background_process_supported() const;
    Dictionary start_background_process(const String &application, const Array &arguments);
    bool background_process_running() const;
    void stop_background_process();
    int64_t replace_atomic(const String &source, const String &destination) const;
};
}
