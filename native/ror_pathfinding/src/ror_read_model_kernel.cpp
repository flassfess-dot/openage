#include "ror_script_boundary_profile.hpp"
#include "ror_read_model_kernel.hpp"
#include "ror_path_kernel.hpp"
#include "ror_actor_stage_scope.hpp"
#include "ror_actor_keys.hpp"
#include "ror_actor_motion_frame.hpp"
#include "ror_entity_change_journal.hpp"
#include "ror_journal_version_reader.hpp"

#include <godot_cpp/classes/rendering_server.hpp>
#include <godot_cpp/variant/transform2d.hpp>
#include <godot_cpp/variant/packed_int64_array.hpp>
#include <limits>
#include <algorithm>
#include <cmath>
#include <chrono>
#include <unordered_set>
#include <unordered_map>
#include <vector>
#include <map>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/templates/sort_array.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

namespace godot {
namespace {
RoREntityChangeJournalKernel *native_entity_journal(Object *journal) {
    if (!journal || !bool(journal->get("native_active"))) return nullptr;
    const Variant value = journal->get("native_journal");
    Object *object = value.get_type() == Variant::OBJECT ? static_cast<Object *>(value) : nullptr;
    auto *kernel = Object::cast_to<RoREntityChangeJournalKernel>(object);
    if (!kernel) return nullptr;
    const Variant script = RoRScriptBoundaryProfile::call(kernel, "get_script");
    return script.get_type() == Variant::NIL || (script.get_type() == Variant::OBJECT && !static_cast<Object *>(script)) ? kernel : nullptr;
}
constexpr double MAX_INTERPOLATION_ALPHA = 5.0;
uint32_t canonical_entity_value_hash(const Dictionary &entity) {
    static const StringName ignored[] = {"selected", "formation_shared_motion", "_formation_path_cache", "formation_steering_target", "formation_shared_isolated"};
    Dictionary record = entity;
    bool detached = false;
    for (const StringName &field : ignored) {
        if (!record.has(field)) continue;
        if (!detached) { record = record.duplicate(false); detached = true; }
        record.erase(field);
    }
    return Variant(record).hash();
}
}

bool RoRResourceDigest::begin(const Array &resources) {
    cancel();
    const StringName id_key("id");
    records.reserve(resources.size());
    indices.reserve(resources.size());
    for (int64_t i = 0; i < resources.size(); ++i) {
        if (resources[i].get_type() != Variant::DICTIONARY) { cancel(); return false; }
        const Dictionary record = resources[i];
        const int64_t id = record.get(id_key, -1);
        if (id < 0 || indices.count(id)) { cancel(); return false; }
        indices[id] = 0;
        records.push_back({id, record, false});
    }
    struct Compare { bool operator()(const Record &a, const Record &b) const { return a.id < b.id; } };
    SortArray<Record, Compare>().sort(records.data(), int64_t(records.size()));
    digests.resize(int64_t(records.size()) * 2);
    for (size_t i = 0; i < records.size(); ++i) {
        indices[records[i].id] = i;
        digests.set(int64_t(i) * 2, records[i].id);
    }
    remaining = records.size();
    active = true;
    return true;
}

void RoRResourceDigest::consume(size_t index) {
    Record &record = records[index];
    if (record.consumed) return;
    digests.set(int64_t(index) * 2 + 1, canonical_entity_value_hash(record.value));
    record.consumed = true;
    record.value = Dictionary();
    --remaining;
}

void RoRResourceDigest::before_change(int64_t id) {
    if (!active) return;
    const auto found = indices.find(id);
    if (found != indices.end()) consume(found->second);
}

bool RoRResourceDigest::advance(int64_t budget_usec) {
    if (!active) return false;
    const auto started = std::chrono::steady_clock::now();
    while (cursor < records.size() && remaining) {
        consume(cursor++);
        const auto elapsed = std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now() - started).count();
        if (elapsed >= std::max<int64_t>(1, budget_usec)) break;
    }
    return remaining == 0;
}

PackedInt64Array RoRResourceDigest::take() {
    if (!active || remaining) return PackedInt64Array();
    const PackedInt64Array output = digests;
    cancel();
    return output;
}

void RoRResourceDigest::cancel() {
    active = false;
    records.clear();
    indices.clear();
    digests = PackedInt64Array();
    cursor = remaining = 0;
}

void RoRResourceDigest::_bind_methods() {
    ClassDB::bind_method(D_METHOD("begin", "resources"), &RoRResourceDigest::begin);
    ClassDB::bind_method(D_METHOD("before_change", "id"), &RoRResourceDigest::before_change);
    ClassDB::bind_method(D_METHOD("advance", "budget_usec"), &RoRResourceDigest::advance);
    ClassDB::bind_method(D_METHOD("take"), &RoRResourceDigest::take);
    ClassDB::bind_method(D_METHOD("cancel"), &RoRResourceDigest::cancel);
}

void RoRReadModelKernel::cache_actor_sprites(const Array &items, double scale) const {
    if (scale <= 0.0) return;
    static const Variant info_key("frame_info"), texture("texture"), mirrored("mirrored"), rotation("rotation"), polygon("gate_polygon");
    static const Variant kind("kind"), hotspot("hotspot"), screen_offset("screen_offset"), size("sprite_source_size"), command("sprite_command"), screen("screen_position");
    for (int64_t i = 0; i < items.size(); ++i) {
        Dictionary item = items[i];
        const String type = item[kind];
        if (type != ROR_TEXT("unit") && type != ROR_TEXT("unit_part")) continue;
        if (String(Dictionary(item[ROR_FIELD("data")]).get(ROR_FIELD("movement_domain"), ROR_FIELD("land"))) == ROR_TEXT("static")) continue;
        const Dictionary info = item[info_key];
        Object *source_texture = info.get(texture, Variant());
        if (!source_texture || info.has(rotation) || info.has(polygon)) continue;
        const Vector2 source_size = source_texture->call("get_size");
        const Vector2 offset = info.get(screen_offset, Vector2());
        const bool flip = info.get(mirrored, false);
        item[size] = source_size;
        item[ROR_FIELD("sprite_screen_offset")] = offset;
        item[ROR_FIELD("sprite_mirrored")] = flip;
        Array sprite;
        sprite.append(source_texture);
        Vector2 corner = Vector2(item[screen]).round() + offset * scale - Vector2(item[hotspot]) * scale;
        if (flip) corner.x = Vector2(item[screen]).round().x + offset.x * scale + Vector2(item[hotspot]).x * scale - source_size.x * scale;
        sprite.append(Rect2(corner, source_size * scale));
        sprite.append(Color(1, 1, 1, float(item[ROR_FIELD("opacity")])));
        sprite.append(source_texture->call("get_rid"));
        sprite.append(Rect2(Vector2(), Vector2(flip ? -source_size.x : source_size.x, source_size.y)));
        sprite.append(Rect2(Vector2(flip ? 1 : 0, 0), Vector2(flip ? -1 : 1, 1)));
        sprite.append(flip);
        item[command] = sprite;
    }
}

void RoRReadModelKernel::cache_actor_sprites_atlased(const Array &items, double scale,
        const Callable &atlas, Dictionary cache) const {
    if (scale <= 0.0) return;
    Array actors;
    for (int64_t i = 0; i < items.size(); ++i) {
        const Dictionary item = items[i];
        const String kind = item[ROR_FIELD("kind")];
        if (kind != ROR_TEXT("unit") && kind != ROR_TEXT("unit_part")) continue;
        const Dictionary source = item[ROR_FIELD("data")];
        if (String(source.get(ROR_FIELD("movement_domain"), ROR_TEXT("land"))) != ROR_TEXT("static")) actors.append(item);
    }
    cache_sprite_items(actors, scale, Vector2(), atlas, cache);
}

// The match supplies its detached terrain view and camera once per draw. Other
// clients can provide an arbitrary projection callable, including tools.
struct RoRReadModelKernel::FrameProjection {
    const Callable &fallback;
    double scale = 0.0, elevation_step = 0.0;
    Vector2 offset, half_tile;
    Vector2i size;
    Dictionary levels;

    FrameProjection(const Callable &project, const Array &camera) : fallback(project) {
        if (camera.size() != 6) return;
        scale = camera[0]; offset = camera[1]; half_tile = camera[2];
        elevation_step = camera[3]; size = camera[4]; levels = camera[5];
    }
    Vector2 screen(const Vector2 &p) const {
        if (scale <= 0.0 || size.x <= 0 || size.y <= 0) return fallback.call(p);
        const Vector2 flat((double(p.x) - double(p.y)) * half_tile.x,
                (double(p.x) + double(p.y)) * half_tile.y);
        const double height = terrain_height_at(p, size, levels);
        return flat * real_t(scale) + offset + Vector2(0, -height * elevation_step * scale);
    }
};

bool RoRReadModelKernel::refresh_interpolated_items(const Array &items, const Callable &project, double alpha, const Dictionary &depth_index, double sprite_scale, const Array &camera, bool force_projection) const {
    static const Variant kind("kind"), data("data"), id("stable_id"), pos("pos"), previous("previous_pos"), anchor("world_anchor"), screen_key("screen_position"), y("screen_y"), depth("depth_offset"), command("sprite_command");
    const FrameProjection projection(project, camera);
    struct Projected { Dictionary source; Vector2 position, screen; double depth = 0; bool projected = false; };
    std::unordered_map<int64_t, Projected> projected;
    bool moved = false;
	alpha = std::max(0.0, std::min(MAX_INTERPOLATION_ALPHA, alpha));
    for (int64_t i = 0; i < items.size(); ++i) {
        Dictionary item = items[i];
        const String type = item[kind];
        if (type == ROR_TEXT("environment")) continue; // Ambient flight keeps its existing spline.
        const Dictionary source = item[data];
        const int64_t entity_id = item[id];
        auto found = projected.find(entity_id);
        if (found == projected.end() || !UtilityFunctions::is_same(found->second.source, source)) {
            Projected point; point.source = source;
            const double bounded_alpha = std::min(alpha, double(source.get(ROR_FIELD("render_prediction_alpha_limit"), MAX_INTERPOLATION_ALPHA)));
            point.position = Vector2(source.get(previous, source.get(pos, Vector2()))).lerp(source.get(pos, Vector2()), real_t(bounded_alpha));
            projected[entity_id] = point;
            found = projected.find(entity_id);
        }
        Projected &point = found->second;
        // At a waypoint the interpolation limit may hold a pose over several
        // frames. Preserve its already projected sprite and sorting key.
        if (!force_projection && point.position == Vector2(item[anchor])) continue;
        if (!point.projected) {
            point.screen = projection.screen(point.position);
            point.depth = projected_unit_depth_offset(point.position, point.screen.y, depth_index, projection);
            point.projected = true;
        }
        if (!point.position.is_equal_approx(Vector2(item.get(anchor, point.position)))) moved = true;
        item[anchor] = point.position; item[screen_key] = point.screen;
        if (type == ROR_TEXT("unit") || type == ROR_TEXT("unit_part")) item[depth] = point.depth;
        item[y] = point.screen.y + double(item.get(depth, 0.0));
        if (item.has(command)) {
            Array sprite = item[command];
            const Vector2 offset = item[ROR_FIELD("sprite_screen_offset")], hotspot = item[ROR_FIELD("hotspot")], size = item[ROR_FIELD("sprite_source_size")];
            Vector2 corner = point.screen.round() + offset * sprite_scale - hotspot * sprite_scale;
            if (sprite.size() >= 7 && bool(sprite[6])) corner.x = point.screen.round().x + offset.x * sprite_scale + hotspot.x * sprite_scale - size.x * sprite_scale;
            sprite[1] = Rect2(corner, size * sprite_scale);
        }
    }
    return moved;
}
Array RoRReadModelKernel::changed_combat_ids(const Dictionary &delta, const Dictionary &units, const Dictionary &buildings, const Dictionary &sources, const Dictionary &classifications) const {
    const Array ids = delta[ROR_FIELD("ids")];
    const Dictionary masks = delta[ROR_FIELD("masks")];
    Array result;
    for (int64_t i = 0; i < ids.size(); ++i) {
        const Variant id = ids[i];
        if (!(int64_t(masks[id]) & (1 | 2 | 4 | 8 | 128))) continue;
        const Variant source = units.get(id, buildings.get(id, Variant()));
        if (source.get_type() == Variant::NIL ||
                !UtilityFunctions::is_same(sources.get(id, Variant()), source) ||
                !matches_combat_classification(source, classifications.get(id, Array()))) result.append(id);
    }
    return result;
}

Array RoRReadModelKernel::filter_visible_entities(const Array &entities, int64_t observer, const PackedByteArray &states, const Vector2i &map_size) const {
    static const Variant team("team"), pos("pos"), position("position");
    Array result;
    const uint8_t *fog = states.ptr();
    for (int64_t i = 0; i < entities.size(); ++i) {
        const Dictionary entity = entities[i];
        if (observer <= 0 || int64_t(entity.get(team, 0)) == observer) { result.append(entity); continue; }
        const Vector2 point = entity.get(pos, entity.get(position, Vector2()));
        const int64_t x = int64_t(Math::floor(point.x)), y = int64_t(Math::floor(point.y));
        if (x >= 0 && y >= 0 && x < map_size.x && y < map_size.y && y * map_size.x + x < states.size() && fog[y * map_size.x + x] == 2) result.append(entity);
    }
    return result;
}

Array RoRReadModelKernel::project_cached_render_entities(const Array &entities, const Dictionary &cache) const {
    static const Variant id_key("id"), anim("anim"), previous_pos("previous_pos"), type("entity_type"), schema_key("_ror_render_schema");
    const RoRJournalVersionReader journal(cache[ROR_FIELD("journal")]);
    if (!journal.supported) return Array();
    const Dictionary groups = cache[ROR_FIELD("groups")];
    Dictionary records = cache[ROR_FIELD("records")], cached_versions = cache[ROR_FIELD("versions")], categories = cache[ROR_FIELD("categories")];
    const Array fields = cache[ROR_FIELD("fields")], nested = cache[ROR_FIELD("nested")];
    const int64_t schema = cache[ROR_FIELD("schema")], capacity = cache[ROR_FIELD("capacity")];
    const Variant scope_value = cache.get(ROR_FIELD("scene_clocks"), Variant());
    Dictionary samples;
    Rect2 view;
    if (scope_value.get_type() == Variant::DICTIONARY) {
        const Dictionary scope = scope_value;
        const Variant bounds = scope.get(ROR_FIELD("bounds"), Variant()), values = scope.get(ROR_FIELD("samples"), Variant());
        if (bounds.get_type() == Variant::RECT2 && values.get_type() == Variant::DICTIONARY && !Dictionary(values).is_read_only()) {
            view = bounds;
            samples = values;
        }
    }
    Array result; result.resize(entities.size());
    for (int64_t i = 0; i < entities.size(); ++i) {
        const Dictionary source = entities[i];
        if (source.is_read_only() && int64_t(source.get(schema_key, -1)) == schema) { result[i] = source; continue; }
        const int64_t id = source.get(id_key, -1);
        const auto versions = journal.read(id);
        if (!versions.valid) return Array();
        const PackedInt64Array old = cached_versions.get(id, PackedInt64Array());
        const int64_t old_size = old.size();
        const int64_t *old_values = old.ptr();
        Dictionary previous = records.get(id, Dictionary()), projected;
        int64_t mask = 0;
        if (versions.size != old_size || (versions.size && !std::equal(versions.values, versions.values + versions.size, old_values))) {
            for (int64_t g = 0; g < versions.size; ++g) if (g >= old_size || versions.values[g] != old_values[g]) mask |= int64_t(1) << g;
        }
        if (previous.is_empty() || (mask & (1 | 128 | 32)) || versions.size == 0) projected = project_render(source, previous, fields, nested, schema);
        else if (!mask && previous.get(previous_pos, Variant()) == source.get(previous_pos, Variant())) {
            const double clock = source.get(anim, 0.0);
            if (double(previous.get(anim, 0.0)) == clock) {
                projected = previous;
            } else if (id >= 0 && view.has_area() && !view.has_point(source.get(ROR_FIELD("pos"), Vector2()))) {
                // A complete scene also serves immediate camera jumps. Keep
                // the exact clock separately until a client selects this row.
                samples[id] = clock;
                projected = previous;
            } else projected = patch_render(source, previous, mask, groups);
        } else projected = patch_render(source, previous, mask, groups);
        if (id >= 0 && (records.has(id) || records.size() < capacity)) {
            records[id] = projected;
            cached_versions[id] = mask || versions.size != old_size ? journal.retain(versions) : old;
            const String declared = projected.get(type, ROR_FIELD("unit"));
            categories[id] = declared == ROR_TEXT("resource") ? "resource" : (declared == ROR_TEXT("building") || declared == ROR_TEXT("foundation") ? "building" : "unit");
        }
        result[i] = projected;
    }
    return result;
}
void RoRStaticSpriteProjection::_bind_methods() {
    ClassDB::bind_method(D_METHOD("get_record_count"), &RoRStaticSpriteProjection::get_record_count);
}

Ref<RoRStaticSpriteProjection> RoRReadModelKernel::prepare_static_projection(const Array &items, const Vector2 &origin, double scale) const {
    static const Variant local("projection_anchor"), sort_local("projection_sort_y"), position("screen_position"), y("screen_y");
    static const Variant command("sprite_command"), clip("clip_static_sprite"), size("sprite_source_size"), offset("sprite_screen_offset"), hotspot("hotspot");
    Ref<RoRStaticSpriteProjection> result; result.instantiate();
    const int64_t count = items.size();
    result->records.reserve(size_t(count));
    for (int64_t i = 0; i < count; ++i) {
        Dictionary item = items[i];
        if (!item.has(local)) {
            item[local] = (Vector2(item[position]) - origin) / scale;
            item[sort_local] = (double(item[y]) - origin.y) / scale;
        }
        RoRStaticSpriteProjection::Record row;
        row.item = item;
        row.anchor = item[local];
        row.depth = item.get(sort_local, row.anchor.y);
        if (bool(item.get(clip, false)) && item.has(command)) {
            row.conservative = false;
            row.offset = item[offset]; row.hotspot = item[hotspot]; row.size = item[size];
            row.command = item[command];
        }
        result->records.push_back(row);
    }
    return result;
}

Array RoRReadModelKernel::project_prepared_static_items(const Ref<RoRStaticSpriteProjection> &prepared, const Vector2 &origin, double scale, const Rect2 &viewport) const {
    static const Variant position("screen_position"), y("screen_y");
    Array result;
    if (prepared.is_null()) return result;
    for (const auto &row : prepared->records) {
        if (row.conservative) {
            Array single; single.append(row.item);
            result.append_array(project_visible_static_items(single, origin, scale, viewport));
            continue;
        }
        const Vector2 screen = row.anchor * scale + origin;
        const Rect2 rectangle(screen.round() + row.offset * scale - row.hotspot * scale, row.size * scale);
        if (viewport.has_area() && !viewport.intersects(rectangle, true)) continue;
        Dictionary visible = row.item;
        visible[position] = screen; visible[y] = row.depth * scale + origin.y;
        Array draw = row.command; draw[1] = rectangle;
        result.append(visible);
    }
    return result;
}
Array RoRReadModelKernel::project_visible_static_items(const Array &items, const Vector2 &origin, double scale, const Rect2 &viewport, bool clip_buildings) const {
    static const Variant position("screen_position"), y("screen_y"), local("projection_anchor"), sort_local("projection_sort_y");
    static const Variant command("sprite_command"), size("sprite_source_size"), offset("sprite_screen_offset"), hotspot("hotspot"), clip("clip_static_sprite"), kind("kind");
    Array result;
    for (int64_t i = 0; i < items.size(); ++i) {
        Dictionary item = items[i];
        if (!item.has(local)) {
            item[local] = (Vector2(item[position]) - origin) / scale;
            item[sort_local] = (double(item[y]) - origin.y) / scale;
        }
        const Vector2 screen = Vector2(item[local]) * scale + origin;
        const bool sprite = item.has(command);
        Rect2 rectangle;
        if (sprite) {
            rectangle = Rect2(screen.round() + Vector2(item[offset]) * scale - Vector2(item[hotspot]) * scale, Vector2(item[size]) * scale);
            const String type = item[kind];
            if (viewport.has_area() && (bool(item.get(clip, false)) || (clip_buildings && (type == ROR_TEXT("building") || type == ROR_TEXT("building_part")))) && !viewport.intersects(rectangle, true)) continue;
        }
        item[position] = screen;
        item[y] = double(item.get(sort_local, Vector2(item[local]).y)) * scale + origin.y;
        if (sprite) {
            Array draw = item[command]; draw[1] = rectangle;
        }
        result.append(item);
    }
    return result;
}

Array RoRReadModelKernel::merge_projected_static_items(const Array &first, const Array &second, const Vector2 &origin, double scale) const {
    static const Variant layer("layer"), y("screen_y"), elevation("elevation"), sub("sub_order"), wall("wall_depth_tie"), anchor("world_anchor"), id("stable_id"), local("projection_anchor"), sort_local("projection_sort_y");
    const auto less = [&](const Dictionary &a, const Dictionary &b) {
        const int64_t al = a[layer], bl = b[layer]; if (al != bl) return al < bl;
        const double ay = a.has(local) ? double(a.get(sort_local, Vector2(a[local]).y)) * scale + origin.y : double(a[y]);
        const double by = b.has(local) ? double(b.get(sort_local, Vector2(b[local]).y)) * scale + origin.y : double(b[y]);
        if (!Math::is_equal_approx(ay, by)) return ay < by;
        const double ae = a[elevation], be = b[elevation]; if (!Math::is_equal_approx(ae, be)) return ae < be;
        const int64_t as = a.get(sub, 0), bs = b.get(sub, 0); if (as != bs) return as < bs;
        const bool aw = a.get(wall, false), bw = b.get(wall, false); if (aw != bw) return aw;
        if (aw) {
            const Vector2 ap = a[anchor], bp = b[anchor];
            if (!Math::is_equal_approx(double(ap.x), double(bp.x))) return ap.x < bp.x;
            if (!Math::is_equal_approx(double(ap.y), double(bp.y))) return ap.y < bp.y;
        }
        return int64_t(a[id]) < int64_t(b[id]);
    };
    Array result; result.resize(first.size() + second.size());
    int64_t a = 0, b = 0;
    for (int64_t i = 0; i < result.size(); ++i) {
        if (b >= second.size() || (a < first.size() && less(first[a], second[b]))) result[i] = first[a++];
        else result[i] = second[b++];
    }
    return result;
}

Array RoRReadModelKernel::create_unit_render_items(const Array &units, const Callable &project, const Callable &provider, const Callable &colors,
        double alpha, const Dictionary &depth_index, const Array &preview, const Array &selected, const Array &camera) const {
    const FrameProjection projection(project, camera);
    static const Variant kind("kind"), layer("layer"), elevation("elevation"), anchor("world_anchor"), screen_key("screen_position"), y("screen_y");
    static const Variant stable_id("stable_id"), frame("frame"), hotspot("hotspot"), tint("player_color"), opacity("opacity"), sub("sub_order");
    static const Variant wall("wall_depth_tie"), data("data"), info_key("frame_info"), phase("death_phase"), hp("hp"), pos("pos"), previous("previous_pos");
    static const Variant frame_index("frame_index"), graphic_layer("graphic_layer"), parts("composite_parts"), depth("depth_offset"), id("id"), team("team");
    std::unordered_set<int64_t> selected_ids, preview_ids;
    for (int64_t i = 0; i < selected.size(); ++i) selected_ids.insert(selected[i]);
    for (int64_t i = 0; i < preview.size(); ++i) preview_ids.insert(preview[i]);
    Dictionary team_colors;
    Array result;
    const auto item = [&](const char *type, int64_t render_layer, const Vector2 &position, const Vector2 &screen, int64_t entity_id,
            const Dictionary &entity, const Dictionary &info, double height, const Color &color, int64_t order) {
        Dictionary value;
        value[kind] = String(type); value[layer] = render_layer; value[elevation] = height;
        value[anchor] = position; value[screen_key] = screen; value[y] = double(screen.y); value[stable_id] = entity_id;
        value[frame] = int64_t(info.get(frame_index, 0)); value[hotspot] = info.get(hotspot, Vector2());
        value[tint] = color; value[opacity] = 1.0; value[sub] = order;
        value[wall] = String(entity.get(kind, ROR_FIELD(""))) == ROR_TEXT("wall"); value[data] = entity; value[info_key] = info;
        return value;
    };
    for (int64_t i = 0; i < units.size(); ++i) {
        const Dictionary unit = units[i];
        const String death = unit.get(phase, ROR_FIELD("alive"));
        if (double(unit.get(hp, 0.0)) <= 0.0 && death != ROR_TEXT("dying") && death != ROR_TEXT("corpse")) continue;
		const double bounded_alpha = std::min(std::max(0.0, std::min(MAX_INTERPOLATION_ALPHA, alpha)), double(unit.get(ROR_FIELD("render_prediction_alpha_limit"), MAX_INTERPOLATION_ALPHA)));
		const Vector2 position = Vector2(unit.get(previous, unit[pos])).lerp(unit[pos], real_t(bounded_alpha));
        const Vector2 screen = projection.screen(position);
        const double offset = projected_unit_depth_offset(position, screen.y, depth_index, projection);
        Vector2 sort_screen = screen; sort_screen.y += offset;
        Dictionary info;
        if (provider.is_valid()) {
            const Variant provided = provider.call(ROR_TEXT("unit"), unit);
            if (provided.get_type() == Variant::DICTIONARY) info = provided;
        }
        const int64_t entity_id = unit[id], owner = unit.get(team, 0);
        const double height = unit.get(elevation, 0.0);
        if (!team_colors.has(owner)) team_colors[owner] = colors.call(owner);
        const Color color = team_colors[owner];
        if (death != ROR_TEXT("corpse")) result.append(item("shadow", 3, position, screen, entity_id, unit, Dictionary(), height, Color(0, 0, 0, 0.32), 0));
        const int64_t base_order = int64_t(info.get(graphic_layer, 20)) * 1000;
        Dictionary body = item("unit", 4, position, screen, entity_id, unit, info, height, color, base_order);
        body[y] = double(sort_screen.y); body[depth] = offset; result.append(body);
        const Array overlays = info.get(parts, Array());
        for (int64_t part = 0; part < overlays.size(); ++part) {
            const Dictionary overlay = overlays[part];
            Dictionary body_part = item("unit_part", 4, position, screen, entity_id, unit, overlay, height, color, int64_t(overlay.get(graphic_layer, 20)) * 1000 + part + 1);
            body_part[y] = double(sort_screen.y); body_part[depth] = offset; result.append(body_part);
        }
        const bool chosen = selected_ids.find(entity_id) != selected_ids.end() || bool(unit.get(ROR_FIELD("selected"), false)) || preview_ids.find(entity_id) != preview_ids.end();
        if (death == ROR_TEXT("alive") && (chosen || preview_ids.find(entity_id) != preview_ids.end()))
            result.append(item("selection", 2, position, screen, entity_id, unit, info, height, color, 1));
        if (death == ROR_TEXT("alive") && chosen)
            result.append(item("health_bar", 7, position, screen, entity_id, unit, info, height, color, 2));
    }
    return result;
}

