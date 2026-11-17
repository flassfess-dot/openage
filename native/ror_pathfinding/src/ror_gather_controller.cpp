#include "ror_script_boundary_profile.hpp"
#include "ror_read_model_kernel.hpp"
#include "ror_entity_change_journal.hpp"
#include "ror_actor_keys.hpp"
#include "ror_actor_stage_scope.hpp"
#include "ror_path_kernel.hpp"
#include <algorithm>
#include <cmath>
#include <limits>

namespace godot {
namespace {
enum GatherResult { IDLE = 0, MOVE = 1, ACTION = 2, CARRY_IDLE = 3, CARRY_MOVE = 4, MOVE_IDLE = 5 };

bool in_resource_range(const Dictionary &worker, const Dictionary &resource) {
    const Vector2 position = worker[ROR_FIELD("pos")];
    const Vector2i cell(position);
    const Vector2 offset = position - Vector2(cell);
    if (String(worker.get(ROR_FIELD("movement_domain"), ROR_FIELD("land"))) != ROR_TEXT("water") &&
            (cell == Vector2i(Vector2(resource[ROR_FIELD("pos")])) || offset.x < 0.12 || offset.x > 0.88 || offset.y < 0.12 || offset.y > 0.88)) return false;
    const double reach = std::max(0.5, double(resource.get(ROR_FIELD("footprint_radius"), 0.2))) + double(worker.get(ROR_FIELD("footprint_radius"), 0.3)) + 0.32;
    return position.distance_squared_to(Vector2(resource[ROR_FIELD("pos")])) <= reach * reach;
}

bool accessible(const Dictionary &resource, int64_t team) {
    return !bool(resource.get(ROR_FIELD("harvestable"), false)) || int64_t(resource.get(ROR_FIELD("team"), 0)) == team;
}
}

int64_t RoRReadModelKernel::maximum_gatherers(const Dictionary &resource, ActorBatchContext &batch) const {
    const String kind = resource.get(ROR_FIELD("kind"), String());
    if (!batch.maximum_gatherers.has(kind))
        batch.maximum_gatherers[kind] = RoRScriptBoundaryProfile::call(batch.repository, "runtime_field", kind, ROR_TEXT("max_gatherers"), int64_t(0));
    return batch.maximum_gatherers[kind];
}

bool RoRReadModelKernel::advance_worksite_clock(Dictionary unit, int64_t id, double delta,
        ActorBatchContext &batch, MovementBatchContext &movement) const {
    // A worker between two actions has only two advancing scalars. Finish at
    // this actor's ordinary ordered position so depletion by an earlier worker
    // or displacement by another unit takes effect on this very tick.
    if (!movement.scoped_resource_digest || unit.is_read_only() ||
            unit.get(ROR_FIELD("gather_stage"), Variant()) != ROR_FIELD("harvesting")) return false;
    RoRActorStageScope clock_scope(batch.profile_stages, batch.worksite_ns, batch.worksite_calls);
    const double work = unit.get(ROR_FIELD("work"), 0.0);
    if (!(work > delta) || !std::isfinite(delta)) return false;
    const int64_t resource_id = unit[ROR_FIELD("resource_id")];
    const Variant target = gather_target(resource_id, batch);
    if (target.get_type() != Variant::DICTIONARY) return false;
    const Dictionary resource = target;
    if (int64_t(resource[ROR_FIELD("amount")]) <= 0) return false;
    const Vector2 resource_position = resource[ROR_FIELD("pos")];
    const auto contested = [&]() {
        const Variant slots = batch.resource_slots.get(resource_id, Variant());
        return slots.get_type() == Variant::DICTIONARY && Dictionary(slots).size() > 1;
    };
    const auto advance_clocks = [&]() {
        if (movement.resource_digest.is_valid()) movement.resource_digest->before_change(id);
        unit[ROR_FIELD("work")] = work - delta;
        unit[ROR_FIELD("anim")] = double(unit[ROR_FIELD("anim")]) + delta;
        ++batch.worksite_clock_updates;
        ++batch.calls;
        ++batch.native_animations;
    };
    WorksiteClock *site = nullptr;
    int64_t revision = -1;
    if (batch.journal && !batch.journal->is_full()) {
        site = &worksite_clocks[size_t(id) % worksite_clocks.size()];
        revision = batch.journal->revision_for(id);
        if (site->worker == id && site->revision == revision && site->resource == resource_id &&
                site->resource_position == resource_position && (!site->needs_single_slot || !contested())) {
            advance_clocks();
            ++batch.retained_worksites;
            return true;
        }
    }
    if (unit.get(ROR_FIELD("anim_state"), Variant()) != ROR_FIELD("Gather") ||
            double(unit.get(ROR_FIELD("hp"), 0.0)) <= 0.0 || double(unit.get(ROR_FIELD("cooldown"), 0.0)) > 0.0 ||
            int64_t(unit.get(ROR_FIELD("retaliation_target_id"), -1)) >= 0) return false;
    const Variant route = unit.get(ROR_FIELD("path"), Variant()), slot = unit.get(ROR_FIELD("resource_approach_slot"), Variant());
    if (route.get_type() != Variant::ARRAY || !Array(route).is_empty() ||
            Vector2(unit.get(ROR_FIELD("actual_velocity"), Vector2())) != Vector2()) return false;
    const Vector2 position = unit[ROR_FIELD("pos")];
    const bool at_slot = slot.get_type() == Variant::VECTOR2 && position.distance_squared_to(Vector2(slot)) <= 0.0144;
    const bool needs_single_slot = !at_slot && slot.get_type() == Variant::VECTOR2;
    if (!at_slot && (!in_resource_range(unit, resource) || (needs_single_slot && contested()))) return false;
    const Dictionary parts = unit[ROR_FIELD("components")];
    const Dictionary role = parts[ROR_FIELD("worker")], faith = parts[ROR_FIELD("conversion")], order = parts[ROR_FIELD("order")];
    if (!bool(role[ROR_FIELD("enabled")]) || bool(faith[ROR_FIELD("enabled")]) ||
            order.get(ROR_FIELD("phase"), Variant()) != ROR_FIELD("Recover")) return false;
    const double capacity = unit[ROR_FIELD("carry_capacity")];
    if (capacity > 0.0 && double(unit[ROR_FIELD("carried_amount")]) >= capacity - 0.0001) return false;
    const Vector2 difference = resource_position - position;
    if (difference.length_squared() > 0.0001) {
        const double facing_angle = std::atan2(-double((difference.x - difference.y) * 32.0),
                double((difference.x + difference.y) * 16.0));
        const int64_t facing = (int64_t(std::round(facing_angle / (6.283185307179586476925286766559 / 8.0))) % 8 + 8) % 8;
        if (unit[ROR_FIELD("facing")] != Variant(facing) || unit[ROR_FIELD("desired_facing")] != Variant(facing) ||
                unit[ROR_FIELD("action_facing")] != Variant(facing)) return false;
    }
    // A revision in the open journal batch can still coalesce another change
    // at that same number. Only a closed revision certifies later ticks.
    if (site && revision >= 0 && revision <= batch.journal->get_revision())
        *site = {id, revision, resource_id, resource_position, needs_single_slot};
    advance_clocks();
    return true;
}

Vector4 RoRReadModelKernel::advance_gather_motion(Dictionary unit, double delta,
        ActorBatchContext &batch, MovementBatchContext &movement) const {
    RoRActorStageScope scope(batch.profile_stages, batch.gather_ns[0], batch.gather_calls[0]);
    const int64_t team = unit.get(ROR_FIELD("team"), 0);
    const int64_t revision = select_actor_planner(team, batch, movement);
    const int64_t id = unit[ROR_FIELD("id")], stalled = unit[ROR_FIELD("stuck_ticks")];
    const int64_t group = unit[ROR_FIELD("formation_group_id")];
    const Vector2 position = unit[ROR_FIELD("pos")], waypoint = unit[ROR_FIELD("target")];
    Object *kernel = movement.shared_kernel;
    if (!kernel && movement.bindings_fresh) {
        const Variant actor_kernel = movement.by_unit.get(id, Variant());
        if (actor_kernel.get_type() == Variant::OBJECT) kernel = actor_kernel;
    }
    if (revision >= 0 && movement.motion_enabled && kernel && movement.publish &&
            group < 0 && stalled < 4 && !movement.envelopes.has(id) &&
            unit.get(ROR_FIELD("path_knowledge_revision"), int64_t(-1)) == Variant(revision) &&
            position.distance_squared_to(waypoint) >= 0.001225 && !Array(unit[ROR_FIELD("path")]).is_empty()) {
        // The committed route already supplies a waypoint. Use the same
        // collision, terrain, progress and journal operations as every mover.
        // Crossing a waypoint or changing topology goes through the planner.
        const MotionInputs inputs{position, waypoint, id, stalled, group};
        const Vector4 step = advance_motion_internal(unit, kernel, delta, movement.map_size,
                movement.vertices, nullptr, nullptr, 30, &inputs);
        if (step.x >= 0.0) {
            ++batch.committed_worker_steps;
            ++movement.operations;
            const int64_t mask = int64_t(std::llround(step.x));
            if (mask) movement.publish(unit, id, mask);
            if (int64_t(std::llround(step.w)) != 0) {
                movement.bindings_fresh = false;
                RoRScriptBoundaryProfile::call(batch.movement, "_finish_native_move", unit, batch.planner, step, false, Variant(), stalled);
                movement.bindings_fresh = false;
            }
            ++batch.motion_updates;
            batch.candidates += int64_t(std::llround(step.y));
            return Vector4(1, 1, step.y, 0);
        }
        // The solver rejected before writing. Continue from the same stage
        // used by the general movement pipeline for a blocked step.
        movement.bindings_fresh = false;
        const bool moved = RoRScriptBoundaryProfile::call(batch.movement, "_advance_motion_body", unit, delta,
                batch.planner, batch.world, Variant(), false);
        movement.bindings_fresh = false;
        return Vector4(moved ? 1 : 0, 0, 0, 0);
    }
    Vector4 step = advance_move_pipeline_internal(unit, delta, batch.planner, movement);
    if (step.x < 0.0) {
        movement.bindings_fresh = false;
        const bool moving = RoRScriptBoundaryProfile::call(batch.movement, "_move_unit_reference", unit, delta, batch.planner);
        movement.bindings_fresh = false;
        return Vector4(moving ? 1 : 0, 0, 0, 0);
    }
    batch.motion_updates += std::max(int64_t(0), int64_t(std::llround(step.y)));
    batch.candidates += std::max(int64_t(0), int64_t(std::llround(step.z)));
    return step;
}

Variant RoRReadModelKernel::adopt_gather_resource(Dictionary unit, Dictionary requested,
        ActorBatchContext &batch, MovementBatchContext &movement) const {
    RoRActorStageScope scope(batch.profile_stages, batch.gather_ns[1], batch.gather_calls[1]);
    const Vector2 position = unit[ROR_FIELD("pos")];
    if (String(unit.get(ROR_FIELD("movement_domain"), ROR_FIELD("land"))) != ROR_TEXT("land") ||
            position.distance_squared_to(Vector2(requested[ROR_FIELD("pos")])) > 7.501 * 7.501) return Variant();
    const Dictionary resources_by_cell = batch.world->get(ROR_PROPERTY("resource_nodes_by_cell"));
    const Vector2i size = batch.world->get(ROR_PROPERTY("map_size"));
    const String kind = requested.get(ROR_FIELD("kind"), String());
    const Vector2 requested_position = requested[ROR_FIELD("pos")];
    Array candidates;
    const Array nearby = resources_in_radius(resources_by_cell, size, position, 1.5);
    for (int64_t index = 0; index < nearby.size(); ++index) {
        const Dictionary candidate = nearby[index];
        if (String(candidate.get(ROR_FIELD("kind"), String())) == kind && int64_t(candidate.get(ROR_FIELD("amount"), 0)) > 0 &&
                Vector2(candidate[ROR_FIELD("pos")]).distance_squared_to(requested_position) <= 36.0) candidates.append(candidate);
    }
    if (candidates.is_empty()) return Variant();
    Object *physical = batch.world->get(ROR_PROPERTY("pathfinder"));
    const Variant kernel_value = RoRScriptBoundaryProfile::call(physical, "_native_kernel_for", ROR_TEXT("land"), int64_t(unit.get(ROR_FIELD("terrain_restriction"), -1)));
    RoRPathKernel *kernel = kernel_value.get_type() == Variant::OBJECT ? Object::cast_to<RoRPathKernel>(static_cast<Object *>(kernel_value)) : nullptr;
    if (!kernel || !kernel->position_walkable(position, double(unit[ROR_FIELD("footprint_radius")]))) return Variant();
    if (!movement.bindings_fresh) refresh_movement_batch(movement);
    refresh_spatial_bindings(movement);
    const int64_t overlap = spatial_unit_match(unit, 1.5, 1, movement.buckets, movement.entities, movement.positions,
            movement.radii, movement.cell_size, movement.maximum_radius);
    if (overlap > 0 || (overlap < 0 && bool(RoRScriptBoundaryProfile::call(movement.spatial, "has_live_overlap", unit, 1.5)))) return Variant();
    // resources_in_radius uses the same ID ordering as the canonical query.
    // Explicit sorting also protects compatibility providers of that index.
    std::vector<Dictionary> ordered;
    ordered.reserve(candidates.size());
    for (int64_t index = 0; index < candidates.size(); ++index) ordered.push_back(candidates[index]);
    std::sort(ordered.begin(), ordered.end(), [](const Dictionary &left, const Dictionary &right) {
        return int64_t(left[ROR_FIELD("id")]) < int64_t(right[ROR_FIELD("id")]);
    });
    const int64_t actor_id = unit[ROR_FIELD("id")], team = unit.get(ROR_FIELD("team"), 0);
    const String domain = unit.get(ROR_FIELD("movement_domain"), ROR_FIELD("land"));
    const Dictionary by_unit = batch.world->get(ROR_PROPERTY("units_by_id"));
    const Dictionary reservations = batch.world->get(ROR_PROPERTY("resource_approach_slots"));
    for (const Dictionary &candidate : ordered) {
        if (!in_resource_range(unit, candidate) || !accessible(candidate, team)) continue;
        if (candidate.has(ROR_FIELD("allowed_gatherer_domains"))) {
            Array allowed = candidate[ROR_FIELD("allowed_gatherer_domains")];
            if (allowed.is_empty()) { if (domain != ROR_TEXT("land")) continue; }
            else if (!allowed.has(domain)) continue;
        } else if (!bool(RoRScriptBoundaryProfile::call(batch.world, "resource_allows_worker", candidate, unit))) continue;
        if (maximum_gatherers(candidate, batch) > 0) continue;
        Array displaced;
        bool occupied = false;
        const Array neighborhood = resources_in_radius(resources_by_cell, size, position, 3.0);
        for (int64_t index = 0; index < neighborhood.size() && !occupied; ++index) {
            const Dictionary resource = neighborhood[index];
            const Dictionary slots = reservations.get(resource[ROR_FIELD("id")], Dictionary());
            const Array ids = slots.keys();
            for (int64_t slot_index = 0; slot_index < ids.size(); ++slot_index) {
                const int64_t other_id = ids[slot_index];
                if (other_id == actor_id) continue;
                const Variant other_value = by_unit.get(other_id, Variant());
                if (other_value.get_type() != Variant::DICTIONARY) continue;
                const Dictionary other = other_value;
                const double separation = double(unit[ROR_FIELD("footprint_radius")]) + double(other[ROR_FIELD("footprint_radius")]) + 0.06;
                if (position.distance_squared_to(Vector2(slots[other_id])) >= separation * separation) continue;
                if (String(other.get(ROR_FIELD("gather_stage"), String())) == ROR_TEXT("harvesting") ||
                        Vector2(other[ROR_FIELD("pos")]).distance_squared_to(Vector2(slots[other_id])) <= 0.0144) { occupied = true; break; }
                displaced.append(other);
            }
        }
        // Occupancy tests the worker's current position against all nearby
        // reservations, independently of the candidate resource. Once blocked,
        // every remaining eligible candidate would repeat the same failed test.
        if (occupied) { ++batch.gather_controller_blocked_adoptions; return Variant(); }
        movement.bindings_fresh = false;
        RoRScriptBoundaryProfile::call(batch.gathering, "_complete_cluster_adoption", unit, candidate, position, displaced);
        movement.bindings_fresh = false;
        ++batch.gather_controller_adoptions;
        return candidate;
    }
    return Variant();
}

Variant RoRReadModelKernel::gather_target(const Variant &id, const ActorBatchContext &batch) {
    const Variant node = batch.resource_nodes.get(id, Variant());
    if (node.get_type() != Variant::NIL) return node;
    const Variant entity = batch.buildings.get(id, Variant());
    if (entity.get_type() != Variant::DICTIONARY) return Variant();
    const Dictionary building = entity;
    if (bool(building.get(ROR_FIELD("harvestable"), false)) &&
            String(building.get(ROR_FIELD("state"), ROR_TEXT("complete"))) == ROR_TEXT("complete") &&
            double(building.get(ROR_FIELD("hp"), 0.0)) > 0.0) return entity;
    return Variant();
}

int64_t RoRReadModelKernel::advance_gather_controller(Dictionary unit, double delta, bool waiting, const Variant &target,
        ActorBatchContext &batch, MovementBatchContext &movement) const {
    ++batch.gather_controller_calls;
    const auto continuation = [&]() -> int64_t {
        RoRActorStageScope scope(batch.profile_stages, batch.gather_ns[2], batch.gather_calls[2]);
        ++batch.gather_controller_transitions;
        movement.bindings_fresh = false;
        const Variant result = RoRScriptBoundaryProfile::invoke(batch.gather_continue, "gather_continuation", unit, delta, waiting);
        movement.bindings_fresh = false;
        return result.get_type() == Variant::INT ? int64_t(result) : std::numeric_limits<int64_t>::min();
    };
    const auto ensure_destination = [&](const Vector2 &destination) {
        RoRActorStageScope scope(batch.profile_stages, batch.gather_ns[3], batch.gather_calls[3]);
        const Vector2 previous = unit.get(ROR_FIELD("destination"), unit[ROR_FIELD("pos")]);
        if (previous.distance_squared_to(destination) <= 0.25 && !Array(unit.get(ROR_FIELD("path"), Array())).is_empty()) return;
        movement.bindings_fresh = false;
        RoRScriptBoundaryProfile::call(batch.movement, "ensure_navigation_destination", unit, destination);
        movement.bindings_fresh = false;
    };
    RoRActorStageScope setup_scope(batch.profile_stages, batch.gather_ns[7], batch.gather_calls[7]);
    const Dictionary parts = unit[ROR_FIELD("components")], worker = parts[ROR_FIELD("worker")];
    if (!bool(worker[ROR_FIELD("enabled")])) return continuation();
    setup_scope.stop();
    if (String(unit[ROR_FIELD("gather_stage")]) == ROR_TEXT("returning")) {
        RoRActorStageScope returning_scope(batch.profile_stages, batch.gather_ns[6], batch.gather_calls[6]);
        ++batch.gather_controller_returns;
        if (double(unit[ROR_FIELD("carried_amount")]) <= 0.0) return continuation();
        const Variant value = batch.buildings.get(unit[ROR_FIELD("dropoff_id")], Variant());
        if (value.get_type() != Variant::DICTIONARY) return continuation();
        const Dictionary dropoff = value;
        if (double(dropoff[ROR_FIELD("hp")]) <= 0.0 || unit[ROR_FIELD("dropoff_position")].get_type() != Variant::VECTOR2) return continuation();
        const Vector2 destination = unit[ROR_FIELD("dropoff_position")], position = unit[ROR_FIELD("pos")];
        bool within = position.distance_squared_to(destination) <= 0.0144;
        if (!within) {
            const Dictionary footprint = dropoff.get(ROR_FIELD("footprint"), Dictionary());
            const Vector2 half = footprint.get(ROR_FIELD("half_size"), Vector2(0.5, 0.5));
            const Vector2 offset = (position - Vector2(dropoff[ROR_FIELD("pos")])).abs();
            const Vector2 outside(std::max(0.0, double(offset.x) - half.x), std::max(0.0, double(offset.y) - half.y));
            const double radius = unit.get(ROR_FIELD("footprint_radius"), 0.3), reach = radius + 0.55 + 0.12;
            if (outside.length_squared() <= reach * reach) {
                Object *physical = batch.world->get(ROR_PROPERTY("pathfinder"));
                const Variant kernel_value = RoRScriptBoundaryProfile::call(physical, "_native_kernel_for", String(unit.get(ROR_FIELD("movement_domain"), ROR_FIELD("land"))), int64_t(unit.get(ROR_FIELD("terrain_restriction"), -1)));
                RoRPathKernel *kernel = kernel_value.get_type() == Variant::OBJECT ? Object::cast_to<RoRPathKernel>(static_cast<Object *>(kernel_value)) : nullptr;
                within = kernel && kernel->position_walkable(position, radius);
            }
        }
        if (within) {
            ++batch.gather_controller_transitions;
            movement.bindings_fresh = false;
            const int64_t result = RoRScriptBoundaryProfile::call(batch.gathering, "_complete_resource_deposit", unit, dropoff);
            movement.bindings_fresh = false;
            return result;
        }
        ensure_destination(destination);
        ++batch.gather_controller_moves;
        return advance_gather_motion(unit, delta, batch, movement).x > 0.0 ? CARRY_MOVE : CARRY_IDLE;
    }

    RoRActorStageScope resource_scope(batch.profile_stages, batch.gather_ns[8], batch.gather_calls[8]);
    const double capacity = std::max(0.0, double(unit[ROR_FIELD("carry_capacity")]));
    if (target.get_type() != Variant::DICTIONARY) return continuation();
    Dictionary resource = target;
    if (int64_t(resource[ROR_FIELD("amount")]) <= 0 || (capacity > 0.0 && double(unit[ROR_FIELD("carried_amount")]) >= capacity - 0.0001)) return continuation();
    if (waiting) {
        if (double(unit[ROR_FIELD("work")]) > 0.0) return IDLE;
        return continuation();
    }
    resource_scope.stop();
    if (String(unit.get(ROR_FIELD("gather_stage"), String())) == ROR_TEXT("approaching") &&
            int64_t(unit.get(ROR_FIELD("path_index"), 0)) == 0 && Array(unit.get(ROR_FIELD("path"), Array())).size() > 1) {
        RoRActorStageScope shortening_scope(batch.profile_stages, batch.gather_ns[4], batch.gather_calls[4]);
        if (String(unit.get(ROR_FIELD("movement_domain"), ROR_FIELD("land"))) == ROR_TEXT("land") && maximum_gatherers(resource, batch) <= 0) {
            const Array route = unit[ROR_FIELD("path")];
            const Variant reviewed = unit.get(ROR_FIELD("gather_route_review"), Variant());
            bool needs_review = true;
            if (!batch.exhaustive_cluster_routes && reviewed.get_type() == Variant::ARRAY) {
                const Array key = reviewed;
                const int64_t request = unit.get(ROR_FIELD("path_request_id"), -1);
                const int64_t route_id = request > 0 ? request : -1 - int64_t(route.hash());
                // A local same-cell endpoint adjustment can reuse a request.
                // All other installed gather paths get a new navigation request.
                needs_review = key.size() != 5 || key[0] != resource[ROR_FIELD("id")] ||
                    key[1] != unit[ROR_FIELD("team")] || key[3] != Variant(route_id) || key[4] != route.back() ||
                    key[2] != Dictionary(parts[ROR_FIELD("order")])[ROR_FIELD("revision")];
            }
            if (needs_review) {
                movement.bindings_fresh = false;
                const Variant replacement = RoRScriptBoundaryProfile::call(batch.gathering, "_shorten_cluster_route", unit, resource);
                movement.bindings_fresh = false;
                if (replacement.get_type() == Variant::DICTIONARY) resource = replacement;
            }
        }
    }
    if (int64_t(unit.get(ROR_FIELD("stuck_ticks"), 0)) >= 6 && String(unit.get(ROR_FIELD("gather_stage"), String())) == ROR_TEXT("approaching")) {
        const Variant replacement = adopt_gather_resource(unit, resource, batch, movement);
        if (replacement.get_type() == Variant::DICTIONARY) resource = replacement;
    }
    RoRActorStageScope range_scope(batch.profile_stages, batch.gather_ns[5], batch.gather_calls[5]);
    bool in_range = in_resource_range(unit, resource);
    if (!in_range && unit[ROR_FIELD("resource_approach_slot")].get_type() != Variant::VECTOR2) {
        movement.bindings_fresh = false;
        const bool prepared = RoRScriptBoundaryProfile::call(batch.gathering, "prepare_group_gather_approach", unit, resource);
        movement.bindings_fresh = false;
        if (!prepared) { RoRScriptBoundaryProfile::call(batch.gathering, "finish_gather_order", unit, ROR_TEXT("no_approach_slot")); return IDLE; }
        const Variant assigned = gather_target(unit[ROR_FIELD("resource_id")], batch);
        if (assigned.get_type() != Variant::DICTIONARY) return continuation();
        resource = assigned;
    }
    const Variant slot = unit[ROR_FIELD("resource_approach_slot")];
    if (slot.get_type() == Variant::VECTOR2) {
        const Vector2 position = unit[ROR_FIELD("pos")];
        bool at_slot = position.distance_squared_to(Vector2(slot)) <= 0.0144;
        const Dictionary &all_reservations = batch.resource_slots;
        Dictionary reservations = all_reservations.get(unit[ROR_FIELD("resource_id")], Dictionary());
        const double minimum = double(resource.get(ROR_FIELD("footprint_radius"), 0.2)) + double(unit.get(ROR_FIELD("footprint_radius"), 0.3)) + 0.12;
        if (!at_slot && in_range && position.distance_squared_to(Vector2(resource[ROR_FIELD("pos")])) >= minimum * minimum && reservations.size() > 1) {
            Array positions; positions.append(position);
            const Dictionary by_cell = batch.world->get(ROR_PROPERTY("resource_nodes_by_cell")), by_unit = batch.world->get(ROR_PROPERTY("units_by_id"));
            const PackedByteArray occupied = occupied_resource_slots(unit, positions, Vector2i(batch.world->get(ROR_PROPERTY("map_size"))), by_cell, all_reservations, by_unit, 0.03, 0.06);
            if (occupied.size() == 1 && occupied[0] == 0) {
                reservations[unit[ROR_FIELD("id")]] = position;
                movement.bindings_fresh = false;
                RoRScriptBoundaryProfile::call(batch.world, "set_entity_field", unit, ROR_TEXT("resource_approach_slot"), position);
                movement.bindings_fresh = false;
                at_slot = true;
            }
        }
        in_range = reservations.size() > 1 ? at_slot : in_range || at_slot;
    }
    range_scope.stop();
    if (!in_range) {
        const Vector2 destination = unit[ROR_FIELD("resource_approach_slot")];
        if (String(unit[ROR_FIELD("gather_stage")]) != ROR_TEXT("approaching")) {
            movement.bindings_fresh = false;
            RoRScriptBoundaryProfile::call(batch.world, "set_entity_field", unit, ROR_TEXT("gather_stage"), ROR_TEXT("approaching"));
            movement.bindings_fresh = false;
        }
        ensure_destination(destination);
        ++batch.gather_controller_moves;
        return advance_gather_motion(unit, delta, batch, movement).x > 0.0 ? MOVE : MOVE_IDLE;
    }
    ++batch.gather_controller_transitions;
    RoRActorStageScope action_scope(batch.profile_stages, batch.gather_ns[9], batch.gather_calls[9]);
    movement.bindings_fresh = false;
    const int64_t result = RoRScriptBoundaryProfile::call(batch.gathering, "_perform_gather_action", unit, resource, capacity);
    movement.bindings_fresh = false;
    return result;
}

} // namespace godot
