#include "ror_actor_keys.hpp"
#include "ror_read_model_kernel.hpp"
#include "ror_path_kernel.hpp"
#include "ror_script_boundary_profile.hpp"
#include <godot_cpp/variant/rect2.hpp>
#include <cmath>

namespace godot {
namespace {
bool route_script(Object *object, const char *path) {
    if (!object) return false;
    const Variant value = RoRScriptBoundaryProfile::call(object, "get_script");
    Object *script = value.get_type() == Variant::OBJECT ? static_cast<Object *>(value) : nullptr;
    return script && String(script->get("resource_path")) == path;
}
}

// The ordered pass owns this reader. The canonical grid and unit dictionaries
// remain authoritative; a revision/epoch change discards all borrowed regions.
// This does not defer a route check or change the order of actor updates.
bool RoRReadModelKernel::prepare_move_route_native(Dictionary unit, Object *planner, MovementBatchContext &batch) const {
    if (!batch.publish) return false;
    const Variant digest = batch.scoped_resource_digest ? Variant() : batch.world->get("resource_digest_job");
    if (digest.get_type() == Variant::OBJECT && static_cast<Object *>(digest)) return false;
    if (batch.resource_digest.is_valid()) batch.resource_digest->before_change(int64_t(unit[ROR_FIELD("id")]));
    auto found = batch.route_preparations.find(planner);
    if (found == batch.route_preparations.end()) {
        MovementBatchContext::RoutePreparation reader;
        reader.canonical = route_script(planner, "res://scripts/pathfinder.gd") && bool(planner->get("fast_direct_checks_enabled")) && bool(planner->get("native_enabled")) &&
            bool(planner->get("native_available"));
        if (reader.canonical) {
            reader.grid_reference = planner->get("grid");
            reader.grid = reader.grid_reference.get_type() == Variant::OBJECT ? static_cast<Object *>(reader.grid_reference) : nullptr;
            reader.canonical = route_script(reader.grid, "res://scripts/navigation_grid.gd") ||
                route_script(reader.grid, "res://scripts/navigation_knowledge_grid.gd");
        }
        found = batch.route_preparations.emplace(planner, std::move(reader)).first;
    }
    auto &reader = found->second;
    if (!reader.canonical || !reader.grid) return false;
    const int64_t revision = reader.grid->get("revision"), epoch = reader.grid->get("cache_epoch");
    if (revision != reader.revision || epoch != reader.epoch) {
        reader.regions.clear(); reader.revision = revision; reader.epoch = epoch;
    }
    static const Variant id_key("id"), pos_key("pos"), target_key("target"), path_key("path");
    static const Variant revision_key("path_knowledge_revision"), index_key("path_index"), radius_key("footprint_radius");
    const int64_t id = unit[id_key], old_revision = unit.get(revision_key, revision);
    const Array path = unit[path_key];
    const Vector2 position = unit[pos_key];
    const double radius = unit[radius_key];
    const String domain = unit[ROR_FIELD("movement_domain")];
    const int64_t restriction = unit[ROR_FIELD("terrain_restriction")];
    // Obtain a synchronized canonical mask only when a geometry predicate is
    // needed. Merely reading metadata must not rebuild or copy that mask.
    Ref<RoRPathKernel> kernel;
    const auto get_kernel = [&]() -> RoRPathKernel * {
        if (kernel.is_valid()) return kernel.ptr();
        for (auto &entry : reader.kernels) {
            if (entry.domain != domain || entry.restriction != restriction) continue;
            auto *cached = Object::cast_to<RoRPathKernel>(static_cast<Object *>(entry.reference));
            if (cached && cached->get_revision() == int64_t(reader.grid->get("revision"))) {
                kernel = Ref<RoRPathKernel>(cached);
                return cached;
            }
            break;
        }
        const Variant value = RoRScriptBoundaryProfile::call(planner, "_native_kernel_for", domain, restriction);
        Object *object = value.get_type() == Variant::OBJECT ? static_cast<Object *>(value) : nullptr;
        auto *native = object ? Object::cast_to<RoRPathKernel>(object) : nullptr;
        if (!native) return nullptr;
        const Variant script = RoRScriptBoundaryProfile::call(native, "get_script");
        if (script.get_type() == Variant::OBJECT && static_cast<Object *>(script)) return nullptr;
        kernel = Ref<RoRPathKernel>(native);
        bool retained = false;
        for (auto &entry : reader.kernels) {
            if (entry.domain == domain && entry.restriction == restriction) {
                entry.reference = value; retained = true; break;
            }
        }
        if (!retained && reader.kernels.size() < 32) reader.kernels.push_back({domain, restriction, value});
        return native;
    };
    if (old_revision != revision && !path.is_empty()) {
        auto region = reader.regions.find(old_revision);
        if (region == reader.regions.end()) {
            if (reader.regions.size() >= 32) reader.regions.clear();
            const Variant value = RoRScriptBoundaryProfile::call(reader.grid, "change_region_since", old_revision);
            region = reader.regions.emplace(old_revision, value).first;
            ++batch.route_region_reads;
        }
        const Vector2 target = unit[target_key];
        const Rect2 bounds = Rect2(position, Vector2()).expand(target).grow(radius + 1.0);
        if (region->second.get_type() != Variant::RECT2 || bounds.intersects(Rect2(region->second))) {
            auto *native = get_kernel();
            if (!native) return false; // No writes have happened yet.
            const Vector2i start(int32_t(std::floor(position.x)), int32_t(std::floor(position.y)));
            const Vector2i goal(int32_t(std::floor(target.x)), int32_t(std::floor(target.y)));
            const bool water_clear = domain != ROR_TEXT("water") || radius <= 0.0 ||
                native->is_segment_walkable(Vector2(start) + Vector2(0.5, 0.5), Vector2(goal) + Vector2(0.5, 0.5), radius);
            if (!water_clear || !native->has_direct_cell_path(start, goal, radius)) {
                ++batch.route_replans;
                batch.bindings_fresh = false;
                RoRScriptBoundaryProfile::call(batch.system, "assign_unit_destination", unit, unit[ROR_FIELD("destination")], false);
                batch.bindings_fresh = false;
            }
        }
        const int64_t current_revision = reader.grid->get("revision");
        if (unit.get(revision_key, Variant()) != Variant(current_revision)) {
            unit[revision_key] = current_revision;
            batch.publish(unit, id, 96); // Same scalar field mask as the facade.
        }
    }
    ++batch.route_preparation_calls;
    const String task = unit[ROR_FIELD("task")];
    if (int64_t(unit[ROR_FIELD("formation_group_id")]) < 0 || (task != ROR_TEXT("move") && task != ROR_TEXT("attack_move"))) return true;
    const Array current_path = unit[path_key];
    const int64_t next = int64_t(unit[index_key]) + 1;
    if (next <= int64_t(unit.get(ROR_FIELD("formation_traffic_prefix"), 0))) return true;
    if (next >= current_path.size() || position.distance_squared_to(Vector2(unit[target_key])) > 4.0) return true;
    auto *native = get_kernel();
    if (!native) {
        batch.bindings_fresh = false;
        RoRScriptBoundaryProfile::call(batch.system, "_advance_formation_corner", unit, planner);
        batch.bindings_fresh = false;
        return true;
    }
    if (!native->is_segment_walkable(position, Vector2(current_path[next]), radius)) return true;
    if (next == current_path.size() - 1 && position.distance_squared_to(Vector2(unit[ROR_FIELD("destination")])) < 64.0) {
        // Final deployment also consults live mobile bodies. Preserve that
        // complete policy, including its original spatial query and ordering.
        batch.bindings_fresh = false;
        RoRScriptBoundaryProfile::call(batch.system, "_advance_formation_corner", unit, planner);
        batch.bindings_fresh = false;
        return true;
    }
    ++batch.route_corners;
    unit[index_key] = next;
    const Vector2 target = current_path[next];
    int64_t mask = 68;
    if (Vector2(unit[target_key]) != target) { unit[target_key] = target; mask |= 70; }
    batch.publish(unit, id, mask);
    return true;
}
} // namespace godot