Dictionary RoRReadModelKernel::create_building_render_items(const Array &buildings, const Callable &project,
        const Callable &provider, const Callable &colors, Dictionary records, const Array &preview, const Array &selected,
        int64_t observer, double scale, bool affine, const Callable &cache_sprite) const {
    static const Variant kind("kind"), hp("hp"), pos("pos"), id("id"), data("data"), info_key("frame_info");
    static const Variant signature_key("signature"), screen_key("screen_position"), y("screen_y"), scale_key("scale");
    static const Variant source_key("source"), items_key("items"), screen_cache("screen"), elevation("elevation");
    static const Variant graphic_layer("graphic_layer"), depth_key("depth_world_offset"), info_signature_key("info_signature");
    std::unordered_set<int64_t> chosen, highlighted, present;
    for (int64_t i = 0; i < selected.size(); ++i) chosen.insert(selected[i]);
    for (int64_t i = 0; i < preview.size(); ++i) highlighted.insert(preview[i]);
    Array result, rally, moved_items, uncached;
    const Vector2 origin = project.call(Vector2());
    const auto frame = [&](const char *type, const Dictionary &actor) {
        const Variant value = provider.is_valid() ? provider.call(String(type), actor) : Variant();
        return value.get_type() == Variant::DICTIONARY ? Dictionary(value) : Dictionary();
    };
    const auto item = [&](const char *type, int64_t layer, const Vector2 &position, const Vector2 &screen,
            int64_t entity_id, const Dictionary &actor, const Dictionary &info, double height, const Color &color, int64_t sub) {
        Dictionary value;
        value[kind] = String(type); value[ROR_FIELD("layer")] = layer; value[elevation] = height;
        value[ROR_FIELD("world_anchor")] = position; value[screen_key] = screen; value[y] = double(screen.y); value[ROR_FIELD("stable_id")] = entity_id;
        value[ROR_FIELD("frame")] = int64_t(info.get(ROR_FIELD("frame_index"), 0)); value[ROR_FIELD("hotspot")] = info.get(ROR_FIELD("hotspot"), Vector2());
        value[ROR_FIELD("player_color")] = color; value[ROR_FIELD("opacity")] = 1.0; value[ROR_FIELD("sub_order")] = sub;
        value[ROR_FIELD("wall_depth_tie")] = String(actor.get(kind, ROR_FIELD(""))) == ROR_TEXT("wall");
        value[data] = actor; value[info_key] = info; return value;
    };
    for (int64_t i = 0; i < buildings.size(); ++i) {
        const Dictionary building = buildings[i];
        const String phase = building.get(ROR_FIELD("death_phase"), ROR_FIELD("removed"));
        if (double(building[hp]) <= 0.0 && phase != ROR_TEXT("dying") && phase != ROR_TEXT("ruin")) continue;
        const Vector2 position = building[pos], screen = project.call(position);
        const Dictionary info = frame("building", building);
        const int64_t entity_id = building[id];
        const double height = building.get(elevation, 0.0);
        const bool ruin = phase == ROR_TEXT("ruin");
        const bool interior = bool(building.get(ROR_FIELD("harvestable"), false)) || ruin, selected_actor = chosen.count(entity_id), previewed = highlighted.count(entity_id);
        const bool has_rally = selected_actor && bool(building.get(ROR_FIELD("rally_point_set"), false));
        const int64_t order = int64_t(info.get(graphic_layer, 20)) * 1000 - (interior ? 100 : 0);
        present.insert(entity_id);
        Dictionary retained = records.get(entity_id, Dictionary());
        const int64_t info_signature = info.is_read_only() && UtilityFunctions::is_same(retained.get(info_key, Variant()), info)
                ? int64_t(retained[info_signature_key]) : UtilityFunctions::hash(info);
        Array signature_parts;
        signature_parts.append(info_signature); signature_parts.append(position); signature_parts.append(height);
        signature_parts.append(String(building.get(kind, ROR_FIELD("")))); signature_parts.append(interior);
        signature_parts.append(selected_actor); signature_parts.append(previewed); signature_parts.append(observer);
        const int64_t signature = UtilityFunctions::hash(signature_parts);
        if (!has_rally && retained.get(signature_key, Variant()) == Variant(signature)) {
            const bool moved = Vector2(retained[screen_cache]) != screen || double(retained[scale_key]) != scale;
            const bool changed = !UtilityFunctions::is_same(retained[source_key], building);
            const Array items = retained[items_key];
            if (moved || changed) {
                for (int64_t j = 0; j < items.size(); ++j) {
                    Dictionary sprite = items[j];
                    if (changed) sprite[data] = building;
                    if (moved) {
                        if (affine) moved_items.append(sprite);
                        else {
                            sprite[screen_key] = screen;
                            sprite[y] = double(Vector2(project.call(position + Vector2(sprite.get(depth_key, Vector2())))).y);
                            uncached.append(sprite);
                        }
                    }
                }
            }
            retained[screen_cache] = screen; retained[scale_key] = scale; retained[source_key] = building;
            result.append_array(items); continue;
        }
        Array items;
        items.append(item("building", interior ? 1 : 4, position, screen, entity_id, building, info, height, Color(1,1,1), order));
        const Array parts = info.get(ROR_FIELD("composite_parts"), Array());
        for (int64_t j = 0; j < parts.size(); ++j) {
            const Dictionary part = parts[j];
            const String role = part.get(ROR_FIELD("presentation_layer"), ROR_FIELD(""));
            const int64_t layer = role == ROR_TEXT("shadow") ? 3 : ((role == ROR_TEXT("upright") && !ruin) || !interior ? 4 : 1);
            Dictionary sprite = item("building_part", layer, position, screen, entity_id, building, part, height, Color(1,1,1), int64_t(part.get(graphic_layer,20))*1000+(interior?100:0)+j+1);
            const Vector2 depth = part.get(depth_key, Vector2());
            sprite[depth_key] = depth; sprite[y] = double(Vector2(project.call(position + depth)).y); items.append(sprite);
        }
        const int64_t team = building.get(ROR_FIELD("team"), 0);
        if (selected_actor || previewed)
            items.append(item("selection", 2, position, screen, entity_id, building, info, height, colors.call(team), 1));
        if (selected_actor && team == observer && bool(building.get(ROR_FIELD("rally_point_set"),false)) && double(building[hp]) > 0.0 && String(building.get(ROR_FIELD("state"),"")) == ROR_TEXT("complete")) {
            const Vector2 destination = building.get(ROR_FIELD("rally_point"), position);
            const Dictionary rally_info = frame("rally_flag", building);
            Dictionary flag = item("rally_flag", 4, destination, project.call(destination), entity_id, building, rally_info, 0.0, colors.call(observer), 20001);
            items.append(flag); rally.append(flag);
        }
        uncached.append_array(items);
        retained = Dictionary();
        retained[signature_key] = signature; retained[info_key] = info; retained[info_signature_key] = info_signature;
        retained[items_key] = items; retained[source_key] = building; retained[screen_cache] = screen; retained[scale_key] = scale;
        records[entity_id] = retained; result.append_array(items);
    }
    if (!uncached.is_empty()) cache_sprite.call(uncached);
    if (!moved_items.is_empty()) project_visible_static_items(moved_items, origin, scale, Rect2());
    const Array ids = records.keys();
    for (int64_t i = 0; i < ids.size(); ++i) if (!present.count(int64_t(ids[i]))) records.erase(ids[i]);
    Dictionary output; output[ROR_FIELD("items")] = result; output[ROR_FIELD("rally")] = rally; return output;
}

Array RoRReadModelKernel::clip_building_render_items(const Array &items, const Rect2 &viewport) const {
    if (!viewport.has_area()) return items;
    static const Variant kind("kind"), command("sprite_command");
    Array result;
    for (int64_t i = 0; i < items.size(); ++i) {
        const Dictionary item = items[i];
        const String type = item[kind];
        if ((type == ROR_TEXT("building") || type == ROR_TEXT("building_part")) && item.has(command)) {
            const Array sprite = item[command];
            if (!viewport.intersects(sprite[1], true)) continue;
        }
        result.append(item);
    }
    return result;
}

void RoRReadModelKernel::cache_sprite_items(const Array &items, double scale, const Vector2 &origin,
        const Callable &atlas, Dictionary cache) const {
    static const Variant kind("kind"), command("sprite_command"), info_key("frame_info"), texture_key("texture");
    static const Variant anchor("projection_anchor"), screen("screen_position"), y("screen_y"), hotspot("hotspot"), offset("screen_offset");
    Dictionary entries = cache.get(ROR_FIELD("entries"), Dictionary());
    int64_t bytes = cache.get(ROR_FIELD("bytes"), 0);
    constexpr int64_t MAX_BYTES = 96 * 1024 * 1024, MAX_ENTRIES = 4096;
    for (int64_t i = 0; i < items.size(); ++i) {
        Dictionary item = items[i];
        item.erase(command);
        const String type = item[kind];
        const bool actor = type == ROR_TEXT("unit") || type == ROR_TEXT("unit_part");
        // Actors retain live screen/depth coordinates. Static projection
        // anchors must never freeze their interpolated painter order.
        if (!actor && scale > 0.0 && !item.has(anchor)) {
            item[anchor] = (Vector2(item[screen]) - origin) / scale;
            item[ROR_FIELD("projection_sort_y")] = (double(item[y]) - origin.y) / scale;
        }
        if (type != ROR_TEXT("building") && type != ROR_TEXT("building_part") && type != ROR_TEXT("resource") && type != ROR_TEXT("resource_shadow") &&
                type != ROR_TEXT("unit") && type != ROR_TEXT("unit_part") && type != ROR_TEXT("projectile") && type != ROR_TEXT("effect") && type != ROR_TEXT("marker") &&
                type != ROR_TEXT("environment") && type != ROR_TEXT("rally_flag")) continue;
        const Dictionary info = item[info_key];
        const Variant source = info.get(texture_key, Variant());
        Object *texture = source;
        const bool flipped = info.get(ROR_FIELD("mirrored"), false);
        if (scale <= 0.0 || !texture || info.has(ROR_FIELD("gate_polygon")) || info.has(ROR_FIELD("rotation")) || (flipped && !actor)) continue;
        Dictionary prepared = entries.get(source, Dictionary());
        if (prepared.is_empty()) {
            const Vector2 size = texture->call("get_size");
            const Variant rendered = atlas.is_valid() ? atlas.call(texture) : source;
            Object *rendered_texture = rendered;
            if (!rendered_texture) continue;
            RID rid = rendered_texture->call("get_rid");
            Rect2 region(Vector2(), size);
            Vector2 texture_size = rendered_texture->call("get_size");
            if (rendered_texture->is_class("AtlasTexture")) {
                Object *page = rendered_texture->call("get_atlas");
                if (page) { rid = page->call("get_rid"); texture_size = page->call("get_size"); }
                region = rendered_texture->call("get_region");
            }
            prepared[ROR_FIELD("size")] = size; prepared[texture_key] = rendered;
            prepared[ROR_FIELD("rid")] = rid; prepared[ROR_FIELD("region")] = region;
            if (texture_size.x > 0 && texture_size.y > 0) prepared[ROR_FIELD("uv")] = Rect2(region.position / texture_size, region.size / texture_size);
            const int64_t weight = int64_t(size.x) * int64_t(size.y) * 8 + 256;
            prepared[ROR_FIELD("bytes")] = weight;
            if (weight <= MAX_BYTES) {
                while (!entries.is_empty() && (entries.size() >= MAX_ENTRIES || bytes + weight > MAX_BYTES)) {
                    const Variant expired = entries.keys()[0];
                    bytes -= int64_t(Dictionary(entries[expired])[ROR_FIELD("bytes")]); entries.erase(expired);
                }
                entries[source] = prepared; bytes += weight;
            }
        }
        const Vector2 size = prepared[ROR_FIELD("size")], screen_offset = info.get(offset, Vector2());
        item[ROR_FIELD("sprite_source_size")] = size; item[ROR_FIELD("sprite_screen_offset")] = screen_offset;
        const Vector2 point = Vector2(item[screen]).round() + screen_offset * scale;
        Vector2 corner = point - Vector2(item[hotspot]) * scale;
        if (flipped) corner.x = point.x + Vector2(item[hotspot]).x * scale - size.x * scale;
        Rect2 region = prepared[ROR_FIELD("region")];
        if (flipped) region.size.x = -region.size.x;
        Array sprite;
        sprite.append(prepared[texture_key]);
        sprite.append(Rect2(corner, size * scale));
        sprite.append(Color(1,1,1,float(item[ROR_FIELD("opacity")])));
        sprite.append(prepared[ROR_FIELD("rid")]); sprite.append(region);
        if (prepared.has(ROR_FIELD("uv"))) {
            Rect2 uv = prepared[ROR_FIELD("uv")];
            if (flipped) { uv.position.x += uv.size.x; uv.size.x = -uv.size.x; }
            sprite.append(uv);
            if (actor) sprite.append(flipped);
        }
        if (actor) item[ROR_FIELD("sprite_mirrored")] = flipped;
        item[command] = sprite;
    }
    cache[ROR_FIELD("entries")] = entries; cache[ROR_FIELD("bytes")] = bytes;
}

bool RoRReadModelKernel::matches_combat_classification(const Dictionary &entity, const Array &previous) const {
    if (previous.size() != 12) return false;
    static const Variant hp("hp"), pos("pos"), team("team"), combat("combat_enabled"), task("task"), target("target_id"), retaliation("retaliation_target_id");
    static const Variant pursuit("combat_pursuit"), stance("stance"), autonomous("attack_autonomous"), tags("behavior_tags"), radius("footprint_radius");
    return bool(previous[0]) == (double(entity.get(hp, 0.0)) > 0.0) &&
        Vector2i(previous[1]) == Vector2i((Vector2(entity.get(pos, Vector2())) / 4.0).floor()) &&
        int64_t(previous[2]) == int64_t(entity.get(team, 0)) &&
        bool(previous[3]) == bool(entity.get(combat, false)) &&
        String(previous[4]) == String(entity.get(task, ROR_FIELD("idle"))) &&
        int64_t(previous[5]) == int64_t(entity.get(target, -1)) &&
        int64_t(previous[6]) == int64_t(entity.get(retaliation, -1)) &&
        bool(previous[7]) == bool(entity.get(pursuit, false)) &&
        String(previous[8]) == String(entity.get(stance, ROR_FIELD("passive"))) &&
        bool(previous[9]) == bool(entity.get(autonomous, false)) &&
        previous[10] == entity.get(tags, Array()) &&
        double(previous[11]) == double(entity.get(radius, 0.0));
}

int64_t RoRReadModelKernel::advance_harvesting_recovery(Dictionary worker, const Dictionary &resources, const Dictionary &reservations) const {
    const Variant target = resources.get(worker.get(ROR_FIELD("resource_id"), -1), Variant());
    return target.get_type() == Variant::DICTIONARY ? advance_harvesting_at_target(worker, target, reservations) : -1;
}

int64_t RoRReadModelKernel::advance_harvesting_at_target(Dictionary worker, const Dictionary &resource, const Dictionary &reservations) const {
    static const Variant components("components"), worker_key("worker"), enabled("enabled"), stage("gather_stage"), work("work"), resource_id("resource_id");
    static const Variant amount("amount"), capacity("carry_capacity"), carried("carried_amount"), pos("pos"), domain("movement_domain"), radius("footprint_radius"), slot_key("resource_approach_slot");
    static const Variant order_key("order"), completed("completed"), phase("phase"), history("history");
    if (double(worker.get(work, 0.0)) <= 0.0 || String(worker.get(stage, ROR_FIELD(""))) == ROR_TEXT("returning")) return -1;
    const Dictionary parts = worker.get(components, Dictionary()), role = parts.get(worker_key, Dictionary());
    if (!bool(role.get(enabled, false))) return -1;
    if (int64_t(resource.get(amount, 0)) <= 0) return -1;
    const double limit = std::max(0.0, double(worker.get(capacity, 0.0)));
    if (limit > 0.0 && double(worker.get(carried, 0.0)) >= limit - 0.0001) return -1;
    const Vector2 position = worker[pos], target = resource[pos], local = position - Vector2(Vector2i(position));
    bool in_range = true;
    if (String(worker.get(domain, ROR_FIELD("land"))) != ROR_TEXT("water") && (Vector2i(position) == Vector2i(target) || local.x < 0.12 || local.x > 0.88 || local.y < 0.12 || local.y > 0.88)) in_range = false;
    const double reach = std::max(0.5, double(resource.get(radius, 0.2))) + double(worker.get(radius, 0.3)) + 0.32;
    in_range = in_range && position.distance_squared_to(target) <= reach * reach;
    const Variant slot = worker.get(slot_key, Variant());
    if (slot.get_type() == Variant::VECTOR2) {
        const bool at_slot = position.distance_squared_to(slot) <= 0.0144;
        const Dictionary assigned = reservations.get(worker[resource_id], Dictionary());
        in_range = assigned.size() > 1 ? at_slot : in_range || at_slot;
    }
    if (!in_range) return -1;
    Dictionary order = parts.get(order_key, Dictionary());
    if (order.is_empty()) return -1;
    int64_t mask = 0;
    const auto put = [&](const String &key, const Variant &value, int64_t changed) {
        if (!worker.has(key) || worker[key].get_type() != value.get_type() || worker[key] != value) { worker[key] = value; mask |= changed; }
    };
    const auto transition = [&](const char *next) {
        if (bool(order.get(completed, true)) || String(order.get(phase, ROR_FIELD(""))) == next) return;
        order[phase] = String(next);
        Array phases = order.get(history, Array());
        phases.append(String(next));
        if (phases.size() > 32) phases.pop_front();
        order[history] = phases;
        mask |= 68; // ACTIVITY | CONTROL, sampled at the owner-thread boundary.
    };
    put(stage, ROR_TEXT("harvesting"), 96);
    transition("FaceTarget");
    const Vector2 difference = target - position;
    if (difference.length_squared() > 0.0001) {
        const Vector2 screen((difference.x - difference.y) * 32.0, (difference.x + difference.y) * 16.0);
        const int64_t facing = (int64_t(std::round(std::atan2(-double(screen.x), double(screen.y)) / (6.283185307179586476925286766559 / 8.0))) % 8 + 8) % 8;
        put(ROR_TEXT("desired_facing"), facing, 96);
        put(ROR_TEXT("action_facing"), facing, 96);
        put(ROR_TEXT("facing"), facing, 2);
    }
    transition("Recover");
    return mask;
}

Array RoRReadModelKernel::resources_in_radius(const Dictionary &cells, const Vector2i &size, const Vector2 &origin, double radius) const {
    struct Record { int64_t id; Dictionary value; };
    struct Compare { bool operator()(const Record &a, const Record &b) const { return a.id < b.id; } };
    Array result;
    if (size.x <= 0 || size.y <= 0 || !std::isfinite(radius) || radius < 0.0 || radius > 32.0) return result;
    const int min_x = std::max(0, int(std::floor(double(origin.x) - radius)));
    const int min_y = std::max(0, int(std::floor(double(origin.y) - radius)));
    const int end_x = std::min(size.x, int(std::floor(double(origin.x) + radius)) + 1);
    const int end_y = std::min(size.y, int(std::floor(double(origin.y) + radius)) + 1);
    const double squared_radius = radius * radius;
    static const Variant pos("pos"), id("id");
    const Array empty;
    std::vector<Record> records;
    for (int y = min_y; y < end_y; ++y) for (int x = min_x; x < end_x; ++x) {
        const Array bucket = cells.get(int64_t(y) * size.x + x, empty);
        for (int64_t i = 0; i < bucket.size(); ++i) {
            const Dictionary resource = bucket[i];
            if (double(origin.distance_squared_to(Vector2(resource[pos]))) <= squared_radius) records.push_back({int64_t(resource[id]), resource});
        }
    }
    // Preserve the original global ID ordering, including duplicate entries.
    if (!records.empty()) SortArray<Record, Compare>().sort(records.data(), int64_t(records.size()));
    result.resize(int64_t(records.size()));
    for (size_t i = 0; i < records.size(); ++i) result[int64_t(i)] = records[i].value;
    return result;
}

void RoRReadModelKernel::set_motion_profiling(bool enabled) {
    motion_profiling = enabled;
    for (auto &measurement : motion_measurements) measurement = MotionMeasurement();
}

Dictionary RoRReadModelKernel::profile_storage_graph(const Dictionary &roots, int64_t node_limit) const {
    // Diagnostic, synchronous read of an exclusively owned graph. Identity
    // comes from supported const element/payload pointers, never opaque ABI
    // storage. Sets live for this call only; nothing retains a measured root.
    node_limit = std::clamp(node_limit, int64_t(1), int64_t(32000000));
    std::unordered_set<const void *> dictionaries, arrays, strings, packed;
    struct Visit { Variant value; int depth; };
    std::vector<Visit> stack;
    Dictionary categories;
    int64_t visited = 0;
    bool limited = false;
    const Array names = roots.keys();
    for (int64_t category = 0; category < names.size(); ++category) {
        int64_t dictionary_count = 0, entries = 0, array_count = 0, slots = 0, string_count = 0, string_bytes = 0, packed_bytes = 0, empty_dictionaries = 0, empty_arrays = 0, objects = 0;
        stack.clear(); stack.push_back({roots[names[category]], 0});
        while (!stack.empty()) {
            if (++visited > node_limit) { limited = true; break; }
            const Visit visit = std::move(stack.back()); stack.pop_back();
            if (visit.depth > 64) { limited = true; continue; }
            const Variant &value = visit.value;
            switch (value.get_type()) {
                case Variant::DICTIONARY: {
                    const Dictionary object = value;
                    if (object.is_empty()) { ++empty_dictionaries; break; }
                    const Array keys = object.keys();
                    if (!dictionaries.insert(&object[keys[0]]).second) break;
                    ++dictionary_count; entries += object.size();
                    for (int64_t i = 0; i < keys.size(); ++i) {
                        stack.push_back({keys[i], visit.depth + 1});
                        stack.push_back({object[keys[i]], visit.depth + 1});
                    }
                    break;
                }
                case Variant::ARRAY: {
                    const Array object = value;
                    if (object.is_empty()) { ++empty_arrays; break; }
                    if (!arrays.insert(&object[0]).second) break;
                    ++array_count; slots += object.size();
                    for (int64_t i = 0; i < object.size(); ++i) stack.push_back({object[i], visit.depth + 1});
                    break;
                }
                case Variant::STRING: {
                    const String object = value;
                    if (!object.is_empty() && strings.insert(object.ptr()).second) { ++string_count; string_bytes += (object.length() + 1) * 4; }
                    break;
                }
                case Variant::PACKED_BYTE_ARRAY: { const PackedByteArray a = value; if (!a.is_empty() && packed.insert(a.ptr()).second) packed_bytes += a.size(); break; }
                case Variant::PACKED_INT32_ARRAY: { const PackedInt32Array a = value; if (!a.is_empty() && packed.insert(a.ptr()).second) packed_bytes += a.size() * 4; break; }
                case Variant::PACKED_INT64_ARRAY: { const PackedInt64Array a = value; if (!a.is_empty() && packed.insert(a.ptr()).second) packed_bytes += a.size() * 8; break; }
                case Variant::PACKED_FLOAT32_ARRAY: { const PackedFloat32Array a = value; if (!a.is_empty() && packed.insert(a.ptr()).second) packed_bytes += a.size() * 4; break; }
                case Variant::PACKED_FLOAT64_ARRAY: { const PackedFloat64Array a = value; if (!a.is_empty() && packed.insert(a.ptr()).second) packed_bytes += a.size() * 8; break; }
                case Variant::PACKED_VECTOR2_ARRAY: { const PackedVector2Array a = value; if (!a.is_empty() && packed.insert(a.ptr()).second) packed_bytes += a.size() * sizeof(Vector2); break; }
                case Variant::PACKED_VECTOR3_ARRAY: { const PackedVector3Array a = value; if (!a.is_empty() && packed.insert(a.ptr()).second) packed_bytes += a.size() * sizeof(Vector3); break; }
                case Variant::PACKED_COLOR_ARRAY: { const PackedColorArray a = value; if (!a.is_empty() && packed.insert(a.ptr()).second) packed_bytes += a.size() * sizeof(Color); break; }
                case Variant::OBJECT: ++objects; break;
                default: break;
            }
        }
        Dictionary row;
        row[ROR_FIELD("dictionaries")] = dictionary_count; row[ROR_FIELD("dictionary_entries")] = entries;
        row[ROR_FIELD("arrays")] = array_count; row[ROR_FIELD("array_slots")] = slots;
        row[ROR_FIELD("unique_string_payload_bytes")] = string_bytes; row[ROR_FIELD("unique_strings")] = string_count;
        row[ROR_FIELD("packed_payload_bytes")] = packed_bytes; row[ROR_FIELD("empty_dictionary_references")] = empty_dictionaries;
        row[ROR_FIELD("empty_array_references")] = empty_arrays; row[ROR_FIELD("object_references_not_followed")] = objects;
        categories[names[category]] = row;
        if (limited) break;
    }
    Dictionary result;
    result[ROR_FIELD("categories")] = categories; result[ROR_FIELD("visited_values")] = visited; result[ROR_FIELD("limited")] = limited;
    result[ROR_FIELD("note")] = ROR_TEXT("Unique const storage identity across categories; empty references and allocator overhead are not unique byte measurements. Objects are not traversed.");
    return result;
}

