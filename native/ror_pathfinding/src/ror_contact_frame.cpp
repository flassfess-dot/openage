#include "ror_read_model_kernel.hpp"
#include "ror_actor_motion_frame.hpp"
#include <godot_cpp/variant/variant_internal.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <algorithm>
#include <cmath>
#include <limits>
#include <unordered_map>
#include <unordered_set>
#include <vector>

namespace godot {
namespace {
bool contact_source(Object *object, const char *path) {
    if (!object) return false;
    const Variant value = object->call("get_script");
    Object *script = value.get_type() == Variant::OBJECT ? static_cast<Object *>(value) : nullptr;
    return script && String(script->get("resource_path")) == path;
}
uint64_t contact_cell(int32_t x, int32_t y) { return (uint64_t(uint32_t(x)) << 32) | uint32_t(y); }
bool contact_number(const Variant &value) { return value.get_type() == Variant::FLOAT || value.get_type() == Variant::INT; }
double contact_number_value(const Variant *value) {
    return value->get_type() == Variant::FLOAT ? *VariantInternal::get_float(value) : double(*VariantInternal::get_int(value));
}
const Variant *contact_array_values(const Array &source) {
    return source.is_empty() ? nullptr : reinterpret_cast<const Variant *>(gdextension_interface::array_operator_index_const(source._native_ptr(), 0));
}
struct ContactRow {
    int64_t id;
    Dictionary entity;
    Vector2 indexed, position;
    double indexed_radius, radius, hp;
    String domain;
    bool present, isolated;
};

// The spatial index already assigns a single cell to each slot. Build flat
// chains from those cells instead of copying every Godot bucket and allocating
// a second vector for it. Ordinary maps have a small rectangular grid.
struct ContactGrid {
    Vector2i minimum, maximum;
    std::vector<int32_t> next, heads;
    std::unordered_map<uint64_t, int32_t> sparse_heads;
    int64_t width = 0;

    bool build(const Array &cells) {
        const Variant *values = contact_array_values(cells);
        for (int64_t i = 0; i < cells.size(); ++i) {
            if (values[i].get_type() != Variant::VECTOR2I) return false;
            const Vector2i cell = *VariantInternal::get_vector2i(&values[i]);
            if (i == 0) minimum = maximum = cell;
            else {
                minimum.x = std::min(minimum.x, cell.x); minimum.y = std::min(minimum.y, cell.y);
                maximum.x = std::max(maximum.x, cell.x); maximum.y = std::max(maximum.y, cell.y);
            }
        }
        width = int64_t(maximum.x) - minimum.x + 1;
        const int64_t height = int64_t(maximum.y) - minimum.y + 1;
        if (width <= 65536 && height <= 65536 / width) heads.assign(size_t(width * height), -1);
        else sparse_heads.reserve(size_t(cells.size()));
        next.resize(size_t(cells.size()));
        for (int64_t i = 0; i < cells.size(); ++i) {
            const Vector2i cell = *VariantInternal::get_vector2i(&values[i]);
            if (heads.empty()) {
                auto entry = sparse_heads.emplace(contact_cell(cell.x, cell.y), -1);
                next[i] = entry.first->second;
                entry.first->second = int32_t(i);
            } else {
                int32_t &head = heads[(int64_t(cell.y) - minimum.y) * width + cell.x - minimum.x];
                next[i] = head;
                head = int32_t(i);
            }
        }
        return true;
    }

