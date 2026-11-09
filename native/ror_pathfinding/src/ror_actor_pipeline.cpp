#include "ror_script_boundary_profile.hpp"
#include "ror_read_model_kernel.hpp"
#include "ror_actor_keys.hpp"
#include "ror_actor_stage_scope.hpp"
#include <algorithm>
#include <cmath>
#include <limits>

namespace godot {

bool RoRReadModelKernel::prepare_actor_batch(ActorBatchContext &batch, const Dictionary &context) const {
    batch.profile_stages = context.get(ROR_FIELD("profile_actor_stages"), false);
    batch.world = context[ROR_FIELD("world")]; batch.movement = context[ROR_FIELD("movement_system")];
    batch.gathering = context.get(ROR_FIELD("gathering_system"), Variant());
    batch.conversion = context.get(ROR_FIELD("conversion_system"), Variant()); batch.knowledge = context[ROR_FIELD("knowledge")];
    batch.domain = context.get(ROR_FIELD("actor_domain"), Callable());
    batch.gather_continue = context.get(ROR_FIELD("gather_continue"), Callable());
    batch.context = context[ROR_FIELD("actor_context")];
    const Variant result = batch.context.get(ROR_FIELD("domain_result"), Variant());
    const Variant states = batch.context.get(ROR_FIELD("animation_states"), Variant()), clips = batch.context.get(ROR_FIELD("animation_clips"), Variant());
    const Variant visuals = batch.context.get(ROR_FIELD("gather_visuals"), Variant());
    if (!batch.world || !batch.movement || !batch.gathering || !batch.conversion || !batch.knowledge ||
            !batch.domain.is_valid() || !batch.gather_continue.is_valid() || result.get_type() != Variant::ARRAY ||
            states.get_type() != Variant::ARRAY || clips.get_type() != Variant::DICTIONARY || visuals.get_type() != Variant::DICTIONARY) return false;
    batch.result = result; batch.animation_states = states; batch.animation_clips = clips; batch.gather_visuals = visuals;
    if (batch.result.size() != 3 || batch.result.is_read_only() || !batch.animation_states.has(ROR_TEXT("Idle"))) return false;
    batch.gather_action = batch.context.get(ROR_FIELD("gather_action"), -1);
    const Variant visual = batch.gather_visuals.get(batch.gather_action, Variant());
    if (visual.get_type() != Variant::ARRAY || Array(visual).size() != 2) return false;
    Object *kernel = batch.gathering->get(ROR_PROPERTY("recovery_kernel"));
    const Variant script = kernel ? RoRScriptBoundaryProfile::call(kernel, "get_script") : Variant();
    batch.native_gather = bool(batch.gathering->get(ROR_PROPERTY("native_recovery_enabled"))) &&
        bool(batch.gathering->get(ROR_PROPERTY("native_recovery_supported"))) && !bool(batch.gathering->get(ROR_PROPERTY("profile_gather_portions"))) &&
        kernel && Object::cast_to<RoRReadModelKernel>(kernel) && (script.get_type() == Variant::NIL || (script.get_type() == Variant::OBJECT && !static_cast<Object *>(script)));
    batch.repository = batch.world->get(ROR_PROPERTY("data_repository"));
    batch.approach = batch.world->get(ROR_PROPERTY("approach_system"));
    const Variant gather_script_value = RoRScriptBoundaryProfile::call(batch.gathering, "get_script");
    Object *gather_script = gather_script_value.get_type() == Variant::OBJECT ? static_cast<Object *>(gather_script_value) : nullptr;
    batch.gather_controller = batch.native_gather && bool(context.get(ROR_FIELD("gather_controller"), false)) && batch.repository && batch.approach &&
        gather_script && String(gather_script->get(ROR_PROPERTY("resource_path"))) == ROR_TEXT("res://scripts/simulation_gathering_system.gd") &&
        batch.gather_action == 2 && batch.gathering->has_method("_perform_gather_action") &&
        batch.gathering->has_method("_complete_resource_deposit") && batch.gathering->has_method("_complete_cluster_adoption");
    return true;
}

int64_t RoRReadModelKernel::advance_actor_animation(Dictionary unit, const String &requested, double delta,
        const Array &states, const Dictionary &clips) const {
    static const Variant state_key("anim_state"), anim_key("anim"), events_key("animation_events_fired");
    const String state = states.has(requested) ? requested : ROR_TEXT("Idle");
    const String previous = unit.get(state_key, String());
    if (previous != state) {
        unit[state_key] = state;
        const bool restart_attack = state == ROR_TEXT("AttackWindup") && previous == ROR_TEXT("AttackRecover");
        if (restart_attack || clips.get(previous, ROR_TEXT("idle")) != clips.get(state, ROR_TEXT("idle"))) {
            unit[anim_key] = 0.0; unit[events_key] = Dictionary();
        } else unit[anim_key] = double(unit.get(anim_key, 0.0)) + std::max(0.0, delta);
        return 32;
    }
    unit[anim_key] = double(unit.get(anim_key, 0.0)) + std::max(0.0, delta);
    return 0;
}

// -1 rejects before writes; 0 completes one actor; 1 aborts without replay.
int64_t RoRReadModelKernel::advance_actor_pipeline(Dictionary unit, double delta, ActorBatchContext &batch,
        MovementBatchContext &movement) const {
    RoRActorStageScope actor_scope(batch.profile_stages, batch.stage_ns[0], batch.stage_calls[0]);
    static const Variant id("id"), hp("hp"), task("task"), pos("pos"), target("target"), path("path"), path_index("path_index");
    static const Variant parts_key("components"), conversion_key("conversion"), enabled_key("enabled"), retaliation("retaliation_target_id");
    static const Variant stage("gather_stage"), slot_key("resource_approach_slot"), work("work"), velocity("actual_velocity");
    RoRActorStageScope preparation_scope(batch.profile_stages, batch.stage_ns[1], batch.stage_calls[1]);
    const Variant pv = unit.get(pos, Variant()), routev = unit.get(path, Variant()), partsv = unit.get(parts_key, Variant());
    if (unit.is_read_only() || pv.get_type() != Variant::VECTOR2 || routev.get_type() != Variant::ARRAY ||
            partsv.get_type() != Variant::DICTIONARY || !std::isfinite(delta) || delta <= 0.0) return -1;
    const int64_t actor_id = unit.get(id, -1);
    if (actor_id < 0) return -1;
    if (movement.scoped_resource_digest) {
        ++batch.scoped_digest_actors;
        if (movement.resource_digest.is_valid()) {
            movement.resource_digest->before_change(actor_id);
            ++batch.scoped_digest_protections;
        }
    }
    ++batch.calls;
    const auto publish = [&](int64_t mask) {
        if (!mask) return;
        if (movement.publish) movement.publish(unit, actor_id, mask);
        else RoRScriptBoundaryProfile::call(batch.world, "notify_entity_changed", unit, mask);
    };
    if (double(unit.get(hp, 0.0)) <= 0.0) {
        movement.bindings_fresh = false;
        RoRScriptBoundaryProfile::call(batch.world, "begin_death", unit);
        return 0;
    }
    // Capture the domain and idle predicate before reaction, as on the original
    // actor path. A reaction may change the live task/target for this tick.
    const String task_name = unit.get(task, ROR_TEXT("idle"));
    const Vector2 position = pv;
    const bool stable_idle = task_name == ROR_TEXT("idle") && Array(routev).is_empty() &&
        int64_t(unit.get(path_index, 0)) == 0 && Vector2(unit.get(target, position)) == position;
    int64_t timer_mask = 0;
    const Variant digest = movement.scoped_resource_digest ? Variant() : batch.world->get(ROR_PROPERTY("resource_digest_job"));
    const bool digest_active = digest.get_type() == Variant::OBJECT && static_cast<Object *>(digest);
    for (const char *name : {"cooldown", "work"}) {
        const double value = unit.get(name, 0.0);
        if (!(value > 0.0)) continue;
        if (digest_active) RoRScriptBoundaryProfile::call(batch.world, "set_entity_field", unit, String(name), std::max(0.0, value-delta));
        else { unit[String(name)] = std::max(0.0, value-delta); timer_mask |= 68; }
    }
    publish(timer_mask);
    const Dictionary parts = partsv, faith = parts.get(conversion_key, Dictionary());
    if (bool(faith.get(enabled_key, false))) {
        movement.bindings_fresh = false;
        RoRScriptBoundaryProfile::call(batch.conversion, "advance_faith", unit, delta);
        movement.bindings_fresh = false;
    }
    if (int64_t(unit.get(retaliation, -1)) >= 0) {
        movement.bindings_fresh = false;
        RoRScriptBoundaryProfile::call(batch.world, "_update_huntable_reaction", unit);
        movement.bindings_fresh = false;
    }
    preparation_scope.stop();
    bool moving = false, handled = false;
    String animation = ROR_TEXT("Idle");
    Variant attack_target;
    if (task_name == ROR_TEXT("move") || task_name == ROR_TEXT("attack_move")) {
        RoRActorStageScope stage_scope(batch.profile_stages, batch.stage_ns[2], batch.stage_calls[2]);
        const int64_t team = unit.get(ROR_FIELD("team"), 0);
        if (!batch.planner || batch.planner_team != team || !movement.bindings_fresh) {
            batch.planner_value = RoRScriptBoundaryProfile::call(batch.knowledge, "planner", batch.world, team);
            batch.planner = batch.planner_value.get_type() == Variant::OBJECT ? static_cast<Object *>(batch.planner_value) : nullptr;
            batch.planner_team = team;
        }
        ++batch.move_attempts;
        const Vector4 step = advance_move_pipeline_internal(unit, delta, batch.planner, movement);
        if (step.x >= 0.0) {
            moving = step.x > 0.0; handled = true; ++batch.direct_moves;
            batch.motion_updates += std::max(int64_t(0), int64_t(std::llround(step.y)));
            batch.candidates += std::max(int64_t(0), int64_t(std::llround(step.z)));
        }
    } else if (task_name == ROR_TEXT("gather") && batch.native_gather) {
        RoRActorStageScope stage_scope(batch.profile_stages, batch.stage_ns[3], batch.stage_calls[3]);
        const Variant slot = unit.get(slot_key, Variant());
        const bool waiting = String(unit.get(stage, String())) == ROR_TEXT("approaching") && slot.get_type() != Variant::VECTOR2;
        const bool reached = double(unit.get(work, 0.0)) > 0.0 && slot.get_type() == Variant::VECTOR2 &&
            Vector2(unit[pos]).distance_squared_to(Vector2(slot)) <= 0.0144;
        if ((String(unit.get(stage, String())) == ROR_TEXT("harvesting") || reached) &&
                (!Array(unit[path]).is_empty() || Vector2(unit.get(velocity, Vector2())) != Vector2())) {
            movement.bindings_fresh = false;
            RoRScriptBoundaryProfile::call(batch.movement, "stop_unit_motion", unit, false);
            movement.bindings_fresh = false;
        }
        int64_t result = -1;
        if (!waiting) {
            RoRActorStageScope recovery_scope(batch.profile_stages, batch.stage_ns[4], batch.stage_calls[4]);
            const Dictionary resources = batch.world->get(ROR_PROPERTY("resource_nodes_by_id")), reservations = batch.world->get(ROR_PROPERTY("resource_approach_slots"));
            const int64_t mask = advance_harvesting_recovery(unit, resources, reservations);
            if (mask >= 0) { publish(mask); result = batch.gather_action; ++batch.gather_recoveries; }
        }
        if (result < 0) {
            RoRActorStageScope continuation_scope(batch.profile_stages, batch.stage_ns[5], batch.stage_calls[5]);
            Variant value;
            if (batch.gather_controller) {
                value = advance_gather_controller(unit, delta, waiting, batch, movement);
            } else {
                movement.bindings_fresh = false;
                value = RoRScriptBoundaryProfile::invoke(batch.gather_continue, "gather_continuation", unit, delta, waiting);
                movement.bindings_fresh = false;
            }
            if (value.get_type() != Variant::INT) return 1;
            result = value; ++batch.gather_continuations;
        }
        const Variant visual = batch.gather_visuals.get(result, Variant());
        if (visual.get_type() != Variant::ARRAY || Array(visual).size() != 2) return 1;
        const Array state = visual;
        moving = state[0]; animation = state[1]; handled = true;
    }
    if (!handled) {
        RoRActorStageScope stage_scope(batch.profile_stages, batch.stage_ns[6], batch.stage_calls[6]);
        movement.bindings_fresh = false;
        RoRScriptBoundaryProfile::invoke_kind(batch.domain, "actor_domain", task_name, unit, delta, batch.context, task_name, stable_idle);
        movement.bindings_fresh = false;
        moving = batch.result[0]; animation = batch.result[1]; attack_target = batch.result[2];
        ++batch.domain_callbacks;
    }
    {
    RoRActorStageScope animation_scope(batch.profile_stages, batch.stage_ns[7], batch.stage_calls[7]);
    if (moving && animation != ROR_TEXT("Carry")) animation = ROR_TEXT("Move");
    const Variant animation_digest = movement.scoped_resource_digest ? Variant() : batch.world->get(ROR_PROPERTY("resource_digest_job"));
    if (animation_digest.get_type() == Variant::OBJECT && static_cast<Object *>(animation_digest)) {
        const bool restart = animation == ROR_TEXT("AttackWindup") && String(unit.get(ROR_FIELD("anim_state"), String())) == ROR_TEXT("AttackRecover");
        RoRScriptBoundaryProfile::call(batch.world, "advance_entity_animation", unit, animation, delta, restart);
        ++batch.script_animations;
    } else {
        publish(advance_actor_animation(unit, animation, delta, batch.animation_states, batch.animation_clips));
        ++batch.native_animations;
    }
    }
    if (attack_target.get_type() != Variant::NIL) {
        RoRActorStageScope stage_scope(batch.profile_stages, batch.stage_ns[8], batch.stage_calls[8]);
        movement.bindings_fresh = false;
        RoRScriptBoundaryProfile::call(batch.world, "apply_attack_frame_event", unit, attack_target, batch.context[ROR_FIELD("player")]);
        movement.bindings_fresh = false;
    }
    return 0;
}

} // namespace godot