Dictionary RoRReadModelKernel::motion_profile() const {
    Dictionary result;
    const char *names[] = {"calculate", "yield", "velocities", "integrate", "progress", "checked_order"};
    for (int i = 0; i < 6; ++i) {
        const auto &measurement = motion_measurements[i];
        Dictionary row;
        row[ROR_FIELD("count")] = measurement.count;
        row[ROR_FIELD("total_us")] = double(measurement.total_ns) / 1000.0;
        row[ROR_FIELD("mean_us")] = measurement.count ? double(measurement.total_ns) / double(measurement.count) / 1000.0 : 0.0;
        row[ROR_FIELD("max_us")] = double(measurement.maximum_ns) / 1000.0;
        result[names[i]] = row;
    }
    return result;
}

Dictionary RoRReadModelKernel::typed_motion_stats() const {
    Dictionary result;
    result[ROR_FIELD("updates")] = typed_motion_updates; result[ROR_FIELD("rejections")] = typed_motion_rejections;
    result[ROR_FIELD("comparisons")] = typed_motion_comparisons; result[ROR_FIELD("mismatches")] = typed_motion_mismatches;
    result[ROR_FIELD("borrowed_field_updates")] = borrowed_motion_field_updates;
    return result;
}

Dictionary RoRReadModelKernel::advance_ordered_unit_span(const Dictionary &context, double delta) const {
    RoRActorKeys::Scope key_scope(bool(context.get(ROR_FIELD("cached_actor_keys"), true)), bool(context.get(ROR_FIELD("profile_cached_actor_keys"), false)));
    RoRScriptBoundaryProfile boundary_scope(bool(context.get(ROR_FIELD("profile_script_boundaries"), false)), context.get(ROR_FIELD("script_boundary_stats"), Dictionary()));
    // One owner-loop pass. Movement has explicit preparation, route, motion
    // and event stages; other domain actors retain their original order.
    // A schema fallback returns the untouched suffix, never replaying work.
    Object *world = context[ROR_FIELD("world")], *journal = context[ROR_FIELD("journal")], *activity = context[ROR_FIELD("activity")];
    Object *physical = context[ROR_FIELD("physical")];
    const Array units = context[ROR_FIELD("units")];
    Object *knowledge = context[ROR_FIELD("knowledge")], *elevation = context[ROR_FIELD("elevation")], *spatial = context[ROR_FIELD("spatial")];
    const Callable fallback_actor = context[ROR_FIELD("fallback")];
    Object *movement_system = context.get(ROR_FIELD("movement_system"), Variant());
    const Callable continue_prepared = context.get(ROR_FIELD("continue_prepared"), Callable());
    MovementBatchContext movement_batch;
    const bool common_pipeline = bool(context.get(ROR_FIELD("common_pipeline"), false)) && movement_system && continue_prepared.is_valid() &&
        prepare_movement_batch(movement_batch, world, movement_system);
    ActorBatchContext actor_batch;
    const bool full_actor_pipeline = common_pipeline && bool(context.get(ROR_FIELD("actor_pipeline"), false)) && prepare_actor_batch(actor_batch, context);
    movement_batch.profile_stages = full_actor_pipeline && actor_batch.profile_stages;
    Dictionary actor_context = context[ROR_FIELD("actor_context")];
    int64_t cursor = 0, last_order = -1;
    Object *planner = nullptr;
    Variant planner_value;
    int64_t planner_team = std::numeric_limits<int64_t>::min();
    bool bindings_fresh = false;
    static const StringName pins_name("read_generation_pins"), prepared_name("tick_prepared"), probe_name("performance_probe");
    static const StringName pending_name("_legacy_pending"), versions_name("_legacy_versions_by_id"), removed_name("_legacy_pending_removed");
    static const StringName full_name("_legacy_pending_full"), revision_name("revision"), deferred_name("pending_units"), members_name("member_ids");
    static const StringName notify_method("notify_entity_changed");
    if (!world || !journal || !activity || !physical || !knowledge || !elevation || !spatial || !fallback_actor.is_valid() || delta <= 0.0 ||
            units.size() > 65536 || cursor < 0 || cursor >= units.size() || int64_t(world->get(pins_name)) != 0 ||
            !bool(activity->get(prepared_name))) return Dictionary();
    const Dictionary orders = context[ROR_FIELD("orders")], unit_ids = context[ROR_FIELD("unit_ids")], envelopes = context[ROR_FIELD("envelopes")], groups = context[ROR_FIELD("groups")];
    Dictionary by_unit = context[ROR_FIELD("movement_by_unit")], vertices = context[ROR_FIELD("vertices")];
    Object *shared_kernel = context[ROR_FIELD("movement_shared")];
    const Vector2i map_size = context[ROR_FIELD("map_size")];
    Array neighbors = context[ROR_FIELD("neighbors")];
    if (neighbors.is_read_only()) return Dictionary();
    Dictionary buckets = context[ROR_FIELD("buckets")];
    Array entities = context[ROR_FIELD("entities")], positions = context[ROR_FIELD("positions")], radii = context[ROR_FIELD("radii")];
    double cell_size = context[ROR_FIELD("cell_size")], max_radius = context[ROR_FIELD("maximum_radius")], max_clearance = context[ROR_FIELD("maximum_clearance")];
    const bool group_enabled = context[ROR_FIELD("group_enabled")];
    const bool direct_neighbors = context[ROR_FIELD("direct_neighbors")];
    static const StringName shared_name("native_shared_movement_kernel"), by_unit_name("native_movement_kernels_by_unit_id");
    static const StringName nonzero_name("nonzero_vertex_count"), vertices_name("vertex_levels"), planner_method("planner");
    static const StringName buckets_name("unit_buckets"), entities_name("unit_entities"), positions_name("unit_positions"), radii_name("unit_radii");
    static const StringName cell_size_name("cell_size"), maximum_radius_name("maximum_unit_radius"), maximum_clearance_name("maximum_unit_clearance");
    static const Variant id_key("id"), team_key("team"), task_key("task"), shared_key("formation_shared_motion");
    static const Variant group_key("formation_group_id"), ticks_key("stuck_ticks"), radius_key("footprint_radius");
    static const Variant hp_key("hp"), retaliation_key("retaliation_target_id"), parts_key("components"), faith_key("conversion"), enabled_key("enabled");
    static const Variant index_key("index"), order_key("last_order"), updates_key("updates"), candidates_key("candidates");
    int64_t updates = 0, motion_updates = 0, pipeline_calls = 0, candidates = 0, attempts = 0;
    int64_t coalesced_deferred_skips = 0;
    const bool coalesced_activity = activity->get(ROR_PROPERTY("coalesced_boundaries_enabled"));
    const bool profile_move_fallbacks = context.get(ROR_FIELD("profile_move_fallbacks"), false);
    Dictionary move_fallbacks;
    bool failed = false;
    std::unordered_map<int64_t, int64_t> stop_ticks;
    const auto finish = [&]() {
        Dictionary result;
        if (key_scope.profile) result[ROR_FIELD("actor_key_counts")] = key_scope.stats();
        result[index_key] = cursor; result[order_key] = last_order;
        result[updates_key] = updates + actor_batch.direct_moves; result[ROR_FIELD("motion_updates")] = motion_updates + actor_batch.motion_updates; result[ROR_FIELD("pipeline_calls")] = pipeline_calls + actor_batch.direct_moves; result[candidates_key] = candidates + actor_batch.candidates; result[ROR_FIELD("attempts")] = attempts + actor_batch.move_attempts; result[ROR_FIELD("failed")] = failed;
        if (profile_move_fallbacks) result[ROR_FIELD("move_fallbacks")] = move_fallbacks;
        result[ROR_FIELD("batch_operations")] = movement_batch.operations;
        result[ROR_FIELD("batch_binding_refreshes")] = movement_batch.binding_refreshes;
        if (full_actor_pipeline) {
            Dictionary counters;
            counters[ROR_FIELD("actors")] = actor_batch.calls; counters[ROR_FIELD("gather_recoveries")] = actor_batch.gather_recoveries;
            counters[ROR_FIELD("coalesced_deferred_updates_skipped")] = coalesced_deferred_skips;
            counters[ROR_FIELD("gather_controller_calls")] = actor_batch.gather_controller_calls;
            counters[ROR_FIELD("gather_controller_moves")] = actor_batch.gather_controller_moves;
            counters[ROR_FIELD("gather_controller_returns")] = actor_batch.gather_controller_returns;
            counters[ROR_FIELD("gather_controller_transitions")] = actor_batch.gather_controller_transitions;
            counters[ROR_FIELD("gather_controller_adoptions")] = actor_batch.gather_controller_adoptions;
            counters[ROR_FIELD("gather_controller_blocked_adoptions")] = actor_batch.gather_controller_blocked_adoptions;
            counters[ROR_FIELD("gather_continuations")] = actor_batch.gather_continuations; counters[ROR_FIELD("domain_callbacks")] = actor_batch.domain_callbacks;
            counters[ROR_FIELD("native_animations")] = actor_batch.native_animations; counters[ROR_FIELD("script_animations")] = actor_batch.script_animations;
            counters[ROR_FIELD("scoped_digest_actors")] = actor_batch.scoped_digest_actors;
            counters[ROR_FIELD("scoped_digest_protections")] = actor_batch.scoped_digest_protections;
            counters[ROR_FIELD("route_preparation_calls")] = movement_batch.route_preparation_calls;
            counters[ROR_FIELD("route_region_reads")] = movement_batch.route_region_reads;
            counters[ROR_FIELD("route_preparation_fallbacks")] = movement_batch.route_preparation_fallbacks;
            counters[ROR_FIELD("route_replans")] = movement_batch.route_replans;
            counters[ROR_FIELD("route_corners")] = movement_batch.route_corners;
            counters[ROR_FIELD("traffic_checkpoint_entries")] = movement_batch.traffic_checkpoint_entries;
            counters[ROR_FIELD("traffic_checkpoint_holds_skipped")] = movement_batch.traffic_checkpoint_holds;
            if (actor_batch.profile_stages) {
                const char *names[] = {"actor_total", "preparation", "movement", "gather_total", "gather_recovery", "gather_continue", "domain", "animation", "attack_event", "publication"};
                for (int i = 0; i < 10; ++i) {
                    counters[String(names[i]) + "_ns"] = actor_batch.stage_ns[i];
                    counters[String(names[i]) + "_calls"] = actor_batch.stage_calls[i];
                }
                const char *motion_names[] = {"setup", "route_prepare", "arrival", "script_body", "bindings", "native_body", "finish"};
                for (int i = 0; i < 7; ++i) {
                    counters[String("motion_") + motion_names[i] + "_ns"] = movement_batch.stage_ns[i];
                    counters[String("motion_") + motion_names[i] + "_calls"] = movement_batch.stage_calls[i];
                }
                const char *gather_names[] = {"motion", "adoption", "continuation", "destination", "shortening", "range_slots", "returning", "setup", "resource", "action"};
                for (int i = 0; i < 10; ++i) {
                    counters[String("gather_detail_") + gather_names[i] + "_ns"] = actor_batch.gather_ns[i];
                    counters[String("gather_detail_") + gather_names[i] + "_calls"] = actor_batch.gather_calls[i];
                }
            }
            result[ROR_FIELD("actor_pipeline")] = counters;
        }
        return result;
    };
    auto *native_journal = native_entity_journal(journal);
    const bool journal_native_active = bool(journal->get("native_active"));
    const auto publish = [&](const Dictionary &unit, int64_t id, int64_t mask) {
        if (!mask) return;
        RoRActorStageScope publication_scope(actor_batch.profile_stages, actor_batch.stage_ns[9], actor_batch.stage_calls[9]);
        // Fetch live journal containers after movement's planner callbacks.
        // Never keep a pending/history reference across a publication boundary.
        const Variant probe = journal->get(probe_name);
        const auto fallback = [&]() { RoRScriptBoundaryProfile::call(world, notify_method, unit, mask); };
        if ((probe.get_type() == Variant::OBJECT && static_cast<Object *>(probe)) || !bool(activity->get(prepared_name))) { fallback(); return; }
        if (journal_native_active) {
            if (!native_journal) { fallback(); return; }
            if (coalesced_activity) {
                // finish_tick consumes this exact journal. Duplicating the same
                // actor in pending_units adds another hash table and script pass
                // without providing another membership change. Explicit refresh
                // calls without a journal event still use pending_units.
                native_journal->mark(id, mask);
                if (mask & 4) ++coalesced_deferred_skips;
                return;
            }
            const Variant value = activity->get(deferred_name);
            if (value.get_type() != Variant::DICTIONARY || Dictionary(value).is_read_only()) { fallback(); return; }
            native_journal->mark(id, mask);
            Dictionary deferred = value;
            if ((mask & 4) && unit_ids.has(id)) deferred[id] = unit;
            return;
        }
        const Variant pv = journal->get(pending_name), vv = journal->get(versions_name), rv = journal->get(removed_name), dv = activity->get(deferred_name);
        if (pv.get_type() != Variant::DICTIONARY || vv.get_type() != Variant::DICTIONARY || rv.get_type() != Variant::DICTIONARY || dv.get_type() != Variant::DICTIONARY) { fallback(); return; }
        Dictionary pending = pv, versions = vv, removed = rv, deferred = dv;
        if (pending.is_read_only() || versions.is_read_only() || removed.is_read_only() || deferred.is_read_only()) { fallback(); return; }
        const int64_t revision = journal->get(revision_name);
        if (revision == std::numeric_limits<int64_t>::max()) { fallback(); return; }
        mask &= 255;
        const bool original_full = journal->get(full_name);
        bool full = original_full;
        if (id >= 0 && (int64_t(pending.get(id, 0)) & mask) != mask) {
            const Variant stored = versions.get(id, PackedInt64Array());
            if (stored.get_type() != Variant::PACKED_INT64_ARRAY) { fallback(); return; }
            PackedInt64Array entry = stored;
            if (!entry.is_empty() && entry.size() != 8) { fallback(); return; }
            if (entry.is_empty() && versions.size() >= 262144) {
                pending.clear(); removed.clear(); full = true;
            } else {
                if (entry.is_empty()) entry.resize(8);
                const int64_t next = revision + 1;
                for (int group = 0; group < 8; ++group) if (mask & (int64_t(1) << group)) entry.set(group, next);
                versions[id] = entry;
                if (!full) {
                    pending[id] = int64_t(pending.get(id, 0)) | mask;
                    if (pending.size() > 8192) { pending.clear(); removed.clear(); full = true; }
                }
            }
        }
        if (full != original_full) journal->set(full_name, full);
        if ((mask & 4) && unit_ids.has(id)) deferred[id] = unit;
    };
    // The lending scope includes domain callbacks; GDS gather/build/attack
    // movement joins the same prepared pass without a second object graph walk.
    struct BatchScope {
        MovementBatchContext *&slot;
        MovementBatchContext *previous;
        ~BatchScope() { slot = previous; }
    } batch_scope{active_movement_batch, active_movement_batch};
    if (common_pipeline) {
        movement_batch.publish = publish;
        active_movement_batch = &movement_batch;
    }
    while (cursor < units.size()) {
        if (units[cursor].get_type() != Variant::DICTIONARY) return finish();
        Dictionary unit = units[cursor];
        const Variant id_value = unit.get(id_key, Variant());
        if (id_value.get_type() != Variant::INT) return finish();
        const int64_t id = id_value, order = orders.get(id, id);
        if (order <= last_order) { ++cursor; continue; }
        bool checked_already = false, moved_natively = false;
        int32_t failure_reason = 18;
        const String task = unit.get(task_key, String());
        if (full_actor_pipeline) {
            const int64_t completed = advance_actor_pipeline(unit, delta, actor_batch, movement_batch);
            if (completed >= 0) {
                ++cursor; last_order = order;
                if (completed > 0) { failed = true; return finish(); }
                if (int64_t(world->get(pins_name)) != 0 || !bool(activity->get(prepared_name))) return finish();
                continue;
            }
        }
        const bool move_task = task == ROR_TEXT("move") || task == ROR_TEXT("attack_move");
        bool continued_prepared = false;
        if (common_pipeline && move_task && !unit.is_read_only() && double(unit.get(hp_key, 0.0)) > 0.0 &&
                int64_t(unit.get(retaliation_key, -1)) < 0) {
            const Dictionary parts = unit.get(parts_key, Dictionary()), conversion = parts.get(faith_key, Dictionary());
            if (!bool(conversion.get(enabled_key, false))) {
                ++attempts;
                // The same preparation precedes every domain movement stage.
                // Use the mutation API so read-model invalidation stays ordered.
                for (const char *name : {"cooldown", "work"}) {
                    const double value = unit.get(name, 0.0);
                    if (value > 0.0) RoRScriptBoundaryProfile::call(world, "set_entity_field", unit, String(name), std::max(0.0, value - delta));
                }
                const int64_t team = unit.get(team_key, 0);
                if (!planner || planner_team != team) {
                    planner_value = RoRScriptBoundaryProfile::call(knowledge, planner_method, world, team);
                    planner = planner_value.get_type() == Variant::OBJECT ? static_cast<Object *>(planner_value) : nullptr;
                    planner_team = team;
                }
                const Vector4 step = advance_move_pipeline_internal(unit, delta, planner, movement_batch);
                if (step.x >= 0.0) {
                    ++updates; ++pipeline_calls;
                    motion_updates += std::max(int64_t(0), int64_t(std::llround(step.y)));
                    candidates += std::max(int64_t(0), int64_t(std::llround(step.z)));
                    RoRScriptBoundaryProfile::call(world, "advance_entity_animation", unit, String(step.x > 0.0 ? "Move" : "Idle"), delta, false);
                    moved_natively = true;
                } else {
                    // The movement core rejects only before writes. Preparation
                    // is already complete, so resume after it exactly once.
                    movement_batch.bindings_fresh = false;
                    const Variant completed = RoRScriptBoundaryProfile::invoke(continue_prepared, "prepared_actor_continuation", unit, delta, actor_context);
                    if (completed.get_type() != Variant::BOOL || !bool(completed)) { failed = true; return finish(); }
                    continued_prepared = true;
                }
                if (!movement_batch.bindings_fresh) {
                    planner = nullptr; planner_value = Variant();
                    planner_team = std::numeric_limits<int64_t>::min();
                    bindings_fresh = false; stop_ticks.clear();
                }
                if (int64_t(world->get(pins_name)) != 0 || !bool(activity->get(prepared_name))) {
                    ++cursor; last_order = order; return finish();
                }
            }
        }
        if (!common_pipeline && double(unit.get(hp_key, 0.0)) > 0.0 && move_task) {
            ++attempts;
            checked_already = true;
            if (!bindings_fresh) {
                shared_kernel = physical->get(shared_name);
                by_unit = physical->get(by_unit_name);
                vertices = int64_t(elevation->get(nonzero_name)) > 0 ? Dictionary(elevation->get(vertices_name)) : Dictionary();
                buckets = spatial->get(buckets_name); entities = spatial->get(entities_name);
                positions = spatial->get(positions_name); radii = spatial->get(radii_name);
                cell_size = spatial->get(cell_size_name); max_radius = spatial->get(maximum_radius_name); max_clearance = spatial->get(maximum_clearance_name);
                bindings_fresh = true;
            }
            Object *kernel = shared_kernel;
            if (!kernel) {
                const Variant value = by_unit.get(id, Variant());
                if (value.get_type() == Variant::OBJECT) kernel = value;
            }
            if (!bool(unit.get(shared_key, false)) && !envelopes.has(id) && kernel) {
                const int64_t team = unit.get(team_key, 0);
                if (!planner || planner_team != team) {
                    planner_value = RoRScriptBoundaryProfile::call(knowledge, planner_method, world, team);
                    planner = planner_value.get_type() == Variant::OBJECT ? static_cast<Object *>(planner_value) : nullptr;
                    planner_team = team;
                }
                bool can_check = planner != nullptr;
                const int64_t group = unit.get(group_key, -1), stalled = unit.get(ticks_key, 0);
                int64_t stop_tick = 30;
                if (group >= 0 && stalled >= 4) {
                    if (!group_enabled) can_check = false;
                    else if (!direct_neighbors) { can_check = false; checked_already = false; --attempts; }
                    else {
                        const auto cached = stop_ticks.find(group);
                        if (cached != stop_ticks.end()) stop_tick = cached->second;
                        else {
                            const Variant group_value = groups.get(group, Variant());
                            if (group_value.get_type() != Variant::NIL) {
                                Object *formation = group_value.get_type() == Variant::OBJECT ? static_cast<Object *>(group_value) : nullptr;
                                const Variant members = formation ? formation->get(members_name) : Variant();
                                if (members.get_type() != Variant::ARRAY) can_check = false;
                                else stop_tick += std::min(int64_t(1200), Array(members).size() * int64_t(20));
                            }
                            if (can_check) stop_ticks[group] = stop_tick;
                            else { checked_already = false; --attempts; }
                        }
                        if (can_check) {
                            const double search_radius = 1.6 * double(unit[radius_key]) + 0.6 * max_radius + 1.6 * max_clearance;
                            neighbors.clear();
                            if (!spatial_unit_neighbors(unit, search_radius, Variant(), buckets, entities, positions, radii, cell_size, max_radius, neighbors)) {
                                can_check = false; checked_already = false; --attempts;
                            }
                        }
                    }
                }
                if (can_check) {
                    const Vector4 step = advance_checked_move_order_internal(unit, kernel, delta, map_size, vertices, neighbors, physical, planner, stop_tick, profile_move_fallbacks ? &failure_reason : nullptr);
                    if (step.x >= 0.0) {
                        publish(unit, id, int64_t(std::llround(step.x)));
                        ++updates; ++motion_updates;
                        candidates += std::max(int64_t(0), int64_t(std::llround(step.y)));
                        moved_natively = true;
                    }
                } else failure_reason = planner ? 16 : 17;
            } else failure_reason = bool(unit.get(shared_key, false)) ? 13 : envelopes.has(id) ? 14 : 15;
        }
        ++cursor; last_order = order;
        if (!moved_natively && !continued_prepared) {
            const bool measure = profile_move_fallbacks && (task == ROR_TEXT("move") || task == ROR_TEXT("attack_move"));
            const auto fallback_started = measure ? std::chrono::steady_clock::now() : std::chrono::steady_clock::time_point();
            movement_batch.bindings_fresh = false;
            const Variant completed = RoRScriptBoundaryProfile::invoke(fallback_actor, "fallback_actor", unit, delta, actor_context, checked_already);
            if (measure) {
                Dictionary measurement = move_fallbacks.get(failure_reason, Dictionary());
                measurement[ROR_FIELD("calls")] = int64_t(measurement.get(ROR_FIELD("calls"), 0)) + 1;
                measurement[ROR_FIELD("us")] = int64_t(measurement.get(ROR_FIELD("us"), 0)) + std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now() - fallback_started).count();
                move_fallbacks[failure_reason] = measurement;
            }
            if (completed.get_type() != Variant::BOOL || !bool(completed)) { failed = true; return finish(); }
            movement_batch.bindings_fresh = false;
            // A domain callback can change policy, terrain, group membership or
            // native snapshot bindings. Re-resolve before the next pure move.
            planner = nullptr; planner_value = Variant();
            planner_team = std::numeric_limits<int64_t>::min();
            bindings_fresh = false; stop_ticks.clear();
            if (int64_t(world->get(pins_name)) != 0 || !bool(activity->get(prepared_name))) return finish();
        }
    }
    return finish();
}

Vector4 RoRReadModelKernel::advance_native_motion(Dictionary unit, Object *movement_kernel, double delta,
        const Vector2i &map_size, const Dictionary &vertex_levels) const {
    return advance_motion_internal(unit, movement_kernel, delta, map_size, vertex_levels, nullptr, nullptr, 30);
}

Vector4 RoRReadModelKernel::advance_native_group_motion(Dictionary unit, Object *movement_kernel, double delta,
        const Vector2i &map_size, const Dictionary &vertex_levels, const Array &neighbors, Object *planner, int64_t stop_tick) const {
    return advance_motion_internal(unit, movement_kernel, delta, map_size, vertex_levels, &neighbors, planner, stop_tick);
}

Vector4 RoRReadModelKernel::advance_checked_move_order(Dictionary unit, Object *movement_kernel, double delta,
        const Vector2i &map_size, const Dictionary &vertex_levels, const Array &neighbors, Object *physical_planner,
        Object *knowledge_planner, int64_t stop_tick) const {
    return advance_checked_move_order_internal(unit, movement_kernel, delta, map_size, vertex_levels, neighbors, physical_planner, knowledge_planner, stop_tick, nullptr);
}

