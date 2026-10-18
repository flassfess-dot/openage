#pragma once

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>
#include <vector>

namespace godot {

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

// Stateless; does not retain live entities or publications.
class RoRReadModelKernel : public RefCounted {
    GDCLASS(RoRReadModelKernel, RefCounted)

public:
    bool refresh_interpolated_items(const Array &items, const Callable &project, double alpha, const Dictionary &depth_index, double sprite_scale) const;
    void cache_actor_sprites(const Array &items, double scale) const;
    Array changed_combat_ids(const Dictionary &delta, const Dictionary &units, const Dictionary &buildings, const Dictionary &sources, const Dictionary &classifications) const;
    Array filter_visible_entities(const Array &entities, int64_t observer, const PackedByteArray &states, const Vector2i &map_size) const;
    Array project_cached_render_entities(const Array &entities, const Dictionary &cache) const;
    Ref<RoRStaticSpriteProjection> prepare_static_projection(const Array &items, const Vector2 &origin, double scale) const;
    Array project_prepared_static_items(const Ref<RoRStaticSpriteProjection> &prepared, const Vector2 &origin, double scale, const Rect2 &viewport) const;
    Array project_visible_static_items(const Array &items, const Vector2 &origin, double scale, const Rect2 &viewport, bool clip_buildings = false) const;
    Array merge_projected_static_items(const Array &first, const Array &second, const Vector2 &origin, double scale) const;
    Array create_unit_render_items(const Array &units, const Callable &project, const Callable &provider, const Callable &colors, double alpha, const Dictionary &depth_index, const Array &preview, const Array &selected) const;
    Dictionary create_building_render_items(const Array &buildings, const Callable &project, const Callable &provider, const Callable &colors, Dictionary records, const Array &preview, const Array &selected, int64_t observer, double scale, bool affine, const Callable &cache_sprite) const;
    Array clip_building_render_items(const Array &items, const Rect2 &viewport) const;
    void cache_sprite_items(const Array &items, double scale, const Vector2 &origin, const Callable &atlas, Dictionary cache) const;
    bool matches_combat_classification(const Dictionary &entity, const Array &classification) const;
    int64_t advance_harvesting_recovery(Dictionary worker, const Dictionary &resources, const Dictionary &reservations) const;
    int64_t integrate_unit_motion(Dictionary unit, double delta, const Vector2i &map_size, const Dictionary &vertex_levels, const String &reason) const;
    Dictionary owned_ai_actor_profile(const Dictionary &entity) const;
    Dictionary partition_render_items(const Array &items) const;
    int64_t submit_sprite_run(const RID &canvas, const Array &items, int64_t start) const;
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
    Array query_resource_candidates(const Array &buckets, const Vector2 &position, int64_t resource_type, double cell_size, int64_t maximum) const;
    Dictionary build_resource_buckets(const Array &resources, const Array &domains, bool unrestricted, bool typed, double cell_size) const;
    Dictionary economy_resource_view(const Array &resources, const Array &buildings, int64_t team) const;
    Dictionary reachable_cell_lookup(const Dictionary &navigation) const;
    bool refresh_resource_bucket_rows(const Dictionary &index, const Array &previous, const Array &current) const;
    Array build_site_ring_cells(const Vector2i &center, int64_t radius, const Vector2i &size, Dictionary seen, const Dictionary &pages) const;
    Dictionary infrastructure_site_bonuses(const Array &resources, const Array &sites, const String &kind) const;
    bool foundation_intersects_structures(const Dictionary &footprint, const Vector2 &center, const Dictionary &structures, const Dictionary &replaced) const;
    PackedByteArray walkability_mask(const Vector2i &size, const Dictionary &terrain, const Dictionary &terrain_ids, const Dictionary &occupied, const Array &restrictions, const PackedByteArray &learned, bool knowledge, const String &domain, int64_t restriction) const;
    Dictionary project_control(const Dictionary &source, const Dictionary &rendered, int64_t observer, const Array &fields, const Array &private_trade_fields) const;
    Dictionary encode_replay_variant(const Variant &source, bool quantize_numbers = true) const;
    Dictionary capture_frozen(const Variant &source, const Array &trusted) const;
    Dictionary capture_owned_frozen(const Variant &source, const Array &trusted) const;
    Dictionary capture_navigation_pages(const Dictionary &sources, const Dictionary &previous, const Array &keys, const Vector2i &size) const;
    PackedByteArray rasterize_minimap_fog(const Vector2i &size, const Rect2 &rectangle, const Vector2 &center, double scale, const PackedByteArray &fog) const;

protected:
    static void _bind_methods();
};

} // namespace godot
