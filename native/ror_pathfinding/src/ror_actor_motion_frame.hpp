#pragma once
#include "ror_actor_keys.hpp"

#include <algorithm>
#include <cmath>
#include <godot_cpp/core/gdextension_interface_loader.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/vector2.hpp>
#include <godot_cpp/variant/vector2i.hpp>

namespace godot {

inline double terrain_height_at(const Vector2 &position, const Vector2i &size, const Dictionary &vertices) {
    if (vertices.is_empty()) return 0.0;
    const Vector2 clamped(std::clamp(double(position.x), 0.0, double(size.x) - 0.0001),
            std::clamp(double(position.y), 0.0, double(size.y) - 0.0001));
    const Vector2i cell(int32_t(std::floor(clamped.x)), int32_t(std::floor(clamped.y)));
    const Vector2 local = clamped - Vector2(cell);
    const double a = int64_t(vertices.get(cell, 0)), b = int64_t(vertices.get(cell + Vector2i(1, 0), 0));
    const double c = int64_t(vertices.get(cell + Vector2i(0, 1), 0)), d = int64_t(vertices.get(cell + Vector2i(1, 1), 0));
    const double top = a + (b - a) * double(local.x), bottom = c + (d - c) * double(local.x);
    return top + (bottom - top) * double(local.y);
}

// One synchronous actor stage. Canonical rows are decoded once, then arithmetic
// uses typed values. Commit precedes publication/another actor or script call.
// Nothing here survives the stage, so external writers need no invalidation API.
struct RoRActorMotionFrame {
    enum Field { DESIRED, ACTUAL, POSITION, DESIRED_FACING, HEIGHT, DIAGNOSTIC,
        MOVEMENT_FACING, FACING, STUCK, PRIORITY, FIELD_COUNT };
    static const Variant &key(Field field) {
        static const Variant keys[FIELD_COUNT] = {"desired_velocity", "actual_velocity", "pos", "desired_facing",
            "elevation", "diagnostic_reason", "movement_facing", "facing", "stuck_ticks", "push_priority"};
        return keys[field];
    }
    enum NavigationField { COMPONENTS, ORDER, DESTINATION, BASE_PRIORITY, PROGRESS, GOAL, LEG, BEST, ORDER_REVISION };
    static const Variant &navigation_key(NavigationField field) {
        static const Variant keys[] = {"components", "order", "destination", "base_push_priority", "navigation_progress",
            "goal", "leg", "best", "order_revision"};
        return keys[field];
    }
    Vector2 position, target, destination, desired, actual;
    int64_t desired_facing = 0, movement_facing = 0, facing = 0, stuck = 0, priority = 0, base_priority = 0;
    int64_t order_revision = 0;
    double elevation = 0;
    String diagnostic;
    static const Dictionary &empty_watch() {
        static const Dictionary value = []() { Dictionary result; result.make_read_only(); return result; }();
        return value;
    }
    Dictionary watch = empty_watch();
    Vector2 watch_goal, watch_leg;
    double watch_best = 0;
    int64_t watch_revision = 0;
    uint32_t dirty = 0;
    int64_t mask = 0;
    bool watch_reset = false;
    bool has_watch = false, watch_leg_changed = false, watch_best_changed = false;

    // The same const-index API used by godot-cpp's Dictionary::operator[].
    // A missing key stays null instead of being inserted. Borrowed pointers
    // are decoded here and never survive a mutation, callback or owner stage.
    static const Variant *find_field(const Dictionary &row, const Variant &name) {
        if (!row.has(name)) return nullptr;
        return reinterpret_cast<const Variant *>(gdextension_interface::dictionary_operator_index_const(row._native_ptr(), name._native_ptr()));
    }
    bool load_borrowed(const Dictionary &unit, const Vector2 &start, const Vector2 &leg) {
        const Variant *values[FIELD_COUNT] = {};
        static const Variant::Type types[FIELD_COUNT] = {Variant::VECTOR2, Variant::VECTOR2, Variant::VECTOR2,
            Variant::INT, Variant::FLOAT, Variant::STRING, Variant::INT, Variant::INT, Variant::INT, Variant::INT};
        for (int i = 0; i < FIELD_COUNT; ++i) {
            if (i == POSITION) continue;
            values[i] = find_field(unit, key(Field(i)));
            if (!values[i] || values[i]->get_type() != types[i]) return false;
        }
        const Variant *base = find_field(unit, navigation_key(BASE_PRIORITY));
        if (!base || base->get_type() != Variant::INT) return false;
        const Variant *goal = find_field(unit, navigation_key(DESTINATION));
        if (goal && goal->get_type() != Variant::VECTOR2) return false;
        position = start; target = leg; destination = goal ? Vector2(*goal) : leg;
        desired = *values[DESIRED]; actual = *values[ACTUAL];
        desired_facing = *values[DESIRED_FACING]; elevation = *values[HEIGHT]; diagnostic = *values[DIAGNOSTIC];
        movement_facing = *values[MOVEMENT_FACING]; facing = *values[FACING];
        stuck = *values[STUCK]; priority = *values[PRIORITY]; base_priority = *base;
        const Variant *parts = find_field(unit, navigation_key(COMPONENTS));
        if (parts) {
            if (parts->get_type() != Variant::DICTIONARY) return false;
            const Dictionary components = *parts;
            const Variant *order_value = find_field(components, navigation_key(ORDER));
            if (order_value) {
                if (order_value->get_type() != Variant::DICTIONARY) return false;
                const Dictionary order = *order_value;
                static const Variant revision_key("revision");
                const Variant *revision = find_field(order, revision_key);
                order_revision = revision ? int64_t(*revision) : 0;
            }
        }
        const Variant *progress = find_field(unit, navigation_key(PROGRESS));
        if (progress) {
            if (progress->get_type() != Variant::DICTIONARY) return false;
            watch = *progress;
            if (watch.is_read_only()) return false;
        }
        has_watch = !watch.is_empty();
        if (has_watch) {
            const Variant *watch_goal_value = find_field(watch, navigation_key(GOAL));
            const Variant *previous_leg = find_field(watch, navigation_key(LEG));
            const Variant *best = find_field(watch, navigation_key(BEST));
            const Variant *revision = find_field(watch, navigation_key(ORDER_REVISION));
            if (!watch_goal_value || !previous_leg || !best || !revision ||
                    watch_goal_value->get_type() != Variant::VECTOR2 || previous_leg->get_type() != Variant::VECTOR2 ||
                    best->get_type() != Variant::FLOAT || revision->get_type() != Variant::INT) return false;
            watch_goal = *watch_goal_value; watch_leg = *previous_leg; watch_best = *best; watch_revision = *revision;
        }
        return true;
    }

