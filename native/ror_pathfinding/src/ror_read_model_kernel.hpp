#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/classes/image.hpp>
#include <godot_cpp/variant/packed_color_array.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <godot_cpp/variant/packed_int64_array.hpp>
#include <vector>
#include <functional>
#include <unordered_map>

namespace godot {

// One configured map's immutable presentation rows. No simulation references.
class RoREnvironmentQueryIndex : public RefCounted {
    GDCLASS(RoREnvironmentQueryIndex, RefCounted)
    struct Row { Dictionary item, entry; int64_t id = -1, signature = 0; bool animated = false; };
    std::vector<Row> rows;
    std::unordered_map<uint64_t, std::vector<int64_t>> cells;
    std::vector<uint32_t> marks;
    uint32_t generation = 0;
    int64_t static_count = 0;
    bool configured = false;
public:
    bool configure(const Array &items, const Dictionary &buckets, const Array &ambient);
    Dictionary query(const Rect2i &bounds, bool include_ambient);
protected:
    static void _bind_methods();
};

// Owner-thread cooperative snapshot. A record is consumed either by a small
// scan portion or immediately before its first mutation after begin().
class RoRResourceDigest : public RefCounted {
    GDCLASS(RoRResourceDigest, RefCounted)
    struct Record { int64_t id; Dictionary value; bool consumed = false; };
    std::vector<Record> records;
    std::unordered_map<int64_t, size_t> indices;
    PackedInt64Array digests;
    size_t cursor = 0;
    size_t remaining = 0;
    bool active = false;
    void consume(size_t index);
public:
    bool begin(const Array &resources);
    void before_change(int64_t id);
    bool advance(int64_t budget_usec);
    PackedInt64Array take();
    void cancel();
protected:
    static void _bind_methods();
};

// Owned by one renderer's current camera query. Clearing/replacing that query
// releases its sprite records; this object never enters a gameplay publication.
class RoRStaticSpriteProjection : public RefCounted {
    GDCLASS(RoRStaticSpriteProjection, RefCounted)
public:
    struct Record {
        Dictionary item;
        Array command;
        Vector2 anchor, offset, hotspot, size;
        double depth = 0.0;
        bool conservative = true;
    };
    std::vector<Record> records;
    int64_t get_record_count() const { return int64_t(records.size()); }
protected:
    static void _bind_methods();
};

// Does not retain live entities or publications. Renderer instances own a small
// immutable geometry cache; simulation instances never populate it.
class RoRReadModelKernel : public RefCounted {
    GDCLASS(RoRReadModelKernel, RefCounted)

public:
    ~RoRReadModelKernel() override;
    void set_selection_meshes_enabled(bool enabled) { selection_meshes_enabled = enabled; }
    Dictionary selection_mesh_stats() const;
    Dictionary control_batch_stats() const;
    Dictionary collect_combat_awareness(Object *world, Object *awareness, int64_t tick, const Dictionary &delta) const;
    bool supports_ordered_gather_controller() const { return true; }
    bool supports_actor_key_cache() const { return true; }
    bool supports_scoped_resource_digest() const { return true; }
    void set_motion_profiling(bool enabled);
    Dictionary motion_profile() const;
    Dictionary typed_motion_stats() const;
    Dictionary contact_frame_stats() const;
    int64_t get_actor_pipeline_version() const { return 1; }
    Dictionary advance_ordered_unit_span(const Dictionary &context, double delta) const;
    Dictionary profile_storage_graph(const Dictionary &roots, int64_t node_limit = 32000000) const;
    bool refresh_interpolated_items(const Array &items, const Callable &project, double alpha, const Dictionary &depth_index, double sprite_scale, const Array &camera = Array(), bool force_projection = true) const;
    void cache_actor_sprites(const Array &items, double scale) const;
    void cache_actor_sprites_atlased(const Array &items, double scale, const Callable &atlas, Dictionary cache) const;
    Array changed_combat_ids(const Dictionary &delta, const Dictionary &units, const Dictionary &buildings, const Dictionary &sources, const Dictionary &classifications) const;
    Array filter_visible_entities(const Array &entities, int64_t observer, const PackedByteArray &states, const Vector2i &map_size) const;
    Array project_cached_render_entities(const Array &entities, const Dictionary &cache) const;
    Ref<RoRStaticSpriteProjection> prepare_static_projection(const Array &items, const Vector2 &origin, double scale) const;
    Array project_prepared_static_items(const Ref<RoRStaticSpriteProjection> &prepared, const Vector2 &origin, double scale, const Rect2 &viewport) const;
    Array project_visible_static_items(const Array &items, const Vector2 &origin, double scale, const Rect2 &viewport, bool clip_buildings = false) const;
    Array merge_projected_static_items(const Array &first, const Array &second, const Vector2 &origin, double scale) const;
    Array create_unit_render_items(const Array &units, const Callable &project, const Callable &provider, const Callable &colors, double alpha, const Dictionary &depth_index, const Array &preview, const Array &selected, const Array &camera = Array()) const;
    Dictionary create_building_render_items(const Array &buildings, const Callable &project, const Callable &provider, const Callable &colors, Dictionary records, const Array &preview, const Array &selected, int64_t observer, double scale, bool affine, const Callable &cache_sprite) const;
    Array clip_building_render_items(const Array &items, const Rect2 &viewport) const;
    void cache_sprite_items(const Array &items, double scale, const Vector2 &origin, const Callable &atlas, Dictionary cache) const;
    bool matches_combat_classification(const Dictionary &entity, const Array &classification) const;
    int64_t advance_harvesting_recovery(Dictionary worker, const Dictionary &resources, const Dictionary &reservations) const;
    int64_t integrate_unit_motion(Dictionary unit, double delta, const Vector2i &map_size, const Dictionary &vertex_levels, const String &reason) const;
    Vector2 constrain_mobile_velocity(const Dictionary &unit, const Vector2 &velocity, const Array &neighbors, double delta) const;
    Vector3 formation_yield_velocity(Dictionary unit, const Array &neighbors, double delta, Object *planner) const;
    String update_route_progress(Dictionary unit, int64_t stop_tick) const;
    Vector4 advance_move_pipeline(Dictionary unit, double delta, Object *world, Object *system, Object *planner) const;
    Vector4 advance_native_motion(Dictionary unit, Object *movement_kernel, double delta, const Vector2i &map_size, const Dictionary &vertex_levels) const;
    Vector4 advance_native_group_motion(Dictionary unit, Object *movement_kernel, double delta, const Vector2i &map_size, const Dictionary &vertex_levels, const Array &neighbors, Object *planner, int64_t stop_tick) const;
    Vector4 advance_checked_move_order(Dictionary unit, Object *movement_kernel, double delta, const Vector2i &map_size, const Dictionary &vertex_levels, const Array &neighbors, Object *physical_planner, Object *knowledge_planner, int64_t stop_tick) const;
    int64_t publish_active_unit_controls(const Array &units, const Dictionary &units_by_id, Object *journal, Object *activity) const;
    int64_t set_motion_velocities(Dictionary unit, const Vector2 &desired, const Vector2 &actual) const;
    int64_t settle_mobile_contacts(const Dictionary &changes, const Array &active_units, const Array &all_units, const Dictionary &units_by_id,
        const Dictionary &buckets, const Array &entities, const Array &positions, const Array &radii,
        double cell_size, double maximum_radius, double delta, Dictionary pending,
        const Callable &query_fallback, const Callable &separate) const;
    int64_t settle_mobile_contacts_flat(const Dictionary &changes, const Array &active_units, const Array &all_units, const Dictionary &units_by_id,
        const Dictionary &buckets, const Array &entities, const Array &positions, const Array &radii,
        double cell_size, double maximum_radius, double delta, Dictionary pending,
        const Callable &query_fallback, const Callable &separate, bool compare = false) const;
    Array resources_in_radius(const Dictionary &cells, const Vector2i &size, const Vector2 &origin, double radius) const;
    Dictionary owned_ai_actor_profile(const Dictionary &entity) const;
    Dictionary partition_render_items(const Array &items) const;
    PackedInt64Array submit_world_queue(const RID &canvas, const Array &items, const Array &context, const Callable &fallback) const;
    int64_t submit_sprite_run(const RID &canvas, const Array &items, int64_t start) const;
    int64_t submit_sprite_batches(const RID &canvas, const Array &items, int64_t start) const;
    int64_t submit_selection_run(const RID &canvas, const Array &items, int64_t first, const Array &selected, const Dictionary &preview, int64_t hover, int64_t feedback, double feedback_time, const String &semantic, double zoom, bool shift_pressed) const;
    void submit_selection_ellipse(const RID &canvas, const Vector2 &center, const Color &color, const Vector2 &radius, double zoom) const;
    double unit_depth_offset(const Vector2 &position, double screen_y, const Dictionary &index, const Callable &project) const;
    void reproject_static_items(const Array &items, const Vector2 &origin, const Vector2 &previous_origin, double previous_scale, double scale) const;
    Dictionary diff_resource_records(const Array &previous, const Array &current) const;
    Array known_resources_in_bounds(const Dictionary &known, const Dictionary &chunks, const Rect2i &bounds, int32_t chunk_size) const;
    Array sort_render_items(const Array &items) const;
    Array merge_render_items(const Array &first, const Array &second) const;
    PackedInt32Array advance_idle_animation(const Array &entities, double delta) const;
    Dictionary patch_render(const Dictionary &source, const Dictionary &previous, int64_t mask, const Dictionary &groups) const;
    Dictionary project_render(const Dictionary &source, const Dictionary &previous, const Array &fields, const Array &nested_fields, int64_t schema) const;
    Dictionary project_ai(const Dictionary &source, const Dictionary &previous, int64_t observer_team, const Array &fields, const Array &array_fields, const Array &private_trade_fields) const;
    Dictionary collect_ai_projection_changes(const Array &legal_sets, const Array &categories, const Dictionary &cache, const Variant &entity_versions, const Dictionary &schema) const;
    bool retain_ai_projection_portion(const Array &rows, int64_t begin, int64_t end, int64_t observer_team, Dictionary cache, const Variant &entity_versions, const Dictionary &schema) const;
    Array query_resource_candidates(const Array &buckets, const Vector2 &position, int64_t resource_type, double cell_size, int64_t maximum) const;
    Dictionary build_resource_buckets(const Array &resources, const Array &domains, bool unrestricted, bool typed, double cell_size) const;
    Dictionary economy_resource_view(const Array &resources, const Array &buildings, int64_t team) const;
    Dictionary reachable_cell_lookup(const Dictionary &navigation) const;
    bool refresh_resource_bucket_rows(const Dictionary &index, const Array &previous, const Array &current) const;
    Array build_site_ring_cells(const Vector2i &center, int64_t radius, const Vector2i &size, Dictionary seen, const Dictionary &pages) const;
    Dictionary infrastructure_site_bonuses(const Array &resources, const Array &sites, const String &kind) const;
    bool foundation_intersects_structures(const Dictionary &footprint, const Vector2 &center, const Dictionary &structures, const Dictionary &replaced) const;
    PackedByteArray walkability_mask(const Vector2i &size, const Dictionary &terrain, const Dictionary &terrain_ids, const Dictionary &occupied, const Array &restrictions, const PackedByteArray &learned, bool knowledge, const String &domain, int64_t restriction) const;
    Dictionary surface_components(const Vector2i &size, const Dictionary &terrain, const Dictionary &terrain_ids, const Array &restrictions, const PackedByteArray &learned, bool knowledge, const String &domain, int64_t restriction) const;
    PackedInt32Array surface_component_labels(const Vector2i &size, const Dictionary &terrain, const Dictionary &terrain_ids, const Array &restrictions, const PackedByteArray &learned, bool knowledge, const String &domain, int64_t restriction) const;
    PackedInt32Array surface_reachability_changes(const Array &points, const Array &previous, const Dictionary &surface, const Dictionary &reachable, int64_t width) const;
    Dictionary project_control(const Dictionary &source, const Dictionary &rendered, int64_t observer, const Array &fields, const Array &private_trade_fields) const;
    Dictionary project_retained_control(const Dictionary &source, const Dictionary &rendered, int64_t observer, const Array &fields, const Array &private_trade_fields, Dictionary entry, Dictionary counters, bool metadata_only) const;
    Dictionary project_ui_control(const Dictionary &source, const Dictionary &rendered, int64_t observer, const Array &fields, const Dictionary &component_fields, const Array &private_trade_fields, Dictionary entry, Dictionary counters) const;
    Array capture_building_control_rows(const Array &rows, Dictionary counters) const;
    void clear_control_row_certificates() { control_row_certificates.clear(); published_building_rows.clear(); }
    Dictionary project_control_legacy(const Dictionary &source, const Dictionary &rendered, int64_t observer, const Array &fields, const Array &private_trade_fields) const;
    Dictionary encode_replay_variant(const Variant &source, bool quantize_numbers = true) const;
    bool supports_capture_identity_tracking() const { return true; }
    Dictionary capture_frozen(const Variant &source, const Array &trusted, bool track_identity = true) const;
    Dictionary capture_owned_frozen(const Variant &source, const Array &trusted, bool track_identity = true) const;
    Dictionary capture_navigation_pages(const Dictionary &sources, const Dictionary &previous, const Array &keys, const Vector2i &size) const;
    PackedByteArray rasterize_minimap_fog(const Vector2i &size, const Rect2 &rectangle, const Vector2 &center, double scale, const PackedByteArray &fog) const;
    Ref<Image> remap_player_image(const Ref<Image> &blue, const Ref<Image> &red, const PackedColorArray &source_ramp, const PackedColorArray &target_ramp) const;
    PackedInt64Array autosave_entity_digests(const Array &entities) const;
    PackedByteArray occupied_resource_slots(const Dictionary &worker, const Array &candidates, const Vector2i &size, const Dictionary &resources_by_cell, const Dictionary &reservations_by_resource, const Dictionary &units_by_id, double minimum_clearance, double default_clearance) const;
    PackedByteArray occupied_idle_unit_slots(const Dictionary &worker, const Array &candidates, const Array &nearby, const Dictionary &indices, const Array &positions, const Array &radii, double default_clearance) const;
    bool spatial_unit_circle(const Vector2 &center, double radius, const Dictionary &buckets, const Array &entities, const Array &positions, const Array &radii, double cell_size, double maximum_radius, Array result) const;
    bool sort_active_units(Array units, const Dictionary &orders) const;
    Dictionary stable_activity_updates(const Array &ids, const Dictionary &context) const;
    Dictionary classify_activity_changes(const Array &ids, const Dictionary &context) const;
    int64_t synchronize_spatial_units_prefix(const Array &units, const Dictionary &indices, const Array &entities, Array positions, Array cells, Dictionary buckets, double cell_size) const;
    bool spatial_unit_neighbors(const Dictionary &unit, double radius, const Variant &excluded_group, const Dictionary &buckets, const Array &entities, const Array &positions, const Array &radii, double cell_size, double maximum_radius, Array result) const;
    int64_t spatial_unit_match(const Dictionary &unit, double radius, int64_t mode, const Dictionary &buckets, const Array &entities, const Array &positions, const Array &radii, double cell_size, double maximum_radius) const;

private:
    Dictionary activity_updates_impl(const Array &ids, const Dictionary &context, bool compact) const;
    // Detached outputs of this kernel's own projection factory. Never live
    // entities; pruned after each building publication and cleared on load.
    mutable std::unordered_map<int64_t, Dictionary> control_row_certificates;
    mutable std::unordered_map<int64_t, Dictionary> published_building_rows;
    // Stack-owned by one ordered owner pass. No references survive publication.
    struct FrameProjection;
    double projected_unit_depth_offset(const Vector2 &position, double screen_y, const Dictionary &index, const FrameProjection &project) const;
    struct MovementBatchContext {
        struct RoutePreparation {
            struct Kernel {
                String domain;
                int64_t restriction = -1;
                Variant reference;
            };
            Variant grid_reference;
            Object *grid = nullptr;
            int64_t revision = -1, epoch = -1;
            bool canonical = false;
            std::unordered_map<int64_t, Variant> regions;
            std::vector<Kernel> kernels;
        };
        Object *world = nullptr, *system = nullptr, *physical = nullptr;
        Object *activity = nullptr, *elevation = nullptr, *spatial = nullptr;
        Object *shared_kernel = nullptr;
        Dictionary by_unit, envelopes, groups, vertices, buckets;
        Array neighbors, entities, positions, radii;
        Vector2i map_size;
        double cell_size = 0.0, maximum_radius = 0.0, maximum_clearance = 0.0;
        bool motion_enabled = false, group_enabled = false, direct_neighbors = false;
        bool typed_motion = false, compare_typed_motion = false, borrowed_motion_fields = false;
        bool native_route_preparation = false;
        // One synchronous owner span. The checksum job contains resource IDs,
        // not the entire live world; native before_change is idempotent.
        bool scoped_resource_digest = false;
        Ref<RoRResourceDigest> resource_digest;
        std::unordered_map<Object *, RoutePreparation> route_preparations;
        int64_t route_preparation_calls = 0, route_region_reads = 0;
        int64_t route_preparation_fallbacks = 0, route_replans = 0, route_corners = 0;
        bool bindings_fresh = false;
        bool spatial_bindings_fresh = false;
        int64_t operations = 0, binding_refreshes = 0;
        bool profile_stages = false;
        int64_t stage_ns[7] = {}, stage_calls[7] = {};
        int64_t traffic_checkpoint_entries = 0, traffic_checkpoint_holds = 0;
        std::function<void(const Dictionary &, int64_t, int64_t)> publish;
    };
    mutable MovementBatchContext *active_movement_batch = nullptr;
    struct MotionInputs {
        Vector2 position, target;
        int64_t id, stalled, group;
    };
    struct ActorBatchContext {
        Object *world = nullptr, *movement = nullptr, *gathering = nullptr, *conversion = nullptr, *knowledge = nullptr;
        Callable domain, gather_continue;
        Dictionary context, animation_clips, gather_visuals;
        Array result, animation_states;
        bool native_gather = false;
        bool gather_controller = false;
        Object *repository = nullptr, *approach = nullptr;
        Dictionary maximum_gatherers;
        int64_t gather_controller_calls = 0, gather_controller_moves = 0, gather_controller_returns = 0;
        int64_t gather_controller_transitions = 0, gather_controller_adoptions = 0;
        int64_t gather_controller_blocked_adoptions = 0;
        int64_t gather_action = -1;
        Variant planner_value;
        Object *planner = nullptr;
        int64_t planner_team = INT64_MIN;
        int64_t calls = 0, move_attempts = 0, direct_moves = 0, motion_updates = 0, candidates = 0;
        int64_t gather_recoveries = 0, gather_continuations = 0, domain_callbacks = 0;
        int64_t native_animations = 0, script_animations = 0;
        int64_t scoped_digest_actors = 0, scoped_digest_protections = 0;
        bool profile_stages = false;
        int64_t stage_ns[10] = {}, stage_calls[10] = {};
        int64_t gather_ns[10] = {}, gather_calls[10] = {};
    };
    bool prepare_actor_batch(ActorBatchContext &batch, const Dictionary &context) const;
    int64_t advance_actor_pipeline(Dictionary unit, double delta, ActorBatchContext &batch, MovementBatchContext &movement) const;
    int64_t advance_gather_controller(Dictionary unit, double delta, bool waiting, ActorBatchContext &batch, MovementBatchContext &movement) const;
    Variant adopt_gather_resource(Dictionary unit, Dictionary requested, ActorBatchContext &batch, MovementBatchContext &movement) const;
    int64_t maximum_gatherers(const Dictionary &resource, ActorBatchContext &batch) const;
    Vector4 advance_gather_motion(Dictionary unit, double delta, ActorBatchContext &batch, MovementBatchContext &movement) const;
    int64_t advance_actor_animation(Dictionary unit, const String &requested, double delta, const Array &states, const Dictionary &clips) const;

