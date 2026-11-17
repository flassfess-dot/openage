#include "ror_read_model_kernel.hpp"
#include <godot_cpp/core/gdextension_interface_loader.hpp>
#include <godot_cpp/variant/packed_int64_array.hpp>
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
    static const Variant land("land");
    // The spatial owner maintains both directions of the dense roster as it
    // inserts/removes units. Reuse them instead of rebuilding an ID table and
    // decoding collision policy for every idle body on every tick.
    const PackedInt64Array roster = spatial->get("unit_ids");
    const Dictionary slots = spatial->get("unit_index_by_id");
    if (roster.size() != entities.size() || slots.size() != entities.size()) return reject();
    const int64_t *roster_ids = roster.ptr();
    const int64_t count = entities.size();
    const int64_t revision = changes.get("revision", -1);
    const int64_t roster_revision = spatial->get("unit_roster_revision");
    const bool full = changes.get("full", false);
    const bool rebuild = full || revision < 0 || contact_journal_revision < 0 ||
            contact_spatial_owner != spatial->get_instance_id() || contact_roster_revision != roster_revision ||
            contact_journal_revision != int64_t(system->get("collision_cursor")) || int64_t(contact_poses.size()) != count;
    // A rejected or interrupted admission forces a full refresh next time.
    contact_journal_revision = -1;
    if (rebuild) contact_poses.resize(size_t(count));
    const double coordinate_limit = double(std::numeric_limits<int32_t>::max()) - 4096.0;
    const auto read_pose = [&](int64_t slot) -> bool {
        const Variant &value = entities[slot];
        if (value.get_type() != Variant::DICTIONARY) return false;
        const Dictionary &row = *VariantInternal::get_dictionary(&value);
        const Variant position = row.get(pos_key, Variant()), radius = row.get(radius_key, Variant());
        if (position.get_type() != Variant::VECTOR2 || !contact_number(radius)) return false;
        const Vector2 factual = *VariantInternal::get_vector2(&position);
        const double live_radius = contact_number_value(&radius);
        if (!std::isfinite(factual.x) || !std::isfinite(factual.y) || !std::isfinite(live_radius) || live_radius < 0.0 ||
                std::abs(double(factual.x) / cell_size) > coordinate_limit || std::abs(double(factual.y) / cell_size) > coordinate_limit) return false;
        ContactPose &pose = contact_poses[slot];
        pose.position = factual;
        pose.radius = live_radius;
        ++contact_pose_reads;
        return true;
    };
    if (rebuild) {
        ++contact_full_syncs;
        const Variant *indexed_radii = contact_array_values(radii);
        for (int64_t i = 0; i < count; ++i) {
            if (!read_pose(i) || !contact_number(indexed_radii[i])) return reject();
            contact_poses[i].indexed_radius = contact_number_value(&indexed_radii[i]);
            if (!std::isfinite(contact_poses[i].indexed_radius) || contact_poses[i].indexed_radius < 0.0) return reject();
        }
    }
    const Array cells = spatial->get("unit_cells");
    ContactGrid grid;
    if (cells.size() != entities.size() || !grid.build(cells)) return reject();

    std::vector<int32_t> ordered;
    ordered.reserve(size_t(active_units.size() + pending.size()));
    std::vector<uint8_t> selected(size_t(count), 0);
    std::unordered_set<int64_t> retired;
    const auto add = [&](const Dictionary &row, bool force) -> bool {
        const Variant id = row.get(id_key, Variant());
        if (id.get_type() != Variant::INT) return false;
        const int64_t slot = slots.get(id, -1);
        if (slot < 0) {
            // The spatial owner has not admitted this newly spawned actor yet.
            if (units_by_id.has(id) && double(row.get(hp_key, 0.0)) > 0.0) return false;
            if (force || !bool(row.get(isolated_key, false))) retired.insert(int64_t(id));
            return true;
        }
        if (slot >= count || roster_ids[slot] != int64_t(id)) return false;
        if (!selected[slot] && (force || !bool(row.get(isolated_key, false)))) {
            selected[slot] = 1;
            ordered.push_back(int32_t(slot));
        }
        return true;
    };
    const Array pending_ids = pending.keys();
    for (int64_t i = 0; i < pending_ids.size(); ++i) {
        if (pending_ids[i].get_type() != Variant::INT) return reject();
        const Variant value = pending[pending_ids[i]];
        if (value.get_type() != Variant::DICTIONARY || Dictionary(value).get(id_key, Variant()) != pending_ids[i] || !add(value, true)) return reject();
    }
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
            const int64_t slot = slots.get(ids[i], -1);
            if (slot >= count || (slot >= 0 && roster_ids[slot] != int64_t(ids[i]))) return reject();
            if (!rebuild && slot >= 0 && !read_pose(slot)) return reject();
            if (slot >= 0 && selected[slot]) continue;
            const Variant value = units_by_id.get(ids[i], Variant());
            if (value.get_type() != Variant::NIL && (value.get_type() != Variant::DICTIONARY || !add(value, false))) return reject();
        }
    }
    if (ordered.size() + retired.size() > 65536) return reject();
    for (const int32_t slot : ordered) {
        const double width = std::ceil(2.0 * (contact_poses[slot].radius + 0.25 + maximum_radius) / cell_size) + 3.0;
        if (width * width > 4096.0) return reject();
    }
    std::sort(ordered.begin(), ordered.end(), [&](int32_t a, int32_t b) { return roster_ids[a] < roster_ids[b]; });
    // Admission is complete. No rejection/restart is possible after writes.
    ++contact_frame_calls; contact_frame_rows += count;
    pending.clear();
    std::unordered_set<uint64_t> pairs;
    std::vector<int32_t> neighbors;
    Array reference;
    const auto correct = [&](ContactPose &row, const Dictionary &entity, const Vector2 &offset) -> double {
        const double moved = separate.call(entity, offset);
        row.position = entity[pos_key];
        return moved;
    };
    for (int32_t candidate_slot : ordered) {
        ContactPose &unit = contact_poses[candidate_slot];
        const int64_t id = roster_ids[candidate_slot];
        const Dictionary source_unit = entities[candidate_slot];
        if (double(source_unit.get(hp_key, 0.0)) <= 0.0 || !units_by_id.has(id)) continue;
        const double radius = unit.radius + 0.25, extent = radius + maximum_radius;
        const Vector2 minimum = (unit.position - Vector2(1, 1) * real_t(extent)) / real_t(cell_size);
        const Vector2 maximum = (unit.position + Vector2(1, 1) * real_t(extent)) / real_t(cell_size);
        neighbors.clear();
        // Typed Array[Vector2] belongs to the spatial owner. Borrow only
        // until this query finishes, before any script correction.
        const Variant *indexed = contact_array_values(positions);
        for (int y = int(std::floor(minimum.y)); y <= int(std::floor(maximum.y)); ++y) {
            for (int x = int(std::floor(minimum.x)); x <= int(std::floor(maximum.x)); ++x) {
                for (int32_t slot = grid.first(x, y); slot >= 0; slot = grid.next[slot]) {
                    const double allowed = radius + contact_poses[slot].indexed_radius;
                    if (slot != candidate_slot && unit.position.distance_squared_to(*VariantInternal::get_vector2(&indexed[slot])) <= allowed * allowed)
                        neighbors.push_back(slot);
                }
            }
        }
        std::stable_sort(neighbors.begin(), neighbors.end(), [&](int32_t left, int32_t right) { return roster_ids[left] < roster_ids[right]; });
        ++contact_frame_queries; contact_frame_neighbors += int64_t(neighbors.size());
        if (compare && contact_frame_comparisons < 512 && (contact_frame_comparisons < 8 || contact_frame_queries % 512 == 0)) {
            bool equal = spatial_unit_neighbors(source_unit, radius, Variant(), buckets, entities, positions, radii, cell_size, maximum_radius, reference);
            equal = equal && reference.size() == int64_t(neighbors.size());
            for (int64_t j = 0; equal && j < reference.size(); ++j) equal = int64_t(Dictionary(reference[j])[id_key]) == roster_ids[neighbors[size_t(j)]];
            ++contact_frame_comparisons;
            if (!equal) { ++contact_frame_mismatches; UtilityFunctions::push_error("Contact frame neighbor query differs from its spatial generation"); }
        }
        for (const int32_t slot : neighbors) {
            ContactPose &other = contact_poses[slot];
            const Vector2 gap = unit.position - other.position;
            const double sum = unit.radius + other.radius;
            if (gap.length_squared() >= (sum - 0.001) * (sum - 0.001)) continue;
            // Health and movement domain are needed only for a penetrating
            // pair. Corrections below alter position/targets only.
            const Dictionary other_unit = entities[slot];
            if (double(other_unit.get(hp_key, 0.0)) <= 0.0 || other_unit.get(domain_key, land) != source_unit.get(domain_key, land)) continue;
            const uint64_t pair = contact_cell(std::min(candidate_slot, slot), std::max(candidate_slot, slot));
            if (!pairs.insert(pair).second) continue;
            pending[id] = source_unit; pending[roster_ids[slot]] = other_unit;
            const double distance = gap.length();
            const Vector2 normal = distance > 0.0001 ? gap / real_t(distance) : Vector2(0, id < roster_ids[slot] ? -1 : 1);
            const double correction = std::min(sum - distance + 0.002, std::max(0.01, delta * 2.0));
            const double first = correct(unit, source_unit, normal * real_t(correction * 0.5));
            const double second = correct(other, other_unit, -normal * real_t(correction - first));
            if (second < correction * 0.5) correct(unit, source_unit, normal * real_t(correction * 0.5 - second));
        }
    }
    contact_spatial_owner = spatial->get_instance_id();
    contact_roster_revision = roster_revision;
    contact_journal_revision = revision;
    return int64_t(ordered.size() + retired.size());
}

Dictionary RoRReadModelKernel::contact_frame_stats() const {
    Dictionary result;
    result["calls"] = contact_frame_calls; result["rows"] = contact_frame_rows;
    result["queries"] = contact_frame_queries; result["neighbors"] = contact_frame_neighbors;
    result["fallbacks"] = contact_frame_fallbacks;
    result["full_pose_syncs"] = contact_full_syncs; result["pose_reads"] = contact_pose_reads;
    result["comparisons"] = contact_frame_comparisons; result["mismatches"] = contact_frame_mismatches;
    return result;
}
} // namespace godot
