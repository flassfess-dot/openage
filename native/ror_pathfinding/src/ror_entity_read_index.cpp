#include "ror_entity_read_index.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <godot_cpp/variant/packed_int64_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <cmath>
#include <algorithm>
#include <unordered_set>

namespace godot {
uint64_t RoREntityReadIndexKernel::key(const Vector2i &cell) {
    return (uint64_t(uint32_t(cell.x)) << 32) | uint32_t(cell.y);
}
Vector2i RoREntityReadIndexKernel::unkey(uint64_t value) {
    return Vector2i(int32_t(value >> 32), int32_t(value));
}
Vector2i RoREntityReadIndexKernel::cell_for(const Vector2 &position) {
    return Vector2i(int32_t(std::floor(position.x / 4.0)), int32_t(std::floor(position.y / 4.0)));
}
int RoREntityReadIndexKernel::category_id(const String &name) {
    return name == "units" ? 0 : name == "buildings" ? 1 : name == "objectives" ? 2 : -1;
}
Array RoREntityReadIndexKernel::copy_array(const Array &source) const { return source.duplicate(false); }
void RoREntityReadIndexKernel::clear() {
    records.clear(); buckets.clear(); observers.clear(); observer_order.clear();
    epoch = cursor = -1; overflow = false; ++generation;
}
void RoREntityReadIndexKernel::put(const Dictionary &row, int category) {
    static const Variant id_key("id"), pos_key("pos");
    const int64_t id = row[id_key];
    auto found = records.find(id);
    if (found == records.end() && records.size() >= 65536) { overflow = true; return; }
    const Vector2 position = row.get(pos_key, Vector2());
    const Vector2i cell = cell_for(position);
    if (found != records.end() && found->second.cell != cell) {
        auto bucket = buckets.find(key(found->second.cell));
        if (bucket != buckets.end()) {
            bucket->second.erase(std::remove(bucket->second.begin(), bucket->second.end(), id), bucket->second.end());
            if (bucket->second.empty()) buckets.erase(bucket);
        }
        ++crossings;
    }
    if (found == records.end() || found->second.cell != cell) buckets[key(cell)].push_back(id);
    Record &record = found == records.end() ? records[id] : found->second;
    record.row = row; record.position = position; record.cell = cell; record.category = category;
    ++updates;
}
void RoREntityReadIndexKernel::erase(int64_t id) {
    auto found = records.find(id);
    if (found == records.end()) return;
    auto bucket = buckets.find(key(found->second.cell));
    if (bucket != buckets.end()) {
        bucket->second.erase(std::remove(bucket->second.begin(), bucket->second.end(), id), bucket->second.end());
        if (bucket->second.empty()) buckets.erase(bucket);
    }
    records.erase(found);
}
Dictionary RoREntityReadIndexKernel::synchronize(const Dictionary &input) {
    const Dictionary delta = input["delta"];
    const Array ids = delta["ids"];
    if (bool(delta["full"])) {
        clear();
        for (int category = 0; category < 3; ++category) {
            const Array rows = input[category == 0 ? "unit_rows" : category == 1 ? "building_rows" : "objectives"];
            const int64_t count = rows.size();
            for (int64_t i = 0; i < count; ++i) put(rows[i], category);
        }
    } else {
        const Dictionary masks = delta["masks"], units = input["units"], buildings = input["buildings"];
        const Array objectives = input["objectives"];
        const int64_t count = ids.size(), objective_count = objectives.size();
        for (int64_t i = 0; i < count; ++i) {
            const int64_t id = ids[i], mask = masks[id];
            if (records.find(id) != records.end() && !(mask & (1 | 2 | 128))) continue;
            Variant value = units.get(id, Variant()); int category = 0;
            if (value.get_type() != Variant::DICTIONARY) { value = buildings.get(id, Variant()); category = 1; }
            if (value.get_type() != Variant::DICTIONARY) {
                category = 2;
                for (int64_t j = 0; j < objective_count; ++j) {
                    const Dictionary row = objectives[j];
                    if (int64_t(row["id"]) == id) { value = row; break; }
                }
            }
            if (value.get_type() == Variant::DICTIONARY) put(value, category);
            else erase(id);
        }
    }
    epoch = input["epoch"]; cursor = delta["revision"];
    if (!ids.is_empty() || bool(delta["full"])) ++generation;
    Dictionary result;
    result["epoch"] = epoch; result["cursor"] = cursor; result["generation"] = generation; result["overflow"] = overflow;
    return result;
}
std::set<int64_t> RoREntityReadIndexKernel::bounded_ids(const Rect2 &bounds, int category) const {
    const Vector2i minimum = cell_for(bounds.position), maximum = cell_for(bounds.get_end());
    std::set<int64_t> result;
    for (int32_t y = minimum.y; y <= maximum.y; ++y) for (int32_t x = minimum.x; x <= maximum.x; ++x) {
        const auto bucket = buckets.find(key(Vector2i(x, y)));
        if (bucket == buckets.end()) continue;
        for (int64_t id : bucket->second) {
            const auto row = records.find(id);
            if (row != records.end() && (category < 0 || row->second.category == category) && bounds.has_point(row->second.position)) result.insert(id);
        }
    }
    return result;
}
Array RoREntityReadIndexKernel::all(const String &category) const {
    Array result;
    const int which = category_id(category);
    for (const auto &entry : records) if (entry.second.category == which) result.append(entry.second.row);
    return result;
}
Array RoREntityReadIndexKernel::in_bounds(const Rect2 &bounds, const String &category) const {
    Array result;
    const int which = category_id(category);
    if (!category.is_empty() && which < 0) return result;
    for (int64_t id : bounded_ids(bounds, which)) result.append(records.at(id).row);
    return result;
}
Array RoREntityReadIndexKernel::buildings_in_cells(const Array &cells) const {
    Array result;
    std::unordered_set<uint64_t> visited;
    const int64_t count = cells.size();
    for (int64_t i = 0; i < count; ++i) {
        const uint64_t cell = key(cell_for(Vector2(Vector2i(cells[i]))));
        if (!visited.insert(cell).second) continue;
        const auto bucket = buckets.find(cell);
        if (bucket == buckets.end()) continue;
        for (int64_t id : bucket->second) if (records.at(id).category == 1) result.append(id);
    }
    return result;
}
Array RoREntityReadIndexKernel::changed_buildings(const Array &ids) const {
    Array result;
    const int64_t count = ids.size();
    for (int64_t i = 0; i < count; ++i) {
        const int64_t id = ids[i];
        const auto found = records.find(id);
        if (found != records.end() && found->second.category == 1) result.append(id);
    }
    return result;
}
Variant RoREntityReadIndexKernel::cached_legal(int64_t team, const String &category, int64_t fog_revision) const {
    const auto found = observers.find(team);
    const int which = category_id(category);
    if (which < 0) return Array();
    if (found != observers.end() && found->second.generation == generation && found->second.fog == fog_revision && found->second.cursor == cursor)
        return copy_array(found->second.arrays[which]);
    return Variant();
}
int64_t RoREntityReadIndexKernel::observer_entity_cursor(int64_t team) const {
    const auto found = observers.find(team); return found == observers.end() ? -1 : found->second.cursor;
}
int64_t RoREntityReadIndexKernel::observer_fog_cursor(int64_t team) const {
    const auto found = observers.find(team); return found == observers.end() ? -1 : found->second.fog;
}
void RoREntityReadIndexKernel::touch_sector(Observer &observer, const Vector2i &cell) {
    ++observer.sectors[key(cell)];
}

Array RoREntityReadIndexKernel::legal_entities(int64_t team, const String &category, const PackedByteArray &states,
        const Vector2i &map_size, const Dictionary &fog_delta, const Dictionary &entity_delta) {
    ++queries;
    const int which = category_id(category);
    if (which < 0) return Array();
    auto found = observers.find(team);
    if (found == observers.end()) {
        if (observers.size() >= 8) { observers.erase(observer_order.front()); observer_order.pop_front(); }
        found = observers.emplace(team, Observer()).first; observer_order.push_back(team);
    }
    Observer &observer = found->second;
    const Dictionary masks = entity_delta["masks"];
    const bool full_fog = fog_delta["full"];
    std::set<int64_t> candidates;
    if (observer.generation < 0 || full_fog || bool(entity_delta["full"])) {
        for (const auto &entry : records) candidates.insert(entry.first);
    } else {
        const Array ids = entity_delta["ids"];
        const int64_t count = ids.size();
        for (int64_t i = 0; i < count; ++i) {
            const int64_t id = ids[i];
            if (int64_t(masks[id]) & (1 | 2 | 8 | 128)) candidates.insert(id);
        }
    }
    if (observer.generation >= 0 && !full_fog) {
        if (bool(fog_delta["exact"])) {
            const Array changed_cells = fog_delta["cells"];
            std::unordered_set<uint64_t> visited;
            const int64_t count = changed_cells.size();
            for (int64_t i = 0; i < count; ++i) {
                const uint64_t cell = key(cell_for(Vector2(Vector2i(changed_cells[i]))));
                if (!visited.insert(cell).second) continue;
                const auto bucket = buckets.find(cell);
                if (bucket != buckets.end()) candidates.insert(bucket->second.begin(), bucket->second.end());
            }
        } else {
            const auto bounded = bounded_ids(fog_delta["region"], -1);
            candidates.insert(bounded.begin(), bounded.end());
        }
    }
    const uint8_t *state_data = states.ptr();
    const int64_t state_count = states.size();
    const auto visible_at = [&](const Record &record) {
        if (team <= 0 || int64_t(record.row.get("team", 0)) == team) return true;
        const int32_t x = int32_t(std::floor(record.position.x)), y = int32_t(std::floor(record.position.y));
        const int64_t index = int64_t(y) * map_size.x + x;
        return x >= 0 && y >= 0 && x < map_size.x && y < map_size.y && index >= 0 && index < state_count && state_data[index] == 2;
    };
    for (int64_t id : candidates) {
        const auto record = records.find(id);
        const auto previous = observer.members.find(id);
        const bool was_visible = previous != observer.members.end();
        const bool visible = record != records.end() && visible_at(record->second);
        const int64_t physical_change = int64_t(masks.get(id, 0)) & (1 | 2 | 8 | 128);
        if (was_visible != visible || ((was_visible || visible) && physical_change)) {
            if (observer.sectors.size() >= 65536) { observer.sectors.clear(); ++observer.sector_epoch; }
            if (was_visible) touch_sector(observer, previous->second.cell);
            if (visible) touch_sector(observer, record->second.cell);
        }
        if (visible) {
            if (was_visible && !UtilityFunctions::is_same(previous->second.row, record->second.row)) observer.dirty = true;
            Member &member = was_visible ? previous->second : observer.members[id];
            member.row = record->second.row;
            if (!was_visible || physical_change) member.cell = record->second.cell;
        } else if (was_visible) observer.members.erase(previous);
        if (was_visible != visible) observer.dirty = true;
    }
    if (full_fog) {
        for (auto it = observer.members.begin(); it != observer.members.end(); ) {
            if (records.find(it->first) == records.end()) { it = observer.members.erase(it); observer.dirty = true; }
            else ++it;
        }
    }
    observer.generation = generation; observer.fog = fog_delta["revision"]; observer.cursor = cursor;
    if (observer.dirty) {
        for (auto &array : observer.arrays) array = Array();
        for (const auto &member : observer.members) {
            const auto record = records.find(member.first);
            if (record != records.end()) observer.arrays[record->second.category].append(member.second.row);
        }
        observer.dirty = false;
    }
    return copy_array(observer.arrays[which]);
}
Array RoREntityReadIndexKernel::scope_versions(int64_t team, const Array &keys) const {
    const auto observer = observers.find(team);
    Array versions;
    for (int64_t i = 0; i < keys.size(); ++i) {
        const Vector2i cell = keys[i];
        int64_t version = 0;
        if (observer != observers.end()) {
            const auto found = observer->second.sectors.find(key(cell));
            if (found != observer->second.sectors.end()) version = found->second;
        }
        Array entry; entry.append(cell); entry.append(version); versions.append(entry);
    }
    Array result; result.append(observer == observers.end() ? int64_t(0) : observer->second.sector_epoch); result.append(versions);
    return result;
}

Dictionary RoREntityReadIndexKernel::build_query_scope(int64_t team, const PackedVector2Array &centers, int radius, const Array &changed_cells) const {
    // Nearby workers often cover the same sectors. Merge their intervals on
    // each row before reading versions. Each sector appears exactly once.
    using Interval = std::pair<int32_t, int32_t>;
    std::map<int32_t, std::vector<Interval>> rows;
    const Vector2 span(radius, radius);
    for (int64_t i = 0; i < centers.size(); ++i) {
        const Vector2i first = cell_for(centers[i] - span);
        const Vector2i last = cell_for(centers[i] + span);
        for (int y = first.y; y <= last.y; ++y)
            rows[y].emplace_back(first.x, last.x);
    }
    PackedInt64Array versions;
    const auto observer = observers.find(team);
    for (auto &row : rows) {
        auto &ranges = row.second;
        std::sort(ranges.begin(), ranges.end());
        size_t count = 0;
        for (auto range : ranges) {
            if (count && int64_t(range.first) <= int64_t(ranges[count - 1].second) + 1)
                ranges[count - 1].second = std::max(ranges[count - 1].second, range.second);
            else
                ranges[count++] = range;
        }
        ranges.resize(count);
        for (const auto &range : ranges) {
            // Encode the coordinate of the first sector, the count, and the
            // exact version at every x. This is an equality key, not a hash.
            versions.append(int64_t(key(Vector2i(range.first, row.first))));
            versions.append(int64_t(range.second) - range.first + 1);
            for (int x = range.first; x <= range.second; ++x) {
                int64_t version = 0;
                if (observer != observers.end()) {
                    const auto found = observer->second.sectors.find(key(Vector2i(x, row.first)));
                    if (found != observer->second.sectors.end()) version = found->second;
                }
                versions.append(version);
            }
        }
    }
    bool grid_changed = false;
    for (int64_t i = 0; i < changed_cells.size() && !grid_changed; ++i) {
        const Vector2i sector = cell_for(Vector2(Vector2i(changed_cells[i])));
        const auto row = rows.find(sector.y);
        if (row == rows.end()) continue;
        const auto &ranges = row->second;
        const auto found = std::lower_bound(ranges.begin(), ranges.end(), sector.x,
                [](const Interval &range, int x) { return range.second < x; });
        grid_changed = found != ranges.end() && found->first <= sector.x;
    }
    Array signature;
    signature.append(observer == observers.end() ? int64_t(0) : observer->second.sector_epoch);
    signature.append(versions);
    Dictionary result;
    result["versions"] = signature;
    result["grid_changed"] = grid_changed;
    return result;
}
Dictionary RoREntityReadIndexKernel::debug_view() const {
    Dictionary entities, categories, cells, bucket_view;
    static const String names[] = {"units", "buildings", "objectives"};
    for (const auto &entry : records) {
        entities[entry.first] = entry.second.row; categories[entry.first] = names[entry.second.category]; cells[entry.first] = entry.second.cell;
    }
    for (const auto &entry : buckets) {
        Dictionary members;
        for (int64_t id : entry.second) members[id] = true;
        bucket_view[unkey(entry.first)] = members;
    }
    Dictionary result;
    result["entities"] = entities; result["categories"] = categories; result["cells"] = cells; result["buckets"] = bucket_view;
    return result;
}
Dictionary RoREntityReadIndexKernel::debug_observer(int64_t team) const {
    const auto found = observers.find(team);
    if (found == observers.end()) return Dictionary();
    const Observer &observer = found->second;
    Dictionary members, cells, sectors, arrays;
    for (const auto &entry : observer.members) { members[entry.first] = entry.second.row; cells[entry.first] = entry.second.cell; }
    for (const auto &entry : observer.sectors) sectors[unkey(entry.first)] = entry.second;
    arrays["units"] = copy_array(observer.arrays[0]); arrays["buildings"] = copy_array(observer.arrays[1]); arrays["objectives"] = copy_array(observer.arrays[2]);
    Dictionary result;
    result["fog"] = observer.fog; result["generation"] = observer.generation; result["entity_cursor"] = observer.cursor;
    result["members"] = members; result["member_cells"] = cells; result["sectors"] = sectors; result["sector_epoch"] = observer.sector_epoch;
    result["arrays"] = arrays; result["dirty"] = observer.dirty;
    return result;
}
Dictionary RoREntityReadIndexKernel::stats() const {
    Dictionary result;
    result["records"] = int64_t(records.size()); result["buckets"] = int64_t(buckets.size()); result["observers"] = int64_t(observers.size());
    result["updates"] = updates; result["bucket_crossings"] = crossings; result["uncached_queries"] = queries;
    return result;
}
void RoREntityReadIndexKernel::_bind_methods() {
    ClassDB::bind_method(D_METHOD("clear"), &RoREntityReadIndexKernel::clear);
    ClassDB::bind_method(D_METHOD("synchronize", "input"), &RoREntityReadIndexKernel::synchronize);
    ClassDB::bind_method(D_METHOD("all", "category"), &RoREntityReadIndexKernel::all);
    ClassDB::bind_method(D_METHOD("in_bounds", "bounds", "category"), &RoREntityReadIndexKernel::in_bounds);
    ClassDB::bind_method(D_METHOD("buildings_in_cells", "cells"), &RoREntityReadIndexKernel::buildings_in_cells);
    ClassDB::bind_method(D_METHOD("changed_buildings", "ids"), &RoREntityReadIndexKernel::changed_buildings);
    ClassDB::bind_method(D_METHOD("cached_legal", "team", "category", "fog_revision"), &RoREntityReadIndexKernel::cached_legal);
    ClassDB::bind_method(D_METHOD("observer_entity_cursor", "team"), &RoREntityReadIndexKernel::observer_entity_cursor);
    ClassDB::bind_method(D_METHOD("observer_fog_cursor", "team"), &RoREntityReadIndexKernel::observer_fog_cursor);
    ClassDB::bind_method(D_METHOD("legal_entities", "team", "category", "states", "map_size", "fog_delta", "entity_delta"), &RoREntityReadIndexKernel::legal_entities);
    ClassDB::bind_method(D_METHOD("scope_versions", "team", "keys"), &RoREntityReadIndexKernel::scope_versions);
    ClassDB::bind_method(D_METHOD("build_query_scope", "team", "centers", "radius", "changed_cells"), &RoREntityReadIndexKernel::build_query_scope);
    ClassDB::bind_method(D_METHOD("debug_view"), &RoREntityReadIndexKernel::debug_view);
    ClassDB::bind_method(D_METHOD("debug_observer", "team"), &RoREntityReadIndexKernel::debug_observer);
    ClassDB::bind_method(D_METHOD("stats"), &RoREntityReadIndexKernel::stats);
}
} // namespace godot