Vector4 RoRReadModelKernel::advance_checked_move_order_internal(Dictionary unit, Object *movement_kernel, double delta,
        const Vector2i &map_size, const Dictionary &vertex_levels, const Array &neighbors, Object *physical_planner,
        Object *knowledge_planner, int64_t stop_tick, int32_t *failure_reason) const {
    const auto failed = [&](int32_t reason) { if (failure_reason) *failure_reason = reason; return Vector4(-1, 0, 0, 0); };
    const auto checked_started = motion_profiling ? std::chrono::steady_clock::now() : std::chrono::steady_clock::time_point();
    // Synchronous owner only. Unsupported cases return before any mutation.
    static const Variant task("task"), hp("hp"), retaliation("retaliation_target_id"), parts_key("components");
    static const Variant target("target"), pos("pos"), revision("path_knowledge_revision"), path("path"), index("path_index");
    static const Variant group("formation_group_id"), ticks("stuck_ticks"), cooldown("cooldown"), work("work"), radius("footprint_radius");
    static const Variant anim("anim"), anim_state("anim_state"), events("animation_events_fired"), domain("movement_domain");
    static const StringName grid_key("grid"), grid_revision_key("revision"), region_method("change_region_since"), native_key("native_enabled"), kernel_method("_native_kernel_for");
    if (!knowledge_planner || unit.is_read_only() || delta <= 0.0 || double(unit.get(hp, 0.0)) <= 0.0 || int64_t(unit.get(retaliation, -1)) >= 0) return failed(1);
    const String order = unit.get(task, String());
    if (order != ROR_TEXT("move") && order != ROR_TEXT("attack_move")) return failed(2);
    const Dictionary parts = unit.get(parts_key, Dictionary()), conversion = parts.get(ROR_FIELD("conversion"), Dictionary());
    if (bool(conversion.get(ROR_FIELD("enabled"), false))) return failed(3);
    const Vector2 position = unit[pos], destination = unit[target];
    const double distance_squared = (destination - position).length_squared();
    if (distance_squared < 0.001225) return failed(4);
    const int64_t group_id = unit.get(group, -1), stalled = unit.get(ticks, 0);
    // Recovery callbacks and intermediate corners retain their original order.
    if (stalled == 5 || stalled == 17 || stalled == 59 || stalled == 179 || stalled == 359 || stalled == 719) return failed(5);
    const Array route = unit.get(path, Array());
    if (group_id >= 0 && distance_squared <= 4.0 && int64_t(unit.get(index, 0)) + 1 < route.size()) return failed(6);
    const Variant grid_value = knowledge_planner->get(grid_key);
    if (grid_value.get_type() != Variant::OBJECT) return failed(7);
    Object *grid = grid_value;
    if (!grid) return failed(7);
    const int64_t current_revision = grid->get(grid_revision_key), old_revision = unit.get(revision, current_revision);
    const bool refresh_revision = old_revision != current_revision && !route.is_empty();
    if (refresh_revision) {
        const Variant changed = RoRScriptBoundaryProfile::call(grid, region_method, old_revision);
        const Rect2 bounds = Rect2(position, Vector2()).expand(destination).grow(double(unit[radius]) + 1.0);
        if (changed.get_type() != Variant::RECT2 || bounds.intersects(Rect2(changed))) {
            if (!bool(knowledge_planner->get(native_key))) return failed(8);
            const Variant resolved = RoRScriptBoundaryProfile::call(knowledge_planner, kernel_method, unit[domain], unit[ROR_FIELD("terrain_restriction")]);
            const RoRPathKernel *knowledge = resolved.get_type() == Variant::OBJECT ? Object::cast_to<RoRPathKernel>(static_cast<Object *>(resolved)) : nullptr;
            if (!knowledge || !knowledge->is_configured() || knowledge->get_revision() != current_revision) return failed(9);
            const Vector2i start(int32_t(std::floor(position.x)), int32_t(std::floor(position.y))), goal(int32_t(std::floor(destination.x)), int32_t(std::floor(destination.y)));
            const double clearance = unit[radius];
            if (String(unit[domain]) == ROR_TEXT("water") && clearance > 0.0 && !knowledge->is_segment_walkable(Vector2(start) + Vector2(0.5, 0.5), Vector2(goal) + Vector2(0.5, 0.5), clearance)) return failed(10);
            if (!knowledge->has_direct_cell_path(start, goal, clearance)) return failed(11);
        }
    }
    const bool yielding = group_id >= 0 && stalled >= 4;
    Vector4 result = advance_motion_internal(unit, movement_kernel, delta, map_size, vertex_levels, yielding ? &neighbors : nullptr, yielding ? physical_planner : nullptr, stop_tick);
    if (result.x < 0.0) { if (failure_reason) *failure_reason = 12; return result; }
    int64_t mask = int64_t(std::llround(result.x));
    if (refresh_revision) { unit[revision] = current_revision; mask |= 96; }
    // These timers cannot influence the pure movement above. No read boundary
    // occurs between their original position and this single publication.
    for (const Variant *key : {&cooldown, &work}) {
        const double before = unit[*key];
        if (before > 0.0) { unit[*key] = std::max(0.0, before - delta); mask |= 68; }
    }
    const String previous = unit.get(anim_state, String());
    if (previous != ROR_TEXT("Move")) {
        unit[anim_state] = ROR_TEXT("Move"); mask |= 32;
        if (previous != ROR_TEXT("Carry")) { unit[anim] = 0.0; unit[events] = Dictionary(); }
        else unit[anim] = double(unit.get(anim, 0.0)) + std::max(0.0, delta);
    } else unit[anim] = double(unit.get(anim, 0.0)) + std::max(0.0, delta);
    result.x = real_t(mask);
    if (motion_profiling) {
        auto &measurement = motion_measurements[5];
        const int64_t elapsed = std::chrono::duration_cast<std::chrono::nanoseconds>(std::chrono::steady_clock::now() - checked_started).count();
        ++measurement.count;
        measurement.total_ns += elapsed;
        measurement.maximum_ns = std::max(measurement.maximum_ns, elapsed);
    }
    return result;
}

int64_t RoRReadModelKernel::publish_active_unit_controls(const Array &units, const Dictionary &units_by_id, Object *journal, Object *activity) const {
    // Exact owner-only bulk form of notify_entity_changed(unit, ACTIVITY|CONTROL)
    // while activity membership is deferred until finish_tick(). No callback or
    // observer can run inside this pass. Unsupported inputs precede all writes.
    if (!journal || !activity || units.size() > 65536 || !bool(activity->get("tick_prepared"))) return -1;
    const Variant probe = journal->get("performance_probe");
    if (probe.get_type() == Variant::OBJECT && static_cast<Object *>(probe)) return -1;
    if (bool(journal->get("native_active"))) {
        auto *native_journal = native_entity_journal(journal);
        const Variant value = activity->get("pending_units");
        if (!native_journal || value.get_type() != Variant::DICTIONARY || Dictionary(value).is_read_only()) return -1;
        Dictionary deferred = value;
        std::vector<std::pair<int64_t, Dictionary>> native_rows;
        native_rows.reserve(size_t(units.size()));
        for (int64_t i = 0; i < units.size(); ++i) {
            if (units[i].get_type() != Variant::DICTIONARY) return -1;
            const Dictionary unit = units[i];
            const Variant id = unit.get(ROR_FIELD("id"), int64_t(-1));
            if (id.get_type() != Variant::INT) return -1;
            native_rows.emplace_back(int64_t(id), unit);
        }
        for (const auto &row : native_rows) {
            native_journal->mark(row.first, 68);
            if (units_by_id.has(row.first)) deferred[row.first] = row.second;
        }
        return units.size();
    }
    const Variant pending_value = journal->get("_legacy_pending"), versions_value = journal->get("_legacy_versions_by_id"), removed_value = journal->get("_legacy_pending_removed"), activity_value = activity->get("pending_units");
    if (pending_value.get_type() != Variant::DICTIONARY || versions_value.get_type() != Variant::DICTIONARY || removed_value.get_type() != Variant::DICTIONARY || activity_value.get_type() != Variant::DICTIONARY) return -1;
    Dictionary pending = pending_value, versions = versions_value, removed = removed_value, deferred = activity_value;
    if (pending.is_read_only() || versions.is_read_only() || removed.is_read_only() || deferred.is_read_only()) return -1;
    std::vector<std::pair<int64_t, Dictionary>> rows;
    rows.reserve(size_t(units.size()));
    static const Variant id_key("id");
    for (int64_t i = 0; i < units.size(); ++i) {
        if (units[i].get_type() != Variant::DICTIONARY) return -1;
        const Dictionary unit = units[i];
        const Variant id = unit.get(id_key, int64_t(-1));
        if (id.get_type() != Variant::INT) return -1;
        rows.emplace_back(int64_t(id), unit);
    }
    bool full = journal->get("_legacy_pending_full");
    const int64_t next_version = int64_t(journal->get("revision")) + 1;
    constexpr int64_t mask = 68; // EntityChangeJournal.ACTIVITY | CONTROL.
    for (const auto &row : rows) {
        const int64_t id = row.first;
        if (id >= 0 && (int64_t(pending.get(id, 0)) & mask) != mask) {
            PackedInt64Array entry = versions.get(id, PackedInt64Array());
            if (entry.is_empty()) {
                if (versions.size() >= 262144) {
                    pending.clear(); removed.clear(); full = true;
                    if (units_by_id.has(id)) deferred[id] = row.second;
                    continue;
                }
                entry.resize(8);
            }
            // Normal journal records always have eight groups. A malformed
            // entry is not a supported source for this owner-only helper.
            if (entry.size() != 8) {
                journal->set("_legacy_pending_full", full);
                // Preserve completed publications, then perform the current
                // and remaining rows through the original method exactly once.
                for (size_t i = size_t(&row - rows.data()); i < rows.size(); ++i) {
                    RoRScriptBoundaryProfile::call(journal, "mark", rows[i].first, mask);
                    if (units_by_id.has(rows[i].first)) deferred[rows[i].first] = rows[i].second;
                }
                return units.size();
            }
            entry.set(2, next_version); entry.set(6, next_version); versions[id] = entry;
            if (!full) {
                pending[id] = int64_t(pending.get(id, 0)) | mask;
                if (pending.size() > 8192) { pending.clear(); removed.clear(); full = true; }
            }
        }
        if (units_by_id.has(id)) deferred[id] = row.second;
    }
    journal->set("_legacy_pending_full", full);
    return units.size();
}

Vector4 RoRReadModelKernel::advance_motion_internal(Dictionary unit, Object *movement_kernel, double delta,
        const Vector2i &map_size, const Dictionary &vertex_levels, const Array *neighbors, Object *planner, int64_t stop_tick,
        const MotionInputs *prepared) const {
    const RoRPathKernel *kernel = Object::cast_to<RoRPathKernel>(movement_kernel);
    if (!kernel || delta <= 0.0 || unit.is_read_only()) return Vector4(-1, 0, 0, 0);
    static const Variant stuck_key("stuck_ticks"), group_key("formation_group_id"), target_key("target"), position_key("pos");
    static const Variant id_key("id"), speed_key("speed"), scale_key("cohesion_speed_scale"), task_key("task");
    const int64_t stalled = prepared ? prepared->stalled : int64_t(unit[stuck_key]);
    const bool group_yield = stalled >= 4 && (prepared ? prepared->group : int64_t(unit.get(group_key, -1))) >= 0;
    if (neighbors) {
        // The caller supplies the unchanged group budget. Leave its terminal
        // stop and the gatherer's nearby-worker budget on the original path.
        if (!group_yield || stop_tick < 30 || stop_tick > 1230 || stalled >= stop_tick - 1 ||
            (stalled >= 29 && String(unit[task_key]) == ROR_TEXT("gather"))) return Vector4(-1, 0, 0, 0);
    } else if (stalled >= 29 || group_yield) return Vector4(-1, 0, 0, 0);
    const Vector2 target = prepared ? prepared->target : Vector2(unit[target_key]);
    const Vector2 position = prepared ? prepared->position : Vector2(unit[position_key]);
    auto portion_started = motion_profiling ? std::chrono::steady_clock::now() : std::chrono::steady_clock::time_point();
    const auto observe_portion = [&](int index) {
        if (!motion_profiling) return;
        const auto now = std::chrono::steady_clock::now();
        const int64_t elapsed = std::chrono::duration_cast<std::chrono::nanoseconds>(now - portion_started).count();
        auto &measurement = motion_measurements[index];
        ++measurement.count;
        measurement.total_ns += elapsed;
        measurement.maximum_ns = std::max(measurement.maximum_ns, elapsed);
        portion_started = now;
    };
    const double base_speed = unit[speed_key], cohesion = unit[scale_key];
    const Vector4 motion = kernel->calculate_movement(prepared ? prepared->id : int64_t(unit[id_key]), target, base_speed, cohesion, delta);
    observe_portion(0);
    const int state = int(std::llround(motion.z));
    if (state < 0 || state == 2) return Vector4(-1, 0, 0, 0);
    Vector3 yielding;
    if (group_yield) {
        // This helper reads position/radius/speed and the supplied neighbors,
        // not this unit's desired/actual velocity. Resolve before writing so
        // an unsupported planner/watch still falls back without partial edits.
        yielding = formation_yield_velocity(unit, *neighbors, delta, planner);
        observe_portion(1);
        if (yielding.z < 0.0) return Vector4(-1, 0, 0, 0);
    }
    const Vector2 difference = target - position;
    const double speed = std::max(0.0, group_yield ? double(unit[speed_key]) * double(unit[scale_key]) : base_speed * cohesion);
    const Vector2 desired = difference.length_squared() > 0.000001 ? difference.normalized() * speed : Vector2();
    if (active_movement_batch && active_movement_batch->typed_motion) {
        RoRActorMotionFrame frame;
        if (active_movement_batch->borrowed_motion_fields ? frame.load_borrowed(unit, position, target) : frame.load(unit, position, target)) {
            if (active_movement_batch->borrowed_motion_fields) ++borrowed_motion_field_updates;
            Dictionary reference;
            const bool compare = active_movement_batch->compare_typed_motion && typed_motion_comparisons < 256 &&
                (typed_motion_comparisons < 16 || typed_motion_updates % 1024 == 0);
            if (compare) {
                reference = unit.duplicate(false);
                if (unit.has(ROR_FIELD("navigation_progress"))) reference[ROR_FIELD("navigation_progress")] = Dictionary(unit[ROR_FIELD("navigation_progress")]).duplicate(true);
            }
            frame.set_velocities(desired, Vector2(motion.x, motion.y));
            if (yielding.z > 0.0) frame.set_velocities(desired, Vector2(yielding.x, yielding.y));
            observe_portion(2);
            const String reason = state == 1 ? ROR_TEXT("local_obstacle") : String();
            frame.integrate(delta, map_size, vertex_levels, reason);
            observe_portion(3);
            const String recovery = yielding.z > 0.0 ? String() : frame.advance_progress(stop_tick);
            frame.commit(unit);
            observe_portion(4);
            ++typed_motion_updates;
            if (compare) {
                int64_t expected_mask = set_motion_velocities(reference, desired, Vector2(motion.x, motion.y));
                if (yielding.z > 0.0) expected_mask |= set_motion_velocities(reference, desired, Vector2(yielding.x, yielding.y));
                expected_mask |= integrate_unit_motion(reference, delta, map_size, vertex_levels, reason);
                const String expected_recovery = yielding.z > 0.0 ? String() : update_route_progress(reference, stop_tick);
                ++typed_motion_comparisons;
                if (expected_mask != frame.mask || expected_recovery != recovery || reference != unit) {
                    ++typed_motion_mismatches;
                    UtilityFunctions::push_error("Typed actor motion differs from the canonical motion stages");
                }
            }
            const int route_action = recovery == ROR_TEXT("local_repath") ? 1 : recovery == ROR_TEXT("global_repath") ? 2 : 0;
            return Vector4(real_t(frame.mask), motion.w, real_t(state | (yielding.z > 0.0 ? 4 : 0)), real_t(route_action));
        }
        ++typed_motion_rejections;
    }
    int64_t mask = set_motion_velocities(unit, desired, Vector2(motion.x, motion.y));
    if (yielding.z > 0.0) mask |= set_motion_velocities(unit, desired, Vector2(yielding.x, yielding.y));
    observe_portion(2);
    mask |= integrate_unit_motion(unit, delta, map_size, vertex_levels, state == 1 ? ROR_TEXT("local_obstacle") : String());
    observe_portion(3);
    const String recovery = yielding.z > 0.0 ? String() : update_route_progress(unit, stop_tick);
    observe_portion(4);
    const int route_action = recovery == ROR_TEXT("local_repath") ? 1 : recovery == ROR_TEXT("global_repath") ? 2 : 0;
    return Vector4(real_t(mask), motion.w, real_t(state | (yielding.z > 0.0 ? 4 : 0)), real_t(route_action));
}

int64_t RoRReadModelKernel::set_motion_velocities(Dictionary unit, const Vector2 &desired, const Vector2 &actual) const {
    // The ordered owner publishes this union with integrate_unit_motion before
    // the next actor. Intermediate collision queries see the same velocities.
    static const Variant desired_key("desired_velocity"), actual_key("actual_velocity");
    int64_t mask = 0;
    const Variant previous_desired = unit.get(desired_key, Variant());
    if (previous_desired.get_type() != Variant::VECTOR2 || Vector2(previous_desired) != desired) {
        unit[desired_key] = desired;
        mask |= 96; // APPEARANCE | CONTROL, matching field_mask.
    }
    const Variant previous_actual = unit.get(actual_key, Variant());
    if (previous_actual.get_type() != Variant::VECTOR2 || Vector2(previous_actual) != actual) {
        unit[actual_key] = actual;
        mask |= 70; // POSITION | ACTIVITY | CONTROL.
    }
    return mask;
}

String RoRReadModelKernel::update_route_progress(Dictionary unit, int64_t stop_tick) const {
    // The same escalation state as StuckRecovery, owned by the ordered unit
    // loop. No new cache, task scheduling or journal boundary is introduced.
    static const Variant destination("destination"), target("target"), pos("pos"), components("components"), order("order"), revision_key("revision");
    static const Variant progress("navigation_progress"), goal_key("goal"), leg_key("leg"), best("best"), order_revision("order_revision");
    static const Variant ticks("stuck_ticks"), base_priority("base_push_priority"), priority("push_priority"), diagnostic("diagnostic_reason");
    const Vector2 goal = unit.get(destination, unit[target]), leg = unit[target], position = unit[pos];
    const Dictionary component_state = unit.get(components, Dictionary());
    const Dictionary order_state = component_state.get(order, Dictionary());
    const int64_t revision = order_state.get(revision_key, 0);
    const double distance = position.distance_to(leg);
    Dictionary watch = unit.get(progress, Dictionary());
    if (watch.is_empty() || (revision == 0 && double(Vector2(watch[goal_key]).distance_squared_to(goal)) > 0.01) || int64_t(watch[order_revision]) != revision) {
        unit.erase(progress);
        if (int64_t(unit[ticks]) != 0) unit[ticks] = int64_t(0);
        if (int64_t(unit[priority]) != int64_t(unit[base_priority])) unit[priority] = int64_t(unit[base_priority]);
        watch = Dictionary();
        watch[goal_key] = goal;
        watch[leg_key] = leg;
        watch[best] = distance;
        watch[order_revision] = revision;
        unit[progress] = watch;
        return String();
    }
    double squared_progress = 0.0;
    if (double(Vector2(watch[leg_key]).distance_squared_to(leg)) > 0.0001) {
        const double forward = double(watch[best]) - double(position.distance_to(Vector2(watch[leg_key])));
        watch[leg_key] = leg;
        watch[best] = distance;
        if (forward >= 0.015) squared_progress = forward * forward;
    } else {
        const double improvement = double(watch[best]) - distance;
        if (improvement >= 0.015) {
            watch[best] = distance;
            squared_progress = improvement * improvement;
        }
    }
    if (squared_progress > 0.000001) {
        if (int64_t(unit[ticks]) != 0) unit[ticks] = int64_t(0);
        if (int64_t(unit[priority]) != int64_t(unit[base_priority])) unit[priority] = int64_t(unit[base_priority]);
        const String reason = unit[diagnostic];
        if (!reason.is_empty() && reason.begins_with(ROR_TEXT("stuck_"))) unit[diagnostic] = String();
        return String();
    }
    const int64_t stuck = int64_t(unit[ticks]) + 1;
    unit[ticks] = stuck;
    if (stuck == 6) { unit[diagnostic] = ROR_TEXT("stuck_local_repath"); return "local_repath"; }
    if (stuck == 12) {
        unit[priority] = int64_t(unit[base_priority]) + 2;
        unit[diagnostic] = ROR_TEXT("stuck_priority_boost");
        return "priority_boost";
    }
    if (stuck == 18) { unit[diagnostic] = ROR_TEXT("stuck_global_repath"); return "global_repath"; }
    if (stuck >= std::max(int64_t(30), stop_tick)) { unit[diagnostic] = ROR_TEXT("stuck_stopped_nearest_valid"); return "stop"; }
    return String();
}

Vector2 RoRReadModelKernel::constrain_mobile_velocity(const Dictionary &unit, const Vector2 &requested, const Array &neighbors, double delta) const {
    // Pure owner-thread counterpart of MobileCollision.constrain. Retain the
    // supplied neighbor order and its previous-position collision generation.
    if (delta <= 0.0) return requested;
    static const Variant pos("pos"), previous_pos("previous_pos"), hp("hp"), footprint("footprint_radius");
    const Vector2 origin = unit[pos];
    const double own_radius = unit[footprint];
    const auto crosses = [](const Vector2 &gap, const Vector2 &step, double radius) {
        const double step_squared = step.length_squared();
        if (step_squared <= 0.000001) return false;
        if (double(gap.length_squared()) < radius * radius) return double(gap.dot(step)) < -0.000001;
        const double fraction = std::clamp(-double(gap.dot(step)) / step_squared, 0.0, 1.0);
        return double((gap + step * real_t(fraction)).length_squared()) < radius * radius - 0.000001;
    };
    Vector2 velocity = requested;
    for (int64_t i = 0; i < neighbors.size(); ++i) {
        const Dictionary other = neighbors[i];
        if (double(other.get(hp, 0.0)) <= 0.0) continue;
        const Vector2 center = other.get(previous_pos, other[pos]);
        const Vector2 gap = origin - center;
        const double radius = own_radius + double(other[footprint]) + 0.03;
        if (!crosses(gap, velocity * real_t(delta), radius)) continue;
        const Vector2 normal = gap.normalized();
        velocity -= normal * real_t(std::min(0.0, double(velocity.dot(normal))));
        if (crosses(gap, velocity * real_t(delta), radius)) velocity = Vector2();
    }
    if (velocity.is_equal_approx(requested)) return velocity;
    for (int64_t i = 0; i < neighbors.size(); ++i) {
        const Dictionary other = neighbors[i];
        if (double(other.get(hp, 0.0)) <= 0.0) continue;
        const Vector2 gap = origin - Vector2(other.get(previous_pos, other[pos]));
        const double radius = own_radius + double(other[footprint]) + 0.03;
        if (crosses(gap, velocity * real_t(delta), radius)) return Vector2();
    }
    return velocity;
}

Vector3 RoRReadModelKernel::formation_yield_velocity(Dictionary unit, const Array &neighbors, double delta, Object *planner) const {
    static const Variant group("formation_group_id"), id("id"), ticks("stuck_ticks"), pos("pos"), destination("destination");
    static const Variant progress("navigation_progress"), yield_ticks("formation_yield_ticks"), speed_key("speed"), scale("cohesion_speed_scale");
    static const Variant radius("footprint_radius"), domain("movement_domain"), restriction("terrain_restriction");
    static const StringName resolve("_native_kernel_for");
    if (delta <= 0.0 || unit.is_read_only()) return Vector3(0, 0, -1);
    const int64_t own_group = unit[group], own_id = unit[id];
    const Vector2 position = unit[pos];
    bool blocked = false;
    for (int64_t i = 0; i < neighbors.size(); ++i) {
        if (neighbors[i].get_type() != Variant::DICTIONARY) return Vector3(0, 0, -1);
        const Dictionary other = neighbors[i];
        if (int64_t(other[group]) != own_group || int64_t(other[id]) >= own_id || int64_t(other[ticks]) < 4) continue;
        if (Vector2(other[pos]).distance_to(position) > 1.5) continue;
        blocked = true;
    }
    if (!blocked) return Vector3();
    Dictionary watch = unit.get(progress, Dictionary());
    if (watch.is_empty() || int64_t(watch.get(yield_ticks, 0)) >= 1200) return Vector3();
    if (watch.is_read_only() || !planner || !planner->has_method(resolve)) return Vector3(0, 0, -1);
    // Resolve the same authoritative terrain kernel only when yielding is
    // needed. Most calls return above without crossing into the planner.
    const Variant resolved = RoRScriptBoundaryProfile::call(planner, resolve, unit[domain], unit[restriction]);
    const RoRPathKernel *kernel = resolved.get_type() == Variant::OBJECT ? Object::cast_to<RoRPathKernel>(static_cast<Object *>(resolved)) : nullptr;
    if (!kernel || !kernel->is_configured()) return Vector3(0, 0, -1);
    const Vector2 backwards = (position - Vector2(unit[destination])).normalized();
    const double speed = double(unit[speed_key]) * double(unit[scale]);
    constexpr double pi = 3.1415926535897932384626433832795;
    for (double angle : {0.0, pi / 4.0, -pi / 4.0, pi / 2.0, -pi / 2.0}) {
        const Vector2 requested = backwards.rotated(real_t(angle)) * speed;
        const Vector2 velocity = constrain_mobile_velocity(unit, requested, neighbors, delta);
        if (velocity.length_squared() < speed * speed * 0.1) continue;
        if (kernel->is_segment_walkable(position, position + velocity * delta, double(unit[radius]))) {
            watch[yield_ticks] = int64_t(watch.get(yield_ticks, 0)) + 1;
            return Vector3(velocity.x, velocity.y, 1);
        }
    }
    return Vector3();
}

