#pragma once

#include <cstdint>
#include <deque>
#include <memory>
#include <unordered_map>
#include <vector>

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/vector4.hpp>
#include <godot_cpp/variant/vector2i.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/typed_array.hpp>
#include <godot_cpp/variant/callable.hpp>

namespace godot {

class RoRPathKernel : public RefCounted {
    GDCLASS(RoRPathKernel, RefCounted)

public:
    Ref<RoRPathKernel> create_search_context() const;
    Ref<RoRPathKernel> create_movement_context() const;
    PackedInt32Array connectivity_labels(double radius = 0.0);
    bool install_connectivity(const PackedInt32Array &labels, double radius = 0.0);
    void configure(int32_t width, int32_t height, int64_t revision, const PackedByteArray &walkable);
    bool update_walkable(int64_t revision, const PackedInt32Array &indices, const PackedByteArray &values);
    void configure_route_cache(bool enabled, bool profile, bool reference);
    Dictionary route_cache_stats() const;
    PackedInt32Array find_cell_path(const Vector2i &start, const Vector2i &goal, double clearance_radius = 0.0);
    PackedInt32Array find_smoothed_cell_path(const Vector2i &start, const Vector2i &goal, double clearance_radius = 0.0);
    void configure_movement_snapshot(
        const PackedInt32Array &ids,
        const PackedVector2Array &positions,
        const PackedFloat32Array &radii,
        const PackedFloat32Array &clearances,
        const PackedInt32Array &priorities,
        const PackedFloat32Array &health,
        const PackedByteArray &solid_animals = PackedByteArray());
    Dictionary configure_movement_entities(const Array &units, bool incremental = true);
    Dictionary update_movement_entities(const Array &units);
    Array collect_movement_delta(const Dictionary &delta, const Dictionary &units_by_id, const Dictionary &configurations) const;
    Dictionary configure_movement_entity_rows(const Array &units, bool incremental, bool delta);
    void release_movement_snapshot();
    void share_movement_snapshot(const Ref<RoRPathKernel> &source);
    Vector4 calculate_movement(int32_t unit_id, const Vector2 &target, double speed, double cohesion_scale, double delta) const;
    int64_t get_revision() const;
    int64_t get_walkability_version() const;
    int64_t get_connectivity_rebuild_count() const;
    int32_t get_last_expanded_nodes() const;
    bool get_last_path_was_direct() const;
    bool is_configured() const;
    int32_t component_id(const Vector2i &cell, double clearance_radius = 0.0);
    Dictionary group_points_by_component(const TypedArray<Vector2> &points, double clearance_radius = 0.0);
    bool cells_connected(const Vector2i &start, const Vector2i &goal, double clearance_radius = 0.0);
    PackedInt32Array corridor_widths(const TypedArray<Vector2i> &cells, int64_t maximum, double radius) const;
    bool is_segment_walkable(const Vector2 &start, const Vector2 &finish, double radius) const;
    PackedByteArray positions_walkable(const Array &positions, double radius) const;
    Dictionary local_recovery_position(const Vector2 &origin, double radius, const PackedByteArray &known, const Array &neighbors, const Array &spatial);
    PackedVector2Array smooth_swept_world_path(const Vector2 &origin, const PackedVector2Array &candidates, double radius, const Vector2 &escape_center) const;
    PackedVector2Array finish_world_path(const Vector2 &origin, const Vector2 &destination, const Vector2i &goal, const TypedArray<Vector2i> &smoothed, double radius);
    PackedVector2Array find_local_traffic_path(const Vector2 &origin, const Vector2 &goal, double radius, double clearance, const Array &blockers) const;
    Dictionary select_work_traffic_route(const Vector2 &origin, const Vector2 &destination, double radius, double clearance,
        const Array &candidates, int64_t first_candidate, const Array &blockers, const Array &tail_blockers, const Callable &find_path) const;
    PackedInt32Array direct_cell_path(const Vector2i &start, const Vector2i &goal, double radius) const;
    bool has_direct_cell_path(const Vector2i &start, const Vector2i &goal, double radius) const;
    Vector2i nearest_walkable(const Vector2i &requested, double radius) const;
    Vector2i nearest_reachable(const Vector2i &start, const Vector2i &requested, double radius);

protected:
    static void _bind_methods();

private:
    friend class RoRReadModelKernel;
    struct FrontierEntry {
        int32_t index = -1;
        double score = 0.0;
        double cost = 0.0;
    };

