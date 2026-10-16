#include "ror_read_model_kernel.hpp"

#include <godot_cpp/classes/rendering_server.hpp>
#include <godot_cpp/variant/packed_int64_array.hpp>
#include <limits>
#include <algorithm>
#include <unordered_set>
#include <unordered_map>
#include <vector>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

namespace godot {
void RoRReadModelKernel::cache_actor_sprites(const Array &items, double scale) const {
    if (scale <= 0.0) return;
    static const Variant info_key("frame_info"), texture("texture"), mirrored("mirrored"), rotation("rotation"), polygon("gate_polygon");
    static const Variant kind("kind"), hotspot("hotspot"), screen_offset("screen_offset"), size("sprite_source_size"), command("sprite_command"), screen("screen_position");
    for (int64_t i = 0; i < items.size(); ++i) {
        Dictionary item = items[i];
        const String type = item[kind];
        if (type != "unit" && type != "unit_part") continue;
        const Dictionary info = item[info_key];
        Object *source_texture = info.get(texture, Variant());
        if (!source_texture || bool(info.get(mirrored, false)) || info.has(rotation) || info.has(polygon)) continue;
        const Vector2 source_size = source_texture->call("get_size");
        const Vector2 offset = info.get(screen_offset, Vector2());
        item[size] = source_size;
        item["sprite_screen_offset"] = offset;
        Array sprite;
        sprite.append(source_texture);
        sprite.append(Rect2(Vector2(item[screen]).round() + offset * scale - Vector2(item[hotspot]) * scale, source_size * scale));
        sprite.append(Color(1, 1, 1, float(item["opacity"])));
        sprite.append(source_texture->call("get_rid"));
        sprite.append(Rect2(Vector2(), source_size));
        item[command] = sprite;
    }
}

bool RoRReadModelKernel::refresh_interpolated_items(const Array &items, const Callable &project, double alpha, const Dictionary &depth_index, double sprite_scale) const {
    static const Variant kind("kind"), data("data"), id("stable_id"), pos("pos"), previous("previous_pos"), anchor("world_anchor"), screen_key("screen_position"), y("screen_y"), depth("depth_offset"), command("sprite_command");
    struct Projected { Dictionary source; Vector2 position, screen; double depth; };
    std::unordered_map<int64_t, Projected> projected;
    bool moved = false;
    alpha = std::max(0.0, std::min(1.0, alpha));
    for (int64_t i = 0; i < items.size(); ++i) {
        Dictionary item = items[i];
        const String type = item[kind];
        if (type == "environment") continue; // Ambient flight keeps its existing spline.
        const Dictionary source = item[data];
        const int64_t entity_id = item[id];
        auto found = projected.find(entity_id);
        if (found == projected.end() || !UtilityFunctions::is_same(found->second.source, source)) {
            Projected point; point.source = source;
            point.position = Vector2(source.get(previous, source.get(pos, Vector2()))).lerp(source.get(pos, Vector2()), real_t(alpha));
            point.screen = project.call(point.position);
            point.depth = unit_depth_offset(point.position, point.screen.y, depth_index, project);
            projected[entity_id] = point;
            found = projected.find(entity_id);
        }
        const Projected &point = found->second;
        if (!point.position.is_equal_approx(Vector2(item.get(anchor, point.position)))) moved = true;
        item[anchor] = point.position; item[screen_key] = point.screen;
        if (type == "unit" || type == "unit_part") item[depth] = point.depth;
        item[y] = point.screen.y + double(item.get(depth, 0.0));
        if (item.has(command)) {
            Array sprite = item[command];
            sprite[1] = Rect2(point.screen.round() + Vector2(item["sprite_screen_offset"]) * sprite_scale - Vector2(item["hotspot"]) * sprite_scale, Vector2(item["sprite_source_size"]) * sprite_scale);
        }
    }
    return moved;
}
Array RoRReadModelKernel::changed_combat_ids(const Dictionary &delta, const Dictionary &units, const Dictionary &buildings, const Dictionary &sources, const Dictionary &classifications) const {
    const Array ids = delta["ids"];
    const Dictionary masks = delta["masks"];
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
    const Dictionary journal = cache["journal"], groups = cache["groups"];
    Dictionary records = cache["records"], cached_versions = cache["versions"], categories = cache["categories"];
    const Array fields = cache["fields"], nested = cache["nested"];
    const int64_t schema = cache["schema"], capacity = cache["capacity"];
    Array result; result.resize(entities.size());
    for (int64_t i = 0; i < entities.size(); ++i) {
        const Dictionary source = entities[i];
        if (source.is_read_only() && int64_t(source.get(schema_key, -1)) == schema) { result[i] = source; continue; }
        const int64_t id = source.get(id_key, -1);
        const PackedInt64Array versions = journal.get(id, PackedInt64Array());
        const PackedInt64Array old = cached_versions.get(id, PackedInt64Array());
        Dictionary previous = records.get(id, Dictionary()), projected;
        int64_t mask = 0;
        if (Variant(versions) != Variant(old)) {
            for (int64_t g = 0; g < versions.size(); ++g) if (g >= old.size() || versions[g] != old[g]) mask |= int64_t(1) << g;
        }
        if (previous.is_empty() || (mask & (1 | 128 | 32)) || versions.is_empty()) projected = project_render(source, previous, fields, nested, schema);
        else if (!mask && double(previous.get(anim, 0.0)) == double(source.get(anim, 0.0)) && previous.get(previous_pos, Variant()) == source.get(previous_pos, Variant())) projected = previous;
        else projected = patch_render(source, previous, mask, groups);
        if (id >= 0 && (records.has(id) || records.size() < capacity)) {
            records[id] = projected; cached_versions[id] = versions;
            const String declared = projected.get(type, "unit");
            categories[id] = declared == "resource" ? "resource" : (declared == "building" || declared == "foundation" ? "building" : "unit");
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
            if (viewport.has_area() && (bool(item.get(clip, false)) || (clip_buildings && (type == "building" || type == "building_part"))) && !viewport.intersects(rectangle, true)) continue;
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
        double alpha, const Dictionary &depth_index, const Array &preview, const Array &selected) const {
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
        value[wall] = String(entity.get(kind, "")) == "wall"; value[data] = entity; value[info_key] = info;
        return value;
    };
    for (int64_t i = 0; i < units.size(); ++i) {
        const Dictionary unit = units[i];
        const String death = unit.get(phase, "alive");
        if (double(unit.get(hp, 0.0)) <= 0.0 && death != "dying" && death != "corpse") continue;
        const Vector2 position = Vector2(unit.get(previous, unit[pos])).lerp(unit[pos], real_t(std::max(0.0, std::min(1.0, alpha))));
        const Vector2 screen = project.call(position);
        const double offset = unit_depth_offset(position, screen.y, depth_index, project);
        Vector2 sort_screen = screen; sort_screen.y += offset;
        Dictionary info;
        if (provider.is_valid()) {
            const Variant provided = provider.call(String("unit"), unit);
            if (provided.get_type() == Variant::DICTIONARY) info = provided;
        }
        const int64_t entity_id = unit[id], owner = unit.get(team, 0);
        const double height = unit.get(elevation, 0.0);
        if (!team_colors.has(owner)) team_colors[owner] = colors.call(owner);
        const Color color = team_colors[owner];
        if (death != "corpse") result.append(item("shadow", 3, position, screen, entity_id, unit, Dictionary(), height, Color(0, 0, 0, 0.32), 0));
        const int64_t base_order = int64_t(info.get(graphic_layer, 20)) * 1000;
        Dictionary body = item("unit", 4, position, screen, entity_id, unit, info, height, color, base_order);
        body[y] = double(sort_screen.y); body[depth] = offset; result.append(body);
        const Array overlays = info.get(parts, Array());
        for (int64_t part = 0; part < overlays.size(); ++part) {
            const Dictionary overlay = overlays[part];
            Dictionary body_part = item("unit_part", 4, position, screen, entity_id, unit, overlay, height, color, int64_t(overlay.get(graphic_layer, 20)) * 1000 + part + 1);
            body_part[y] = double(sort_screen.y); body_part[depth] = offset; result.append(body_part);
        }
        const bool chosen = selected_ids.find(entity_id) != selected_ids.end() || bool(unit.get("selected", false)) || preview_ids.find(entity_id) != preview_ids.end();
        if (death == "alive" && (chosen || preview_ids.find(entity_id) != preview_ids.end()))
            result.append(item("selection", 2, position, screen, entity_id, unit, info, height, color, 1));
        if (death == "alive" && chosen)
            result.append(item("health_bar", 7, position, screen, entity_id, unit, info, height, color, 2));
    }
    return result;
}

bool RoRReadModelKernel::matches_combat_classification(const Dictionary &entity, const Array &previous) const {
    if (previous.size() != 12) return false;
    static const Variant hp("hp"), pos("pos"), team("team"), combat("combat_enabled"), task("task"), target("target_id"), retaliation("retaliation_target_id");
    static const Variant pursuit("combat_pursuit"), stance("stance"), autonomous("attack_autonomous"), tags("behavior_tags"), radius("footprint_radius");
    return bool(previous[0]) == (double(entity.get(hp, 0.0)) > 0.0) &&
        Vector2i(previous[1]) == Vector2i((Vector2(entity.get(pos, Vector2())) / 4.0).floor()) &&
        int64_t(previous[2]) == int64_t(entity.get(team, 0)) &&
        bool(previous[3]) == bool(entity.get(combat, false)) &&
        String(previous[4]) == String(entity.get(task, "idle")) &&
        int64_t(previous[5]) == int64_t(entity.get(target, -1)) &&
        int64_t(previous[6]) == int64_t(entity.get(retaliation, -1)) &&
        bool(previous[7]) == bool(entity.get(pursuit, false)) &&
        String(previous[8]) == String(entity.get(stance, "passive")) &&
        bool(previous[9]) == bool(entity.get(autonomous, false)) &&
        previous[10] == entity.get(tags, Array()) &&
        double(previous[11]) == double(entity.get(radius, 0.0));
}

int64_t RoRReadModelKernel::advance_harvesting_recovery(Dictionary worker, const Dictionary &resources, const Dictionary &reservations) const {
    static const Variant components("components"), worker_key("worker"), enabled("enabled"), stage("gather_stage"), work("work"), resource_id("resource_id");
    static const Variant amount("amount"), capacity("carry_capacity"), carried("carried_amount"), pos("pos"), domain("movement_domain"), radius("footprint_radius"), slot_key("resource_approach_slot");
    static const Variant order_key("order"), completed("completed"), phase("phase"), history("history");
    if (double(worker.get(work, 0.0)) <= 0.0 || String(worker.get(stage, "")) == "returning") return -1;
    const Dictionary parts = worker.get(components, Dictionary()), role = parts.get(worker_key, Dictionary());
    if (!bool(role.get(enabled, false))) return -1;
    const Variant resource_value = resources.get(worker.get(resource_id, -1), Variant());
    if (resource_value.get_type() != Variant::DICTIONARY) return -1;
    const Dictionary resource = resource_value;
    if (int64_t(resource.get(amount, 0)) <= 0) return -1;
    const double limit = std::max(0.0, double(worker.get(capacity, 0.0)));
    if (limit > 0.0 && double(worker.get(carried, 0.0)) >= limit - 0.0001) return -1;
    const Vector2 position = worker[pos], target = resource[pos], local = position - Vector2(Vector2i(position));
    bool in_range = true;
    if (String(worker.get(domain, "land")) != "water" && (Vector2i(position) == Vector2i(target) || local.x < 0.12 || local.x > 0.88 || local.y < 0.12 || local.y > 0.88)) in_range = false;
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
        if (bool(order.get(completed, true)) || String(order.get(phase, "")) == next) return;
        order[phase] = String(next);
        Array phases = order.get(history, Array());
        phases.append(String(next));
        if (phases.size() > 32) phases.pop_front();
        order[history] = phases;
        mask |= 68; // ACTIVITY | CONTROL, sampled at the owner-thread boundary.
    };
    put(stage, String("harvesting"), 96);
    transition("FaceTarget");
    const Vector2 difference = target - position;
    if (difference.length_squared() > 0.0001) {
        const Vector2 screen((difference.x - difference.y) * 32.0, (difference.x + difference.y) * 16.0);
        const int64_t facing = (int64_t(std::round(std::atan2(-double(screen.x), double(screen.y)) / (6.283185307179586476925286766559 / 8.0))) % 8 + 8) % 8;
        put(String("desired_facing"), facing, 96);
        put(String("action_facing"), facing, 96);
        put(String("facing"), facing, 2);
    }
    transition("Recover");
    return mask;
}

Dictionary RoRReadModelKernel::partition_render_items(const Array &items) const {
    static const Variant kind("kind"), data("data"), domain("movement_domain"), presentation("presentation_layer");
    Array statics, moving, ambient;
    for (int64_t i = 0; i < items.size(); ++i) {
        const Dictionary item = items[i];
        const String type = item[kind];
        const Dictionary entity = item.get(data, Dictionary());
        const bool dynamic = type == "projectile" ||
                ((type == "unit" || type == "unit_part" || type == "shadow" || type == "selection" || type == "health_bar") && String(entity.get(domain, "land")) != "static") ||
                (type == "environment" && String(entity.get(presentation, "scenery")) == "ambient_actor");
        if (dynamic) moving.append(item); else statics.append(item);
        if (type == "environment" && dynamic) ambient.append(item);
    }
    Dictionary result; result["static"] = statics; result["moving"] = moving; result["ambient"] = ambient; return result;
}

int64_t RoRReadModelKernel::submit_sprite_run(const RID &canvas, const Array &items, int64_t start) const {
    RenderingServer *server = RenderingServer::get_singleton();
    static const Variant command("sprite_command");
    while (start < items.size()) {
        const Dictionary item = items[start];
        if (!item.has(command)) break;
        const Array sprite = item[command];
        if (sprite.size() < 5) break;
        server->canvas_item_add_texture_rect_region(canvas, sprite[1], sprite[3], sprite[4], sprite[2], false, true);
        ++start;
    }
    return start;
}

double RoRReadModelKernel::unit_depth_offset(const Vector2 &position, double screen_y, const Dictionary &index, const Callable &project) const {
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
            const double depth = Vector2(project.call(segment[depth_key])).y;
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
        if (offset.x >= half.x || offset.y >= half.y) adjusted = std::max(adjusted, double(Vector2(project.call(center)).y) + 0.01);
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

Dictionary RoRReadModelKernel::diff_resource_records(const Array &previous, const Array &current) const {
    static const Variant id("id"), tags("behavior_tags");
    Dictionary result;
    result["valid"] = false;
    if (!previous.is_read_only() || !current.is_read_only()) return result;
    Array changed, removed;
    int64_t old = 0;
    int64_t last_id = -1;
    for (int64_t i = 0; i < current.size(); ++i) {
        const Dictionary row = current[i];
        if (!row.is_read_only() || (row.has(tags) && (row[tags].get_type() != Variant::ARRAY || !Array(row[tags]).is_read_only()))) return result;
        const int64_t next = row[id];
        if (next <= last_id) return result;
        last_id = next;
        while (old < previous.size() && int64_t(Dictionary(previous[old])[id]) < next) {
            removed.append(Dictionary(previous[old++])[id]);
        }
        if (old < previous.size() && int64_t(Dictionary(previous[old])[id]) == next) {
            if (!UtilityFunctions::is_same(row, previous[old])) changed.append(row);
            ++old;
        } else changed.append(row);
    }
    while (old < previous.size()) removed.append(Dictionary(previous[old++])[id]);
    result["valid"] = true;
    result["changed"] = changed;
    result["removed"] = removed;
    return result;
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

Array RoRReadModelKernel::merge_render_items(const Array &first, const Array &second) const {
    static const Variant layer("layer"), y("screen_y"), elevation("elevation"), sub("sub_order");
    static const Variant wall("wall_depth_tie"), anchor("world_anchor"), id("stable_id");
    struct Head { Dictionary row; int64_t layer; double depth; };
    const auto read = [&](const Array &items, int64_t index) {
        Head head; head.row = items[index]; head.layer = head.row[layer]; head.depth = head.row[y]; return head;
    };
    const auto less = [&](const Head &left, const Head &right) {
        if (left.layer != right.layer) return left.layer < right.layer;
        if (!Math::is_equal_approx(left.depth, right.depth)) return left.depth < right.depth;
        const Dictionary &a = left.row, &b = right.row;
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
    };
    Array result; result.resize(first.size() + second.size());
    int64_t a = 0, b = 0, output = 0;
    if (!first.is_empty() && !second.is_empty()) {
        Head left = read(first, 0), right = read(second, 0);
        while (a < first.size() && b < second.size()) {
            if (less(left, right)) {
                result[output++] = first[a++];
                if (a < first.size()) left = read(first, a);
            } else {
                result[output++] = second[b++];
                if (b < second.size()) right = read(second, b);
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
        if (previous != "Idle") {
            entity[state] = String("Idle");
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

namespace {

// Validate, detach and freeze in one traversal. A readonly flag or copied marker
// is not a certificate: only exact validated roots or scalar typed maps are shared.
struct Capture {
    const Array &trusted;
    std::vector<bool> shared;
    bool valid = true;

    explicit Capture(const Array &roots) : trusted(roots), shared(roots.size(), false) {}

    bool trusted_identity(const Variant &value) {
        for (int64_t i = 0; i < trusted.size(); ++i) {
            if (UtilityFunctions::is_same(value, trusted[i])) {
                shared[i] = true;
                return true;
            }
        }
        return false;
    }

    Variant run(const Variant &value, int depth = 0) {
        if (!valid || depth > 64) {
            valid = false;
            return Variant();
        }
        switch (value.get_type()) {
            case Variant::OBJECT:
            case Variant::CALLABLE:
            case Variant::RID:
            case Variant::SIGNAL:
                valid = false;
                return Variant();
            case Variant::DICTIONARY: {
                const Dictionary source = value;
                const auto value_type = source.get_typed_value_builtin();
                const bool scalar_cells = source.get_typed_key_builtin() == Variant::VECTOR2I &&
                        (value_type == Variant::BOOL || value_type == Variant::INT || value_type == Variant::STRING);
                if (source.is_read_only() && (scalar_cells || trusted_identity(value))) {
                    return value;
                }
                Dictionary result = source.duplicate(false);
                result.clear();
                const Array keys = source.keys();
                for (int64_t i = 0; i < keys.size(); ++i) {
                    Variant key = run(keys[i], depth + 1);
                    Variant item = run(source[keys[i]], depth + 1);
                    if (!valid) {
                        return Variant();
                    }
                    result[key] = item;
                }
                result.make_read_only();
                return result;
            }
            case Variant::ARRAY: {
                const Array source = value;
                const bool scalar_points = source.is_typed() &&
                        (source.get_typed_builtin() == Variant::VECTOR2 || source.get_typed_builtin() == Variant::VECTOR2I);
                if (source.is_read_only() && (scalar_points || trusted_identity(value))) {
                    return value;
                }
                Array result = source.duplicate(false);
                for (int64_t i = 0; i < source.size(); ++i) {
                    Variant item = run(source[i], depth + 1);
                    if (!valid) {
                        return Variant();
                    }
                    result[i] = item;
                }
                result.make_read_only();
                return result;
            }
            // Packed arrays share their mutable reference through Variant. They
            // require an explicit duplicate even inside a readonly Dictionary.
            case Variant::PACKED_BYTE_ARRAY: return PackedByteArray(value).duplicate();
            case Variant::PACKED_INT32_ARRAY: return PackedInt32Array(value).duplicate();
            case Variant::PACKED_INT64_ARRAY: return PackedInt64Array(value).duplicate();
            case Variant::PACKED_FLOAT32_ARRAY: return PackedFloat32Array(value).duplicate();
            case Variant::PACKED_FLOAT64_ARRAY: return PackedFloat64Array(value).duplicate();
            case Variant::PACKED_STRING_ARRAY: return PackedStringArray(value).duplicate();
            case Variant::PACKED_VECTOR2_ARRAY: return PackedVector2Array(value).duplicate();
            case Variant::PACKED_VECTOR3_ARRAY: return PackedVector3Array(value).duplicate();
            case Variant::PACKED_VECTOR4_ARRAY: return PackedVector4Array(value).duplicate();
            case Variant::PACKED_COLOR_ARRAY: return PackedColorArray(value).duplicate();
            default: return value; // Remaining types have value semantics.
        }
    }
};

String entity_type(const Dictionary &source) {
    String declared = source.get("entity_type", "");
    if (!declared.is_empty()) {
        return declared;
    }
    if (source.has("production_queue")) {
        return "building";
    }
    if (source.has("resource_type_id") && (source.has("amount") || !source.has("team"))) {
        return "resource";
    }
    return "unit";
}

} // namespace

void RoRReadModelKernel::_bind_methods() {
    ClassDB::bind_method(D_METHOD("refresh_interpolated_items", "items", "project", "alpha", "depth_index", "sprite_scale"), &RoRReadModelKernel::refresh_interpolated_items);
    ClassDB::bind_method(D_METHOD("cache_actor_sprites", "items", "scale"), &RoRReadModelKernel::cache_actor_sprites);
    ClassDB::bind_method(D_METHOD("changed_combat_ids", "delta", "units", "buildings", "sources", "classifications"), &RoRReadModelKernel::changed_combat_ids);
    ClassDB::bind_method(D_METHOD("filter_visible_entities", "entities", "observer", "states", "map_size"), &RoRReadModelKernel::filter_visible_entities);
    ClassDB::bind_method(D_METHOD("project_cached_render_entities", "entities", "cache"), &RoRReadModelKernel::project_cached_render_entities);
    ClassDB::bind_method(D_METHOD("prepare_static_projection", "items", "origin", "scale"), &RoRReadModelKernel::prepare_static_projection);
    ClassDB::bind_method(D_METHOD("project_prepared_static_items", "prepared", "origin", "scale", "viewport"), &RoRReadModelKernel::project_prepared_static_items);
    ClassDB::bind_method(D_METHOD("project_visible_static_items", "items", "origin", "scale", "viewport", "clip_buildings"), &RoRReadModelKernel::project_visible_static_items, DEFVAL(false));
    ClassDB::bind_method(D_METHOD("merge_projected_static_items", "first", "second", "origin", "scale"), &RoRReadModelKernel::merge_projected_static_items);
    ClassDB::bind_method(D_METHOD("create_unit_render_items", "units", "project", "provider", "colors", "alpha", "depth_index", "preview", "selected"), &RoRReadModelKernel::create_unit_render_items);
    ClassDB::bind_method(D_METHOD("matches_combat_classification", "entity", "classification"), &RoRReadModelKernel::matches_combat_classification);
    ClassDB::bind_method(D_METHOD("advance_harvesting_recovery", "worker", "resources", "reservations"), &RoRReadModelKernel::advance_harvesting_recovery);
    ClassDB::bind_method(D_METHOD("partition_render_items", "items"), &RoRReadModelKernel::partition_render_items);
    ClassDB::bind_method(D_METHOD("submit_sprite_run", "canvas", "items", "start"), &RoRReadModelKernel::submit_sprite_run);
    ClassDB::bind_method(D_METHOD("unit_depth_offset", "position", "screen_y", "index", "project"), &RoRReadModelKernel::unit_depth_offset);
    ClassDB::bind_method(D_METHOD("diff_resource_records", "previous", "current"), &RoRReadModelKernel::diff_resource_records);
    ClassDB::bind_method(D_METHOD("sort_render_items", "items"), &RoRReadModelKernel::sort_render_items);
    ClassDB::bind_method(D_METHOD("reproject_static_items", "items", "origin", "previous_origin", "previous_scale", "scale"), &RoRReadModelKernel::reproject_static_items);
    ClassDB::bind_method(D_METHOD("merge_render_items", "first", "second"), &RoRReadModelKernel::merge_render_items);
    ClassDB::bind_method(D_METHOD("advance_idle_animation", "entities", "delta"), &RoRReadModelKernel::advance_idle_animation);
    ClassDB::bind_method(D_METHOD("patch_render", "source", "previous", "mask", "groups"), &RoRReadModelKernel::patch_render);
    ClassDB::bind_method(D_METHOD("project_render", "source", "previous", "fields", "nested_fields", "schema"), &RoRReadModelKernel::project_render);
    ClassDB::bind_method(D_METHOD("project_ai", "source", "previous", "observer_team", "fields", "array_fields", "private_trade_fields"), &RoRReadModelKernel::project_ai);
    ClassDB::bind_method(D_METHOD("encode_replay_variant", "source", "quantize_numbers"), &RoRReadModelKernel::encode_replay_variant, DEFVAL(true));
    ClassDB::bind_method(D_METHOD("capture_frozen", "source", "trusted"), &RoRReadModelKernel::capture_frozen);
}

Dictionary RoRReadModelKernel::patch_render(const Dictionary &source, const Dictionary &previous, int64_t mask, const Dictionary &groups) const {
    Dictionary result = previous;
    bool edited = false;
    const auto put = [&](const Variant &key, const Variant &value) {
        if (previous.has(key) && previous[key] == value) return;
        if (!edited) { result = previous.duplicate(); edited = true; }
        result[key] = value;
    };
    const Array keys = groups.keys();
    for (int64_t i = 0; i < keys.size(); ++i) {
        if (!(mask & int64_t(keys[i]))) continue;
        const Array fields = groups[keys[i]];
        for (int64_t field = 0; field < fields.size(); ++field) {
            const Variant key = fields[field];
            if (source.has(key)) put(key, source[key]);
            else if (result.has(key)) {
                if (!edited) { result = previous.duplicate(); edited = true; }
                result.erase(key);
            }
        }
    }
    static const Variant anim("anim"), previous_pos("previous_pos");
    put(anim, double(source.get(anim, 0.0)));
    if (source.has(previous_pos)) put(previous_pos, source[previous_pos]);
    if (edited) result.make_read_only();
    return result;
}

Dictionary RoRReadModelKernel::project_render(const Dictionary &source, const Dictionary &previous,
        const Array &fields, const Array &nested_fields, int64_t schema) const {
    static const Variant k_entity_type("entity_type");
    static const Variant k__ror_render_schema("_ror_render_schema");
    static const Variant k_components("components");
    static const Variant k_ownership("ownership");
    static const Variant k_civilization_id("civilization_id");
    static const Variant k_enabled("enabled");
    static const Variant k_cargo("cargo");
    static const Variant k_capacity("capacity");
    static const Variant k_trade("trade");
    static const Variant k_target_building_source_id("target_building_source_id");
    Dictionary result;
    for (int64_t i = 0; i < fields.size(); ++i) {
        if (source.has(fields[i])) {
            result[fields[i]] = source[fields[i]];
        }
    }
    result[k_entity_type] = entity_type(source);
    result[k__ror_render_schema] = schema;
    for (int64_t i = 0; i < nested_fields.size(); ++i) {
        if (source.has(nested_fields[i])) {
            result[nested_fields[i]] = source[nested_fields[i]];
        }
    }
    const Dictionary components = source.get(k_components, Dictionary());
    Dictionary projected;
    const Dictionary ownership = components.get(k_ownership, Dictionary());
    if (!ownership.is_empty()) {
        Dictionary row;
        row[k_civilization_id] = int64_t(ownership.get(k_civilization_id, 13));
        projected[k_ownership] = row;
    }
    for (const char *name : {"worker", "conversion", "healing"}) {
        const Dictionary input = components.get(name, Dictionary());
        if (!input.is_empty()) {
            Dictionary row;
            row[k_enabled] = bool(input.get(k_enabled, false));
            projected[name] = row;
        }
    }
    const Dictionary cargo = components.get(k_cargo, Dictionary());
    if (!cargo.is_empty()) {
        Dictionary row;
        row[k_enabled] = bool(cargo.get(k_enabled, false));
        row[k_capacity] = std::max(int64_t(0), int64_t(cargo.get(k_capacity, 0)));
        projected[k_cargo] = row;
    }
    const Dictionary trade = components.get(k_trade, Dictionary());
    if (!trade.is_empty()) {
        Dictionary row;
        row[k_enabled] = bool(trade.get(k_enabled, false));
        row[k_target_building_source_id] = int64_t(trade.get(k_target_building_source_id, -1));
        projected[k_trade] = row;
    }
    result[k_components] = projected;
    if (previous.is_read_only() && previous == result) {
        return previous;
    }
    // Unchanged children remain immutable. Only changed containers are detached.
    const Array keys = result.keys();
    const Array no_trusted_roots;
    Capture capture(no_trusted_roots);
    for (int64_t i = 0; i < keys.size(); ++i) {
        Variant key = keys[i];
        Variant item = result[key];
        if (previous.is_read_only() && previous.has(key) && previous[key] == item) {
            result[key] = previous[key];
        } else if (item.get_type() == Variant::DICTIONARY || item.get_type() == Variant::ARRAY || item.get_type() >= Variant::PACKED_BYTE_ARRAY) {
            result[key] = capture.run(item);
            if (!capture.valid) {
                return Dictionary();
            }
        }
    }
    result.make_read_only();
    return result;
}

Dictionary RoRReadModelKernel::project_ai(const Dictionary &source, const Dictionary &previous,
        int64_t observer_team, const Array &fields, const Array &array_fields, const Array &private_trade_fields) const {
    static const Variant k_team("team");
    static const Variant k_components("components");
    static const Variant k_worker("worker");
    static const Variant k_enabled("enabled");
    static const Variant k_order("order");
    static const Variant k_type("type");
    static const Variant k_target_entity_id("target_entity_id");
    static const Variant k_completed("completed");
    static const Variant k_completion_reason("completion_reason");
    static const Variant k_healing("healing");
    static const Variant k_combat("combat");
    static const Variant k_projectile_id("projectile_id");
    static const Variant k_blast_range("blast_range");
    static const Variant k_cargo("cargo");
    static const Variant k_capacity("capacity");
    static const Variant k_allow_allied("allow_allied");
    static const Variant k_allow_artifacts("allow_artifacts");
    static const Variant k_passenger_ids("passenger_ids");
    static const Variant k_trade("trade");
    static const Variant k_production_queue("production_queue");
    static const Variant k_order_type("order_type");
    static const Variant k_kind("kind");
    static const Variant k_technology_id("technology_id");
    static const Variant k_status("status");
    static const Variant k_population_cost("population_cost");
    static const Variant k_entity_type("entity_type");
    Dictionary result;
    for (int64_t i = 0; i < fields.size(); ++i) {
        if (source.has(fields[i])) result[fields[i]] = source[fields[i]];
    }
    const bool own = observer_team <= 0 || int64_t(source.get(k_team, 0)) == observer_team;
    if (own) {
        for (const char *field : {"resource_id", "path_request_id"}) {
            if (source.has(field)) result[field] = int64_t(source[field]);
        }
    }
    for (int64_t i = 0; i < array_fields.size(); ++i) {
        if (source.has(array_fields[i])) result[array_fields[i]] = source[array_fields[i]];
    }
    const Dictionary components = source.get(k_components, Dictionary());
    Dictionary projected;
    const Dictionary worker = components.get(k_worker, Dictionary());
    Dictionary worker_row;
    worker_row[k_enabled] = bool(worker.get(k_enabled, false));
    projected[k_worker] = worker_row;
    if (own) {
        const Dictionary order = components.get(k_order, Dictionary());
        if (!order.is_empty()) {
            Dictionary row;
            row[k_type] = String(order.get(k_type, "none"));
            row[k_target_entity_id] = int64_t(order.get(k_target_entity_id, -1));
            row[k_completed] = bool(order.get(k_completed, true));
            row[k_completion_reason] = String(order.get(k_completion_reason, ""));
            projected[k_order] = row;
        }
    }
    const Dictionary healing = components.get(k_healing, Dictionary());
    if (bool(healing.get(k_enabled, false))) {
        Dictionary row;
        row[k_enabled] = true;
        projected[k_healing] = row;
    }
    const Dictionary combat = components.get(k_combat, Dictionary());
    if (!combat.is_empty()) {
        Dictionary row;
        row[k_projectile_id] = int64_t(source.get(k_projectile_id, combat.get(k_projectile_id, -1)));
        row[k_blast_range] = double(source.get(k_blast_range, combat.get(k_blast_range, 0.0)));
        projected[k_combat] = row;
    }
    const Dictionary cargo = components.get(k_cargo, Dictionary());
    if (bool(cargo.get(k_enabled, false))) {
        Dictionary row;
        row[k_enabled] = true;
        row[k_capacity] = std::max(int64_t(0), int64_t(cargo.get(k_capacity, 0)));
        row[k_allow_allied] = bool(cargo.get(k_allow_allied, true));
        row[k_allow_artifacts] = bool(cargo.get(k_allow_artifacts, true));
        if (own) row[k_passenger_ids] = cargo.get(k_passenger_ids, Array());
        projected[k_cargo] = row;
    }
    const Dictionary trade = components.get(k_trade, Dictionary());
    if (bool(trade.get(k_enabled, false))) {
        Dictionary row;
        row[k_enabled] = true;
        if (own) {
            for (int64_t i = 0; i < private_trade_fields.size(); ++i) {
                if (trade.has(private_trade_fields[i])) row[private_trade_fields[i]] = trade[private_trade_fields[i]];
            }
        }
        projected[k_trade] = row;
    }
    result[k_components] = projected;
    if (own && source.has(k_production_queue)) {
        const Array source_queue = source[k_production_queue];
        Array queue;
        for (int64_t i = 0; i < source_queue.size(); ++i) {
            const Dictionary order = source_queue[i];
            Dictionary row;
            row[k_order_type] = String(order.get(k_order_type, "unit"));
            row[k_kind] = String(order.get(k_kind, ""));
            row[k_technology_id] = int64_t(order.get(k_technology_id, -1));
            row[k_status] = String(order.get(k_status, "queued"));
            row[k_population_cost] = int64_t(order.get(k_population_cost, 0));
            queue.push_back(row);
        }
        result[k_production_queue] = queue;
    }
    result[k_entity_type] = entity_type(source);
    if (previous.is_read_only() && previous == result) return previous;
    // Unchanged children remain immutable. Only changed containers are detached.
    const Array keys = result.keys();
    const Array no_trusted_roots;
    Capture capture(no_trusted_roots);
    for (int64_t i = 0; i < keys.size(); ++i) {
        Variant key = keys[i];
        Variant item = result[key];
        if (previous.is_read_only() && previous.has(key) && previous[key] == item) {
            result[key] = previous[key];
        } else if (item.get_type() == Variant::DICTIONARY || item.get_type() == Variant::ARRAY || item.get_type() >= Variant::PACKED_BYTE_ARRAY) {
            result[key] = capture.run(item);
            if (!capture.valid) {
                return Dictionary();
            }
        }
    }
    result.make_read_only();
    return result;
}

namespace {
// Exact legacy JSON shape. Ambiguous stringified keys fall back to the reference.
Variant encode_replay_value(const Variant &source, bool quantize, bool &valid, int depth) {
    if (depth > 64) { valid = false; return Variant(); }
    if (source.get_type() == Variant::VECTOR2) {
        const Vector2 point = source;
        Array values;
        values.push_back(quantize ? UtilityFunctions::snappedf(point.x, 0.000001) : double(point.x));
        values.push_back(quantize ? UtilityFunctions::snappedf(point.y, 0.000001) : double(point.y));
        Dictionary result; result["__vector2"] = values; return result;
    }
    if (source.get_type() == Variant::VECTOR2I) {
        const Vector2i point = source;
        Array values; values.push_back(int64_t(point.x)); values.push_back(int64_t(point.y));
        Dictionary result; result["__vector2i"] = values; return result;
    }
    if (source.get_type() == Variant::DICTIONARY) {
        const Dictionary input = source;
        const Array keys = input.keys();
        std::vector<std::pair<String, Variant>> sorted;
        sorted.reserve(static_cast<size_t>(keys.size()));
        for (int64_t i = 0; i < keys.size(); ++i) sorted.emplace_back(UtilityFunctions::str(keys[i]), keys[i]);
        std::sort(sorted.begin(), sorted.end(), [](const std::pair<String, Variant> &a, const std::pair<String, Variant> &b) { return a.first < b.first; });
        Dictionary result;
        for (const auto &item : sorted) {
            if (result.has(item.first)) { valid = false; return Variant(); }
            result[item.first] = encode_replay_value(input[item.second], quantize, valid, depth + 1);
            if (!valid) return Variant();
        }
        return result;
    }
    if (source.get_type() == Variant::ARRAY) {
        const Array input = source;
        Array result; result.resize(input.size());
        for (int64_t i = 0; i < input.size(); ++i) {
            result[i] = encode_replay_value(input[i], quantize, valid, depth + 1);
            if (!valid) return Variant();
        }
        return result;
    }
    if (source.get_type() == Variant::FLOAT && quantize) return UtilityFunctions::snappedf(double(source), 0.000001);
    return source;
}
}

Dictionary RoRReadModelKernel::encode_replay_variant(const Variant &source, bool quantize_numbers) const {
    bool valid = true;
    const Variant value = encode_replay_value(source, quantize_numbers, valid, 0);
    Dictionary result; result["valid"] = valid; result["value"] = value; return result;
}

Dictionary RoRReadModelKernel::capture_frozen(const Variant &source, const Array &trusted) const {
    Capture capture(trusted);
    const Variant value = capture.run(source);
    PackedInt32Array shared_indices;
    for (int64_t i = 0; i < trusted.size(); ++i) {
        if (capture.shared[i]) {
            shared_indices.push_back(int32_t(i));
        }
    }
    Dictionary result;
    result["valid"] = capture.valid;
    result["value"] = capture.valid ? value : Variant();
    result["shared_indices"] = shared_indices;
    return result;
}

} // namespace godot
