#pragma once
#include <godot_cpp/classes/object.hpp>
#include <godot_cpp/variant/callable.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <algorithm>
#include <atomic>
#include <chrono>
#include <unordered_map>

namespace godot {
class RoRScriptBoundaryProfile {
    struct Measure { int64_t calls = 0, ns = 0, max_ns = 0; };
    struct NameHash { size_t operator()(const StringName &name) const { return name.hash(); } };
    struct Context {
        std::unordered_map<StringName, Measure, NameHash> methods;
        int depth = 0;
    };
    inline static thread_local Context *active = nullptr;
    inline static std::atomic<unsigned> recording{0};
    class Boundary {
        Context *context;
        StringName method;
        bool outer = false;
        std::chrono::steady_clock::time_point started;
    public:
        explicit Boundary(const StringName &name) : context(active), method(name) {
            if (!context) return;
            outer = context->depth++ == 0;
            if (outer) started = std::chrono::steady_clock::now();
        }
        ~Boundary() {
            if (!context) return;
            --context->depth;
            if (!outer) return;
            const int64_t ns = std::chrono::duration_cast<std::chrono::nanoseconds>(std::chrono::steady_clock::now() - started).count();
            if (context->methods.size() >= 128 && context->methods.find(method) == context->methods.end()) method = StringName("<other>");
            Measure &entry = context->methods[method];
            ++entry.calls; entry.ns += ns; entry.max_ns = std::max(entry.max_ns, ns);
        }
    };
    Context context;
    Dictionary totals;
    bool owns = false;
public:
    RoRScriptBoundaryProfile(bool enabled, const Dictionary &output) : totals(output) {
        if (enabled && !active) {
            active = &context;
            owns = true;
            recording.fetch_add(1, std::memory_order_relaxed);
        }
    }
    ~RoRScriptBoundaryProfile() {
        if (!owns) return;
        active = nullptr;
        recording.fetch_sub(1, std::memory_order_relaxed);
        for (const auto &method : context.methods) {
            const StringName key = totals.size() >= 128 && !totals.has(method.first) ? StringName("<other>") : method.first;
            Dictionary entry = totals.get(key, Dictionary());
            entry["calls"] = int64_t(entry.get("calls", 0)) + method.second.calls;
            entry["ns"] = int64_t(entry.get("ns", 0)) + method.second.ns;
            entry["max_ns"] = std::max(int64_t(entry.get("max_ns", 0)), method.second.max_ns);
            totals[key] = entry;
        }
    }
    template<class... Args>
    static Variant call(Object *object, const StringName &method, const Args &...args) {
        if (!recording.load(std::memory_order_relaxed) || !active) return object->call(method, args...);
        Boundary boundary(method);
        return object->call(method, args...);
    }
    template<class... Args>
    static Variant invoke(const Callable &callable, const StringName &method, const Args &...args) {
        if (!recording.load(std::memory_order_relaxed) || !active) return callable.call(args...);
        Boundary boundary(method);
        return callable.call(args...);
    }
    template<class... Args>
    static Variant invoke_kind(const Callable &callable, const StringName &method, const String &kind, const Args &...args) {
        if (!recording.load(std::memory_order_relaxed) || !active) return callable.call(args...);
        Boundary boundary(StringName(String(method) + ":" + kind));
        return callable.call(args...);
    }
};
}