    bool load(const Dictionary &unit, const Vector2 &start, const Vector2 &leg) {
        Variant values[FIELD_COUNT];
        static const Variant::Type types[FIELD_COUNT] = {Variant::VECTOR2, Variant::VECTOR2, Variant::VECTOR2,
            Variant::INT, Variant::FLOAT, Variant::STRING, Variant::INT, Variant::INT, Variant::INT, Variant::INT};
        for (int i = 0; i < FIELD_COUNT; ++i) {
            if (i == POSITION) { values[i] = start; continue; }
            values[i] = unit.get(key(Field(i)), Variant());
            if (values[i].get_type() != types[i]) return false;
        }
        const Variant base = unit.get(navigation_key(BASE_PRIORITY), Variant());
        if (base.get_type() != Variant::INT) return false;
        position = start; target = leg; destination = unit.get(navigation_key(DESTINATION), leg);
        desired = values[DESIRED]; actual = values[ACTUAL];
        desired_facing = values[DESIRED_FACING]; elevation = values[HEIGHT]; diagnostic = values[DIAGNOSTIC];
        movement_facing = values[MOVEMENT_FACING]; facing = values[FACING];
        stuck = values[STUCK]; priority = values[PRIORITY]; base_priority = base;
        const Dictionary components = unit.get(navigation_key(COMPONENTS), Dictionary());
        const Dictionary order = components.get(navigation_key(ORDER), Dictionary());
        order_revision = order.get("revision", 0);
        const Variant progress = unit.get(navigation_key(PROGRESS), Dictionary());
        if (progress.get_type() != Variant::DICTIONARY) return false;
        watch = progress;
        if (watch.is_read_only()) return false;
        has_watch = !watch.is_empty();
        if (has_watch) {
            const Variant goal = watch.get(navigation_key(GOAL), Variant()), previous_leg = watch.get(navigation_key(LEG), Variant());
            const Variant best = watch.get(navigation_key(BEST), Variant()), revision = watch.get(navigation_key(ORDER_REVISION), Variant());
            if (goal.get_type() != Variant::VECTOR2 || previous_leg.get_type() != Variant::VECTOR2 ||
                    best.get_type() != Variant::FLOAT || revision.get_type() != Variant::INT) return false;
            watch_goal = goal; watch_leg = previous_leg; watch_best = best; watch_revision = revision;
        }
        return true;
    }
    void set_vector(Vector2 &field, const Vector2 &value, Field index, int64_t changed) {
        if (field == value) return;
        field = value; dirty |= uint32_t(1) << index; mask |= changed;
    }
    void set_integer(int64_t &field, int64_t value, Field index, int64_t changed = 0) {
        if (field == value) return;
        field = value; dirty |= uint32_t(1) << index; mask |= changed;
    }
    void set_reason(const String &value) {
        if (diagnostic == value) return;
        diagnostic = value; dirty |= uint32_t(1) << DIAGNOSTIC;
    }
    void set_velocities(const Vector2 &wanted, const Vector2 &solved) {
        set_vector(desired, wanted, DESIRED, 96);
        set_vector(actual, solved, ACTUAL, 70);
    }
    static int64_t direction_facing(const Vector2 &direction) {
        const Vector2 screen((direction.x - direction.y) * 32.0, (direction.x + direction.y) * 16.0);
        if (screen.length_squared() <= 0.0001) return 0;
        return (int64_t(std::round(std::atan2(-double(screen.x), double(screen.y)) /
            (6.283185307179586476925286766559 / 8.0))) % 8 + 8) % 8;
    }
    void integrate(double delta, const Vector2i &map_size, const Dictionary &vertices, const String &reason) {
        if (desired.length_squared() > 0.000001)
            set_integer(desired_facing, direction_facing(desired), DESIRED_FACING, 96);
        if (!reason.is_empty() && diagnostic != reason) { set_reason(reason); mask |= 96; }
        const Vector2 start = position, difference = target - start;
        const Vector2 step = actual * delta;
        set_vector(position, step.length_squared() >= difference.length_squared() && step.dot(difference) > 0.0 ?
            target : start + step, POSITION, 2);
        if (position.x < 0.5 || position.y < 0.5 || position.x > double(map_size.x) - 0.5 || position.y > double(map_size.y) - 0.5) {
            set_vector(position, Vector2(std::max(0.5, std::min(double(position.x), double(map_size.x) - 0.5)),
                std::max(0.5, std::min(double(position.y), double(map_size.y) - 0.5))), POSITION, 2);
        }
        const double next_height = terrain_height_at(position, map_size, vertices);
        if (elevation != next_height) { elevation = next_height; dirty |= uint32_t(1) << HEIGHT; mask |= 96; }
        const Vector2 displacement = position - start;
        set_vector(actual, delta > 0.0 ? displacement / delta : Vector2(), ACTUAL, 70);
        if (displacement.length_squared() > 0.000001) {
            const int64_t direction = direction_facing(displacement);
            set_integer(movement_facing, direction, MOVEMENT_FACING, 96);
            set_integer(facing, direction, FACING, 2);
        }
    }
    String advance_progress(int64_t stop_tick) {
        const double distance = position.distance_to(target);
        if (!has_watch || (order_revision == 0 && double(watch_goal.distance_squared_to(destination)) > 0.01) || watch_revision != order_revision) {
            watch = Dictionary(); watch_reset = true;
            set_integer(stuck, 0, STUCK); set_integer(priority, base_priority, PRIORITY);
            watch_goal = destination; watch_leg = target; watch_best = distance; watch_revision = order_revision;
            return String();
        }
        double squared_progress = 0.0;
        const Vector2 previous_leg = watch_leg;
        const double best = watch_best;
        if (double(previous_leg.distance_squared_to(target)) > 0.0001) {
            const double forward = best - double(position.distance_to(previous_leg));
            watch_leg = target; watch_best = distance; watch_leg_changed = true; watch_best_changed = true;
            if (forward >= 0.015) squared_progress = forward * forward;
        } else {
            const double improvement = best - distance;
            if (improvement >= 0.015) { watch_best = distance; watch_best_changed = true; squared_progress = improvement * improvement; }
        }
        if (squared_progress > 0.000001) {
            set_integer(stuck, 0, STUCK); set_integer(priority, base_priority, PRIORITY);
            if (!diagnostic.is_empty() && diagnostic.begins_with(ROR_TEXT("stuck_"))) set_reason(String());
            return String();
        }
        set_integer(stuck, stuck + 1, STUCK);
        if (stuck == 6) { set_reason(ROR_TEXT("stuck_local_repath")); return ROR_TEXT("local_repath"); }
        if (stuck == 12) { set_integer(priority, base_priority + 2, PRIORITY); set_reason(ROR_TEXT("stuck_priority_boost")); return ROR_TEXT("priority_boost"); }
        if (stuck == 18) { set_reason(ROR_TEXT("stuck_global_repath")); return ROR_TEXT("global_repath"); }
        if (stuck >= std::max(int64_t(30), stop_tick)) { set_reason(ROR_TEXT("stuck_stopped_nearest_valid")); return ROR_TEXT("stop"); }
        return String();
    }
    void commit(Dictionary unit) {
        for (int i = 0; i < FIELD_COUNT; ++i) {
            if (!(dirty & (uint32_t(1) << i))) continue;
            Variant value;
            switch (Field(i)) {
                case DESIRED: value = desired; break;
                case ACTUAL: value = actual; break;
                case POSITION: value = position; break;
                case DESIRED_FACING: value = desired_facing; break;
                case HEIGHT: value = elevation; break;
                case DIAGNOSTIC: value = diagnostic; break;
                case MOVEMENT_FACING: value = movement_facing; break;
                case FACING: value = facing; break;
                case STUCK: value = stuck; break;
                case PRIORITY: value = priority; break;
                default: break;
            }
            unit[key(Field(i))] = value;
        }
        if (watch_reset) {
            watch[navigation_key(GOAL)] = watch_goal; watch[navigation_key(LEG)] = watch_leg;
            watch[navigation_key(BEST)] = watch_best; watch[navigation_key(ORDER_REVISION)] = watch_revision;
            unit.erase(navigation_key(PROGRESS)); unit[navigation_key(PROGRESS)] = watch;
        } else {
            if (watch_leg_changed) watch[navigation_key(LEG)] = watch_leg;
            if (watch_best_changed) watch[navigation_key(BEST)] = watch_best;
        }
    }
};

} // namespace godot