    int32_t first(int x, int y) const {
        if (x < minimum.x || x > maximum.x || y < minimum.y || y > maximum.y) return -1;
        if (!heads.empty()) return heads[(int64_t(y) - minimum.y) * width + x - minimum.x];
        const auto found = sparse_heads.find(contact_cell(x, y));
        return found == sparse_heads.end() ? -1 : found->second;
    }
};
}

// One synchronous contact stage. Index coordinates stay fixed; factual
// coordinates are refreshed immediately after the canonical correction.
// No world cache, borrowed field pointer or second simulation survives return.
int64_t RoRReadModelKernel::settle_mobile_contacts_flat(const Dictionary &changes, const Array &active_units,
        const Array &all_units, const Dictionary &units_by_id, const Dictionary &buckets, const Array &entities,
        const Array &positions, const Array &radii, double cell_size, double maximum_radius,
        double delta, Dictionary pending, const Callable &query_fallback, const Callable &separate, bool compare) const {
    const auto reject = [&]() -> int64_t { ++contact_frame_fallbacks; return -1; };
    if (delta <= 0.0 || !std::isfinite(delta) || !std::isfinite(cell_size) || cell_size <= 0.0 ||
            !std::isfinite(maximum_radius) || maximum_radius < 0.0 || pending.is_read_only() || pending.size() > 65536 ||
            entities.size() > 65536 || active_units.size() > 65536 || all_units.size() > 65536 || buckets.size() > 65536 ||
            entities.size() != positions.size() || positions.size() != radii.size() || !separate.is_valid()) return reject();
    Object *system = separate.get_object();
    if (separate.get_method() != StringName("_separate_mobile") ||
            !contact_source(system, "res://scripts/simulation_movement_system.gd")) return reject();
    Object *world = system->get("world");
    if (!contact_source(world, "res://scripts/simulation_world.gd")) return reject();
    Object *spatial = world->get("spatial_index"), *activity = world->get("unit_activity_registry");
    // These are the canonical owner buffers. Their identity/lifecycle contract
    // makes repeating source-identity checks for each candidate unnecessary.
    if (!contact_source(spatial, "res://scripts/spatial_hash.gd") || !activity || !UtilityFunctions::is_same(units_by_id, world->get("units_by_id")) ||
            !UtilityFunctions::is_same(all_units, world->get("units")) || !UtilityFunctions::is_same(active_units, activity->get("active_units")) ||
            !UtilityFunctions::is_same(pending, system->get("overlap_pending")) ||
            !UtilityFunctions::is_same(buckets, spatial->get("unit_buckets")) || !UtilityFunctions::is_same(entities, spatial->get("unit_entities")) ||
            !UtilityFunctions::is_same(positions, spatial->get("unit_positions")) || !UtilityFunctions::is_same(radii, spatial->get("unit_radii"))) return reject();

    static const Variant id_key("id"), hp_key("hp"), pos_key("pos"), radius_key("footprint_radius");
    static const Variant domain_key("movement_domain"), isolated_key("formation_shared_isolated");
    static const Variant land("land"), no_health(0.0), not_isolated(false);
    // Admission borrows array/field storage only while it is read-only. No
    // borrowed pointer is used after pending.clear() or any correction call.
    const Variant *entity_values = contact_array_values(entities);
    const Variant *position_values = contact_array_values(positions);
    const Variant *radius_values = contact_array_values(radii);
    std::vector<ContactRow> rows;
    rows.reserve(size_t(entities.size()));
    std::unordered_map<int64_t, int32_t> slots;
    slots.reserve(size_t(entities.size()));
    double maximum_live_radius = 0.0;
    for (int64_t i = 0; i < entities.size(); ++i) {
        if (entity_values[i].get_type() != Variant::DICTIONARY || position_values[i].get_type() != Variant::VECTOR2 || !contact_number(radius_values[i])) return reject();
        const Dictionary &row = *VariantInternal::get_dictionary(&entity_values[i]);
        const Variant *id = RoRActorMotionFrame::find_field(row, id_key), *hp = RoRActorMotionFrame::find_field(row, hp_key);
        const Variant *position = RoRActorMotionFrame::find_field(row, pos_key), *radius = RoRActorMotionFrame::find_field(row, radius_key);
        const Variant *domain = RoRActorMotionFrame::find_field(row, domain_key), *isolated = RoRActorMotionFrame::find_field(row, isolated_key);
        if (!hp) hp = &no_health;
        if (!domain) domain = &land;
        if (!isolated) isolated = &not_isolated;
        if (!id || !position || !radius || id->get_type() != Variant::INT || !contact_number(*hp) || position->get_type() != Variant::VECTOR2 ||
                !contact_number(*radius) || domain->get_type() != Variant::STRING || isolated->get_type() != Variant::BOOL) return reject();
        const Vector2 indexed = *VariantInternal::get_vector2(&position_values[i]), factual = *VariantInternal::get_vector2(position);
        const double indexed_radius = contact_number_value(&radius_values[i]), live_radius = contact_number_value(radius), health = contact_number_value(hp);
        if (!std::isfinite(indexed.x) || !std::isfinite(indexed.y) || !std::isfinite(factual.x) || !std::isfinite(factual.y) ||
                !std::isfinite(indexed_radius) || indexed_radius < 0.0 || !std::isfinite(live_radius) || live_radius < 0.0 || !std::isfinite(health)) return reject();
        const double coordinate_limit = double(std::numeric_limits<int32_t>::max()) - 4096.0;
        if (std::abs(double(indexed.x) / cell_size) > coordinate_limit || std::abs(double(indexed.y) / cell_size) > coordinate_limit ||
                std::abs(double(factual.x) / cell_size) > coordinate_limit || std::abs(double(factual.y) / cell_size) > coordinate_limit) return reject();
        const int64_t actor_id = *VariantInternal::get_int(id);
        if (!slots.emplace(actor_id, int32_t(i)).second) return reject();
        rows.push_back({actor_id, row, indexed, factual, indexed_radius, live_radius, health, *VariantInternal::get_string(domain),
            units_by_id.has(*id), *VariantInternal::get_bool(isolated)});
        maximum_live_radius = std::max(maximum_live_radius, live_radius);
    }
    // Keep every possible query bounded, including a later corrected center.
    const double width = std::ceil(2.0 * (maximum_live_radius + 0.25 + maximum_radius) / cell_size) + 3.0;
    if (width * width > 4096.0) return reject();
    const Array cells = spatial->get("unit_cells");
    ContactGrid grid;
    if (cells.size() != entities.size() || !grid.build(cells)) return reject();
    std::unordered_set<int64_t> candidates;
    candidates.reserve(size_t(active_units.size()) + size_t(pending.size()));
    const auto add = [&](const Dictionary &row, bool force) -> bool {
        const Variant id = row.get(id_key, Variant());
        if (id.get_type() != Variant::INT) return false;
        const auto found = slots.find(int64_t(id));
        if (found == slots.end()) {
            // A newly added live entity needs the complete scalar path until
            // the spatial index contains it. Retired/dead pending rows expire.
            if (units_by_id.has(id) && double(row.get(hp_key, 0.0)) > 0.0) return false;
            if (force || !bool(row.get(isolated_key, false))) candidates.insert(id);
            return true;
        }
        const ContactRow &record = rows[found->second];
        if (force || !record.isolated) candidates.insert(id);
        return true;
    };
    const Array pending_ids = pending.keys();
    for (int64_t i = 0; i < pending_ids.size(); ++i) {
        if (pending_ids[i].get_type() != Variant::INT) return reject();
        const Variant value = pending[pending_ids[i]];
        if (value.get_type() != Variant::DICTIONARY || Dictionary(value).get(id_key, Variant()) != pending_ids[i] || !add(value, true)) return reject();
    }
    const bool full = changes.get("full", false);
    const Array &source = full ? all_units : active_units;
    for (int64_t i = 0; i < source.size(); ++i) {
        if (source[i].get_type() != Variant::DICTIONARY || !add(source[i], full)) return reject();
    }
    if (!full) {
        const Array ids = changes.get("ids", Array());
        const Dictionary masks = changes.get("masks", Dictionary());
        for (int64_t i = 0; i < ids.size(); ++i) {
            if (ids[i].get_type() != Variant::INT) return reject();
            if (!(int64_t(masks.get(ids[i], 0)) & 3)) continue;
            const auto found = slots.find(int64_t(ids[i]));
            if (found != slots.end()) {
                const ContactRow &row = rows[found->second];
                if (row.present && !row.isolated) candidates.insert(row.id);
            } else {
                const Variant value = units_by_id.get(ids[i], Variant());
                if (value.get_type() != Variant::NIL && (value.get_type() != Variant::DICTIONARY || !add(value, false))) return reject();
            }
        }
    }
    if (candidates.size() > 65536) return reject();
    std::vector<int64_t> ordered(candidates.begin(), candidates.end());
    std::sort(ordered.begin(), ordered.end());
    // Admission is complete. No rejection/restart is possible after writes.
    ++contact_frame_calls; contact_frame_rows += int64_t(rows.size());
    pending.clear();
    std::unordered_set<uint64_t> pairs;
    std::vector<int32_t> neighbors;
    Array reference;
    const auto correct = [&](ContactRow &row, const Vector2 &offset) -> double {
        const double moved = separate.call(row.entity, offset);
        row.position = row.entity[pos_key];
        return moved;
    };
    for (const int64_t id : ordered) {
        const auto found = slots.find(id);
        if (found == slots.end()) continue;
        ContactRow &unit = rows[found->second];
        if (unit.hp <= 0.0 || !unit.present) continue;
        const double radius = unit.radius + 0.25, extent = radius + maximum_radius;
        const Vector2 minimum = (unit.position - Vector2(1, 1) * real_t(extent)) / real_t(cell_size);
        const Vector2 maximum = (unit.position + Vector2(1, 1) * real_t(extent)) / real_t(cell_size);
        neighbors.clear();
        for (int y = int(std::floor(minimum.y)); y <= int(std::floor(maximum.y)); ++y) {
            for (int x = int(std::floor(minimum.x)); x <= int(std::floor(maximum.x)); ++x) {
                for (int32_t slot = grid.first(x, y); slot >= 0; slot = grid.next[slot]) {
                    const ContactRow &other = rows[slot];
                    const double allowed = radius + other.indexed_radius;
                    if (other.id != id && unit.position.distance_squared_to(other.indexed) <= allowed * allowed) neighbors.push_back(slot);
                }
            }
        }
        std::stable_sort(neighbors.begin(), neighbors.end(), [&](int32_t left, int32_t right) { return rows[left].id < rows[right].id; });
        ++contact_frame_queries; contact_frame_neighbors += int64_t(neighbors.size());
        if (compare && contact_frame_comparisons < 512 && (contact_frame_comparisons < 8 || contact_frame_queries % 512 == 0)) {
            bool equal = spatial_unit_neighbors(unit.entity, radius, Variant(), buckets, entities, positions, radii, cell_size, maximum_radius, reference);
            equal = equal && reference.size() == int64_t(neighbors.size());
            for (int64_t j = 0; equal && j < reference.size(); ++j) equal = int64_t(Dictionary(reference[j])[id_key]) == rows[neighbors[size_t(j)]].id;
            ++contact_frame_comparisons;
            if (!equal) { ++contact_frame_mismatches; UtilityFunctions::push_error("Contact frame neighbor query differs from its spatial generation"); }
        }
        for (const int32_t slot : neighbors) {
            ContactRow &other = rows[slot];
            if (other.hp <= 0.0 || other.domain != unit.domain) continue;
            const Vector2 gap = unit.position - other.position;
            const double sum = unit.radius + other.radius;
            if (gap.length_squared() >= (sum - 0.001) * (sum - 0.001)) continue;
            const uint64_t pair = contact_cell(int32_t(std::min(id, other.id)), int32_t(std::max(id, other.id)));
            if (!pairs.insert(pair).second) continue;
            pending[id] = unit.entity; pending[other.id] = other.entity;
            const double distance = gap.length();
            const Vector2 normal = distance > 0.0001 ? gap / real_t(distance) : Vector2(0, id < other.id ? -1 : 1);
            const double correction = std::min(sum - distance + 0.002, std::max(0.01, delta * 2.0));
            const double first = correct(unit, normal * real_t(correction * 0.5));
            const double second = correct(other, -normal * real_t(correction - first));
            if (second < correction * 0.5) correct(unit, normal * real_t(correction * 0.5 - second));
        }
    }
    return int64_t(ordered.size());
}

Dictionary RoRReadModelKernel::contact_frame_stats() const {
    Dictionary result;
    result["calls"] = contact_frame_calls; result["rows"] = contact_frame_rows;
    result["queries"] = contact_frame_queries; result["neighbors"] = contact_frame_neighbors;
    result["fallbacks"] = contact_frame_fallbacks;
    result["comparisons"] = contact_frame_comparisons; result["mismatches"] = contact_frame_mismatches;
    return result;
}
} // namespace godot
