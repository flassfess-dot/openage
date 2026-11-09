#pragma once

#include <chrono>
#include <cstdint>

namespace godot {

// Diagnostic only: counters belong to one synchronous owner pass. Disabled
// scopes do not read the clock, allocate, call scripts, or change execution.
class RoRActorStageScope {
    int64_t *elapsed = nullptr;
    std::chrono::steady_clock::time_point started;
public:
    RoRActorStageScope(bool enabled, int64_t &nanoseconds, int64_t &calls) {
        if (!enabled) return;
        elapsed = &nanoseconds;
        ++calls;
        started = std::chrono::steady_clock::now();
    }
    void stop() {
        if (!elapsed) return;
        *elapsed += std::chrono::duration_cast<std::chrono::nanoseconds>(
            std::chrono::steady_clock::now() - started).count();
        elapsed = nullptr;
    }
    ~RoRActorStageScope() { stop(); }
};

} // namespace godot
