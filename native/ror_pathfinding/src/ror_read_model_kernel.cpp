#include "ror_read_model_kernel.hpp"

#include <godot_cpp/classes/rendering_server.hpp>
#include <godot_cpp/variant/packed_int64_array.hpp>
#include <limits>
#include <algorithm>
#include <unordered_set>
#include <unordered_map>
#include <vector>
#include <map>
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
        value[kind] = String(type); value["layer"] = layer; value[elevation] = height;
        value["world_anchor"] = position; value[screen_key] = screen; value[y] = double(screen.y); value["stable_id"] = entity_id;
        value["frame"] = int64_t(info.get("frame_index", 0)); value["hotspot"] = info.get("hotspot", Vector2());
        value["player_color"] = color; value["opacity"] = 1.0; value["sub_order"] = sub;
        value["wall_depth_tie"] = String(actor.get(kind, "")) == "wall";
        value[data] = actor; value[info_key] = info; return value;
    };
    for (int64_t i = 0; i < buildings.size(); ++i) {
        const Dictionary building = buildings[i];
        const String phase = building.get("death_phase", "removed");
        if (double(building[hp]) <= 0.0 && phase != "dying" && phase != "ruin") continue;
        const Vector2 position = building[pos], screen = project.call(position);
        const Dictionary info = frame("building", building);
        const int64_t entity_id = building[id];
        const double height = building.get(elevation, 0.0);
        const bool ruin = phase == "ruin";
        const bool interior = bool(building.get("harvestable", false)) || ruin, selected_actor = chosen.count(entity_id), previewed = highlighted.count(entity_id);
        const bool has_rally = selected_actor && bool(building.get("rally_point_set", false));
        const int64_t order = int64_t(info.get(graphic_layer, 20)) * 1000 - (interior ? 100 : 0);
        present.insert(entity_id);
        Dictionary retained = records.get(entity_id, Dictionary());
        const int64_t info_signature = info.is_read_only() && UtilityFunctions::is_same(retained.get(info_key, Variant()), info)
                ? int64_t(retained[info_signature_key]) : UtilityFunctions::hash(info);
        Array signature_parts;
        signature_parts.append(info_signature); signature_parts.append(position); signature_parts.append(height);
        signature_parts.append(String(building.get(kind, ""))); signature_parts.append(interior);
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
        const Array parts = info.get("composite_parts", Array());
        for (int64_t j = 0; j < parts.size(); ++j) {
            const Dictionary part = parts[j];
            const String role = part.get("presentation_layer", "");
            const int64_t layer = role == "shadow" ? 3 : ((role == "upright" && !ruin) || !interior ? 4 : 1);
            Dictionary sprite = item("building_part", layer, position, screen, entity_id, building, part, height, Color(1,1,1), int64_t(part.get(graphic_layer,20))*1000+(interior?100:0)+j+1);
            const Vector2 depth = part.get(depth_key, Vector2());
            sprite[depth_key] = depth; sprite[y] = double(Vector2(project.call(position + depth)).y); items.append(sprite);
        }
        const int64_t team = building.get("team", 0);
        if (selected_actor || previewed)
            items.append(item("selection", 2, position, screen, entity_id, building, info, height, colors.call(team), 1));
        if (selected_actor && team == observer && bool(building.get("rally_point_set",false)) && double(building[hp]) > 0.0 && String(building.get("state","")) == "complete") {
            const Vector2 destination = building.get("rally_point", position);
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
    Dictionary output; output["items"] = result; output["rally"] = rally; return output;
}

Array RoRReadModelKernel::clip_building_render_items(const Array &items, const Rect2 &viewport) const {
    if (!viewport.has_area()) return items;
    static const Variant kind("kind"), command("sprite_command");
    Array result;
    for (int64_t i = 0; i < items.size(); ++i) {
        const Dictionary item = items[i];
        const String type = item[kind];
        if ((type == "building" || type == "building_part") && item.has(command)) {
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
    Dictionary entries = cache.get("entries", Dictionary());
    int64_t bytes = cache.get("bytes", 0);
    constexpr int64_t MAX_BYTES = 96 * 1024 * 1024, MAX_ENTRIES = 4096;
    for (int64_t i = 0; i < items.size(); ++i) {
        Dictionary item = items[i];
        item.erase(command);
        if (scale > 0.0 && !item.has(anchor)) {
            item[anchor] = (Vector2(item[screen]) - origin) / scale;
            item["projection_sort_y"] = (double(item[y]) - origin.y) / scale;
        }
        const String type = item[kind];
        if (type != "building" && type != "building_part" && type != "resource" && type != "resource_shadow" &&
                type != "unit" && type != "unit_part" && type != "projectile" && type != "effect" && type != "marker" &&
                type != "environment" && type != "rally_flag") continue;
        const Dictionary info = item[info_key];
        const Variant source = info.get(texture_key, Variant());
        Object *texture = source;
        if (scale <= 0.0 || !texture || info.has("gate_polygon") || info.has("rotation") || bool(info.get("mirrored",false))) continue;
        Dictionary prepared = entries.get(source, Dictionary());
        if (prepared.is_empty()) {
            const Vector2 size = texture->call("get_size");
            const Variant rendered = atlas.is_valid() ? atlas.call(texture) : source;
            Object *rendered_texture = rendered;
            if (!rendered_texture) continue;
            RID rid = rendered_texture->call("get_rid");
            Rect2 region(Vector2(), size);
            if (rendered_texture->is_class("AtlasTexture")) {
                Object *page = rendered_texture->call("get_atlas");
                if (page) rid = page->call("get_rid");
                region = rendered_texture->call("get_region");
            }
            prepared["size"] = size; prepared[texture_key] = rendered;
            prepared["rid"] = rid; prepared["region"] = region;
            const int64_t weight = int64_t(size.x) * int64_t(size.y) * 8 + 256;
            prepared["bytes"] = weight;
            if (weight <= MAX_BYTES) {
                while (!entries.is_empty() && (entries.size() >= MAX_ENTRIES || bytes + weight > MAX_BYTES)) {
                    const Variant expired = entries.keys()[0];
                    bytes -= int64_t(Dictionary(entries[expired])["bytes"]); entries.erase(expired);
                }
                entries[source] = prepared; bytes += weight;
            }
        }
        const Vector2 size = prepared["size"], screen_offset = info.get(offset, Vector2());
        item["sprite_source_size"] = size; item["sprite_screen_offset"] = screen_offset;
        const Vector2 point = Vector2(item[screen]).round() + screen_offset * scale;
        Array sprite;
        sprite.append(prepared[texture_key]);
        sprite.append(Rect2(point - Vector2(item[hotspot]) * scale, size * scale));
        sprite.append(Color(1,1,1,float(item["opacity"])));
        sprite.append(prepared["rid"]); sprite.append(prepared["region"]);
        item[command] = sprite;
    }
    cache["entries"] = entries; cache["bytes"] = bytes;
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

int64_t RoRReadModelKernel::integrate_unit_motion(Dictionary unit, double delta, const Vector2i &map_size,
        const Dictionary &vertex_levels, const String &reason) const {
    // Owner-thread only. None of these fields changes task/combat eligibility.
    // Publish the union once after all writes, before the next entity is updated.
    static const Variant pos("pos"), target("target"), velocity("actual_velocity"), desired("desired_velocity");
    static const Variant desired_facing("desired_facing"), movement_facing("movement_facing"), facing("facing"), height("elevation"), diagnostic("diagnostic_reason");
    int64_t mask = 0;
    const auto put = [&](const Variant &key, const Variant &value, int64_t changed) {
        if (!unit.has(key) || unit[key].get_type() != value.get_type() || unit[key] != value) {
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
        const Vector2 clamped(std::clamp(double(position.x), 0.0, double(map_size.x) - 0.0001),
                std::clamp(double(position.y), 0.0, double(map_size.y) - 0.0001));
        const Vector2i cell(int32_t(std::floor(clamped.x)), int32_t(std::floor(clamped.y)));
        const Vector2 local = clamped - Vector2(cell);
        const double a = int64_t(vertex_levels.get(cell, 0)), b = int64_t(vertex_levels.get(cell + Vector2i(1, 0), 0));
        const double c = int64_t(vertex_levels.get(cell + Vector2i(0, 1), 0)), d = int64_t(vertex_levels.get(cell + Vector2i(1, 1), 0));
        const double top = a + (b - a) * double(local.x), bottom = c + (d - c) * double(local.x);
        put(height, top + (bottom - top) * double(local.y), 96);
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
    result["damage"] = double(entity[damage]); result["period"] = double(entity[period]);
    result["range"] = double(entity[range]); result[speed] = double(entity[speed]);
    result[max_hp] = double(entity[max_hp]); result[enabled] = bool(entity[combat_enabled]);
    result["transport"] = bool(cargo.get(enabled, false));
    result[carried] = double(entity.get(carried, 0.0));
    result[resource_type] = int64_t(entity.get(resource_type, -1));
    result[stage] = String(entity.get(stage, ""));
    return result;
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

void RoRReadModelKernel::_bind_methods() {
    ClassDB::bind_method(D_METHOD("rasterize_minimap_fog", "size", "rectangle", "center", "scale", "fog"), &RoRReadModelKernel::rasterize_minimap_fog);
    ClassDB::bind_method(D_METHOD("capture_navigation_pages", "sources", "previous", "keys", "size"), &RoRReadModelKernel::capture_navigation_pages);
    ClassDB::bind_method(D_METHOD("refresh_interpolated_items", "items", "project", "alpha", "depth_index", "sprite_scale"), &RoRReadModelKernel::refresh_interpolated_items);
    ClassDB::bind_method(D_METHOD("cache_actor_sprites", "items", "scale"), &RoRReadModelKernel::cache_actor_sprites);
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
    ClassDB::bind_method(D_METHOD("create_unit_render_items", "units", "project", "provider", "colors", "alpha", "depth_index", "preview", "selected"), &RoRReadModelKernel::create_unit_render_items);
    ClassDB::bind_method(D_METHOD("create_building_render_items", "buildings", "project", "provider", "colors", "records", "preview", "selected", "observer", "scale", "affine", "cache_sprite"), &RoRReadModelKernel::create_building_render_items);
    ClassDB::bind_method(D_METHOD("clip_building_render_items", "items", "viewport"), &RoRReadModelKernel::clip_building_render_items);
    ClassDB::bind_method(D_METHOD("cache_sprite_items", "items", "scale", "origin", "atlas", "cache"), &RoRReadModelKernel::cache_sprite_items);
    ClassDB::bind_method(D_METHOD("matches_combat_classification", "entity", "classification"), &RoRReadModelKernel::matches_combat_classification);
    ClassDB::bind_method(D_METHOD("advance_harvesting_recovery", "worker", "resources", "reservations"), &RoRReadModelKernel::advance_harvesting_recovery);
    ClassDB::bind_method(D_METHOD("integrate_unit_motion", "unit", "delta", "map_size", "vertex_levels", "reason"), &RoRReadModelKernel::integrate_unit_motion);
    ClassDB::bind_method(D_METHOD("owned_ai_actor_profile", "entity"), &RoRReadModelKernel::owned_ai_actor_profile);
    ClassDB::bind_method(D_METHOD("partition_render_items", "items"), &RoRReadModelKernel::partition_render_items);
    ClassDB::bind_method(D_METHOD("submit_sprite_run", "canvas", "items", "start"), &RoRReadModelKernel::submit_sprite_run);
    ClassDB::bind_method(D_METHOD("unit_depth_offset", "position", "screen_y", "index", "project"), &RoRReadModelKernel::unit_depth_offset);
    ClassDB::bind_method(D_METHOD("diff_resource_records", "previous", "current"), &RoRReadModelKernel::diff_resource_records);
    ClassDB::bind_method(D_METHOD("known_resources_in_bounds", "known", "chunks", "bounds", "chunk_size"), &RoRReadModelKernel::known_resources_in_bounds);
    ClassDB::bind_method(D_METHOD("sort_render_items", "items"), &RoRReadModelKernel::sort_render_items);
    ClassDB::bind_method(D_METHOD("reproject_static_items", "items", "origin", "previous_origin", "previous_scale", "scale"), &RoRReadModelKernel::reproject_static_items);
    ClassDB::bind_method(D_METHOD("merge_render_items", "first", "second"), &RoRReadModelKernel::merge_render_items);
    ClassDB::bind_method(D_METHOD("advance_idle_animation", "entities", "delta"), &RoRReadModelKernel::advance_idle_animation);
    ClassDB::bind_method(D_METHOD("patch_render", "source", "previous", "mask", "groups"), &RoRReadModelKernel::patch_render);
    ClassDB::bind_method(D_METHOD("project_render", "source", "previous", "fields", "nested_fields", "schema"), &RoRReadModelKernel::project_render);
    ClassDB::bind_method(D_METHOD("project_ai", "source", "previous", "observer_team", "fields", "array_fields", "private_trade_fields"), &RoRReadModelKernel::project_ai);
    ClassDB::bind_method(D_METHOD("query_resource_candidates", "buckets", "position", "resource_type", "cell_size", "maximum"), &RoRReadModelKernel::query_resource_candidates);
    ClassDB::bind_method(D_METHOD("build_resource_buckets", "resources", "domains", "unrestricted", "typed", "cell_size"), &RoRReadModelKernel::build_resource_buckets);
    ClassDB::bind_method(D_METHOD("build_site_ring_cells", "center", "radius", "size", "seen", "pages"), &RoRReadModelKernel::build_site_ring_cells);
    ClassDB::bind_method(D_METHOD("infrastructure_site_bonuses", "resources", "sites", "kind"), &RoRReadModelKernel::infrastructure_site_bonuses);
    ClassDB::bind_method(D_METHOD("foundation_intersects_structures", "footprint", "center", "structures", "replaced"), &RoRReadModelKernel::foundation_intersects_structures);
    ClassDB::bind_method(D_METHOD("walkability_mask", "size", "terrain", "terrain_ids", "occupied", "restrictions", "learned", "knowledge", "domain", "restriction"), &RoRReadModelKernel::walkability_mask);
    ClassDB::bind_method(D_METHOD("project_control", "source", "rendered", "observer", "fields", "private_trade_fields"), &RoRReadModelKernel::project_control);
    ClassDB::bind_method(D_METHOD("encode_replay_variant", "source", "quantize_numbers"), &RoRReadModelKernel::encode_replay_variant, DEFVAL(true));
    ClassDB::bind_method(D_METHOD("capture_frozen", "source", "trusted"), &RoRReadModelKernel::capture_frozen);
    ClassDB::bind_method(D_METHOD("capture_owned_frozen", "source", "trusted"), &RoRReadModelKernel::capture_owned_frozen);
}

PackedByteArray RoRReadModelKernel::walkability_mask(const Vector2i &size, const Dictionary &terrain, const Dictionary &terrain_ids, const Dictionary &occupied, const Array &restrictions, const PackedByteArray &learned, bool knowledge, const String &domain, int64_t restriction) const {
    PackedByteArray result; result.resize(int64_t(size.x) * size.y); result.fill(knowledge ? 1 : 0);
    Array accessible;
    if (restriction >= 0 && restriction < restrictions.size()) {
        const Dictionary row = restrictions[restriction]; accessible = row.get("accessible_damage_multiplier", Array());
    }
    const auto evaluate = [&](const Vector2i &cell) {
        if (cell.x < 0 || cell.y < 0 || cell.x >= size.x || cell.y >= size.y) return;
        const int64_t index = int64_t(cell.y) * size.x + cell.x;
        if (knowledge && learned[index] == 0) return;
        bool allowed = false;
        if (!occupied.has(cell)) {
            if (restriction >= 0 && !restrictions.is_empty()) {
                int64_t id = terrain_ids.get(cell, -1);
                if (id >= 1000 && id <= 1003) id = 0;
                allowed = id >= 0 && id < accessible.size() && double(accessible[id]) > 0.05;
            } else {
                const String value = terrain.get(cell, "void");
                const bool water = value == "water" || value == "dark_water" || value == "shallows";
                const bool land = value == "land" || value == "shore" || value == "shallows" || value == "grass" || value == "sand" || value == "forest_floor";
                allowed = domain == "water" ? water : domain == "amphibious" ? water || land : land;
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

bool RoRReadModelKernel::foundation_intersects_structures(const Dictionary &footprint, const Vector2 &center, const Dictionary &structures, const Dictionary &replaced) const {
    const PackedVector2Array centers = structures["centers"], halves = structures["halves"];
    const Array cells = structures["cells"], ids = structures["ids"];
    const Vector2 half = footprint.get("obstruction_half_size", footprint.get("half_size", Vector2(0.5, 0.5)));
    const Array occupied = footprint.get("occupied_cells", Array());
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
    Dictionary result = rendered.duplicate(true);
    for (int64_t i = 0; i < fields.size(); ++i) if (source.has(fields[i])) result[fields[i]] = source[fields[i]];
    const bool own = observer <= 0 || int64_t(source.get("team", 0)) == observer;
    if (own && source.has("production_queue")) { const Array queue = source["production_queue"]; result["production_queue"] = queue.duplicate(true); }
    const Dictionary source_components = source.get("components", Dictionary());
    const Dictionary base_components = result.get("components", Dictionary());
    Dictionary components = base_components.duplicate(true);
    for (const char *name : {"combat", "conversion", "healing", "resource_carrier"}) {
        const Dictionary original = source_components.get(name, Dictionary());
        Dictionary component = original.duplicate(true);
        if (String(name) == "combat") {
            component["target_id"] = int64_t(source.get("target_id", component.get("target_id", -1)));
            component["cooldown"] = double(source.get("cooldown", component.get("cooldown", 0.0)));
            component["stance"] = String(source.get("stance", component.get("stance", "passive")));
            component["acquisition_range"] = double(source.get("acquisition_range", component.get("acquisition_range", 0.0)));
            component["chase_range"] = double(source.get("chase_range", component.get("chase_range", 0.0)));
            component["retaliation_target_id"] = int64_t(source.get("retaliation_target_id", component.get("retaliation_target_id", -1)));
        } else if (String(name) == "resource_carrier") {
            if (source.has("amount")) component["amount"] = double(source["amount"]);
            if (source.has("carried_amount")) component["amount"] = double(source["carried_amount"]);
            if (source.has("carried_resource_type_id")) component["resource_type_id"] = int64_t(source["carried_resource_type_id"]);
        }
        if (!component.is_empty()) components[name] = component;
    }
    for (const char *name : {"cargo", "trade"}) {
        const Dictionary original = source_components.get(name, Dictionary());
        if (original.is_empty()) continue;
        Dictionary component = original.duplicate(true);
        if (!own) {
            if (String(name) == "cargo") component.erase("passenger_ids");
            else for (int64_t i = 0; i < private_trade_fields.size(); ++i) component.erase(private_trade_fields[i]);
        }
        components[name] = component;
    }
    if (!own) for (const char *name : {"production_progress", "rally_point", "rally_point_set", "resource_id", "dropoff_id", "worker_role_source_unit_id", "diagnostic_reason"}) result.erase(name);
    result["components"] = components;
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