    int32_t width_ = 0;
    int32_t height_ = 0;
    int64_t revision_ = -1;
    int64_t walkability_version_ = 0;
    int64_t connectivity_rebuild_count_ = 0;
    int32_t last_expanded_nodes_ = 0;
    bool last_path_was_direct_ = false;
    int64_t cached_search_version_ = -1;
    Vector2i cached_search_start_, cached_search_goal_;
    double cached_search_radius_ = 0.0;
    PackedInt32Array cached_search_path_;
    struct RouteKey {
        Vector2i start, goal;
        uint64_t radius;
        bool operator==(const RouteKey &other) const { return start == other.start && goal == other.goal && radius == other.radius; }
    };
    struct RouteKeyHash {
        size_t operator()(const RouteKey &key) const {
            uint64_t hash = key.radius;
            for (int32_t value : {key.start.x, key.start.y, key.goal.x, key.goal.y})
                hash ^= uint64_t(uint32_t(value)) + 0x9e3779b97f4a7c15ULL + (hash << 6) + (hash >> 2);
            return size_t(hash);
        }
    };
    bool route_cache_enabled_ = true, route_cache_profile_ = false, route_cache_reference_ = false;
    std::unordered_map<RouteKey, PackedInt32Array, RouteKeyHash> raw_routes_;
    std::deque<RouteKey> raw_route_fifo_;
    int64_t raw_route_bytes_ = 0;
    int64_t raw_calls_ = 0, single_hits_ = 0, route_hits_ = 0, raw_searches_ = 0, raw_expanded_ = 0;
    int64_t raw_search_us_ = 0, route_hit_us_ = 0, route_evictions_ = 0, route_invalidations_ = 0;
    int64_t route_reference_checks_ = 0, route_reference_mismatches_ = 0, route_reference_us_ = 0, route_reference_nodes_ = 0;
    int64_t route_peak_bytes_ = 0, route_peak_entries_ = 0;
    PackedInt32Array search_cell_path_uncached(const Vector2i &start, const Vector2i &goal, double radius);
    void clear_raw_routes();
    uint32_t search_generation_ = 0;
    std::shared_ptr<std::vector<uint8_t>> walkable_ = std::make_shared<std::vector<uint8_t>>();
    std::vector<double> costs_;
    std::vector<int32_t> parents_;
    std::vector<uint32_t> seen_generation_;
    std::vector<FrontierEntry> frontier_;
    std::unordered_map<uint64_t, std::shared_ptr<const std::vector<int32_t>>> components_by_radius_;
    const std::vector<int32_t> &components(double clearance_radius);
    bool patch_components(double radius, const std::vector<int32_t> &changed,
        std::shared_ptr<const std::vector<int32_t>> &labels) const;
    bool patch_component_region(double radius, const std::vector<int32_t> &changed,
        std::shared_ptr<const std::vector<int32_t>> &labels) const;
    bool patch_open_components(double radius, const std::vector<int32_t> &changed,
        std::shared_ptr<const std::vector<int32_t>> &labels) const;
    // All terrain-specific kernels borrow the same immutable neighbor generation.
    struct MovementSnapshot {
        std::vector<int32_t> ids;
        std::vector<Vector2> positions;
        std::vector<float> radii;
        std::vector<float> clearances;
        std::vector<int32_t> priorities;
        std::vector<float> health;
        std::vector<uint8_t> solid_animals;
        std::unordered_map<int32_t, int32_t> index_by_id;
        std::unordered_map<int64_t, std::vector<int32_t>> buckets;
        float maximum_radius = 0.0f;
        float maximum_clearance = 0.0f;
    };
    std::shared_ptr<const MovementSnapshot> movement_ = std::make_shared<MovementSnapshot>();

    bool contains(int32_t x, int32_t y) const;
    bool cell_walkable(int32_t x, int32_t y) const;
    bool cell_walkable_for(int32_t x, int32_t y, double clearance_radius) const;
    bool can_step(int32_t current, int32_t next, double clearance_radius) const;
    bool direct_path(int32_t start, int32_t goal, double clearance_radius, std::vector<int32_t> *result = nullptr) const;
    PackedInt32Array pack_cells(const std::vector<int32_t> &cells) const;
    double heuristic(int32_t left, int32_t right) const;
    bool frontier_less(const FrontierEntry &left, const FrontierEntry &right) const;
    void frontier_push(const FrontierEntry &entry);
    FrontierEntry frontier_pop();
    int64_t movement_bucket_key(int32_t x, int32_t y) const;
    bool position_walkable(const Vector2 &position, double radius) const;
    bool segment_interior_walkable(const Vector2 &start, const Vector2 &finish, double radius) const;
    Vector2 walkable_alternative(int32_t unit_id, const Vector2 &desired, const Vector2 &position, double speed, double delta, double radius) const;
};

} // namespace godot