int64_t RoRReadModelKernel::integrate_unit_motion(Dictionary unit, double delta, const Vector2i &map_size,
        const Dictionary &vertex_levels, const String &reason) const {
    // Owner-thread only. None of these fields changes task/combat eligibility.
    // Publish the union once after all writes, before the next entity is updated.
    static const Variant pos("pos"), target("target"), velocity("actual_velocity"), desired("desired_velocity");
    static const Variant desired_facing("desired_facing"), movement_facing("movement_facing"), facing("facing"), height("elevation"), diagnostic("diagnostic_reason");
    int64_t mask = 0;
    const auto put = [&](const Variant &key, const Variant &value, int64_t changed) {
        const Variant previous = unit.get(key, Variant());
        if (previous.get_type() != value.get_type() || previous != value) {
            unit[key] = value;
            mask |= changed;
        }
    };
    const auto direction_facing = [](const Vector2 &direction) -> int64_t {
        const Vector2 screen((direction.x - direction.y) * 32.0, (direction.x + direction.y) * 16.0);
        if (screen.length_squared() <= 0.0001) return 0;
        return (int64_t(std::round(std::atan2(-double(screen.x), double(screen.y)) / (6.283185307179586476925286766559 / 8.0))) % 8 + 8) % 8;
    };
    const Vector2 intended = unit[desired];
    if (intended.length_squared() > 0.000001) put(desired_facing, direction_facing(intended), 96);
    if (!reason.is_empty()) put(diagnostic, reason, 96);
    const Vector2 start = unit[pos], destination = unit[target], difference = destination - start;
    const Vector2 step = Vector2(unit[velocity]) * delta;
    Vector2 position = step.length_squared() >= difference.length_squared() && step.dot(difference) > 0.0 ? destination : start + step;
    put(pos, position, 2);
    if (position.x < 0.5 || position.y < 0.5 || position.x > double(map_size.x) - 0.5 || position.y > double(map_size.y) - 0.5) {
        position = Vector2(std::max(0.5, std::min(double(position.x), double(map_size.x) - 0.5)),
                std::max(0.5, std::min(double(position.y), double(map_size.y) - 0.5)));
    }
    put(pos, position, 2);
    if (!vertex_levels.is_empty()) {
        put(height, terrain_height_at(position, map_size, vertex_levels), 96);
    } else if (double(unit[height]) != 0.0) put(height, 0.0, 96);
    const Vector2 displacement = position - start;
    put(velocity, delta > 0.0 ? displacement / delta : Vector2(), 70);
    if (displacement.length_squared() > 0.000001) {
        const int64_t direction = direction_facing(displacement);
        put(movement_facing, direction, 96);
        put(facing, direction, 2);
    }
    return mask;
}

Dictionary RoRReadModelKernel::owned_ai_actor_profile(const Dictionary &entity) const {
    static const Variant components("components"), combat_key("combat"), cargo_key("cargo"), enabled("enabled");
    static const Variant attacks("attacks"), armors("armors"), armor("base_armor"), damage("attack_damage");
    static const Variant period("attack_period"), range("attack_range"), speed("speed"), max_hp("max_hp"), combat_enabled("combat_enabled");
    static const Variant carried("carried_amount"), resource_type("carried_resource_type_id"), stage("gather_stage");
    // Only normalized owned runtime records qualify. Incomplete compatibility
    // fixtures and foreign estimates retain the source-catalog reference path.
    for (const Variant *key : {&damage, &period, &range, &speed, &max_hp, &combat_enabled})
        if (!entity.has(*key)) return Dictionary();
    const Dictionary parts = entity.get(components, Dictionary()), combat = parts.get(combat_key, Dictionary());
    if (!combat.has(attacks) || !combat.has(armors) || !combat.has(armor) ||
            combat[attacks].get_type() != Variant::ARRAY || combat[armors].get_type() != Variant::ARRAY) return Dictionary();
    const Dictionary cargo = parts.get(cargo_key, Dictionary());
    Dictionary result;
    result[attacks] = Array(combat[attacks]).duplicate(true);
    result[armors] = Array(combat[armors]).duplicate(true);
    result[armor] = double(combat[armor]);
    result[ROR_FIELD("damage")] = double(entity[damage]); result[ROR_FIELD("period")] = double(entity[period]);
    result[ROR_FIELD("range")] = double(entity[range]); result[speed] = double(entity[speed]);
    result[max_hp] = double(entity[max_hp]); result[enabled] = bool(entity[combat_enabled]);
    result[ROR_FIELD("transport")] = bool(cargo.get(enabled, false));
    result[carried] = double(entity.get(carried, 0.0));
    result[resource_type] = int64_t(entity.get(resource_type, -1));
    result[stage] = String(entity.get(stage, ROR_FIELD("")));
    return result;
}

Dictionary RoRReadModelKernel::partition_render_items(const Array &items) const {
    static const Variant kind("kind"), data("data"), domain("movement_domain"), presentation("presentation_layer");
    Array statics, moving, ambient, interpolating;
    static const Variant pos("pos"), previous("previous_pos");
    for (int64_t i = 0; i < items.size(); ++i) {
        const Dictionary item = items[i];
        const String type = item[kind];
        const Dictionary entity = item.get(data, Dictionary());
        const bool dynamic = type == ROR_TEXT("projectile") ||
                ((type == ROR_TEXT("unit") || type == ROR_TEXT("unit_part") || type == ROR_TEXT("shadow") || type == ROR_TEXT("selection") || type == ROR_TEXT("health_bar")) && String(entity.get(domain, ROR_FIELD("land"))) != ROR_TEXT("static")) ||
                (type == ROR_TEXT("environment") && String(entity.get(presentation, ROR_FIELD("scenery"))) == ROR_TEXT("ambient_actor"));
        if (dynamic) {
            moving.append(item);
            // Only immutable unit poses qualify. Live compatibility records,
            // projectiles and ambient actors keep their existing refresh path.
            const bool unit_item = type == ROR_TEXT("unit") || type == ROR_TEXT("unit_part") || type == ROR_TEXT("shadow") || type == ROR_TEXT("selection") || type == ROR_TEXT("health_bar");
            const bool stationary = unit_item && entity.is_read_only() && entity.has(pos) && entity.has(previous) &&
                    entity[pos].get_type() == Variant::VECTOR2 && entity[previous].get_type() == Variant::VECTOR2 &&
                    Vector2(entity[pos]) == Vector2(entity[previous]);
            if (!stationary) interpolating.append(item);
        } else statics.append(item);
        if (type == ROR_TEXT("environment") && dynamic) ambient.append(item);
    }
    Dictionary result; result[ROR_FIELD("static")] = statics; result[ROR_FIELD("moving")] = moving; result[ROR_FIELD("ambient")] = ambient; result[ROR_FIELD("interpolating")] = interpolating; return result;
}

// Submit one ordered queue. Complex geometry uses the existing CanvasItem
// handler in place, while the shared frame context is decoded only once.
PackedInt64Array RoRReadModelKernel::submit_world_queue(const RID &canvas, const Array &items,
        const Array &context, const Callable &fallback) const {
    PackedInt64Array result;
    // selected, preview, hover, feedback, feedback_time, semantic, zoom, shift,
    // local team, nearest sprite batching. This small context is per frame.
    if (!fallback.is_valid() || (context.size() != 10 && context.size() != 11) ||
            context[0].get_type() != Variant::ARRAY || context[1].get_type() != Variant::DICTIONARY ||
            context[2].get_type() != Variant::INT || context[3].get_type() != Variant::INT ||
            (context[4].get_type() != Variant::FLOAT && context[4].get_type() != Variant::INT) ||
            context[5].get_type() != Variant::STRING ||
            (context[6].get_type() != Variant::FLOAT && context[6].get_type() != Variant::INT) ||
            context[7].get_type() != Variant::BOOL || context[8].get_type() != Variant::INT ||
            context[9].get_type() != Variant::BOOL) return result;
    const double zoom = context[6], feedback_time = context[4];
    if (!std::isfinite(zoom) || zoom <= 0.0 || !std::isfinite(feedback_time)) return result;
    const Array selected = context[0];
    const Dictionary preview = context[1];
    const int64_t hover = context[2], feedback = context[3], team = context[8];
    const String semantic = context[5];
    const bool shift_pressed = context[7], batch_nearest = context[9];
    RenderingServer *server = RenderingServer::get_singleton();
    static const Variant kind_key("kind"), command_key("sprite_command"), data_key("data"), screen_key("screen_position");
    static const Variant radius_key("footprint_radius"), hotspot_key("hotspot"), hp_key("hp"), maximum_key("max_hp"), team_key("team");
    static const Color shadow_color(0.0, 0.0, 0.0, 0.28), meter_background(0.02, 0.04, 0.03, 0.95);
    static const Color own_meter = Color::html("21dc4b"), other_meter = Color::html("e44339");
    auto snapped = [](const Vector2 &v) { return Vector2(real_t(UtilityFunctions::roundf(double(v.x))), real_t(UtilityFunctions::roundf(double(v.y)))); };
    auto submit_shore = [&](const Dictionary &item) {
        if (context.size() != 11 || context[10].get_type() != Variant::DICTIONARY) return false;
        const Variant info = item.get(ROR_FIELD("frame_info"), Variant());
        if (info.get_type() != Variant::DICTIONARY) return false;
        const Variant value = Dictionary(info).get(ROR_FIELD("shore_draw_commands"), Variant());
        if (value.get_type() != Variant::ARRAY || item.get(screen_key, Variant()).get_type() != Variant::VECTOR2) return false;
        const Array commands = value;
        Dictionary retained = context[10];
        if (retained.is_read_only() || commands.size() > 2) return false;
        for (int i = 0; i < commands.size(); ++i) {
            if (commands[i].get_type() != Variant::ARRAY) return false;
            const Array part = commands[i];
            if (part.size() != 4 || part[0].get_type() != Variant::INT || part[1].get_type() != Variant::OBJECT ||
                    part[2].get_type() != Variant::RID || part[3].get_type() != Variant::RID) return false;
        }
        const Transform2D transform(0, Vector2(zoom, zoom), 0, Vector2(item[screen_key]));
        const Color tint(1, 1, 1, real_t(double(item.get(ROR_FIELD("opacity"), 1.0))));
        for (int i = 0; i < commands.size(); ++i) {
            const Array part = commands[i];
            retained[part[0]] = part[1];
            server->canvas_item_add_mesh(canvas, part[2], transform, tint, part[3]);
            ++prepared_shore_draws;
        }
        return true;
    };
    auto submit_healthbars = [&](int64_t first) -> int64_t {
        // Only combine adjacent health bars. Their background/fill primitive
        // order stays unchanged, including where two bars overlap.
        if (first + 1 >= items.size() || items[first + 1].get_type() != Variant::DICTIONARY ||
                Dictionary(items[first + 1]).get(kind_key, Variant()) != ROR_TEXT("health_bar")) return first;
        struct Bar { Rect2 background, fill; Color color; };
        std::vector<Bar> bars;
        bars.reserve(128);
        int64_t finish = first;
        while (finish < items.size() && bars.size() < 512) {
            if (items[finish].get_type() != Variant::DICTIONARY) break;
            const Dictionary item = items[finish];
            if (item.has(command_key) || item.get(kind_key, Variant()) != ROR_TEXT("health_bar")) break;
            const Variant data_value = item.get(data_key, Variant()), screen_value = item.get(screen_key, Variant());
            if (data_value.get_type() != Variant::DICTIONARY || screen_value.get_type() != Variant::VECTOR2) break;
            const Dictionary data = data_value;
            const Variant hp_value = data.get(hp_key, Variant()), maximum_value = data.get(maximum_key, Variant());
            const Variant hotspot_value = item.get(hotspot_key, Variant()), team_value = data.get(team_key, Variant());
            if ((hp_value.get_type() != Variant::FLOAT && hp_value.get_type() != Variant::INT) ||
                    (maximum_value.get_type() != Variant::FLOAT && maximum_value.get_type() != Variant::INT) ||
                    hotspot_value.get_type() != Variant::VECTOR2 || team_value.get_type() != Variant::INT) break;
            const double hp = hp_value, maximum = maximum_value;
            const Vector2 point = screen_value, hotspot = hotspot_value;
            if (!std::isfinite(hp) || !std::isfinite(maximum) || !std::isfinite(point.x) || !std::isfinite(point.y) ||
                    !std::isfinite(hotspot.x) || !std::isfinite(hotspot.y)) break;
            const Vector2 screen = snapped(point);
            const double ratio = std::max(0.0, std::min(1.0, hp / std::max(1.0, maximum)));
            const double width = 25.0 * zoom, height = std::max(3.0, 3.0 * zoom);
            const Vector2 bar = snapped(Vector2(real_t(double(screen.x) - width * 0.5), real_t(double(screen.y) - double(hotspot.y) * zoom - 5.0)));
            bars.push_back({Rect2(bar, Vector2(real_t(width), real_t(height))).abs(),
                Rect2(bar + Vector2(1, 1), Vector2(real_t(std::max(0.0, (width - 2.0) * ratio)), real_t(std::max(1.0, height - 2.0)))).abs(),
                int64_t(team_value) == team ? own_meter : other_meter});
            ++finish;
        }
        if (bars.size() < 2) return first;
        // Admission ends before the first canvas command; an unsupported row
        // is handled at its original queue position by the existing fallback.
        PackedVector2Array points;
        PackedColorArray colors;
        PackedInt32Array indices;
        points.resize(bars.size() * 8); colors.resize(bars.size() * 8); indices.resize(bars.size() * 12);
        Vector2 *p = points.ptrw(); Color *c = colors.ptrw(); int32_t *idx = indices.ptrw();
        const int32_t order[] = {0, 1, 2, 0, 2, 3};
        for (size_t i = 0; i < bars.size(); ++i) {
            for (int quad = 0; quad < 2; ++quad) {
                const Rect2 &rectangle = quad == 0 ? bars[i].background : bars[i].fill;
                const Color color = quad == 0 ? meter_background : bars[i].color;
                const int32_t base = int32_t(i * 8 + quad * 4);
                p[base] = rectangle.position;
                p[base + 1] = rectangle.position + Vector2(rectangle.size.x, 0);
                p[base + 2] = rectangle.get_end();
                p[base + 3] = rectangle.position + Vector2(0, rectangle.size.y);
                for (int j = 0; j < 4; ++j) c[base + j] = color;
                for (int j = 0; j < 6; ++j) idx[i * 12 + quad * 6 + j] = base + order[j];
            }
        }
        server->canvas_item_add_triangle_array(canvas, indices, points, colors, PackedVector2Array(), PackedInt32Array(), PackedFloat32Array(), RID());
        ++healthbar_batch_calls; healthbar_batch_items += int64_t(bars.size());
        return finish;
    };
    auto submit_shape = [&](const Dictionary &item, const String &kind) -> bool {
        if (kind != ROR_TEXT("shadow") && kind != ROR_TEXT("health_bar")) return false;
        const Variant data_value = item.get(data_key, Variant()), screen_value = item.get(screen_key, Variant());
        if (data_value.get_type() != Variant::DICTIONARY || screen_value.get_type() != Variant::VECTOR2) return false;
        const Dictionary data = data_value;
        const Vector2 point = screen_value;
        if (!std::isfinite(point.x) || !std::isfinite(point.y)) return false;
        const Vector2 screen = snapped(point);
        if (kind == ROR_TEXT("shadow")) {
            const Variant radius_value = data.get(radius_key, 0.3);
            if (radius_value.get_type() != Variant::FLOAT && radius_value.get_type() != Variant::INT) return false;
            const double radius = radius_value;
            if (!std::isfinite(radius)) return false;
            const float draw_radius = float(std::max(0.2, radius) * 34.0 * zoom);
            if (submit_cached_shadow(canvas, screen, draw_radius, shadow_color)) return true;
            // Godot 4.7.2 draw_circle(filled) delegates to the filled ellipse.
            server->canvas_item_add_set_transform(canvas, Transform2D(0.0, Vector2(1.0, 0.42), 0.0, screen));
            server->canvas_item_add_ellipse(canvas, Vector2(), draw_radius, draw_radius, shadow_color, false);
            server->canvas_item_add_set_transform(canvas, Transform2D(0.0, Vector2(1.0, 1.0), 0.0, Vector2()));
        } else {
            const Variant hp_value = data.get(hp_key, Variant()), maximum_value = data.get(maximum_key, Variant());
            const Variant hotspot_value = item.get(hotspot_key, Variant()), team_value = data.get(team_key, Variant());
            if ((hp_value.get_type() != Variant::FLOAT && hp_value.get_type() != Variant::INT) ||
                    (maximum_value.get_type() != Variant::FLOAT && maximum_value.get_type() != Variant::INT) ||
                    hotspot_value.get_type() != Variant::VECTOR2 || team_value.get_type() != Variant::INT) return false;
            const double hp = hp_value, maximum = maximum_value;
            const Vector2 hotspot = hotspot_value;
            if (!std::isfinite(hp) || !std::isfinite(maximum) || !std::isfinite(hotspot.x) || !std::isfinite(hotspot.y)) return false;
            const double ratio = std::max(0.0, std::min(1.0, hp / std::max(1.0, maximum)));
            const double width = 25.0 * zoom, height = std::max(3.0, 3.0 * zoom);
            const Vector2 bar = snapped(Vector2(real_t(double(screen.x) - width * 0.5), real_t(double(screen.y) - double(hotspot.y) * zoom - 5.0)));
            server->canvas_item_add_rect(canvas, Rect2(bar, Vector2(real_t(width), real_t(height))).abs(), meter_background, false);
            server->canvas_item_add_rect(canvas, Rect2(bar + Vector2(1, 1), Vector2(real_t(std::max(0.0, (width - 2.0) * ratio)), real_t(std::max(1.0, height - 2.0)))).abs(), int64_t(team_value) == team ? own_meter : other_meter, false);
        }
        return true;
    };
    int64_t index = 0, native_items = 0, fallback_items = 0;
    while (index < items.size()) {
        if (items[index].get_type() != Variant::DICTIONARY) break;
        const Dictionary item = items[index];
        int64_t next = index;
        if (item.has(command_key)) {
            next = batch_nearest ? submit_sprite_batches(canvas, items, index) : submit_sprite_run(canvas, items, index);
        } else {
            const String kind = item.get(kind_key, String());
            if (kind == ROR_TEXT("selection")) next = submit_selection_run(canvas, items, index, selected, preview, hover, feedback, feedback_time, semantic, zoom, shift_pressed);
            else if (kind == ROR_TEXT("environment") && submit_shore(item)) next = index + 1;
            else {
                if (kind == ROR_TEXT("health_bar")) next = submit_healthbars(index);
                if (next == index && submit_shape(item, kind)) next = index + 1;
            }
        }
        if (next > index) {
            native_items += next - index;
            index = next;
            continue;
        }
        // Keep complex geometry on its original handler at this exact point.
        // No command is replayed or moved across the callback.
        fallback.call(item);
        ++fallback_items;
        ++index;
    }
    result.resize(3);
    result.set(0, index); result.set(1, native_items); result.set(2, fallback_items);
    return result;
}

Dictionary RoRReadModelKernel::control_batch_stats() const {
    Dictionary result;
    result["shadow_meshes"] = int64_t(shadow_meshes.size());
    result["shadow_mesh_draws"] = shadow_mesh_draws;
    result["prepared_shore_draws"] = prepared_shore_draws;
    result["healthbar_batches"] = healthbar_batch_calls;
    result["healthbar_items"] = healthbar_batch_items;
    result["replaced_rect_commands"] = healthbar_batch_items * 2;
    return result;
}

int64_t RoRReadModelKernel::submit_sprite_run(const RID &canvas, const Array &items, int64_t start) const {
    RenderingServer *server = RenderingServer::get_singleton();
    while (start < items.size()) {
        const Dictionary item = items[start];
        if (!item.has(ROR_FIELD("sprite_command"))) break;
        const Array sprite = item[ROR_FIELD("sprite_command")];
        if (sprite.size() < 5) break;
        server->canvas_item_add_texture_rect_region(canvas, sprite[1], sprite[3], sprite[4], sprite[2], false, true);
        ++start;
    }
    return start;
}

int64_t RoRReadModelKernel::submit_sprite_batches(const RID &canvas, const Array &items, int64_t start) const {
    RenderingServer *server = RenderingServer::get_singleton();
    static const Variant command("sprite_command");
    while (start < items.size()) {
        const Dictionary item = items[start];
        if (!item.has(command)) break;
        const Array sprite = item[command];
        if (sprite.size() < 5) break;
        if (sprite.size() >= 6) {
            // Only adjacent quads with the same texture are combined. Primitive
            // order, per-sprite opacity and the existing depth order stay intact.
            struct Quad { Rect2 destination, uv; Color color; };
            std::vector<Quad> quads;
            const RID texture = sprite[3];
            int64_t finish = start;
            while (finish < items.size() && quads.size() < 512) {
                const Dictionary next = items[finish];
                if (!next.has(command)) break;
                const Array value = next[command];
                if (value.size() < 6 || RID(value[3]) != texture) break;
                quads.push_back({Rect2(value[1]), Rect2(value[5]), Color(value[2])});
                ++finish;
            }
            if (quads.size() >= 4) {
                PackedVector2Array points, uvs;
                PackedColorArray colors;
                PackedInt32Array indices;
                points.resize(quads.size() * 4); uvs.resize(quads.size() * 4);
                colors.resize(quads.size() * 4); indices.resize(quads.size() * 6);
                Vector2 *p = points.ptrw(), *uv = uvs.ptrw();
                Color *c = colors.ptrw(); int32_t *index = indices.ptrw();
                for (size_t i = 0; i < quads.size(); ++i) {
                    const Quad &q = quads[i]; const int32_t base = int32_t(i * 4);
                    p[base] = q.destination.position;
                    p[base + 1] = q.destination.position + Vector2(q.destination.size.x, 0);
                    p[base + 2] = q.destination.get_end();
                    p[base + 3] = q.destination.position + Vector2(0, q.destination.size.y);
                    uv[base] = q.uv.position;
                    uv[base + 1] = q.uv.position + Vector2(q.uv.size.x, 0);
                    uv[base + 2] = q.uv.get_end();
                    uv[base + 3] = q.uv.position + Vector2(0, q.uv.size.y);
                    for (int j = 0; j < 4; ++j) c[base + j] = q.color;
                    const int32_t order[] = {0, 1, 2, 0, 2, 3};
                    for (int j = 0; j < 6; ++j) index[i * 6 + j] = base + order[j];
                }
                server->canvas_item_add_triangle_array(canvas, indices, points, colors, uvs, PackedInt32Array(), PackedFloat32Array(), texture);
                start = finish;
                continue;
            }
        }
        server->canvas_item_add_texture_rect_region(canvas, sprite[1], sprite[3], sprite[4], sprite[2], false, true);
        ++start;
    }
    return start;
}

double RoRReadModelKernel::unit_depth_offset(const Vector2 &position, double screen_y, const Dictionary &index, const Callable &project) const {
    return projected_unit_depth_offset(position, screen_y, index, FrameProjection(project, Array()));
}

double RoRReadModelKernel::projected_unit_depth_offset(const Vector2 &position, double screen_y, const Dictionary &index, const FrameProjection &project) const {
    static const Variant gate("gate_occluder"), start("start"), end("end"), depth_key("depth"), harvest("harvestable"), hp("hp"), pos("pos"), footprint("footprint"), half_size("half_size");
    double adjusted = screen_y;
    double front = -std::numeric_limits<double>::infinity(), back = std::numeric_limits<double>::infinity();
    const Array nearby = index.get(Vector2i((position / 4.0).floor()), Array());
    for (int64_t i = 0; i < nearby.size(); ++i) {
        const Dictionary building = nearby[i];
        if (building.has(gate)) {
            const Dictionary segment = building[gate];
            const Vector2 a = segment[start], b = segment[end], direction = b - a;
            const double length = direction.length_squared();
            if (length < 0.0001) continue;
            const double along = (position - a).dot(direction) / length;
            Vector2 normal = direction.orthogonal().normalized();
            if (normal.dot(Vector2(1, 1)) < 0) normal = -normal;
            const double side = (position - a).dot(normal);
            if (along < -0.75 || along > 1.75 || std::abs(side) > 1.25) continue;
            const double depth = project.screen(segment[depth_key]).y;
            const double margin = std::max(0.05, std::abs(depth) * 0.00002);
            if (side >= 0) front = std::max(front, depth + margin);
            else back = std::min(back, depth - margin);
            continue;
        }
        if (bool(building.get(harvest, false)) || double(building.get(hp, 0.0)) <= 0.0) continue;
        const Vector2 center = building[pos];
        const Dictionary shape = building.get(footprint, Dictionary());
        const Vector2 half = shape.get(half_size, Vector2(0.5, 0.5)), offset = position - center;
        if (std::abs(offset.x) > half.x + 1.5 || std::abs(offset.y) > half.y + 1.5) continue;
        if (offset.x >= half.x || offset.y >= half.y) adjusted = std::max(adjusted, double(project.screen(center).y) + 0.01);
    }
    if (front <= back) adjusted = std::max(front, std::min(adjusted, back));
    return adjusted - screen_y;
}

