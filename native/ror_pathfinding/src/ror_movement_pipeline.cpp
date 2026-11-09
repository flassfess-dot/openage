#include "ror_script_boundary_profile.hpp"
#include "ror_read_model_kernel.hpp"
#include "ror_actor_keys.hpp"
#include "ror_path_kernel.hpp"
#include "ror_actor_stage_scope.hpp"
#include <algorithm>
#include <cmath>

namespace godot {

namespace {
bool canonical_script(Object *object, const char *path) {
    if (!object) return false;
    const Variant value = RoRScriptBoundaryProfile::call(object, "get_script");
    Object *script = value.get_type() == Variant::OBJECT ? static_cast<Object *>(value) : nullptr;
    return script && String(script->get(ROR_PROPERTY("resource_path"))) == path;
}
}

bool RoRReadModelKernel::prepare_movement_batch(MovementBatchContext &batch, Object *world, Object *system) const {
    if (!canonical_script(world, "res://scripts/simulation_world.gd") ||
            !canonical_script(system, "res://scripts/simulation_movement_system.gd")) return false;
    batch.world = world; batch.system = system;
    batch.scoped_resource_digest = bool(system->get("scoped_resource_digest_tick"));
    if (batch.scoped_resource_digest) {
        const Variant value = world->get("resource_digest_job");
        if (value.get_type() == Variant::OBJECT && static_cast<Object *>(value)) {
            auto *digest = Object::cast_to<RoRResourceDigest>(static_cast<Object *>(value));
            if (digest && RoRScriptBoundaryProfile::call(digest, "get_script").get_type() == Variant::NIL)
                batch.resource_digest = Ref<RoRResourceDigest>(digest);
            else batch.scoped_resource_digest = false;
        }
    }
    batch.physical = world->get(ROR_PROPERTY("pathfinder")); batch.activity = world->get(ROR_PROPERTY("unit_activity_registry"));
    batch.elevation = world->get(ROR_PROPERTY("terrain_elevation")); batch.spatial = world->get(ROR_PROPERTY("spatial_index"));
    if (!batch.physical || !batch.activity || !batch.elevation || !batch.spatial) return false;
    const auto flag = [&](const char *name) { return bool(system->get(name)); };
    batch.typed_motion = flag("typed_motion_frame_enabled");
    batch.borrowed_motion_fields = flag("borrowed_motion_fields_enabled");
    batch.compare_typed_motion = flag("compare_typed_motion_frame");
    batch.native_route_preparation = flag("native_route_preparation_enabled");
    batch.motion_enabled = flag("native_combined_motion_enabled") && flag("native_combined_motion_supported") &&
        flag("native_integration_enabled") && flag("native_progress_enabled") &&
        !flag("profile_progress_alternatives") && !flag("profile_motion_alternatives");
    batch.group_enabled = flag("native_group_combined_enabled") && flag("native_group_combined_supported") &&
        flag("native_formation_yield_enabled") && flag("native_formation_yield_supported") &&
        flag("native_mobile_collision_enabled") && flag("native_collision_supported") &&
        !flag("profile_formation_yield_alternatives") && bool(RoRScriptBoundaryProfile::call(batch.physical, "uses_native_kernel"));
    Object *query = batch.spatial->get(ROR_PROPERTY("query_kernel"));
    batch.direct_neighbors = bool(batch.spatial->get(ROR_PROPERTY("native_neighbors_enabled"))) &&
        bool(batch.spatial->get(ROR_PROPERTY("native_neighbors_supported"))) && query && RoRScriptBoundaryProfile::call(query, "get_script").get_type() == Variant::NIL &&
        query->is_class("RoRReadModelKernel");
    return true;
}

void RoRReadModelKernel::refresh_movement_batch(MovementBatchContext &batch) const {
    // Policy callbacks may replace native snapshots and journal-backed arrays.
    // Resolve them only after the callback and never retain them across a tick.
    batch.shared_kernel = batch.physical->get(ROR_PROPERTY("native_shared_movement_kernel"));
    if (!batch.shared_kernel) batch.by_unit = batch.physical->get(ROR_PROPERTY("native_movement_kernels_by_unit_id"));
    batch.envelopes = batch.world->get(ROR_PROPERTY("open_movement_envelopes_by_id"));
    batch.vertices = int64_t(batch.elevation->get(ROR_PROPERTY("nonzero_vertex_count"))) > 0 ? Dictionary(batch.elevation->get(ROR_PROPERTY("vertex_levels"))) : Dictionary();
    batch.map_size = batch.world->get(ROR_PROPERTY("map_size"));
    batch.spatial_bindings_fresh = false;
    batch.bindings_fresh = true;
    ++batch.binding_refreshes;
}

void RoRReadModelKernel::refresh_spatial_bindings(MovementBatchContext &batch) const {
    if (batch.spatial_bindings_fresh) return;
    // Straight motion uses the kernel's existing neighborhood snapshot.
    // Only congestion and resource adoption inspect the live spatial index.
    batch.groups = batch.world->get(ROR_PROPERTY("formation_groups_view"));
    batch.neighbors = batch.world->get(ROR_PROPERTY("movement_neighbor_buffer"));
    batch.buckets = batch.spatial->get(ROR_PROPERTY("unit_buckets"));
    batch.entities = batch.spatial->get(ROR_PROPERTY("unit_entities")); batch.positions = batch.spatial->get(ROR_PROPERTY("unit_positions"));
    batch.radii = batch.spatial->get(ROR_PROPERTY("unit_radii")); batch.cell_size = batch.spatial->get(ROR_PROPERTY("cell_size"));
    batch.maximum_radius = batch.spatial->get(ROR_PROPERTY("maximum_unit_radius"));
    batch.maximum_clearance = batch.spatial->get(ROR_PROPERTY("maximum_unit_clearance"));
    batch.spatial_bindings_fresh = true;
}

// Public compatibility entry point. The ordered pass lends its stack context
// to domain handlers called synchronously inside that same pass.
Vector4 RoRReadModelKernel::advance_move_pipeline(Dictionary unit, double delta,
        Object *world, Object *system, Object *planner) const {
    if (active_movement_batch && active_movement_batch->world == world && active_movement_batch->system == system) {
        // A domain handler may issue several moves with mutations between them.
        // Each public re-entry is a new binding boundary, within the same pass.
        active_movement_batch->bindings_fresh = false;
        return advance_move_pipeline_internal(unit, delta, planner, *active_movement_batch);
    }
    MovementBatchContext batch;
    if (!prepare_movement_batch(batch, world, system) || !canonical_script(planner, "res://scripts/pathfinder.gd"))
        return Vector4(-1, 0, 0, 0);
    return advance_move_pipeline_internal(unit, delta, planner, batch);
}

// x: completed moving flag (-1 only before writes), y/z: native updates and
// candidates, w: policy stages. Native rejection resumes at the next stage.
Vector4 RoRReadModelKernel::advance_move_pipeline_internal(Dictionary unit, double delta,
        Object *planner, MovementBatchContext &batch) const {
    RoRActorStageScope setup_scope(batch.profile_stages, batch.stage_ns[0], batch.stage_calls[0]);
    Object *world = batch.world, *system = batch.system, *physical = batch.physical;
    if (!planner || unit.is_read_only() || !std::isfinite(delta) || delta < 0.0 ||
            int64_t(world->get(ROR_PROPERTY("read_generation_pins"))) != 0) return Vector4(-1, 0, 0, 0);
    ++batch.operations;
    static const Variant id("id"), pos("pos"), target("target"), path("path"), index("path_index"), group("formation_group_id");
    static const Variant radius("footprint_radius"), ticks("stuck_ticks"), task("task"), path_revision("path_knowledge_revision");
    const Variant pv = unit.get(pos, Variant()), tv = unit.get(target, Variant()), routev = unit.get(path, Variant());
    if (pv.get_type() != Variant::VECTOR2 || tv.get_type() != Variant::VECTOR2 || routev.get_type() != Variant::ARRAY) return Vector4(-1, 0, 0, 0);
    Object *grid = planner->get(ROR_PROPERTY("grid"));
    if (!grid || !physical) return Vector4(-1, 0, 0, 0);
    int64_t stages = 0;
    const Array route = routev;
    Vector2 position = pv, waypoint = tv;
    int64_t group_id = unit.get(group, -1);
    const int64_t revision = grid->get(ROR_PROPERTY("revision"));
    const bool refresh = int64_t(unit.get(path_revision, revision)) != revision && !route.is_empty();
    bool corner = false;
    if (group_id >= 0 && int64_t(unit.get(index, 0)) + 1 < route.size() && position.distance_squared_to(waypoint) <= 4.0) {
        const String task_name = unit[task];
        corner = task_name == ROR_TEXT("move") || task_name == ROR_TEXT("attack_move");
    }
    setup_scope.stop();
    if (refresh || corner) {
        RoRActorStageScope phase_scope(batch.profile_stages, batch.stage_ns[1], batch.stage_calls[1]);
        if (!batch.native_route_preparation || !prepare_move_route_native(unit, planner, batch)) {
            ++batch.route_preparation_fallbacks;
            batch.bindings_fresh = false;
            RoRScriptBoundaryProfile::call(system, "_prepare_move_route", unit, planner, world);
            batch.bindings_fresh = false;
        }
        // Replanning may change the live waypoint or detach the unit from its formation.
        position = unit[pos];
        waypoint = unit[target];
        group_id = unit[group];
        stages |= 1;
    }
    if (position.distance_squared_to(waypoint) < 0.001225) {
        RoRActorStageScope phase_scope(batch.profile_stages, batch.stage_ns[2], batch.stage_calls[2]);
        batch.bindings_fresh = false;
        const bool moving = RoRScriptBoundaryProfile::call(system, "_advance_move_arrival", unit, delta, world);
        batch.bindings_fresh = false;
        return Vector4(moving ? 1 : 0, 0, 0, real_t(stages | 2));
    }
    const auto script_motion = [&](bool attempt_combined) {
        RoRActorStageScope phase_scope(batch.profile_stages, batch.stage_ns[3], batch.stage_calls[3]);
        batch.bindings_fresh = false;
        const bool moving = RoRScriptBoundaryProfile::call(system, "_advance_motion_body", unit, delta, planner, world, Variant(), attempt_combined);
        batch.bindings_fresh = false;
        return Vector4(moving ? 1 : 0, 0, 0, real_t(stages | 4));
    };
    if (!batch.bindings_fresh) {
        RoRActorStageScope phase_scope(batch.profile_stages, batch.stage_ns[4], batch.stage_calls[4]);
        refresh_movement_batch(batch);
    }
    const int64_t actor_id = unit[id];
    if (batch.envelopes.get(actor_id, Variant()).get_type() != Variant::NIL) return script_motion(true);
    Object *kernel = batch.shared_kernel;
    if (!kernel) {
        const Variant value = batch.by_unit.get(actor_id, Variant());
        if (value.get_type() == Variant::OBJECT) kernel = value;
    }
    if (!kernel || !bool(batch.activity->get(ROR_PROPERTY("tick_prepared"))) || !batch.motion_enabled) return script_motion(true);
    const int64_t stalled = unit[ticks];
    bool group_combined = false;
    int64_t stop_tick = 30;
    if (stalled >= 4 && group_id >= 0 && batch.group_enabled && (String(unit[task]) != ROR_TEXT("gather") || stalled < 29)) {
        refresh_spatial_bindings(batch);
        const Variant value = batch.groups.get(group_id, Variant());
        Object *formation = value.get_type() == Variant::OBJECT ? static_cast<Object *>(value) : nullptr;
        if (formation) {
            const Array members = formation->get(ROR_PROPERTY("member_ids"));
            stop_tick += std::min(int64_t(1200), members.size() * int64_t(20));
        }
        group_combined = stalled < stop_tick - 1;
    }
    if (!(stalled < 4 || (stalled < 29 && group_id < 0) || group_combined)) return script_motion(true);
    Array &neighbors = batch.neighbors;
    if (group_combined) {
        const double search_radius = 1.6 * double(unit[radius]) + 0.6 * batch.maximum_radius + 1.6 * batch.maximum_clearance;
        neighbors.clear();
        if (batch.direct_neighbors) {
            if (!spatial_unit_neighbors(unit, search_radius, Variant(), batch.buckets, batch.entities, batch.positions, batch.radii,
                    batch.cell_size, batch.maximum_radius, neighbors)) return script_motion(true);
        } else {
            RoRScriptBoundaryProfile::call(batch.spatial, "query_neighbors_into", unit, search_radius, ROR_TEXT("unit"), neighbors);
        }
    }
    Vector4 step;
    {
        RoRActorStageScope phase_scope(batch.profile_stages, batch.stage_ns[5], batch.stage_calls[5]);
        // A scripted neighbor provider may have mutated the unit. Only lend
        // these decoded values across the fully native path to the solver.
        const MotionInputs inputs{position, waypoint, actor_id, stalled, group_id};
        step = advance_motion_internal(unit, kernel, delta, batch.map_size, batch.vertices,
            group_combined ? &neighbors : nullptr, group_combined ? physical : nullptr, stop_tick,
            !group_combined || batch.direct_neighbors ? &inputs : nullptr);
    }
    // Native rejection precedes all writes. Continue at the motion solver;
    // route preparation, arrival and actor timers are never replayed.
    if (step.x < 0.0) return script_motion(false);
    const int64_t mask = int64_t(std::llround(step.x));
    if (mask) {
        if (batch.publish) batch.publish(unit, int64_t(unit[id]), mask);
        else RoRScriptBoundaryProfile::call(world, "notify_entity_changed", unit, mask);
    }
    const int64_t checkpoint = unit[ticks];
    const bool at_checkpoint = group_combined && (checkpoint == 60 || checkpoint == 180 || checkpoint == 360 || checkpoint == 720);
    // Yielding deliberately pauses progress escalation. A held counter is not
    // another checkpoint event: retrying here repeated the entire detour search
    // every tick until traffic moved, despite the bounded checkpoint policy.
    const bool late = at_checkpoint && checkpoint != stalled;
    if (at_checkpoint && checkpoint == stalled) ++batch.traffic_checkpoint_holds;
    if (late) ++batch.traffic_checkpoint_entries;
    if (int64_t(std::llround(step.w)) != 0 || late) {
        RoRActorStageScope phase_scope(batch.profile_stages, batch.stage_ns[6], batch.stage_calls[6]);
        batch.bindings_fresh = false;
        RoRScriptBoundaryProfile::call(system, "_finish_native_move", unit, planner, step, group_combined, Variant(), stalled);
        batch.bindings_fresh = false;
        stages |= 8;
    }
    return Vector4(1, 1, step.y, real_t(stages));
}

} // namespace godot
