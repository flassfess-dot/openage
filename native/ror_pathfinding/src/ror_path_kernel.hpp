#pragma once

#include <cstdint>
#include <vector>

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/vector2i.hpp>

namespace godot {

class RoRPathKernel : public RefCounted {
    GDCLASS(RoRPathKernel, RefCounted)

public:
    void configure(int32_t width, int32_t height, int64_t revision, const PackedByteArray &walkable);
    PackedInt32Array find_cell_path(const Vector2i &start, const Vector2i &goal, double clearance_radius = 0.0);
    int64_t get_revision() const;
    int32_t get_last_expanded_nodes() const;
    bool is_configured() const;

protected:
    static void _bind_methods();

private:
    struct FrontierEntry {
        int32_t index = -1;
        double score = 0.0;
        double cost = 0.0;
    };

    int32_t width_ = 0;
    int32_t height_ = 0;
    int64_t revision_ = -1;
    int32_t last_expanded_nodes_ = 0;
    uint32_t search_generation_ = 0;
    std::vector<uint8_t> walkable_;
    std::vector<double> costs_;
    std::vector<int32_t> parents_;
    std::vector<uint32_t> seen_generation_;
    std::vector<FrontierEntry> frontier_;

    bool contains(int32_t x, int32_t y) const;
    bool cell_walkable(int32_t x, int32_t y) const;
    bool cell_walkable_for(int32_t x, int32_t y, double clearance_radius) const;
    bool can_step(int32_t current, int32_t next, double clearance_radius) const;
    double heuristic(int32_t left, int32_t right) const;
    bool frontier_less(const FrontierEntry &left, const FrontierEntry &right) const;
    void frontier_push(const FrontierEntry &entry);
    FrontierEntry frontier_pop();
};

} // namespace godot