void RoRReadModelKernel::reproject_static_items(const Array &items, const Vector2 &origin,
        const Vector2 &previous_origin, double previous_scale, double scale) const {
    if (previous_scale <= 0.0 || scale <= 0.0) return;
    static const Variant position("screen_position"), y("screen_y"), local("projection_anchor");
    static const Variant command("sprite_command"), size("sprite_source_size"), offset("sprite_screen_offset"), hotspot("hotspot");
    for (int64_t i = 0; i < items.size(); ++i) {
        Dictionary item = items[i];
        if (!item.has(local)) item[local] = (Vector2(item[position]) - previous_origin) / previous_scale;
        const Vector2 screen = Vector2(item[local]) * scale + origin;
        item[position] = screen;
        item[y] = screen.y;
        if (item.has(command)) {
            Array sprite = item[command];
            sprite[1] = Rect2(screen.round() + Vector2(item[offset]) * scale - Vector2(item[hotspot]) * scale,
                    Vector2(item[size]) * scale);
        }
    }
}

Array RoRReadModelKernel::sort_render_items(const Array &items) const {
    // Read Variant keys once per item; comparisons stay in native scalar data.
    struct Entry {
        Dictionary item;
        int64_t layer, sub, id;
        double y, elevation;
        bool wall;
        Vector2 anchor;
    };
    static const Variant layer("layer"), sub("sub_order"), id("stable_id"), y("screen_y");
    static const Variant elevation("elevation"), wall("wall_depth_tie"), anchor("world_anchor");
    std::vector<Entry> entries;
    entries.reserve(items.size());
    for (int64_t i = 0; i < items.size(); ++i) {
        const Dictionary item = items[i];
        entries.push_back({item, item[layer], item.get(sub, 0), item[id],
                item[y], item[elevation], item.get(wall, false), item[anchor]});
    }
    std::stable_sort(entries.begin(), entries.end(), [](const Entry &a, const Entry &b) {
        if (a.layer != b.layer) return a.layer < b.layer;
        if (!Math::is_equal_approx(a.y, b.y)) return a.y < b.y;
        if (!Math::is_equal_approx(a.elevation, b.elevation)) return a.elevation < b.elevation;
        if (a.sub != b.sub) return a.sub < b.sub;
        if (a.wall != b.wall) return a.wall;
        if (a.wall) {
            if (!Math::is_equal_approx(double(a.anchor.x), double(b.anchor.x))) return a.anchor.x < b.anchor.x;
            if (!Math::is_equal_approx(double(a.anchor.y), double(b.anchor.y))) return a.anchor.y < b.anchor.y;
        }
        return a.id < b.id;
    });
    Array result;
    result.resize(items.size());
    for (int64_t i = 0; i < result.size(); ++i) result[i] = entries[i].item;
    return result;
}

struct RenderOrderHead {
    Dictionary row;
    int64_t layer;
    double depth;

    explicit RenderOrderHead(const Dictionary &item) :
        row(item), layer(item[ROR_FIELD("layer")]), depth(item[ROR_FIELD("screen_y")]) {}

    bool before(const RenderOrderHead &other) const {
        if (layer != other.layer) return layer < other.layer;
        if (!Math::is_equal_approx(depth, other.depth)) return depth < other.depth;
        static const Variant elevation("elevation"), sub("sub_order"), wall("wall_depth_tie"), anchor("world_anchor"), id("stable_id");
        const Dictionary &a = row, &b = other.row;
        const double ae = a[elevation], be = b[elevation];
        if (!Math::is_equal_approx(ae, be)) return ae < be;
        const int64_t as = a.get(sub, 0), bs = b.get(sub, 0);
        if (as != bs) return as < bs;
        const bool aw = a.get(wall, false), bw = b.get(wall, false);
        if (aw != bw) return aw;
        if (aw) {
            const Vector2 ap = a[anchor], bp = b[anchor];
            if (!Math::is_equal_approx(double(ap.x), double(bp.x))) return ap.x < bp.x;
            if (!Math::is_equal_approx(double(ap.y), double(bp.y))) return ap.y < bp.y;
        }
        return int64_t(a[id]) < int64_t(b[id]);
    }
};

bool RoRReadModelKernel::render_items_in_order(const Array &items) const {
    if (items.size() < 2) return true;
    RenderOrderHead previous(items[0]);
    for (int64_t i = 1; i < items.size(); ++i) {
        RenderOrderHead next(items[i]);
        // A tie uses the original stable sort and merge precedence.
        if (!previous.before(next)) return false;
        previous = next;
    }
    return true;
}

Array RoRReadModelKernel::merge_render_items(const Array &first, const Array &second) const {
    Array result; result.resize(first.size() + second.size());
    int64_t a = 0, b = 0, output = 0;
    if (!first.is_empty() && !second.is_empty()) {
        RenderOrderHead left(first[0]), right(second[0]);
        while (a < first.size() && b < second.size()) {
            if (left.before(right)) {
                result[output++] = first[a++];
                if (a < first.size()) left = RenderOrderHead(first[a]);
            } else {
                result[output++] = second[b++];
                if (b < second.size()) right = RenderOrderHead(second[b]);
            }
        }
    }
    while (a < first.size()) result[output++] = first[a++];
    while (b < second.size()) result[output++] = second[b++];
    return result;
}

PackedInt32Array RoRReadModelKernel::advance_idle_animation(const Array &entities, double delta) const {
    static const Variant anim("anim"), state("anim_state"), events("animation_events_fired"), id("id");
    static const Array reset_clips = []() {
        Array clips;
        for (const char *name : {"Move", "AttackWindup", "AttackRecover", "Gather", "Carry", "Build", "Repair", "Convert", "Heal", "Die", "Decay"}) clips.append(String(name));
        return clips;
    }();
    PackedInt32Array changed;
    for (int64_t i = 0; i < entities.size(); ++i) {
        Dictionary entity = entities[i];
        const String previous = entity.get(state, String());
        if (previous != ROR_TEXT("Idle")) {
            entity[state] = ROR_TEXT("Idle");
            changed.append(int64_t(entity[id]));
            if (reset_clips.has(previous)) {
                entity[anim] = 0.0;
                entity[events] = Dictionary();
                continue;
            }
        }
        entity[anim] = double(entity.get(anim, 0.0)) + std::max(0.0, delta);
    }
    return changed;
}

Ref<Image> RoRReadModelKernel::remap_player_image(const Ref<Image> &blue, const Ref<Image> &red, const PackedColorArray &source_ramp, const PackedColorArray &target_ramp) const {
    // Exact RGBA8 counterpart of PlayerPalette.remap_images. Source textures
    // remain immutable; only pixels differing between the original blue/red
    // decodes and belonging to the ten player shades may change.
    if (blue.is_null() || red.is_null() || blue->get_size() != red->get_size() ||
        blue->get_format() != Image::FORMAT_RGBA8 || red->get_format() != Image::FORMAT_RGBA8 ||
        blue->has_mipmaps() || red->has_mipmaps() || source_ramp.size() != 10 || target_ramp.size() != 10) return Ref<Image>();
    PackedByteArray pixels = blue->get_data();
    const PackedByteArray comparison = red->get_data();
    const int64_t expected = int64_t(blue->get_width()) * blue->get_height() * 4;
    if (pixels.size() != expected || comparison.size() != expected) return Ref<Image>();
    uint32_t source[10], target[10];
    for (int i = 0; i < 10; ++i) { source[i] = source_ramp[i].to_rgba32(); target[i] = target_ramp[i].to_rgba32(); }
    uint8_t *dst = pixels.ptrw();
    const uint8_t *other = comparison.ptr();
    for (int64_t offset = 0; offset < expected; offset += 4) {
        if (!dst[offset + 3] || (dst[offset] == other[offset] && dst[offset + 1] == other[offset + 1] && dst[offset + 2] == other[offset + 2] && dst[offset + 3] == other[offset + 3])) continue;
        const uint32_t color = (uint32_t(dst[offset]) << 24) | (uint32_t(dst[offset + 1]) << 16) | (uint32_t(dst[offset + 2]) << 8) | dst[offset + 3];
        for (int shade = 0; shade < 10; ++shade) {
            if (color != source[shade]) continue;
            dst[offset] = uint8_t(target[shade] >> 24);
            dst[offset + 1] = uint8_t(target[shade] >> 16);
            dst[offset + 2] = uint8_t(target[shade] >> 8);
            dst[offset + 3] = uint8_t(target[shade]);
            break;
        }
    }
    return Image::create_from_data(blue->get_width(), blue->get_height(), false, Image::FORMAT_RGBA8, pixels);
}

PackedByteArray RoRReadModelKernel::occupied_resource_slots(const Dictionary &worker, const Array &candidates, const Vector2i &size, const Dictionary &resources_by_cell, const Dictionary &reservations_by_resource, const Dictionary &units_by_id, double minimum_clearance, double default_clearance) const {
    // One owner-only read of the local reservation tables for the entire ring.
    // Each point still tests exactly the original +/-3-cell neighborhood.
    if (candidates.size() > 128 || size.x <= 0 || size.y <= 0) return PackedByteArray();
    PackedByteArray result;
    result.resize(candidates.size());
    result.fill(0);
    if (candidates.is_empty()) return result;
    struct Point { Vector2 position; Vector2i cell; };
    struct Slot { Vector2 position; Vector2i resource_cell; double separation_squared; };
    std::vector<Point> points;
    std::vector<Slot> slots;
    int first_x = size.x, first_y = size.y, last_x = -1, last_y = -1;
    for (int64_t i = 0; i < candidates.size(); ++i) {
        if (candidates[i].get_type() != Variant::VECTOR2) return PackedByteArray();
        const Vector2 position = candidates[i];
        const Vector2i cell(int(position.x), int(position.y));
        points.push_back({position, cell});
        first_x = std::min(first_x, std::max(0, cell.x - 3));
        first_y = std::min(first_y, std::max(0, cell.y - 3));
        last_x = std::max(last_x, std::min(size.x - 1, cell.x + 3));
        last_y = std::max(last_y, std::min(size.y - 1, cell.y + 3));
    }
    if (int64_t(last_x - first_x + 1) * (last_y - first_y + 1) > 4096) return PackedByteArray();
    const StringName id_key("id"), radius_key("footprint_radius"), clearance_key("minimum_clearance");
    const int64_t worker_id = worker.get(id_key, -1);
    const double radius = worker.get(radius_key, 0.3);
    const double own_clearance = worker.get(clearance_key, default_clearance);
    for (int y = first_y; y <= last_y; ++y) {
        for (int x = first_x; x <= last_x; ++x) {
            const Array resources = resources_by_cell.get(int64_t(y) * size.x + x, Array());
            for (int64_t i = 0; i < resources.size(); ++i) {
                const Dictionary resource = resources[i];
                const Dictionary reservations = reservations_by_resource.get(resource[id_key], Dictionary());
                const Array ids = reservations.keys();
                for (int64_t j = 0; j < ids.size(); ++j) {
                    const int64_t other_id = ids[j];
                    if (other_id == worker_id) continue;
                    const Variant other_value = units_by_id.get(other_id, Variant());
                    const bool has_other = other_value.get_type() == Variant::DICTIONARY;
                    const Dictionary other = has_other ? Dictionary(other_value) : Dictionary();
                    const double other_radius = has_other ? double(other.get(radius_key, 0.3)) : radius;
                    double separation = has_other ? radius + other_radius + std::max(own_clearance, double(other.get(clearance_key, default_clearance))) : radius * 2.0 + default_clearance;
                    if (minimum_clearance >= 0.0) separation = radius + other_radius + minimum_clearance;
                    const Variant position = reservations[ids[j]];
                    if (position.get_type() != Variant::VECTOR2) return PackedByteArray();
                    slots.push_back({Vector2(position), Vector2i(x, y), separation * separation});
                }
            }
        }
    }
    uint8_t *occupied = result.ptrw();
    for (size_t i = 0; i < points.size(); ++i) {
        for (const Slot &slot : slots) {
            if (std::abs(slot.resource_cell.x - points[i].cell.x) > 3 || std::abs(slot.resource_cell.y - points[i].cell.y) > 3) continue;
            if (slot.position.distance_squared_to(points[i].position) < slot.separation_squared) { occupied[i] = 1; break; }
        }
    }
    return result;
}

PackedByteArray RoRReadModelKernel::occupied_idle_unit_slots(const Dictionary &worker, const Array &candidates, const Array &nearby, const Dictionary &indices, const Array &positions, const Array &radii, double default_clearance) const {
    if (candidates.size() > 128 || positions.size() != radii.size()) return PackedByteArray();
    struct Occupant { Vector2 indexed, live; double query_squared, separation_squared; };
    std::vector<Occupant> occupants;
    const StringName id_key("id"), radius_key("footprint_radius"), clearance_key("minimum_clearance"), domain_key("movement_domain"), task_key("task");
    const int64_t own_id = worker.get(id_key, -1);
    const double radius = worker.get(radius_key, 0.3);
    const double clearance = worker.get(clearance_key, default_clearance);
    const String domain = worker.get(domain_key, ROR_FIELD("land"));
    for (int64_t i = 0; i < nearby.size(); ++i) {
        const Dictionary other = nearby[i];
        const int64_t id = other.get(id_key, -1);
        const String task = other.get(task_key, ROR_FIELD("idle"));
        if (id == own_id || double(other.get(ROR_FIELD("hp"), 0.0)) <= 0.0 || String(other.get(domain_key, ROR_FIELD("land"))) != domain || (task != ROR_TEXT("idle") && task != ROR_TEXT("hold"))) continue;
        const int64_t index = indices.get(id, -1);
        if (index < 0 || index >= positions.size()) return PackedByteArray();
        const double query = radius + 2.0 + double(radii[index]);
        const double separation = radius + double(other.get(radius_key, 0.3)) + std::max(clearance, double(other.get(clearance_key, default_clearance)));
        occupants.push_back({Vector2(positions[index]), Vector2(other[ROR_FIELD("pos")]), query * query, separation * separation});
    }
    PackedByteArray result;
    result.resize(candidates.size()); result.fill(0);
    uint8_t *occupied = result.ptrw();
    for (int64_t i = 0; i < candidates.size(); ++i) {
        if (candidates[i].get_type() != Variant::VECTOR2) return PackedByteArray();
        const Vector2 candidate = candidates[i];
        for (const Occupant &other : occupants) {
            // Preserve both the spatial index's source-position query and the
            // original live-position footprint predicate, even within a tick.
            if (candidate.distance_squared_to(other.indexed) <= other.query_squared && candidate.distance_squared_to(other.live) < other.separation_squared) { occupied[i] = 1; break; }
        }
    }
    return result;
}

namespace {
bool query_spatial_units(const Vector2 &center, double radius, const Variant &excluded_id, const Variant &excluded_group,
        const Dictionary &buckets, const Array &entities, const Array &positions, const Array &radii,
        double cell_size, double maximum_radius, Array result) {
    if (cell_size <= 0.0 || !std::isfinite(radius) || !std::isfinite(maximum_radius) ||
            entities.size() != positions.size() || positions.size() != radii.size()) return false;
    const double extent = radius + maximum_radius;
    // Query the same start-of-tick index positions, not the live positions that
    // earlier actors may already have changed. Keep the original bucket math.
    const Vector2 minimum = (center - Vector2(1, 1) * real_t(extent)) / real_t(cell_size);
    const Vector2 maximum = (center + Vector2(1, 1) * real_t(extent)) / real_t(cell_size);
    const int first_x = int(std::floor(minimum.x)), last_x = int(std::floor(maximum.x));
    const int first_y = int(std::floor(minimum.y)), last_y = int(std::floor(maximum.y));
    if (int64_t(last_x - first_x + 1) * (last_y - first_y + 1) > 4096) return false;
    const bool filter_self = excluded_id.get_type() != Variant::NIL;
    const int64_t own_id = filter_self ? int64_t(excluded_id) : 0;
    const bool filter_group = excluded_group.get_type() != Variant::NIL;
    const int64_t group = filter_group ? int64_t(excluded_group) : 0;
    static const Variant id_key("id"), group_key("formation_group_id");
    struct Candidate { int64_t id; Dictionary entity; };
    std::vector<Candidate> found;
    const Array empty;
    bool sorted = true;
    int64_t previous_id = std::numeric_limits<int64_t>::min();
    for (int y = first_y; y <= last_y; ++y) for (int x = first_x; x <= last_x; ++x) {
        const Array indices = buckets.get(Vector2i(x, y), empty);
        for (int64_t i = 0; i < indices.size(); ++i) {
            const int64_t index = indices[i];
            if (index < 0 || index >= entities.size()) return false;
            const Dictionary candidate = entities[index];
            const int64_t candidate_id = candidate[id_key];
            if ((filter_self && candidate_id == own_id) || (filter_group && int64_t(candidate.get(group_key, -1)) == group)) continue;
            const double allowed = radius + double(radii[index]);
            if (center.distance_squared_to(Vector2(positions[index])) > allowed * allowed) continue;
            if (candidate_id < previous_id) sorted = false;
            previous_id = candidate_id;
            found.push_back({candidate_id, candidate});
        }
    }
    if (!sorted) {
        struct Compare { bool operator()(const Candidate &a, const Candidate &b) const { return a.id < b.id; } };
        SortArray<Candidate, Compare>().sort(found.data(), int64_t(found.size()));
    }
    result.clear();
    for (const Candidate &candidate : found) result.append(candidate.entity);
    return true;
}

} // namespace

Dictionary RoRReadModelKernel::stable_activity_updates(const Array &ids, const Dictionary &context) const {
    return activity_updates_impl(ids, context, false);
}

Dictionary RoRReadModelKernel::classify_activity_changes(const Array &ids, const Dictionary &context) const {
    return activity_updates_impl(ids, context, true);
}

Dictionary RoRReadModelKernel::activity_updates_impl(const Array &ids, const Dictionary &context, bool compact) const {
    // Pure owner query. Qualifying records would leave all registry containers
    // unchanged in refresh(); their only effects are two monotone OR flags.
    if (ids.size() > 65536) return Dictionary();
    const Dictionary units = context[ROR_FIELD("units")], active = context[ROR_FIELD("active")], idle = context[ROR_FIELD("idle")], orders = context[ROR_FIELD("orders")], masks = context[ROR_FIELD("masks")];
    const bool filter_changes = context[ROR_FIELD("filter_changes")];
    static const Variant id_key("id"), hp_key("hp"), task_key("task"), group_key("formation_group_id");
    static const Variant shared_key("formation_shared_motion"), isolated_key("formation_shared_isolated"), scale_key("cohesion_speed_scale");
    Dictionary stable, verification;
    std::vector<int64_t> remaining_ids;
    if (compact) remaining_ids.reserve(size_t(ids.size()));
    bool movement = context.get(ROR_FIELD("movement"), false), formation_any = context.get(ROR_FIELD("formation"), false);
    int64_t stable_count = 0;
    const int64_t verify_limit = std::clamp(int64_t(context.get(ROR_FIELD("verify_limit"), 0)), int64_t(0), int64_t(512));
    const auto qualify = [&](const Variant &id, bool &formation) {
        if (int64_t(id) < 0 || !orders.has(id) || idle.has(id) || active.get(id, Variant()).get_type() == Variant::NIL) return false;
        const Variant value = units.get(id, Variant());
        if (value.get_type() != Variant::DICTIONARY) return false;
        const Dictionary unit = value;
        if (unit.get(id_key, Variant()) != id) return false;
        const Variant hp = unit.get(hp_key, 0.0), task = unit.get(task_key, ROR_FIELD("idle"));
        if ((hp.get_type() != Variant::FLOAT && hp.get_type() != Variant::INT) || !std::isfinite(double(hp)) || task.get_type() != Variant::STRING) return false;
        if (double(hp) <= 0.0 || String(task) == ROR_TEXT("idle")) return false;
        // OR-reduction needs no further formation predicate once true. Keep
        // individual predicates for the bounded, opt-in reference observation.
        if (compact && formation_any && verification.size() >= verify_limit) return true;
        const Variant group = unit.get(group_key, -1);
        if (group.get_type() != Variant::INT) return false;
        formation = int64_t(group) >= 0 && String(task) == ROR_TEXT("move");
        if (!formation) {
            const Variant shared = unit.get(shared_key, false), isolated = unit.get(isolated_key, false), scale = unit.get(scale_key, 1.0);
            if (shared.get_type() != Variant::BOOL || isolated.get_type() != Variant::BOOL ||
                    (scale.get_type() != Variant::FLOAT && scale.get_type() != Variant::INT)) return false;
            formation = bool(shared) || bool(isolated) || !UtilityFunctions::is_equal_approx(double(scale), 1.0);
        }
        return true;
    };
    for (int64_t i = 0; i < ids.size(); ++i) {
        const Variant id = ids[i];
        if (id.get_type() != Variant::INT) return Dictionary();
        if (filter_changes) {
            const Variant mask = masks.get(id, 0);
            if (mask.get_type() != Variant::INT) return Dictionary();
            if (!(int64_t(mask) & (1 | 4 | 8 | 128))) continue;
        }
        bool formation = false;
        if (!qualify(id, formation)) {
            if (compact) remaining_ids.push_back(id);
            continue;
        }
        if (compact) {
            ++stable_count;
            movement = true; formation_any = formation_any || formation;
            if (verification.size() < verify_limit) verification[id] = formation;
        } else stable[id] = formation;
    }
    if (compact) {
        Array remaining;
        remaining.resize(remaining_ids.size());
        for (size_t i = 0; i < remaining_ids.size(); ++i) remaining[int64_t(i)] = remaining_ids[i];
        Dictionary result;
        result[ROR_FIELD("remaining")] = remaining; result[ROR_FIELD("movement")] = movement;
        result[ROR_FIELD("formation")] = formation_any; result[ROR_FIELD("stable_count")] = stable_count;
        result[ROR_FIELD("verification")] = verification;
        return result;
    }
    return stable;
}

bool RoRReadModelKernel::sort_active_units(Array units, const Dictionary &orders) const {
    // Capture each comparison key once. This is the same strict (order,id)
    // comparator as the registry; unsupported schemas precede every write.
    if (units.is_read_only() || units.size() > 65536) return false;
    struct Record { int64_t order; int64_t id; Dictionary unit; };
    struct Compare {
        bool operator()(const Record &a, const Record &b) const {
            return a.order < b.order || (a.order == b.order && a.id < b.id);
        }
    };
    static const Variant id_key("id");
    std::vector<Record> rows;
    rows.reserve(size_t(units.size()));
    std::unordered_set<int64_t> seen;
    seen.reserve(size_t(units.size()));
    for (int64_t i = 0; i < units.size(); ++i) {
        if (units[i].get_type() != Variant::DICTIONARY) return false;
        const Dictionary unit = units[i];
        const Variant id = unit.get(id_key, Variant());
        if (id.get_type() != Variant::INT || !seen.insert(int64_t(id)).second) return false;
        const Variant order = orders.get(id, id);
        if (order.get_type() != Variant::INT) return false;
        rows.push_back({int64_t(order), int64_t(id), unit});
    }
    if (!rows.empty()) SortArray<Record, Compare>().sort(rows.data(), int64_t(rows.size()));
    for (size_t i = 0; i < rows.size(); ++i) units[int64_t(i)] = rows[i].unit;
    return true;
}

int64_t RoRReadModelKernel::synchronize_spatial_units_prefix(const Array &units, const Dictionary &indices,
        const Array &entities, Array positions, Array cells, Dictionary buckets, double cell_size) const {
    // Owner-thread pass. Return the completed prefix on an unsupported row;
    // the script resumes at that row, without replaying earlier mutations.
    if (units.size() > 65536 || !std::isfinite(cell_size) || cell_size <= 0.0 ||
            entities.size() != positions.size() || positions.size() != cells.size() ||
            positions.is_read_only() || cells.is_read_only() || buckets.is_read_only()) return 0;
    static const Variant id_key("id"), hp_key("hp"), position_key("pos");
    const auto writable_bucket = [&](const Vector2i &cell) {
        if (!buckets.has(cell)) return true;
        const Variant value = buckets[cell];
        return value.get_type() == Variant::ARRAY && !Array(value).is_read_only();
    };
    for (int64_t i = 0; i < units.size(); ++i) {
        if (units[i].get_type() != Variant::DICTIONARY) return i;
        const Dictionary unit = units[i];
        const Variant id = unit.get(id_key, Variant()), hp = unit.get(hp_key, Variant()), position = unit.get(position_key, Variant());
        if (id.get_type() != Variant::INT || (hp.get_type() != Variant::INT && hp.get_type() != Variant::FLOAT) ||
                double(hp) <= 0.0 || position.get_type() != Variant::VECTOR2) return i;
        const Variant slot = indices.get(id, Variant());
        if (slot.get_type() != Variant::INT) return i;
        const int64_t index = slot;
        if (index < 0 || index >= entities.size() || entities[index].get_type() != Variant::DICTIONARY ||
                Dictionary(entities[index]).get(id_key, Variant()) != id || positions[index].get_type() != Variant::VECTOR2) return i;
        const Vector2 point = position;
        if (Vector2(positions[index]) == point) continue;
        if (!std::isfinite(point.x) || !std::isfinite(point.y) || cells[index].get_type() != Variant::VECTOR2I) return i;
        const double x = std::floor(double(point.x) / cell_size), y = std::floor(double(point.y) / cell_size);
        if (x < std::numeric_limits<int32_t>::min() || x > std::numeric_limits<int32_t>::max() ||
                y < std::numeric_limits<int32_t>::min() || y > std::numeric_limits<int32_t>::max()) return i;
        const Vector2i next_cell{int32_t(x), int32_t(y)}, previous = cells[index];
        if (next_cell != previous && (!writable_bucket(previous) || !writable_bucket(next_cell))) return i;
        positions[index] = point;
        if (next_cell == previous) continue;
        Array old = buckets.get(previous, Array());
        old.erase(index);
        if (old.is_empty()) buckets.erase(previous);
        if (!buckets.has(next_cell)) buckets[next_cell] = Array();
        Array next = buckets[next_cell];
        next.append(index);
        cells[index] = next_cell;
    }
    return units.size();
}