    bool prepare_movement_batch(MovementBatchContext &batch, Object *world, Object *system) const;
    void refresh_movement_batch(MovementBatchContext &batch) const;
    void refresh_spatial_bindings(MovementBatchContext &batch) const;
    bool prepare_move_route_native(Dictionary unit, Object *planner, MovementBatchContext &batch) const;
    Vector4 advance_move_pipeline_internal(Dictionary unit, double delta, Object *planner, MovementBatchContext &batch) const;
    Vector4 advance_checked_move_order_internal(Dictionary unit, Object *movement_kernel, double delta, const Vector2i &map_size, const Dictionary &vertex_levels, const Array &neighbors, Object *physical_planner, Object *knowledge_planner, int64_t stop_tick, int32_t *failure_reason) const;
    Dictionary project_control_impl(const Dictionary &source, const Dictionary &rendered, int64_t observer, const Array &fields, const Array &private_trade_fields, bool legacy_copy) const;
    // Opt-in, fixed-size owner-thread counters. Read only after joining owner.
    struct MotionMeasurement { int64_t count = 0, total_ns = 0, maximum_ns = 0; };
    bool motion_profiling = false;
    mutable MotionMeasurement motion_measurements[6];
    mutable int64_t typed_motion_updates = 0, typed_motion_rejections = 0;
    mutable int64_t typed_motion_comparisons = 0, typed_motion_mismatches = 0;
    mutable int64_t borrowed_motion_field_updates = 0;
    struct SelectionMesh { Vector2 radius; RID mesh; };
    mutable std::vector<SelectionMesh> selection_meshes;
    bool selection_meshes_enabled = false;
    mutable int64_t selection_mesh_hits = 0, selection_mesh_builds = 0, selection_mesh_fallbacks = 0;
    mutable int64_t healthbar_batch_calls = 0, healthbar_batch_items = 0;
    mutable std::unordered_map<float, RID> shadow_meshes;
    mutable int64_t shadow_mesh_draws = 0;
    mutable int64_t prepared_shore_draws = 0;
    bool submit_cached_shadow(const RID &canvas, const Vector2 &center, float radius, const Color &color) const;
    bool submit_cached_selection_mesh(const RID &canvas, const Vector2 &center, const Color &color, const Vector2 &radius) const;
    mutable int64_t contact_frame_calls = 0, contact_frame_rows = 0, contact_frame_queries = 0, contact_frame_neighbors = 0;
    mutable int64_t contact_frame_fallbacks = 0, contact_frame_comparisons = 0, contact_frame_mismatches = 0;
    Vector4 advance_motion_internal(Dictionary unit, Object *movement_kernel, double delta, const Vector2i &map_size, const Dictionary &vertex_levels, const Array *neighbors, Object *planner, int64_t stop_tick, const MotionInputs *prepared = nullptr) const;
protected:
    static void _bind_methods();
};

} // namespace godot
