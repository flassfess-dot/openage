#pragma once

#include <cstdint>
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
    Dictionary configure_movement_entity_rows(const Array &units, bool incremental, bool delta);
    void release_movement_snapshot();
    void share_movement_snapshot(const Ref<RoRPathKernel> &source);
    Vector4 calculate_movement(int32_t unit_id, const Vector2 &target, double speed, double cohesion_scale, double delta) const;
    int64_t get_revision() const;
    int64_t get_walkability_version() const;
    int32_t get_last_expanded_nodes() const;
    bool get_last_path_was_direct() const;
    bool is_configured() const;
    int32_t component_id(const Vector2i &cell, double clearance_radius = 0.0);
    Dictionary group_points_by_component(const TypedArray<Vector2> &points, double clearance_radius = 0.0);
    bool cells_connected(const Vector2i &start, const Vector2i &goal, double clearance_radius = 0.0);

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
    int64_t walkability_version_ = 0;
    int32_t last_expanded_nodes_ = 0;
    bool last_path_was_direct_ = false;
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
    Vector2 walkable_alternative(int32_t unit_id, const Vector2 &desired, const Vector2 &position, double speed, double delta, double radius) const;
};

} // namespace godot