bool RoRReadModelKernel::spatial_unit_neighbors(const Dictionary &unit, double radius, const Variant &excluded_group,
        const Dictionary &buckets, const Array &entities, const Array &positions, const Array &radii,
        double cell_size, double maximum_radius, Array result) const {
    return query_spatial_units(unit[ROR_FIELD("pos")], radius, unit[ROR_FIELD("id")], excluded_group, buckets, entities,
            positions, radii, cell_size, maximum_radius, result);
}

bool RoRReadModelKernel::spatial_unit_circle(const Vector2 &center, double radius,
        const Dictionary &buckets, const Array &entities, const Array &positions, const Array &radii,
        double cell_size, double maximum_radius, Array result) const {
    // A generic circle includes every indexed ID, including negative IDs used
    // by compatibility callers. Only the neighbor API excludes its own ID.
    if (!std::isfinite(radius)) return false;
    return query_spatial_units(center, std::max(0.0, radius), Variant(), Variant(), buckets, entities,
            positions, radii, cell_size, maximum_radius, result);
}

int64_t RoRReadModelKernel::settle_mobile_contacts(const Dictionary &changes, const Array &active_units,
        const Array &all_units, const Dictionary &units_by_id, const Dictionary &buckets, const Array &entities,
        const Array &positions, const Array &radii, double cell_size, double maximum_radius,
        double delta, Dictionary pending, const Callable &query_fallback, const Callable &separate) const {
    // Owner-thread dispatch only. Broad-phase positions stay at the tick's
    // spatial generation; pair tests read live dictionaries after each earlier
    // correction. Actual writes retain the world's terrain/journal callback.
    // Unsupported inputs return before any correction or pending write.
    if (delta <= 0.0 || !std::isfinite(delta) || cell_size <= 0.0 || !std::isfinite(cell_size) ||
            !std::isfinite(maximum_radius) || entities.size() != positions.size() ||
            positions.size() != radii.size() || active_units.size() > 65536 || all_units.size() > 65536 || pending.is_read_only() ||
            !query_fallback.is_valid() || !separate.is_valid()) return -1;
    static const Variant id_key("id"), hp_key("hp"), position_key("pos"), radius_key("footprint_radius"), domain_key("movement_domain");
    std::unordered_map<int64_t, Dictionary> candidates;
    static const Variant isolated_key("formation_shared_isolated");
    const Array previous_ids = pending.keys();
    for (int64_t i = 0; i < previous_ids.size(); ++i) {
        const Variant value = pending[previous_ids[i]];
        if (previous_ids[i].get_type() != Variant::INT || value.get_type() != Variant::DICTIONARY) return -1;
        candidates[int64_t(previous_ids[i])] = value;
    }
    const bool full = changes.get(ROR_FIELD("full"), false);
    const Array &source = full ? all_units : active_units;
    for (int64_t i = 0; i < source.size(); ++i) {
        if (source[i].get_type() != Variant::DICTIONARY) return -1;
        const Dictionary unit = source[i];
        if (unit[id_key].get_type() != Variant::INT) return -1;
        if (full || !bool(unit.get(isolated_key, false))) candidates[int64_t(unit[id_key])] = unit;
    }
    if (!full) {
        const Array changed_ids = changes.get(ROR_FIELD("ids"), Array());
        const Dictionary masks = changes.get(ROR_FIELD("masks"), Dictionary());
        for (int64_t i = 0; i < changed_ids.size(); ++i) {
            if (changed_ids[i].get_type() != Variant::INT) return -1;
            const int64_t id = changed_ids[i];
            if (!(int64_t(masks.get(id, 0)) & 3)) continue; // LIFECYCLE | POSITION
            const Variant value = units_by_id.get(id, Variant());
            if (value.get_type() == Variant::NIL) continue;
            if (value.get_type() != Variant::DICTIONARY) return -1;
            const Dictionary unit = value;
            if (!bool(unit.get(isolated_key, false))) candidates[id] = unit;
        }
    }
    if (candidates.size() > 65536) return -1;
    std::vector<int64_t> ids;
    ids.reserve(candidates.size());
    for (const auto &entry : candidates) ids.push_back(entry.first);
    std::sort(ids.begin(), ids.end());
    pending.clear();
    std::unordered_set<uint64_t> pairs;
    Array neighbors;
    for (size_t i = 0; i < ids.size(); ++i) {
        const int64_t id = ids[i];
        const Dictionary unit = candidates[id];
        if (double(unit.get(hp_key, 0.0)) <= 0.0 || units_by_id.get(id, Variant()).get_type() == Variant::NIL) continue;
        const double search_radius = double(unit[radius_key]) + 0.25;
        if (!spatial_unit_neighbors(unit, search_radius, Variant(), buckets, entities, positions, radii, cell_size, maximum_radius, neighbors)) {
            // Keep the scalar spatial fallback for oversized/custom indices.
            // Never restart the contact pass after earlier pairs were moved.
            neighbors.clear();
            query_fallback.call(unit, search_radius, ROR_TEXT("unit"), neighbors);
        }
        for (int64_t j = 0; j < neighbors.size(); ++j) {
            const Dictionary other = neighbors[j];
            const int64_t other_id = other[id_key];
            if (double(other.get(hp_key, 0.0)) <= 0.0 || String(other.get(domain_key, ROR_FIELD("land"))) != String(unit.get(domain_key, ROR_FIELD("land")))) continue;
            const Vector2 gap = Vector2(unit[position_key]) - Vector2(other[position_key]);
            const double radius = double(unit[radius_key]) + double(other[radius_key]);
            if (gap.length_squared() >= (radius - 0.001) * (radius - 0.001)) continue;
            // Match the existing Vector2i pair key, including its 32-bit lanes.
            const uint64_t pair = (uint64_t(uint32_t(std::min(id, other_id))) << 32) | uint32_t(std::max(id, other_id));
            if (!pairs.insert(pair).second) continue;
            const double distance = gap.length();
            pending[id] = unit;
            pending[other_id] = other;
            const Vector2 normal = distance > 0.0001 ? gap / real_t(distance) : Vector2(0, id < other_id ? -1 : 1);
            const double correction = std::min(radius - distance + 0.002, std::max(0.01, delta * 2.0));
            const double first = separate.call(unit, normal * real_t(correction * 0.5));
            const double second = separate.call(other, -normal * real_t(correction - first));
            if (second < correction * 0.5) separate.call(unit, normal * real_t(correction * 0.5 - second));
        }
    }
    return int64_t(ids.size());
}

int64_t RoRReadModelKernel::spatial_unit_match(const Dictionary &unit, double radius, int64_t mode, const Dictionary &buckets, const Array &entities, const Array &positions, const Array &radii, double cell_size, double maximum_radius) const {
    if (cell_size <= 0.0 || !std::isfinite(radius) || entities.size() != positions.size() || positions.size() != radii.size() || (mode != 0 && mode != 1)) return -1;
    const Vector2 center = unit[ROR_FIELD("pos")];
    const double query_radius = std::max(0.0, radius), extent = query_radius + maximum_radius;
    // Match SpatialHash.cell_for's Vector2 arithmetic at bucket boundaries.
    const Vector2 minimum = (center - Vector2(1, 1) * real_t(extent)) / real_t(cell_size);
    const Vector2 maximum = (center + Vector2(1, 1) * real_t(extent)) / real_t(cell_size);
    const int first_x = int(std::floor(minimum.x)), last_x = int(std::floor(maximum.x));
    const int first_y = int(std::floor(minimum.y)), last_y = int(std::floor(maximum.y));
    if (int64_t(last_x - first_x + 1) * (last_y - first_y + 1) > 4096) return -1;
    const int64_t own_id = unit[ROR_FIELD("id")], team = unit.get(ROR_FIELD("team"), 0);
    const String domain = unit.get(ROR_FIELD("movement_domain"), ROR_FIELD("land"));
    const double own_radius = unit.get(ROR_FIELD("footprint_radius"), 0.3);
    for (int y = first_y; y <= last_y; ++y) for (int x = first_x; x <= last_x; ++x) {
        const Array indices = buckets.get(Vector2i(x, y), Array());
        for (int64_t i = 0; i < indices.size(); ++i) {
            const int64_t index = indices[i];
            if (index < 0 || index >= entities.size()) return -1;
            const double allowed = query_radius + double(radii[index]);
            if (center.distance_squared_to(Vector2(positions[index])) > allowed * allowed) continue;
            const Dictionary other = entities[index];
            if (int64_t(other[ROR_FIELD("id")]) == own_id) continue;
            if (mode == 0) {
                // Original traffic test includes every indexed friendly gatherer.
                if (String(other.get(ROR_FIELD("task"), ROR_FIELD(""))) == ROR_TEXT("gather") && int64_t(other.get(ROR_FIELD("team"), 0)) == team) return 1;
            } else {
                if (double(other.get(ROR_FIELD("hp"), 0.0)) <= 0.0 || String(other.get(ROR_FIELD("movement_domain"), ROR_FIELD("land"))) != domain) continue;
                const double separation = own_radius + double(other.get(ROR_FIELD("footprint_radius"), 0.3));
                if (center.distance_squared_to(Vector2(other[ROR_FIELD("pos")])) < separation * separation - 0.00001) return 1;
            }
        }
    }
    return 0;
}

PackedInt64Array RoRReadModelKernel::autosave_entity_digests(const Array &entities) const {
    // The simulation owner remains stopped at its source boundary throughout
    // this call. Borrow records, sort only local references, and hash the same
    // complete values as GDScript. Never mutate the authoritative dictionaries.
    struct Record { int64_t id; Dictionary value; };
    struct Compare {
        bool operator()(const Record &a, const Record &b) const { return a.id < b.id; }
    };
    const StringName id_key("id");
    std::vector<Record> ordered;
    ordered.reserve(entities.size());
    for (int64_t i = 0; i < entities.size(); ++i) {
        if (entities[i].get_type() != Variant::DICTIONARY) return PackedInt64Array();
        const Dictionary entity = entities[i];
        ordered.push_back({int64_t(entity.get(id_key, -1)), entity});
    }
    // Use the engine's introsort and the original ID comparison, including
    // records without IDs, rather than introducing a new ordering rule.
    SortArray<Record, Compare>().sort(ordered.data(), int64_t(ordered.size()));
    PackedInt64Array result;
    result.resize(entities.size() * 2);
    int64_t *digests = result.ptrw();
    for (size_t i = 0; i < ordered.size(); ++i) {
        digests[i * 2] = ordered[i].id;
        digests[i * 2 + 1] = canonical_entity_value_hash(ordered[i].value);
    }
    return result;
}

int64_t RoRReadModelKernel::submit_selection_run(const RID &canvas, const Array &items, int64_t first,
        const Array &selected, const Dictionary &preview, int64_t hover, int64_t feedback,
        double feedback_time, const String &semantic, double zoom, bool shift_pressed) const {
    // Preserve draw order and the exact existing ellipse primitive. Complex
    // groups and polygons stop the prefix before any unsupported row is drawn.
    if (!canvas.is_valid() || first < 0 || first >= items.size() || !std::isfinite(zoom) || zoom <= 0.0 || !std::isfinite(feedback_time)) return first;
    std::unordered_set<int64_t> selected_ids;
    selected_ids.reserve(size_t(selected.size()));
    for (int64_t i = 0; i < selected.size(); ++i) {
        if (selected[i].get_type() != Variant::INT) return first;
        selected_ids.insert(int64_t(selected[i]));
    }
    static const Variant kind_key("kind"), data_key("data"), id_key("id"), type_key("entity_type"), footprint_key("footprint");
    static const Variant shape_key("shape"), half_key("half_size"), screen_key("screen_position"), members_key("selection_member_ids");
    static const Variant group_key("selection_members"), radius_key("selection_radius");
    static const Color feedback_color = Color::html("ffe56c"), preview_remove = Color::html("f39a55"), cyan = Color::html("66e8ff");
    static const Color attack_color = Color::html("ef5d55"), gather_color = Color::html("d6bc63"), selected_color = Color::html("e8f45b");
    for (int64_t index = first; index < items.size(); ++index) {
        if (items[index].get_type() != Variant::DICTIONARY) return index;
        const Dictionary item = items[index];
        const Variant kind = item.get(kind_key, Variant()), data = item.get(data_key, Variant()), screen = item.get(screen_key, Variant());
        if (kind.get_type() != Variant::STRING || String(kind) != ROR_TEXT("selection") || data.get_type() != Variant::DICTIONARY || screen.get_type() != Variant::VECTOR2) return index;
        const Dictionary entity = data;
        if (entity.has(group_key)) return index;
        const Variant id = entity.get(id_key, Variant()), footprint_value = entity.get(footprint_key, Dictionary());
        if (id.get_type() != Variant::INT || footprint_value.get_type() != Variant::DICTIONARY) return index;
        const Dictionary footprint = footprint_value;
        const String type = entity.get(type_key, String());
        if (type == ROR_TEXT("building") || type == ROR_TEXT("foundation") || String(footprint.get(shape_key, String())) == ROR_TEXT("polygon")) return index;
        Vector2 radius(15.0f, 6.5f);
        const Variant half = footprint.get(half_key, Variant());
        if (half.get_type() == Variant::VECTOR2) {
            const Vector2 size = half;
            const double span = double(size.x) + double(size.y);
            radius = Vector2(real_t(std::max(15.0, span * 17.0)), real_t(std::max(6.5, span * 8.5)));
        } else if (type == ROR_TEXT("resource")) {
            const Variant value = entity.get(radius_key, footprint.get(radius_key, 0.0));
            double extent;
            if (value.get_type() == Variant::VECTOR2) { const Vector2 size = value; extent = std::max(double(size.x), double(size.y)); }
            else if (value.get_type() == Variant::INT || value.get_type() == Variant::FLOAT) extent = value;
            else return index;
            radius = Vector2(real_t(std::max(15.0, extent * 32.0)), real_t(std::max(6.5, extent * 16.0)));
        }
        if (!std::isfinite(radius.x) || !std::isfinite(radius.y)) return index;
        bool previewed = false, hovered = false, chosen = false, feedback_member = false;
        if (entity.has(members_key)) {
            const Variant value = entity[members_key];
            if (value.get_type() != Variant::ARRAY) return index;
            const Array members = value;
            for (int64_t i = 0; i < members.size(); ++i) {
                if (members[i].get_type() != Variant::INT) return index;
                const int64_t member = members[i];
                previewed = previewed || preview.has(member);
                hovered = hovered || member == hover;
                chosen = chosen || selected_ids.count(member) != 0;
                feedback_member = feedback_member || member == feedback;
            }
        } else {
            previewed = preview.has(id);
            hovered = int64_t(id) == hover;
            chosen = selected_ids.count(int64_t(id)) != 0;
            feedback_member = int64_t(id) == feedback;
        }
        Color color;
        if (feedback_time > 0.0 && feedback_member) {
            if (int64_t(feedback_time * 10.0) % 2 != 0) continue;
            color = feedback_color;
        } else if (previewed) color = shift_pressed && chosen ? preview_remove : cyan;
        else if (hovered) color = semantic == ROR_TEXT("attack") ? attack_color : semantic == ROR_TEXT("gather") ? gather_color : cyan;
        else if (chosen) color = selected_color;
        else continue;
        const Vector2 point = screen;
        if (!std::isfinite(point.x) || !std::isfinite(point.y)) return index;
        const Vector2 snapped(real_t(UtilityFunctions::roundf(double(point.x))), real_t(UtilityFunctions::roundf(double(point.y))));
        submit_selection_ellipse(canvas, snapped, color, radius, zoom);
    }
    return items.size();
}

void RoRReadModelKernel::submit_selection_ellipse(const RID &canvas, const Vector2 &center,
        const Color &color, const Vector2 &radius, double zoom) const {
    if (selection_meshes_enabled && submit_cached_selection_mesh(canvas, center, color, radius * real_t(zoom))) return;
    // Preserve the scalar renderer's 33 points, float-vector operation order,
    // width and antialiasing. Only the repeated trigonometry/VM loop is shared.
    struct Circle {
        double x[33], y[33];
        Circle() {
            constexpr double tau = 6.283185307179586476925286766559;
            for (int i = 0; i < 33; ++i) { const double a = tau * double(i) / 32.0; x[i] = std::cos(a); y[i] = std::sin(a); }
        }
    };
    static const Circle circle;
    PackedVector2Array points;
    points.resize(33);
    Vector2 *out = points.ptrw();
    for (int i = 0; i < 33; ++i) out[i] = center + Vector2(real_t(circle.x[i] * radius.x), real_t(circle.y[i] * radius.y)) * real_t(zoom);
    PackedColorArray colors;
    colors.append(color);
    RenderingServer::get_singleton()->canvas_item_add_polyline(canvas, points, colors, 1.5f, true);
}

void RoRReadModelKernel::_bind_methods() {
    ClassDB::bind_method(D_METHOD("supports_actor_key_cache"), &RoRReadModelKernel::supports_actor_key_cache);
    ClassDB::bind_method(D_METHOD("capture_building_control_rows", "rows", "counters"), &RoRReadModelKernel::capture_building_control_rows);
    ClassDB::bind_method(D_METHOD("clear_control_row_certificates"), &RoRReadModelKernel::clear_control_row_certificates);
    ClassDB::bind_method(D_METHOD("set_selection_meshes_enabled", "enabled"), &RoRReadModelKernel::set_selection_meshes_enabled);
    ClassDB::bind_method(D_METHOD("selection_mesh_stats"), &RoRReadModelKernel::selection_mesh_stats);
    ClassDB::bind_method(D_METHOD("control_batch_stats"), &RoRReadModelKernel::control_batch_stats);
    ClassDB::bind_method(D_METHOD("collect_combat_awareness", "world", "awareness", "tick", "delta"), &RoRReadModelKernel::collect_combat_awareness);
    ClassDB::bind_method(D_METHOD("supports_ordered_gather_controller"), &RoRReadModelKernel::supports_ordered_gather_controller);
    ClassDB::bind_method(D_METHOD("submit_world_queue", "canvas", "items", "context", "fallback"), &RoRReadModelKernel::submit_world_queue);
    ClassDB::bind_method(D_METHOD("set_motion_profiling", "enabled"), &RoRReadModelKernel::set_motion_profiling);
    ClassDB::bind_method(D_METHOD("motion_profile"), &RoRReadModelKernel::motion_profile);
    ClassDB::bind_method(D_METHOD("typed_motion_stats"), &RoRReadModelKernel::typed_motion_stats);
    ClassDB::bind_method(D_METHOD("supports_scoped_resource_digest"), &RoRReadModelKernel::supports_scoped_resource_digest);
    ClassDB::bind_method(D_METHOD("contact_frame_stats"), &RoRReadModelKernel::contact_frame_stats);
    ClassDB::bind_method(D_METHOD("settle_mobile_contacts_flat", "changes", "active_units", "all_units", "units_by_id", "buckets", "entities", "positions", "radii", "cell_size", "maximum_radius", "delta", "pending", "query_fallback", "separate", "compare"), &RoRReadModelKernel::settle_mobile_contacts_flat, DEFVAL(false));
    ClassDB::bind_method(D_METHOD("profile_storage_graph", "roots", "node_limit"), &RoRReadModelKernel::profile_storage_graph, DEFVAL(32000000));
    ClassDB::bind_method(D_METHOD("advance_checked_move_order", "unit", "movement_kernel", "delta", "map_size", "vertex_levels", "neighbors", "physical_planner", "knowledge_planner", "stop_tick"), &RoRReadModelKernel::advance_checked_move_order);
    ClassDB::bind_method(D_METHOD("get_actor_pipeline_version"), &RoRReadModelKernel::get_actor_pipeline_version);
    ClassDB::bind_method(D_METHOD("advance_ordered_unit_span", "context", "delta"), &RoRReadModelKernel::advance_ordered_unit_span);
    ClassDB::bind_method(D_METHOD("publish_active_unit_controls", "units", "units_by_id", "journal", "activity"), &RoRReadModelKernel::publish_active_unit_controls);
    ClassDB::bind_method(D_METHOD("submit_selection_run", "canvas", "items", "first", "selected", "preview", "hover", "feedback", "feedback_time", "semantic", "zoom", "shift_pressed"), &RoRReadModelKernel::submit_selection_run);
    ClassDB::bind_method(D_METHOD("submit_selection_ellipse", "canvas", "center", "color", "radius", "zoom"), &RoRReadModelKernel::submit_selection_ellipse);
    ClassDB::bind_method(D_METHOD("settle_mobile_contacts", "changes", "active_units", "all_units", "units_by_id", "buckets", "entities", "positions", "radii", "cell_size", "maximum_radius", "delta", "pending", "query_fallback", "separate"), &RoRReadModelKernel::settle_mobile_contacts);
    ClassDB::bind_method(D_METHOD("advance_native_group_motion", "unit", "movement_kernel", "delta", "map_size", "vertex_levels", "neighbors", "planner", "stop_tick"), &RoRReadModelKernel::advance_native_group_motion);
    ClassDB::bind_method(D_METHOD("occupied_resource_slots", "worker", "candidates", "size", "resources_by_cell", "reservations_by_resource", "units_by_id", "minimum_clearance", "default_clearance"), &RoRReadModelKernel::occupied_resource_slots);
    ClassDB::bind_method(D_METHOD("occupied_idle_unit_slots", "worker", "candidates", "nearby", "indices", "positions", "radii", "default_clearance"), &RoRReadModelKernel::occupied_idle_unit_slots);
    ClassDB::bind_method(D_METHOD("spatial_unit_circle", "center", "radius", "buckets", "entities", "positions", "radii", "cell_size", "maximum_radius", "result"), &RoRReadModelKernel::spatial_unit_circle);
    ClassDB::bind_method(D_METHOD("sort_active_units", "units", "orders"), &RoRReadModelKernel::sort_active_units);
    ClassDB::bind_method(D_METHOD("stable_activity_updates", "ids", "context"), &RoRReadModelKernel::stable_activity_updates);
    ClassDB::bind_method(D_METHOD("classify_activity_changes", "ids", "context"), &RoRReadModelKernel::classify_activity_changes);
    ClassDB::bind_method(D_METHOD("synchronize_spatial_units_prefix", "units", "indices", "entities", "positions", "cells", "buckets", "cell_size"), &RoRReadModelKernel::synchronize_spatial_units_prefix);
    ClassDB::bind_method(D_METHOD("spatial_unit_neighbors", "unit", "radius", "excluded_group", "buckets", "entities", "positions", "radii", "cell_size", "maximum_radius", "result"), &RoRReadModelKernel::spatial_unit_neighbors);
    ClassDB::bind_method(D_METHOD("spatial_unit_match", "unit", "radius", "mode", "buckets", "entities", "positions", "radii", "cell_size", "maximum_radius"), &RoRReadModelKernel::spatial_unit_match);
    ClassDB::bind_method(D_METHOD("autosave_entity_digests", "entities"), &RoRReadModelKernel::autosave_entity_digests);
    ClassDB::bind_method(D_METHOD("remap_player_image", "blue", "red", "source_ramp", "target_ramp"), &RoRReadModelKernel::remap_player_image);
    ClassDB::bind_method(D_METHOD("rasterize_minimap_fog", "size", "rectangle", "center", "scale", "fog"), &RoRReadModelKernel::rasterize_minimap_fog);
    ClassDB::bind_method(D_METHOD("capture_navigation_pages", "sources", "previous", "keys", "size"), &RoRReadModelKernel::capture_navigation_pages);
    ClassDB::bind_method(D_METHOD("refresh_interpolated_items", "items", "project", "alpha", "depth_index", "sprite_scale", "camera", "force_projection"), &RoRReadModelKernel::refresh_interpolated_items, DEFVAL(Array()), DEFVAL(true));
    ClassDB::bind_method(D_METHOD("cache_actor_sprites", "items", "scale"), &RoRReadModelKernel::cache_actor_sprites);
    ClassDB::bind_method(D_METHOD("cache_actor_sprites_atlased", "items", "scale", "atlas", "cache"), &RoRReadModelKernel::cache_actor_sprites_atlased);
    ClassDB::bind_method(D_METHOD("changed_combat_ids", "delta", "units", "buildings", "sources", "classifications"), &RoRReadModelKernel::changed_combat_ids);
    ClassDB::bind_method(D_METHOD("filter_visible_entities", "entities", "observer", "states", "map_size"), &RoRReadModelKernel::filter_visible_entities);
    ClassDB::bind_method(D_METHOD("project_cached_render_entities", "entities", "cache"), &RoRReadModelKernel::project_cached_render_entities);
    ClassDB::bind_method(D_METHOD("prepare_static_projection", "items", "origin", "scale"), &RoRReadModelKernel::prepare_static_projection);
    ClassDB::bind_method(D_METHOD("economy_resource_view", "resources", "buildings", "team"), &RoRReadModelKernel::economy_resource_view);
    ClassDB::bind_method(D_METHOD("reachable_cell_lookup", "navigation"), &RoRReadModelKernel::reachable_cell_lookup);
    ClassDB::bind_method(D_METHOD("refresh_resource_bucket_rows", "index", "previous", "current"), &RoRReadModelKernel::refresh_resource_bucket_rows);
    ClassDB::bind_method(D_METHOD("project_prepared_static_items", "prepared", "origin", "scale", "viewport"), &RoRReadModelKernel::project_prepared_static_items);
    ClassDB::bind_method(D_METHOD("project_visible_static_items", "items", "origin", "scale", "viewport", "clip_buildings"), &RoRReadModelKernel::project_visible_static_items, DEFVAL(false));
    ClassDB::bind_method(D_METHOD("merge_projected_static_items", "first", "second", "origin", "scale"), &RoRReadModelKernel::merge_projected_static_items);
    ClassDB::bind_method(D_METHOD("create_unit_render_items", "units", "project", "provider", "colors", "alpha", "depth_index", "preview", "selected", "camera"), &RoRReadModelKernel::create_unit_render_items, DEFVAL(Array()));
    ClassDB::bind_method(D_METHOD("create_building_render_items", "buildings", "project", "provider", "colors", "records", "preview", "selected", "observer", "scale", "affine", "cache_sprite"), &RoRReadModelKernel::create_building_render_items);
    ClassDB::bind_method(D_METHOD("clip_building_render_items", "items", "viewport"), &RoRReadModelKernel::clip_building_render_items);
    ClassDB::bind_method(D_METHOD("cache_sprite_items", "items", "scale", "origin", "atlas", "cache"), &RoRReadModelKernel::cache_sprite_items);
    ClassDB::bind_method(D_METHOD("matches_combat_classification", "entity", "classification"), &RoRReadModelKernel::matches_combat_classification);
    ClassDB::bind_method(D_METHOD("advance_harvesting_recovery", "worker", "resources", "reservations"), &RoRReadModelKernel::advance_harvesting_recovery);
    ClassDB::bind_method(D_METHOD("advance_harvesting_at_target", "worker", "resource", "reservations"), &RoRReadModelKernel::advance_harvesting_at_target);
    ClassDB::bind_method(D_METHOD("integrate_unit_motion", "unit", "delta", "map_size", "vertex_levels", "reason"), &RoRReadModelKernel::integrate_unit_motion);
    ClassDB::bind_method(D_METHOD("constrain_mobile_velocity", "unit", "velocity", "neighbors", "delta"), &RoRReadModelKernel::constrain_mobile_velocity);
    ClassDB::bind_method(D_METHOD("formation_yield_velocity", "unit", "neighbors", "delta", "planner"), &RoRReadModelKernel::formation_yield_velocity);
    ClassDB::bind_method(D_METHOD("update_route_progress", "unit", "stop_tick"), &RoRReadModelKernel::update_route_progress);
    ClassDB::bind_method(D_METHOD("advance_move_pipeline", "unit", "delta", "world", "system", "planner"), &RoRReadModelKernel::advance_move_pipeline);
    ClassDB::bind_method(D_METHOD("advance_native_motion", "unit", "movement_kernel", "delta", "map_size", "vertex_levels"), &RoRReadModelKernel::advance_native_motion);
    ClassDB::bind_method(D_METHOD("set_motion_velocities", "unit", "desired", "actual"), &RoRReadModelKernel::set_motion_velocities);
    ClassDB::bind_method(D_METHOD("resources_in_radius", "cells", "size", "origin", "radius"), &RoRReadModelKernel::resources_in_radius);
    ClassDB::bind_method(D_METHOD("owned_ai_actor_profile", "entity"), &RoRReadModelKernel::owned_ai_actor_profile);
    ClassDB::bind_method(D_METHOD("partition_render_items", "items"), &RoRReadModelKernel::partition_render_items);
    ClassDB::bind_method(D_METHOD("submit_sprite_run", "canvas", "items", "start"), &RoRReadModelKernel::submit_sprite_run);
    ClassDB::bind_method(D_METHOD("submit_sprite_batches", "canvas", "items", "start"), &RoRReadModelKernel::submit_sprite_batches);
    ClassDB::bind_method(D_METHOD("unit_depth_offset", "position", "screen_y", "index", "project"), &RoRReadModelKernel::unit_depth_offset);
    ClassDB::bind_method(D_METHOD("diff_resource_records", "previous", "current"), &RoRReadModelKernel::diff_resource_records);
    ClassDB::bind_method(D_METHOD("known_resources_in_bounds", "known", "chunks", "bounds", "chunk_size"), &RoRReadModelKernel::known_resources_in_bounds);
    ClassDB::bind_method(D_METHOD("sort_render_items", "items"), &RoRReadModelKernel::sort_render_items);
    ClassDB::bind_method(D_METHOD("reproject_static_items", "items", "origin", "previous_origin", "previous_scale", "scale"), &RoRReadModelKernel::reproject_static_items);
    ClassDB::bind_method(D_METHOD("merge_render_items", "first", "second"), &RoRReadModelKernel::merge_render_items);
    ClassDB::bind_method(D_METHOD("render_items_in_order", "items"), &RoRReadModelKernel::render_items_in_order);
    ClassDB::bind_method(D_METHOD("advance_idle_animation", "entities", "delta"), &RoRReadModelKernel::advance_idle_animation);
    ClassDB::bind_method(D_METHOD("patch_render", "source", "previous", "mask", "groups"), &RoRReadModelKernel::patch_render);
    ClassDB::bind_method(D_METHOD("project_render", "source", "previous", "fields", "nested_fields", "schema"), &RoRReadModelKernel::project_render);
    ClassDB::bind_method(D_METHOD("project_ai", "source", "previous", "observer_team", "fields", "array_fields", "private_trade_fields"), &RoRReadModelKernel::project_ai);
    ClassDB::bind_method(D_METHOD("collect_ai_projection_changes", "legal_sets", "categories", "cache", "entity_versions", "schema"), &RoRReadModelKernel::collect_ai_projection_changes);
    ClassDB::bind_method(D_METHOD("retain_ai_projection_portion", "rows", "begin", "end", "observer_team", "cache", "entity_versions", "schema"), &RoRReadModelKernel::retain_ai_projection_portion);
    ClassDB::bind_method(D_METHOD("query_resource_candidates", "buckets", "position", "resource_type", "cell_size", "maximum"), &RoRReadModelKernel::query_resource_candidates);
    ClassDB::bind_method(D_METHOD("build_resource_buckets", "resources", "domains", "unrestricted", "typed", "cell_size"), &RoRReadModelKernel::build_resource_buckets);
    ClassDB::bind_method(D_METHOD("build_site_ring_cells", "center", "radius", "size", "seen", "pages"), &RoRReadModelKernel::build_site_ring_cells);
    ClassDB::bind_method(D_METHOD("infrastructure_site_bonuses", "resources", "sites", "kind"), &RoRReadModelKernel::infrastructure_site_bonuses);
    ClassDB::bind_method(D_METHOD("foundation_intersects_structures", "footprint", "center", "structures", "replaced"), &RoRReadModelKernel::foundation_intersects_structures);
    ClassDB::bind_method(D_METHOD("walkability_mask", "size", "terrain", "terrain_ids", "occupied", "restrictions", "learned", "knowledge", "domain", "restriction"), &RoRReadModelKernel::walkability_mask);
    ClassDB::bind_method(D_METHOD("surface_components", "size", "terrain", "terrain_ids", "restrictions", "learned", "knowledge", "domain", "restriction"), &RoRReadModelKernel::surface_components);
    ClassDB::bind_method(D_METHOD("surface_component_labels", "size", "terrain", "terrain_ids", "restrictions", "learned", "knowledge", "domain", "restriction"), &RoRReadModelKernel::surface_component_labels);
    ClassDB::bind_method(D_METHOD("surface_reachability_changes", "points", "previous", "surface", "reachable", "width"), &RoRReadModelKernel::surface_reachability_changes);
    ClassDB::bind_method(D_METHOD("project_control", "source", "rendered", "observer", "fields", "private_trade_fields"), &RoRReadModelKernel::project_control);
    ClassDB::bind_method(D_METHOD("project_retained_control", "source", "rendered", "observer", "fields", "private_trade_fields", "entry", "counters", "metadata_only"), &RoRReadModelKernel::project_retained_control, DEFVAL(false));
    ClassDB::bind_method(D_METHOD("project_ui_control", "source", "rendered", "observer", "fields", "component_fields", "private_trade_fields", "entry", "counters"), &RoRReadModelKernel::project_ui_control);
    ClassDB::bind_method(D_METHOD("project_control_legacy", "source", "rendered", "observer", "fields", "private_trade_fields"), &RoRReadModelKernel::project_control_legacy);
    ClassDB::bind_method(D_METHOD("encode_replay_variant", "source", "quantize_numbers"), &RoRReadModelKernel::encode_replay_variant, DEFVAL(true));
    ClassDB::bind_method(D_METHOD("supports_capture_identity_tracking"), &RoRReadModelKernel::supports_capture_identity_tracking);
    ClassDB::bind_method(D_METHOD("capture_frozen", "source", "trusted", "track_identity"), &RoRReadModelKernel::capture_frozen, DEFVAL(true));
    ClassDB::bind_method(D_METHOD("capture_owned_frozen", "source", "trusted", "track_identity"), &RoRReadModelKernel::capture_owned_frozen, DEFVAL(true));
}

PackedByteArray RoRReadModelKernel::walkability_mask(const Vector2i &size, const Dictionary &terrain, const Dictionary &terrain_ids, const Dictionary &occupied, const Array &restrictions, const PackedByteArray &learned, bool knowledge, const String &domain, int64_t restriction) const {
    PackedByteArray result; result.resize(int64_t(size.x) * size.y); result.fill(knowledge ? 1 : 0);
    Array accessible;
    if (restriction >= 0 && restriction < restrictions.size()) {
        const Dictionary row = restrictions[restriction]; accessible = row.get(ROR_FIELD("accessible_damage_multiplier"), Array());
    }
    const auto evaluate = [&](const Vector2i &cell) {
        if (cell.x < 0 || cell.y < 0 || cell.x >= size.x || cell.y >= size.y) return;
        const int64_t index = int64_t(cell.y) * size.x + cell.x;
        if (knowledge && learned[index] == 0) return;
        bool allowed = false;
        if (!occupied.has(cell)) {
            if (restriction >= 0 && !restrictions.is_empty()) {
                int64_t id = terrain_ids.get(cell, -1);
                if (id >= 1000 && id <= 1005) id = 0;
                allowed = id >= 0 && id < accessible.size() && double(accessible[id]) > 0.05;
            } else {
                const String value = terrain.get(cell, ROR_FIELD("void"));
                const bool water = value == ROR_TEXT("water") || value == ROR_TEXT("dark_water") || value == ROR_TEXT("shallows");
                const bool land = value == ROR_TEXT("land") || value == ROR_TEXT("shore") || value == ROR_TEXT("shallows") || value == ROR_TEXT("grass") || value == ROR_TEXT("sand") || value == ROR_TEXT("forest_floor");
                allowed = domain == ROR_TEXT("water") ? water : domain == ROR_TEXT("amphibious") ? water || land : land;
            }
        }
        result.set(index, allowed ? 1 : 0);
    };
    if (knowledge) {
        const Array keys = terrain.keys();
        for (int64_t i = 0; i < keys.size(); ++i) evaluate(keys[i]);
    } else for (int y = 0; y < size.y; ++y) for (int x = 0; x < size.x; ++x) evaluate(Vector2i(x,y));
    return result;
}

Dictionary RoRReadModelKernel::surface_components(const Vector2i &size, const Dictionary &terrain, const Dictionary &terrain_ids, const Array &restrictions, const PackedByteArray &learned, bool knowledge, const String &domain, int64_t restriction) const {
    Dictionary result;
    const int64_t count = int64_t(size.x) * size.y;
    if (size.x <= 0 || size.y <= 0 || count > std::numeric_limits<int32_t>::max() || (knowledge && learned.size() != count)) return result;
    // Surface connectivity deliberately ignores occupants. Each caller supplies
    // its own legal terrain view; unknown knowledge cells remain optimistic.
    const PackedByteArray mask = walkability_mask(size, terrain, terrain_ids, Dictionary(), restrictions, learned, knowledge, domain, restriction);
    const uint8_t *allowed = mask.ptr();
    std::vector<int32_t> labels(size_t(count), -1);
    std::vector<int32_t> queue;
    queue.reserve(size_t(count));
    int32_t component = 0;
    for (int32_t root = 0; root < count; ++root) {
        if (!allowed[root] || labels[root] >= 0) continue;
        queue.clear();
        queue.push_back(root);
        labels[root] = component;
        result[Vector2i(root % size.x, root / size.x)] = int64_t(component);
        for (size_t cursor = 0; cursor < queue.size(); ++cursor) {
            const int32_t index = queue[cursor];
            const int32_t x = index % size.x, y = index / size.x;
            // Match the reference's left, right, up, down visitation and
            // Dictionary insertion order, including serialized publications.
            const int32_t adjacent[] = {x > 0 ? index - 1 : -1, x + 1 < size.x ? index + 1 : -1, y > 0 ? index - size.x : -1, y + 1 < size.y ? index + size.x : -1};
            for (const int32_t neighbor : adjacent) {
                if (neighbor < 0 || !allowed[neighbor] || labels[neighbor] >= 0) continue;
                labels[neighbor] = component;
                queue.push_back(neighbor);
                result[Vector2i(neighbor % size.x, neighbor / size.x)] = int64_t(component);
            }
        }
        ++component;
    }
    return result;
}

bool RoRReadModelKernel::foundation_intersects_structures(const Dictionary &footprint, const Vector2 &center, const Dictionary &structures, const Dictionary &replaced) const {
    const PackedVector2Array centers = structures[ROR_FIELD("centers")], halves = structures[ROR_FIELD("halves")];
    const Array cells = structures[ROR_FIELD("cells")], ids = structures[ROR_FIELD("ids")];
    const Vector2 half = footprint.get(ROR_FIELD("obstruction_half_size"), footprint.get(ROR_FIELD("half_size"), Vector2(0.5, 0.5)));
    const Array occupied = footprint.get(ROR_FIELD("occupied_cells"), Array());
    for (int64_t i = 0; i < centers.size(); ++i) {
        if (replaced.has(ids[i])) continue;
        const Vector2 delta = (centers[i] - center).abs(), existing = halves[i];
        if (delta.x < double(existing.x) + double(half.x) - 0.001 && delta.y < double(existing.y) + double(half.y) - 0.001) return true;
        const Array other = cells[i];
        for (int64_t c = 0; c < occupied.size(); ++c) if (other.has(occupied[c])) return true;
    }
    return false;
}

Dictionary RoRReadModelKernel::project_control(const Dictionary &source, const Dictionary &rendered, int64_t observer, const Array &fields, const Array &private_trade_fields) const {
    return project_control_impl(source, rendered, observer, fields, private_trade_fields, false);
}

Dictionary RoRReadModelKernel::project_control_legacy(const Dictionary &source, const Dictionary &rendered, int64_t observer, const Array &fields, const Array &private_trade_fields) const {
    return project_control_impl(source, rendered, observer, fields, private_trade_fields, true);
}

Dictionary RoRReadModelKernel::project_control_impl(const Dictionary &source, const Dictionary &rendered, int64_t observer, const Array &fields, const Array &private_trade_fields, bool legacy_copy) const {
    Dictionary result = rendered.duplicate(true);
    for (int64_t i = 0; i < fields.size(); ++i) if (source.has(fields[i])) result[fields[i]] = source[fields[i]];
    const bool own = observer <= 0 || int64_t(source.get(ROR_FIELD("team"), 0)) == observer;
    if (own && source.has(ROR_FIELD("production_queue"))) { const Array queue = source[ROR_FIELD("production_queue")]; result[ROR_FIELD("production_queue")] = queue.duplicate(true); }
    const Dictionary source_components = source.get(ROR_FIELD("components"), Dictionary());
    const Dictionary base_components = result.get(ROR_FIELD("components"), Dictionary());
    // result already owns a deep, mutable copy of every rendered component.
    // Reuse that detached subtree instead of cloning it for a second time.
    Dictionary components = legacy_copy ? base_components.duplicate(true) : base_components;
    for (const char *name : {"combat", "conversion", "healing", "resource_carrier"}) {
        const Dictionary original = source_components.get(name, Dictionary());
        Dictionary component = original.duplicate(true);
        if (String(name) == ROR_TEXT("combat")) {
            component[ROR_FIELD("target_id")] = int64_t(source.get(ROR_FIELD("target_id"), component.get(ROR_FIELD("target_id"), -1)));
            component[ROR_FIELD("cooldown")] = double(source.get(ROR_FIELD("cooldown"), component.get(ROR_FIELD("cooldown"), 0.0)));
            component[ROR_FIELD("stance")] = String(source.get(ROR_FIELD("stance"), component.get(ROR_FIELD("stance"), ROR_FIELD("passive"))));
            component[ROR_FIELD("acquisition_range")] = double(source.get(ROR_FIELD("acquisition_range"), component.get(ROR_FIELD("acquisition_range"), 0.0)));
            component[ROR_FIELD("chase_range")] = double(source.get(ROR_FIELD("chase_range"), component.get(ROR_FIELD("chase_range"), 0.0)));
            component[ROR_FIELD("retaliation_target_id")] = int64_t(source.get(ROR_FIELD("retaliation_target_id"), component.get(ROR_FIELD("retaliation_target_id"), -1)));
        } else if (String(name) == ROR_TEXT("resource_carrier")) {
            if (source.has(ROR_FIELD("amount"))) component[ROR_FIELD("amount")] = double(source[ROR_FIELD("amount")]);
            if (source.has(ROR_FIELD("carried_amount"))) component[ROR_FIELD("amount")] = double(source[ROR_FIELD("carried_amount")]);
            if (source.has(ROR_FIELD("carried_resource_type_id"))) component[ROR_FIELD("resource_type_id")] = int64_t(source[ROR_FIELD("carried_resource_type_id")]);
        }
        if (!component.is_empty()) components[name] = component;
    }
    for (const char *name : {"cargo", "trade"}) {
        const Dictionary original = source_components.get(name, Dictionary());
        if (original.is_empty()) continue;
        Dictionary component = original.duplicate(true);
        if (!own) {
            if (String(name) == ROR_TEXT("cargo")) component.erase(ROR_FIELD("passenger_ids"));
            else for (int64_t i = 0; i < private_trade_fields.size(); ++i) component.erase(private_trade_fields[i]);
        }
        components[name] = component;
    }
    if (!own) for (const char *name : {"production_progress", "rally_point", "rally_point_set", "resource_id", "dropoff_id", "worker_role_source_unit_id", "diagnostic_reason"}) result.erase(name);
    result[ROR_FIELD("components")] = components;
    return result;
}
Dictionary RoRReadModelKernel::capture_navigation_pages(const Dictionary &sources, const Dictionary &previous, const Array &keys, const Vector2i &size) const {
    const char *fields[] = {"terrain_cells", "terrain_ids", "occupied_cells", "elevation_cells", "slope_cells"};
    const Variant::Type types[] = {Variant::STRING, Variant::INT, Variant::BOOL, Variant::INT, Variant::BOOL};
    Dictionary result;
    for (int field = 0; field < 5; ++field) {
        const String name(fields[field]);
        const Dictionary source = sources.get(name, Dictionary());
        const Dictionary retained = previous.get(name, Dictionary());
        // Sharing is safe by the engine's scalar type constraints, even after
        // a publication has been evicted from the script identity registry.
        const Array retained_keys = retained.keys();
        for (int64_t i = 0; i < retained_keys.size(); ++i) {
            if (retained_keys[i].get_type() != Variant::VECTOR2I || retained[retained_keys[i]].get_type() != Variant::DICTIONARY) return Dictionary();
            const Dictionary page = retained[retained_keys[i]];
            if (!page.is_read_only() || page.get_typed_key_builtin() != Variant::VECTOR2I || page.get_typed_value_builtin() != types[field]) return Dictionary();
        }
        Dictionary pages = retained.duplicate();
        for (int64_t i = 0; i < keys.size(); ++i) {
            if (keys[i].get_type() != Variant::VECTOR2I) return Dictionary();
            const Vector2i key = keys[i];
            if (key.x < 0 || key.y < 0 || key.x * 16 >= size.x || key.y * 16 >= size.y) return Dictionary();
            Dictionary page;
            page.set_typed(Variant::VECTOR2I, StringName(), Variant(), types[field], StringName(), Variant());
            for (int y = key.y * 16; y < std::min(size.y, (key.y + 1) * 16); ++y) {
                for (int x = key.x * 16; x < std::min(size.x, (key.x + 1) * 16); ++x) {
                    const Vector2i cell(x, y);
                    if (!source.has(cell)) continue;
                    const Variant value = field == 2 ? Variant(true) : source[cell];
                    if (value.get_type() != types[field]) return Dictionary();
                    page[cell] = value;
                }
            }
            if (page.is_empty()) pages.erase(key);
            else { page.make_read_only(); pages[key] = page; }
        }
        pages.make_read_only(); result[name] = pages;
    }
    result.make_read_only();
    return result;
}

PackedByteArray RoRReadModelKernel::rasterize_minimap_fog(const Vector2i &size, const Rect2 &rectangle, const Vector2 &center, double scale, const PackedByteArray &fog) const {
    const int width = std::max(1, int(Math::round(rectangle.size.x)));
    const int height = std::max(1, int(Math::round(rectangle.size.y)));
    PackedByteArray pixels;
    pixels.resize(int64_t(width) * height * 4);
    pixels.fill(255);
    uint8_t *target = pixels.ptrw();
    for (int64_t i = 3; i < pixels.size(); i += 4) target[i] = 0;
    if (size.x <= 0 || size.y <= 0 || scale <= 0.0 || fog.size() < int64_t(size.x) * size.y) return pixels;
    const uint8_t *states = fog.ptr();
    for (int y = 0; y < height; ++y) {
        for (int x = 0; x < width; ++x) {
            const Vector2 relative = rectangle.position + Vector2(x + 0.5, y + 0.5) - center;
            const double difference = relative.x / scale, sum = relative.y * 2.0 / scale;
            const Vector2 world((sum + difference) * 0.5, (sum - difference) * 0.5);
            if (world.x < 0 || world.y < 0 || world.x >= size.x || world.y >= size.y) continue;
            const int cell_x = int(Math::floor(world.x)), cell_y = int(Math::floor(world.y));
            const int64_t offset = (int64_t(y) * width + x) * 4;
            target[offset] = target[offset + 1] = target[offset + 2] = 0;
            target[offset + 3] = states[int64_t(cell_y) * size.x + cell_x] == 0 ? 255 : uint8_t(0.58f * 255.0f);
        }
    }
    return pixels;
}

} // namespace godot


namespace godot {
PackedInt32Array RoRReadModelKernel::surface_component_labels(const Vector2i &size, const Dictionary &terrain, const Dictionary &terrain_ids, const Array &restrictions, const PackedByteArray &learned, bool knowledge, const String &domain, int64_t restriction) const {
    PackedInt32Array result;
    const int64_t count = int64_t(size.x) * size.y;
    if (size.x <= 0 || size.y <= 0 || count > std::numeric_limits<int32_t>::max() || (knowledge && learned.size() != count)) return result;
    // Same terrain-only connectivity and component numbering as surface_components.
    // Keep dense labels packed instead of allocating one Variant dictionary entry
    // for every unknown/traversable cell during a live AI observation.
    const PackedByteArray mask = walkability_mask(size, terrain, terrain_ids, Dictionary(), restrictions, learned, knowledge, domain, restriction);
    const uint8_t *allowed = mask.ptr();
    result.resize(count);
    result.fill(-1);
    int32_t *labels = result.ptrw();
    std::vector<int32_t> queue;
    queue.reserve(size_t(count));
    int32_t component = 0;
    for (int32_t root = 0; root < count; ++root) {
        if (!allowed[root] || labels[root] >= 0) continue;
        queue.clear(); queue.push_back(root); labels[root] = component;
        for (size_t cursor = 0; cursor < queue.size(); ++cursor) {
            const int32_t index = queue[cursor];
            const int32_t x = index % size.x, y = index / size.x;
            const int32_t adjacent[] = {x > 0 ? index - 1 : -1, x + 1 < size.x ? index + 1 : -1, y > 0 ? index - size.x : -1, y + 1 < size.y ? index + size.x : -1};
            for (const int32_t neighbor : adjacent) {
                if (neighbor < 0 || !allowed[neighbor] || labels[neighbor] >= 0) continue;
                labels[neighbor] = component; queue.push_back(neighbor);
            }
        }
        ++component;
    }
    return result;
}


PackedInt32Array RoRReadModelKernel::surface_reachability_changes(const Array &points, const Array &previous, const Dictionary &surface, const Dictionary &reachable, int64_t width) const {
    PackedInt32Array changed;
    if (width <= 0) return changed;
    const PackedInt32Array labels = surface.get(ROR_FIELD("labels"), PackedInt32Array());
    const int32_t *packed = labels.is_empty() ? nullptr : labels.ptr();
    int64_t old_cursor = 0;
    // Both publications are row-major; the old reachable list is a subset of
    // the old walkable points. Compare in one pass without rebuilding buckets.
    for (int64_t i = 0; i < points.size(); ++i) {
        const Vector2 point = points[i];
        const Vector2i cell(point);
        const int64_t index = int64_t(cell.y) * width + cell.x;
        const bool was_included = old_cursor < previous.size() && Vector2(previous[old_cursor]) == point;
        if (was_included) ++old_cursor;
        const int64_t component = packed && index >= 0 && index < labels.size() ? packed[index] : int64_t(surface.get(cell, -1));
        if (was_included != reachable.has(component) && index >= 0 && index <= std::numeric_limits<int32_t>::max()) changed.push_back(int32_t(index));
    }
    return changed;
}

} // namespace godot
