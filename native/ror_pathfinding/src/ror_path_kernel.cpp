#include "ror_path_kernel.hpp"

#include <algorithm>
#include <cmath>
#include <cstring>
#include <limits>
#include <unordered_set>

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/math.hpp>

namespace godot {

namespace {
constexpr double CARDINAL_COST = 1.0;
constexpr double DIAGONAL_COST = 1.41421356237;
constexpr double PI = 3.14159265358979323846;
constexpr int32_t DIRECTIONS[8][2] = {
    {-1, -1}, {0, -1}, {1, -1},
    {-1, 0},           {1, 0},
    {-1, 1},  {0, 1},  {1, 1},
};
}

void RoRPathKernel::_bind_methods() {
    ClassDB::bind_method(D_METHOD("corridor_widths", "cells", "maximum", "radius"), &RoRPathKernel::corridor_widths);
    ClassDB::bind_method(D_METHOD("is_position_walkable", "position", "radius"), &RoRPathKernel::position_walkable);
    ClassDB::bind_method(D_METHOD("is_segment_walkable", "start", "finish", "radius"), &RoRPathKernel::is_segment_walkable);
    ClassDB::bind_method(D_METHOD("direct_cell_path", "start", "goal", "radius"), &RoRPathKernel::direct_cell_path);
    ClassDB::bind_method(D_METHOD("nearest_walkable", "requested", "radius"), &RoRPathKernel::nearest_walkable);
    ClassDB::bind_method(D_METHOD("create_search_context"), &RoRPathKernel::create_search_context);
    ClassDB::bind_method(D_METHOD("create_movement_context"), &RoRPathKernel::create_movement_context);
    ClassDB::bind_method(D_METHOD("connectivity_labels", "radius"), &RoRPathKernel::connectivity_labels, DEFVAL(0.0));
    ClassDB::bind_method(D_METHOD("install_connectivity", "labels", "radius"), &RoRPathKernel::install_connectivity, DEFVAL(0.0));
    ClassDB::bind_method(D_METHOD("configure", "width", "height", "revision", "walkable"), &RoRPathKernel::configure);
    ClassDB::bind_method(D_METHOD("update_walkable", "revision", "indices", "values"), &RoRPathKernel::update_walkable);
    ClassDB::bind_method(D_METHOD("find_cell_path", "start", "goal", "clearance_radius"), &RoRPathKernel::find_cell_path, DEFVAL(0.0));
    ClassDB::bind_method(D_METHOD("find_smoothed_cell_path", "start", "goal", "clearance_radius"), &RoRPathKernel::find_smoothed_cell_path, DEFVAL(0.0));
    ClassDB::bind_method(D_METHOD("configure_movement_snapshot", "ids", "positions", "radii", "clearances", "priorities", "health", "solid_animals"), &RoRPathKernel::configure_movement_snapshot, DEFVAL(PackedByteArray()));
    ClassDB::bind_method(D_METHOD("configure_movement_entities", "units", "incremental"), &RoRPathKernel::configure_movement_entities, DEFVAL(true));
    ClassDB::bind_method(D_METHOD("update_movement_entities", "units"), &RoRPathKernel::update_movement_entities);
    ClassDB::bind_method(D_METHOD("release_movement_snapshot"), &RoRPathKernel::release_movement_snapshot);
    ClassDB::bind_method(D_METHOD("share_movement_snapshot", "source"), &RoRPathKernel::share_movement_snapshot);
    ClassDB::bind_method(D_METHOD("calculate_movement", "unit_id", "target", "speed", "cohesion_scale", "delta"), &RoRPathKernel::calculate_movement);
    ClassDB::bind_method(D_METHOD("get_revision"), &RoRPathKernel::get_revision);
    ClassDB::bind_method(D_METHOD("get_walkability_version"), &RoRPathKernel::get_walkability_version);
    ClassDB::bind_method(D_METHOD("get_connectivity_rebuild_count"), &RoRPathKernel::get_connectivity_rebuild_count);
    ClassDB::bind_method(D_METHOD("get_last_expanded_nodes"), &RoRPathKernel::get_last_expanded_nodes);
    ClassDB::bind_method(D_METHOD("get_last_path_was_direct"), &RoRPathKernel::get_last_path_was_direct);
    ClassDB::bind_method(D_METHOD("is_configured"), &RoRPathKernel::is_configured);
    ClassDB::bind_method(D_METHOD("component_id", "cell", "clearance_radius"), &RoRPathKernel::component_id, DEFVAL(0.0));
    ClassDB::bind_method(D_METHOD("group_points_by_component", "points", "clearance_radius"), &RoRPathKernel::group_points_by_component, DEFVAL(0.0));
    ClassDB::bind_method(D_METHOD("cells_connected", "start", "goal", "clearance_radius"), &RoRPathKernel::cells_connected, DEFVAL(0.0));
}

Ref<RoRPathKernel> RoRPathKernel::create_search_context() const {
    Ref<RoRPathKernel> context;
    context.instantiate();
    context->width_ = width_;
    context->height_ = height_;
    context->revision_ = revision_;
    context->walkability_version_ = walkability_version_;
    context->walkable_ = walkable_;
    context->costs_.resize(walkable_->size());
    context->parents_.resize(walkable_->size());
    context->seen_generation_.assign(walkable_->size(), 0);
    context->components_by_radius_ = components_by_radius_;
    // Completed connectivity labels are immutable and shared by contexts.
    return context;
}

Ref<RoRPathKernel> RoRPathKernel::create_movement_context() const {
    Ref<RoRPathKernel> context;
    context.instantiate();
    context->width_ = width_;
    context->height_ = height_;
    context->revision_ = revision_;
    context->walkability_version_ = walkability_version_;
    context->walkable_ = walkable_;
    context->movement_ = movement_;
    // Movement has thread-local scratch and needs no map-sized A* arrays.
    return context;
}

PackedInt32Array RoRPathKernel::connectivity_labels(double radius) {
    PackedInt32Array packed;
    if (!is_configured()) return packed;
    const auto &labels = components(radius);
    packed.resize(static_cast<int64_t>(labels.size()));
    std::copy(labels.begin(), labels.end(), packed.ptrw());
    return packed;
}

bool RoRPathKernel::install_connectivity(const PackedInt32Array &labels, double radius) {
    if (!is_configured() || static_cast<size_t>(labels.size()) != walkable_->size()) return false;
    for (int64_t i = 0; i < labels.size(); ++i) {
        if (labels[i] < -1 || labels[i] >= labels.size()) return false;
        // Installed labels also serve as centred-footprint passability. Verify
        // that proof once during preparation before any A* edge can use them.
        if ((labels[i] >= 0) != cell_walkable_for(int32_t(i % width_), int32_t(i / width_), radius)) return false;
    }
    radius = radius <= 0.5 ? 0.0 : radius;
    uint64_t key = 0;
    std::memcpy(&key, &radius, sizeof(key));
    if (components_by_radius_.size() >= 16 && components_by_radius_.find(key) == components_by_radius_.end()) components_by_radius_.clear();
    components_by_radius_[key] = std::make_shared<const std::vector<int32_t>>(labels.ptr(), labels.ptr() + labels.size());
    return true;
}

void RoRPathKernel::configure_movement_snapshot(
        const PackedInt32Array &ids,
        const PackedVector2Array &positions,
        const PackedFloat32Array &radii,
        const PackedFloat32Array &clearances,
        const PackedInt32Array &priorities,
        const PackedFloat32Array &health,
        const PackedByteArray &solid_animals) {
    auto next = std::make_shared<MovementSnapshot>();
    const int64_t count = std::min({ids.size(), positions.size(), radii.size(), clearances.size(), priorities.size(), health.size()});
    next->ids.resize(static_cast<size_t>(count));
    next->positions.resize(static_cast<size_t>(count));
    next->radii.resize(static_cast<size_t>(count));
    next->clearances.resize(static_cast<size_t>(count));
    next->priorities.resize(static_cast<size_t>(count));
    next->health.resize(static_cast<size_t>(count));
    next->solid_animals.resize(static_cast<size_t>(count));
    next->index_by_id.clear();
    next->buckets.clear();
    next->maximum_radius = 0.0f;
    next->maximum_clearance = 0.0f;
    for (int64_t index = 0; index < count; ++index) {
        const size_t stored = static_cast<size_t>(index);
        next->ids[stored] = ids[index];
        next->positions[stored] = positions[index];
        next->radii[stored] = std::max(0.0f, radii[index]);
        next->clearances[stored] = std::max(0.0f, clearances[index]);
        next->priorities[stored] = priorities[index];
        next->health[stored] = health[index];
        next->solid_animals[stored] = index < solid_animals.size() ? solid_animals[index] : 0;
        next->index_by_id[next->ids[stored]] = static_cast<int32_t>(index);
        if (next->health[stored] <= 0.0f) {
            continue;
        }
        next->maximum_radius = std::max(next->maximum_radius, next->radii[stored]);
        next->maximum_clearance = std::max(next->maximum_clearance, next->clearances[stored]);
        const int32_t bucket_x = static_cast<int32_t>(std::floor(next->positions[stored].x / 2.0));
        const int32_t bucket_y = static_cast<int32_t>(std::floor(next->positions[stored].y / 2.0));
        next->buckets[movement_bucket_key(bucket_x, bucket_y)].push_back(static_cast<int32_t>(index));
    }
    movement_ = next;
}

// Owner-thread extraction preserves legacy float32 packing and neighbor order.
// No live Dictionary is retained. Workers keep the previous immutable generation.
Dictionary RoRPathKernel::configure_movement_entities(const Array &units, bool incremental) {
    return configure_movement_entity_rows(units, incremental, false);
}
Dictionary RoRPathKernel::update_movement_entities(const Array &units) {
    return configure_movement_entity_rows(units, true, true);
}
void RoRPathKernel::release_movement_snapshot() {
    movement_ = std::make_shared<MovementSnapshot>();
}
Dictionary RoRPathKernel::configure_movement_entity_rows(const Array &units, bool incremental, bool delta) {
    static const String k_id("id");
    static const String k_pos("pos");
    static const String k_footprint_radius("footprint_radius");
    static const String k_minimum_clearance("minimum_clearance");
    static const String k_push_priority("push_priority");
    static const String k_hp("hp");
    static const String k_behavior_tags("behavior_tags");
    static const String k_kind("kind");
    static const String k_solid_animal("solid_animal");
    static const String k_team("team");
    const int64_t count = units.size();
    bool stable = delta || (incremental && count <= 65536 && movement_->ids.size() == static_cast<size_t>(count));
    for (int64_t i = 0; !delta && stable && i < count; ++i) {
        const Dictionary unit = units[i];
        stable = movement_->ids[static_cast<size_t>(i)] == static_cast<int32_t>(int64_t(unit[k_id]));
    }
    Dictionary stats;
    stats["checked"] = count;
    stats["updated"] = 0;
    stats["bucket_updates"] = 0;
    stats["generation_copies"] = 0;
    stats["full_rebuilds"] = stable ? 0 : 1;
    if (!stable) {
        PackedInt32Array ids, priorities;
        PackedVector2Array positions;
        PackedFloat32Array radii, clearances, health;
        PackedByteArray solid;
        ids.resize(count); positions.resize(count); radii.resize(count);
        clearances.resize(count); priorities.resize(count); health.resize(count); solid.resize(count);
        for (int64_t i = 0; i < count; ++i) {
            const Dictionary unit = units[i];
            ids[i] = int64_t(unit[k_id]); positions[i] = unit[k_pos];
            radii[i] = double(unit[k_footprint_radius]); clearances[i] = double(unit[k_minimum_clearance]);
            priorities[i] = int64_t(unit[k_push_priority]); health[i] = double(unit[k_hp]);
            if (unit.has(k_solid_animal)) { solid[i] = bool(unit[k_solid_animal]); continue; }
            const Array tags = unit.get(k_behavior_tags, Array());
            const String kind = unit.get(k_kind, String());
            solid[i] =
                tags.has("predator") || tags.has("huntable") ||
                ((kind == "gazelle" || kind == "elephant" || kind == "lion" || kind == "alligator" || kind == "crocodile") && int64_t(unit.get(k_team, 0)) == 0);
        }
        configure_movement_snapshot(ids, positions, radii, clearances, priorities, health, solid);
        stats["updated"] = count; stats["bucket_updates"] = count;
        return stats;
    }
    std::shared_ptr<MovementSnapshot> next;
    int64_t updated = 0, bucket_updates = 0;
    bool maxima_dirty = false;
    bool copied_generation = false;
    for (int64_t i = 0; i < count; ++i) {
        const Dictionary unit = units[i];
        const auto found = movement_->index_by_id.find(static_cast<int32_t>(int64_t(unit[k_id])));
        if (delta && found == movement_->index_by_id.end()) continue;
        const size_t slot = delta ? static_cast<size_t>(found->second) : static_cast<size_t>(i);
        const Vector2 position = unit[k_pos];
        const float radius = std::max(0.0f, static_cast<float>(double(unit[k_footprint_radius])));
        const float clearance = std::max(0.0f, static_cast<float>(double(unit[k_minimum_clearance])));
        const int32_t priority = int64_t(unit[k_push_priority]);
        const float health = double(unit[k_hp]);
        uint8_t solid;
        if (unit.has(k_solid_animal)) solid = bool(unit[k_solid_animal]);
        else {
            const Array tags = unit.get(k_behavior_tags, Array());
            const String kind = unit.get(k_kind, String());
            solid = tags.has("predator") || tags.has("huntable") ||
                ((kind == "gazelle" || kind == "elephant" || kind == "lion" || kind == "alligator" || kind == "crocodile") && int64_t(unit.get(k_team, 0)) == 0);
        }
        if (movement_->positions[slot] == position && movement_->radii[slot] == radius &&
            movement_->clearances[slot] == clearance && movement_->priorities[slot] == priority &&
            movement_->health[slot] == health && movement_->solid_animals[slot] == solid) continue;
        if (!next) {
            copied_generation = movement_.use_count() > 1;
            next = copied_generation ? std::make_shared<MovementSnapshot>(*movement_) : std::const_pointer_cast<MovementSnapshot>(movement_);
        }
        ++updated;
        const bool old_alive = movement_->health[slot] > 0.0f, alive = health > 0.0f;
        const int64_t old_key = movement_bucket_key(static_cast<int32_t>(std::floor(movement_->positions[slot].x / 2.0)), static_cast<int32_t>(std::floor(movement_->positions[slot].y / 2.0)));
        const int64_t key = movement_bucket_key(static_cast<int32_t>(std::floor(position.x / 2.0)), static_cast<int32_t>(std::floor(position.y / 2.0)));
        if (old_alive != alive || (alive && old_key != key)) {
            if (old_alive) {
                auto &bucket = next->buckets[old_key];
                bucket.erase(std::remove(bucket.begin(), bucket.end(), static_cast<int32_t>(slot)), bucket.end());
                if (bucket.empty()) next->buckets.erase(old_key);
            }
            if (alive) {
                auto &bucket = next->buckets[key];
                // Original configure emits slot order; retain its floating-point sum order.
                bucket.insert(std::lower_bound(bucket.begin(), bucket.end(), static_cast<int32_t>(slot)), static_cast<int32_t>(slot));
            }
            ++bucket_updates;
        }
        maxima_dirty = maxima_dirty || old_alive != alive || radius != movement_->radii[slot] || clearance != movement_->clearances[slot];
        next->positions[slot] = position; next->radii[slot] = radius; next->clearances[slot] = clearance;
        next->priorities[slot] = priority; next->health[slot] = health; next->solid_animals[slot] = solid;
    }
    if (next) {
        if (maxima_dirty) {
            next->maximum_radius = 0.0f; next->maximum_clearance = 0.0f;
            for (size_t i = 0; i < next->ids.size(); ++i) if (next->health[i] > 0.0f) {
                next->maximum_radius = std::max(next->maximum_radius, next->radii[i]);
                next->maximum_clearance = std::max(next->maximum_clearance, next->clearances[i]);
            }
        }
        movement_ = next;
        stats["generation_copies"] = copied_generation ? 1 : 0;
    }
    stats["updated"] = updated; stats["bucket_updates"] = bucket_updates;
    return stats;
}

void RoRPathKernel::share_movement_snapshot(const Ref<RoRPathKernel> &source) {
    if (source.is_valid()) movement_ = source->movement_;
}

Vector4 RoRPathKernel::calculate_movement(int32_t unit_id, const Vector2 &target, double speed, double cohesion_scale, double delta) const {
    // One scratch vector per executing thread. Private movement contexts
    // retain immutable generations while the owner updates its own snapshot.
    thread_local std::vector<int32_t> movement_candidates_;
    const auto own_entry = movement_->index_by_id.find(unit_id);
    if (own_entry == movement_->index_by_id.end() || !is_configured()) {
        return Vector4(0.0, 0.0, -1.0, 0.0);
    }
    const int32_t own_index = own_entry->second;
    const Vector2 position = movement_->positions[static_cast<size_t>(own_index)];
    const Vector2 difference = target - position;
    const double resolved_speed = std::max(0.0, speed * cohesion_scale);
    const Vector2 desired = difference.length_squared() > 0.000001 ? difference.normalized() * resolved_speed : Vector2();
    const bool has_desired = desired.length_squared() > 0.0;
    const Vector2 desired_normalized = has_desired ? desired.normalized() : Vector2();
    const Vector2 lateral_normalized = has_desired ? Vector2(-desired.y, desired.x).normalized() : Vector2();
    const double own_radius = movement_->radii[static_cast<size_t>(own_index)];
    const double own_clearance = movement_->clearances[static_cast<size_t>(own_index)];
    const int32_t own_priority = movement_->priorities[static_cast<size_t>(own_index)];
    const double query_radius = 1.6 * own_radius + 0.6 * movement_->maximum_radius + 1.6 * movement_->maximum_clearance;
    const double bucket_radius = query_radius + movement_->maximum_radius;
    const int32_t minimum_x = static_cast<int32_t>(std::floor((position.x - bucket_radius) / 2.0));
    const int32_t maximum_x = static_cast<int32_t>(std::floor((position.x + bucket_radius) / 2.0));
    const int32_t minimum_y = static_cast<int32_t>(std::floor((position.y - bucket_radius) / 2.0));
    const int32_t maximum_y = static_cast<int32_t>(std::floor((position.y + bucket_radius) / 2.0));
    movement_candidates_.clear();
    for (int32_t y = minimum_y; y <= maximum_y; ++y) {
        for (int32_t x = minimum_x; x <= maximum_x; ++x) {
            const auto bucket = movement_->buckets.find(movement_bucket_key(x, y));
            if (bucket == movement_->buckets.end()) {
                continue;
            }
            for (const int32_t candidate_index : bucket->second) {
                if (candidate_index == own_index) {
                    continue;
                }
                const double allowed_distance = query_radius + movement_->radii[static_cast<size_t>(candidate_index)];
                if (position.distance_squared_to(movement_->positions[static_cast<size_t>(candidate_index)]) <= allowed_distance * allowed_distance) {
                    movement_candidates_.push_back(candidate_index);
                }
            }
        }
    }
    std::sort(movement_candidates_.begin(), movement_candidates_.end(), [this](int32_t left, int32_t right) {
        return movement_->ids[static_cast<size_t>(left)] < movement_->ids[static_cast<size_t>(right)];
    });

    Vector2 avoidance;
    for (const int32_t candidate_index : movement_candidates_) {
        const size_t candidate = static_cast<size_t>(candidate_index);
        if (movement_->health[candidate] <= 0.0f) {
            continue;
        }
        Vector2 gap = position - movement_->positions[candidate];
        double distance = gap.length();
        const double safe_distance = own_radius + movement_->radii[candidate] + std::max(own_clearance, static_cast<double>(movement_->clearances[candidate]));
        if (distance <= 0.0001) {
            const double sign_value = unit_id < movement_->ids[candidate] ? -1.0 : 1.0;
            gap = Vector2(0.0, sign_value);
            distance = 0.0001;
        }
        if (distance < safe_distance * 1.6) {
            const double strength = std::clamp((safe_distance * 1.6 - distance) / (safe_distance * 1.6), 0.0, 1.0);
            const Vector2 gap_normalized = gap.normalized();
            const int32_t other_priority = movement_->priorities[candidate];
            const double displacement_share = own_priority == other_priority ? 0.5 : (own_priority < other_priority ? 0.75 : 0.25);
            avoidance += gap_normalized * resolved_speed * strength * displacement_share;
            const Vector2 to_other = -gap_normalized;
            if (has_desired && desired_normalized.dot(to_other) > 0.55) {
                avoidance += lateral_normalized * resolved_speed * strength * 0.55;
            }
        }
    }

    Vector2 velocity = desired + avoidance;
    if (velocity.length() > resolved_speed && resolved_speed > 0.0) {
        velocity = velocity.normalized() * resolved_speed;
    }
    int32_t state = 0;
    if (!position_walkable(position + velocity * delta, own_radius)) {
        state = 1;
        velocity = walkable_alternative(unit_id, desired, position, resolved_speed, delta, own_radius);
        if (velocity == Vector2()) {
            state = 2;
        }
    }
    const Vector2 pre_collision_velocity = velocity;
    const auto crosses = [](const Vector2 &gap, const Vector2 &step, double radius) {
        const double length = step.length_squared();
        if (length <= 0.000001) return false;
        if (gap.length_squared() < radius * radius) return gap.dot(step) < -0.000001;
        const double fraction = std::clamp(-static_cast<double>(gap.dot(step)) / length, 0.0, 1.0);
        return (gap + step * fraction).length_squared() < radius * radius - 0.000001;
    };
    for (const int32_t candidate_index : movement_candidates_) {
        const size_t candidate = static_cast<size_t>(candidate_index);
        if (movement_->health[candidate] <= 0.0f) continue;
        const Vector2 gap = position - movement_->positions[candidate];
        const double radius = own_radius + movement_->radii[candidate] + 0.03;
        if (!crosses(gap, velocity * delta, radius)) continue;
        const Vector2 normal = gap.normalized();
        velocity -= normal * std::min(0.0, static_cast<double>(velocity.dot(normal)));
        if (crosses(gap, velocity * delta, radius)) velocity = Vector2();
    }
    if (!velocity.is_equal_approx(pre_collision_velocity)) {
        for (const int32_t candidate_index : movement_candidates_) {
            const size_t candidate = static_cast<size_t>(candidate_index);
            if (movement_->health[candidate] <= 0.0f) continue;
            if (crosses(position - movement_->positions[candidate], velocity * delta, own_radius + movement_->radii[candidate] + 0.03)) velocity = Vector2();
        }
        // A tangent chosen to avoid a body still obeys the physical terrain mask.
        if (!position_walkable(position + velocity * delta, own_radius)) velocity = Vector2();
    }
    return Vector4(velocity.x, velocity.y, static_cast<double>(state), static_cast<double>(movement_candidates_.size()));
}

bool RoRPathKernel::update_walkable(int64_t revision, const PackedInt32Array &indices, const PackedByteArray &values) {
    if (!is_configured() || revision < revision_ || indices.size() != values.size()) return false;
    bool differs = false;
    // Validate the entire patch before changing the authoritative mask.
    for (int64_t i = 0; i < indices.size(); ++i) {
        if (indices[i] < 0 || static_cast<size_t>(indices[i]) >= walkable_->size()) return false;
        differs = differs || (*walkable_)[indices[i]] != (values[i] != 0);
    }
    if (!differs) { revision_ = revision; return true; }
    if (!walkable_.unique()) walkable_ = std::make_shared<std::vector<uint8_t>>(*walkable_);
    std::vector<int32_t> changed;
    bool only_opening = true;
    changed.reserve(static_cast<size_t>(indices.size()));
    for (int64_t i = 0; i < indices.size(); ++i) {
        const uint8_t value = values[i] != 0;
        if ((*walkable_)[indices[i]] != value) {
            changed.push_back(indices[i]);
            if (!value) only_opening = false;
        }
        (*walkable_)[indices[i]] = value;
    }
    for (auto it = components_by_radius_.begin(); it != components_by_radius_.end();) {
        double radius = 0.0;
        std::memcpy(&radius, &it->first, sizeof(radius));
        if (only_opening ? patch_open_components(radius, changed, it->second) : patch_components(radius, changed, it->second)) ++it;
        else it = components_by_radius_.erase(it);
    }
    ++walkability_version_;
    revision_ = revision;
    return true;
}

// Keep a component only when a bounded local flood proves that its surviving
// cells remain connected and that no two old components have been joined.
// The unchanged outer ring contains every connection to the rest of the map.
bool RoRPathKernel::patch_open_components(double radius, const std::vector<int32_t> &changed,
        std::shared_ptr<const std::vector<int32_t>> &labels) const {
    if (!std::isfinite(radius) || radius > std::max(width_, height_)) return false;
    const int margin = int(std::ceil(std::max(0.0, radius))) + 2;
    std::unordered_set<int32_t> candidates, added;
    for (const int32_t index : changed) {
        const int x = index % width_, y = index / width_;
        for (int dy = -margin; dy <= margin; ++dy) for (int dx = -margin; dx <= margin; ++dx) {
            if (contains(x + dx, y + dy)) candidates.insert((y + dy) * width_ + x + dx);
        }
        if (candidates.size() > 16384) return false;
    }
    for (const int32_t index : candidates) {
        if ((*labels)[index] < 0 && cell_walkable_for(index % width_, index / width_, radius)) added.insert(index);
    }
    if (added.empty()) return true;
    std::unordered_map<int32_t, int32_t> parents;
    auto root_for = [&parents](int32_t value) {
        parents.emplace(value, value);
        int32_t root = value;
        while (parents[root] != root) root = parents[root];
        while (parents[value] != value) { const int32_t next = parents[value]; parents[value] = root; value = next; }
        return root;
    };
    for (const int32_t index : added) {
        root_for(index);
        const int x = index % width_, y = index / width_;
        for (const auto &direction : DIRECTIONS) {
            const int nx = x + direction[0], ny = y + direction[1];
            if (!contains(nx, ny)) continue;
            const int32_t next = ny * width_ + nx, old = (*labels)[next];
            if ((old < 0 && !added.count(next)) || !can_step(index, next, radius)) continue;
            const int32_t first = root_for(index), second = root_for(old >= 0 ? old : next);
            parents[std::max(first, second)] = std::min(first, second);
        }
    }
    // Openings can merge regions but cannot split them. Relabeling their old
    // IDs is a linear integer pass, without repeating a full map flood.
    auto patched = std::make_shared<std::vector<int32_t>>(*labels);
    bool merged = false;
    for (const auto &item : parents) if (!added.count(item.first) && root_for(item.first) != item.first) { merged = true; break; }
    if (merged) for (int32_t &label : *patched) {
        if (label >= 0 && parents.count(label)) label = root_for(label);
    }
    for (const int32_t index : added) (*patched)[index] = root_for(index);
    labels = std::move(patched);
    return true;
}

bool RoRPathKernel::patch_components(double radius, const std::vector<int32_t> &changed,
        std::shared_ptr<const std::vector<int32_t>> &labels) const {
    if (changed.size() < 2 || changed.size() > 512 || !std::isfinite(radius) || radius > std::max(width_, height_)) return patch_component_region(radius, changed, labels);
    // Distant tree/building edits must not invalidate the entire map merely
    // because their joint bounding rectangle is large. Overlapping expanded
    // neighborhoods are checked together; independent regions keep the same
    // conservative split/merge proof as the single-region implementation.
    const int distance = (int(std::ceil(std::max(0.0, radius))) + 2) * 2 + 1;
    std::unordered_set<int32_t> remaining(changed.begin(), changed.end());
    std::vector<std::vector<int32_t>> regions;
    for (const int32_t root : changed) {
        if (!remaining.erase(root)) continue;
        regions.push_back({root});
        if (regions.size() > 16) return false;
        auto &region = regions.back();
        for (size_t cursor = 0; cursor < region.size(); ++cursor) {
            const int x = region[cursor] % width_, y = region[cursor] / width_;
            for (int dy = -distance; dy <= distance; ++dy) {
                for (int dx = -distance; dx <= distance; ++dx) {
                    if (!contains(x + dx, y + dy)) continue;
                    const int32_t next = (y + dy) * width_ + x + dx;
                    if (remaining.erase(next)) region.push_back(next);
                }
            }
        }
    }
    for (const auto &region : regions) if (!patch_component_region(radius, region, labels)) return false;
    return true;
}

bool RoRPathKernel::patch_component_region(double radius, const std::vector<int32_t> &changed,
        std::shared_ptr<const std::vector<int32_t>> &labels) const {
    if (changed.empty()) return true;
    if (!std::isfinite(radius) || radius > std::max(width_, height_)) return false;
    const int32_t margin = static_cast<int32_t>(std::ceil(std::max(0.0, radius))) + 2;
    int32_t min_x = width_ - 1, min_y = height_ - 1, max_x = 0, max_y = 0;
    for (const int32_t index : changed) {
        min_x = std::min(min_x, index % width_);
        max_x = std::max(max_x, index % width_);
        min_y = std::min(min_y, index / width_);
        max_y = std::max(max_y, index / width_);
    }
    min_x = std::max(0, min_x - margin);
    min_y = std::max(0, min_y - margin);
    max_x = std::min(width_ - 1, max_x + margin);
    max_y = std::min(height_ - 1, max_y + margin);
    const int32_t local_width = max_x - min_x + 1, local_height = max_y - min_y + 1;
    const int64_t area = static_cast<int64_t>(local_width) * local_height;
    if (area > 4096) return false;
    std::vector<uint8_t> passable(static_cast<size_t>(area), 0);
    std::vector<int32_t> groups(static_cast<size_t>(area), -1);
    for (int32_t local = 0; local < area; ++local) {
        passable[local] = cell_walkable_for(min_x + local % local_width, min_y + local / local_width, radius);
    }
    std::vector<int32_t> group_labels;
    std::unordered_map<int32_t, int32_t> group_by_old_label;
    std::unordered_set<int32_t> checked_roots;
    std::vector<int32_t> queue;
    for (int32_t root = 0; root < area; ++root) {
        if (!passable[root] || groups[root] >= 0) continue;
        const int32_t group = static_cast<int32_t>(group_labels.size());
        int32_t old_label = -1;
        queue.clear();
        queue.push_back(root);
        groups[root] = group;
        for (size_t cursor = 0; cursor < queue.size(); ++cursor) {
            const int32_t local = queue[cursor], x = local % local_width, y = local / local_width;
            const int32_t previous = (*labels)[(min_y + y) * width_ + min_x + x];
            if (previous >= 0) {
                // Keep root IDs attached to surviving walkable cells. An old
                // blocked root must never alias a newly opened isolated cell.
                if (checked_roots.insert(previous).second && !cell_walkable_for(previous % width_, previous / width_, radius)) return false;
                if (old_label >= 0 && old_label != previous) return false; // Possible merge.
                old_label = previous;
            }
            for (const auto &d : DIRECTIONS) {
                const int32_t nx = x + d[0], ny = y + d[1];
                if (nx < 0 || ny < 0 || nx >= local_width || ny >= local_height) continue;
                const int32_t next = ny * local_width + nx;
                if (!passable[next] || groups[next] >= 0) continue;
                if (d[0] && d[1] && (!passable[y * local_width + nx] || !passable[ny * local_width + x])) continue;
                groups[next] = group;
                queue.push_back(next);
            }
        }
        if (old_label < 0) return false; // A new isolated component needs a full relabel.
        if (!group_by_old_label.emplace(old_label, group).second) return false; // Possible split.
        group_labels.push_back(old_label);
    }
    // Search contexts retain their immutable old generation.
    auto patched = std::make_shared<std::vector<int32_t>>(*labels);
    for (int32_t local = 0; local < area; ++local) {
        (*patched)[(min_y + local / local_width) * width_ + min_x + local % local_width] =
            groups[local] < 0 ? -1 : group_labels[groups[local]];
    }
    labels = std::move(patched);
    return true;
}

void RoRPathKernel::configure(int32_t width, int32_t height, int64_t revision, const PackedByteArray &walkable) {
    ++walkability_version_;
    width_ = std::max<int32_t>(0, width);
    height_ = std::max<int32_t>(0, height);
    revision_ = revision;
    last_expanded_nodes_ = 0;
    search_generation_ = 0;
    components_by_radius_.clear();
    const int64_t expected_size = static_cast<int64_t>(width_) * static_cast<int64_t>(height_);
    walkable_ = std::make_shared<std::vector<uint8_t>>(static_cast<size_t>(expected_size), 0);
    const int64_t copy_size = std::min<int64_t>(expected_size, walkable.size());
    for (int64_t index = 0; index < copy_size; ++index) {
        (*walkable_)[static_cast<size_t>(index)] = walkable[index] == 0 ? 0 : 1;
    }
    costs_.resize(static_cast<size_t>(expected_size));
    parents_.resize(static_cast<size_t>(expected_size));
    seen_generation_.assign(static_cast<size_t>(expected_size), 0);
    frontier_.clear();
}

// Connectivity uses precisely the same radius and corner rules as A*. Unknown
// terrain remains optimistic because this kernel only receives observer masks.
const std::vector<int32_t> &RoRPathKernel::components(double radius) {
    radius = radius <= 0.5 ? 0.0 : radius;
    uint64_t key = 0;
    std::memcpy(&key, &radius, sizeof(key));
    auto found = components_by_radius_.find(key);
    if (found != components_by_radius_.end()) return *found->second;
    ++connectivity_rebuild_count_;
    if (components_by_radius_.size() >= 16) components_by_radius_.clear();
    std::vector<int32_t> labels(walkable_->size(), -1);
    std::vector<uint8_t> passable;
    if (radius <= 0.5) passable = *walkable_;
    else {
        passable.resize(walkable_->size(), 0);
        for (int32_t i = 0; i < static_cast<int32_t>(labels.size()); ++i)
            passable[i] = cell_walkable_for(i % width_, i / width_, radius);
    }
    // Every legal diagonal has both orthogonal neighbors, so it adds no new
    // connectivity beyond these four edges. Partitions and row-major root IDs
    // remain identical; a full rebuild needs half as many neighbor visits.
    static constexpr int CARDINAL_DIRECTIONS[4][2] = {{0,-1},{-1,0},{1,0},{0,1}};
    std::vector<int32_t> queue;
    for (int32_t root = 0; root < static_cast<int32_t>(labels.size()); ++root) {
        if (!passable[root] || labels[root] >= 0) continue;
        queue.clear();
        queue.push_back(root);
        labels[root] = root;
        for (size_t cursor = 0; cursor < queue.size(); ++cursor) {
            const int32_t current = queue[cursor], x = current % width_, y = current / width_;
            for (const auto &d : CARDINAL_DIRECTIONS) {
                const int32_t nx = x + d[0], ny = y + d[1];
                if (!contains(nx, ny)) continue;
                const int32_t next = ny * width_ + nx;
                if (!passable[next] || labels[next] >= 0) continue;
                labels[next] = root;
                queue.push_back(next);
            }
        }
    }
    return *components_by_radius_.emplace(key, std::make_shared<const std::vector<int32_t>>(std::move(labels))).first->second;
}

int32_t RoRPathKernel::component_id(const Vector2i &cell, double radius) {
    if (!is_configured() || !contains(cell.x, cell.y)) return -1;
    return components(radius)[cell.y * width_ + cell.x];
}

// Same labels, bounds and point conversion as individual component_id calls.
// Input order is retained in each region; no map-sized label copy is published.
Dictionary RoRPathKernel::group_points_by_component(const TypedArray<Vector2> &points, double radius) {
    Dictionary result;
    if (!is_configured() || points.is_empty()) return result;
    const auto &labels = components(radius);
    for (int64_t i = 0; i < points.size(); ++i) {
        const Vector2 point = points[i];
        const Vector2i cell(point);
        if (!contains(cell.x, cell.y)) continue;
        const int32_t region = labels[cell.y * width_ + cell.x];
        if (region < 0) continue;
        TypedArray<Vector2> bucket;
        if (result.has(region)) bucket = Array(result[region]);
        bucket.push_back(point);
        result[region] = bucket;
    }
    return result;
}

bool RoRPathKernel::cells_connected(const Vector2i &start, const Vector2i &goal, double radius) {
    if (!is_configured() || !contains(start.x, start.y) || !contains(goal.x, goal.y)) return false;
    double normalized_radius = radius <= 0.5 ? 0.0 : radius;
    uint64_t key = 0;
    std::memcpy(&key, &normalized_radius, sizeof(key));
    if (components_by_radius_.find(key) == components_by_radius_.end() &&
            direct_path(start.y * width_ + start.x, goal.y * width_ + goal.x, radius)) return true;
    const auto &labels = components(radius);
    const int32_t target = labels[goal.y * width_ + goal.x];
    if (target < 0) return false;
    const int32_t origin = labels[start.y * width_ + start.x];
    if (origin >= 0) return origin == target;
    // A newly occupied start can still escape, as permitted by can_step.
    for (const auto &d : DIRECTIONS) {
        const int32_t x = start.x + d[0], y = start.y + d[1];
        if (contains(x, y) && labels[y * width_ + x] == target &&
                can_step(start.y * width_ + start.x, y * width_ + x, radius)) return true;
    }
    return false;
}

PackedInt32Array RoRPathKernel::find_cell_path(const Vector2i &start, const Vector2i &goal, double clearance_radius) {
    PackedInt32Array result;
    last_expanded_nodes_ = 0;
    // Corridor smoothing immediately requests the same raw A* route. Retain
    // one bounded value result; walkability generations invalidate it exactly.
    if (cached_search_version_ == walkability_version_ && cached_search_start_ == start && cached_search_goal_ == goal && cached_search_radius_ == clearance_radius) return cached_search_path_;
    cached_search_version_ = -1;
    cached_search_path_ = PackedInt32Array();
    if (!is_configured() || !contains(start.x, start.y) || !contains(goal.x, goal.y) || !cell_walkable_for(goal.x, goal.y, clearance_radius)) {
        return result;
    }

    if (!cells_connected(start, goal, clearance_radius)) return result;
    const auto &passable_labels = components(clearance_radius);

    ++search_generation_;
    if (search_generation_ == 0) {
        std::fill(seen_generation_.begin(), seen_generation_.end(), 0);
        search_generation_ = 1;
    }

    const int32_t start_index = start.y * width_ + start.x;
    const int32_t goal_index = goal.y * width_ + goal.x;
    frontier_.clear();
    frontier_push({start_index, 0.0, 0.0});
    seen_generation_[static_cast<size_t>(start_index)] = search_generation_;
    costs_[static_cast<size_t>(start_index)] = 0.0;
    parents_[static_cast<size_t>(start_index)] = start_index;

    while (!frontier_.empty()) {
        const FrontierEntry current_entry = frontier_pop();
        ++last_expanded_nodes_;
        const int32_t current = current_entry.index;
        if (seen_generation_[static_cast<size_t>(current)] != search_generation_ || current_entry.cost > costs_[static_cast<size_t>(current)] + 0.000001) {
            continue;
        }
        if (current == goal_index) {
            break;
        }

        const int32_t current_x = current % width_;
        const int32_t current_y = current / width_;
        for (const auto &direction : DIRECTIONS) {
            const int32_t next_x = current_x + direction[0];
            const int32_t next_y = current_y + direction[1];
            if (!contains(next_x, next_y)) {
                continue;
            }
            const int32_t next = next_y * width_ + next_x;
            // Connectivity already used the exact centred-circle footprint.
            // Reuse its passability instead of repeating geometry/divisions
            // for every A* edge. A blocked origin may still step out as before.
            if (passable_labels[next] < 0 || (direction[0] && direction[1] &&
                    (passable_labels[current_y * width_ + next_x] < 0 || passable_labels[next_y * width_ + current_x] < 0))) {
                continue;
            }
            const double step_cost = direction[0] != 0 && direction[1] != 0 ? DIAGONAL_COST : CARDINAL_COST;
            const double next_cost = costs_[static_cast<size_t>(current)] + step_cost;
            const bool unseen = seen_generation_[static_cast<size_t>(next)] != search_generation_;
            if (!unseen && next_cost >= costs_[static_cast<size_t>(next)]) {
                continue;
            }
            seen_generation_[static_cast<size_t>(next)] = search_generation_;
            costs_[static_cast<size_t>(next)] = next_cost;
            parents_[static_cast<size_t>(next)] = current;
            frontier_push({next, next_cost + heuristic(next, goal_index), next_cost});
        }
    }

    if (seen_generation_[static_cast<size_t>(goal_index)] != search_generation_) {
        return result;
    }

    std::vector<int32_t> reversed;
    int32_t current = goal_index;
    reversed.push_back(current);
    while (current != start_index) {
        current = parents_[static_cast<size_t>(current)];
        reversed.push_back(current);
    }
    result.resize(static_cast<int64_t>(reversed.size()) * 2);
    int64_t output = 0;
    for (auto iterator = reversed.rbegin(); iterator != reversed.rend(); ++iterator) {
        result.set(output++, *iterator % width_);
        result.set(output++, *iterator / width_);
    }
    if (result.size() <= 32768) {
        cached_search_version_ = walkability_version_;
        cached_search_start_ = start;
        cached_search_goal_ = goal;
        cached_search_radius_ = clearance_radius;
        cached_search_path_ = result;
    }
    return result;
}

PackedInt32Array RoRPathKernel::find_smoothed_cell_path(const Vector2i &start, const Vector2i &goal, double clearance_radius) {
    last_path_was_direct_ = false;
    if (!is_configured() || !contains(start.x, start.y) || !contains(goal.x, goal.y)) {
        last_expanded_nodes_ = 0;
        return PackedInt32Array();
    }
    const int32_t start_index = start.y * width_ + start.x;
    const int32_t goal_index = goal.y * width_ + goal.x;
    std::vector<int32_t> direct_cells;
    if (direct_path(start_index, goal_index, clearance_radius, &direct_cells)) {
        last_expanded_nodes_ = 0;
        last_path_was_direct_ = true;
        if (direct_cells.size() > 1) {
            direct_cells = {direct_cells.front(), direct_cells.back()};
        }
        return pack_cells(direct_cells);
    }

    const PackedInt32Array raw_packed = find_cell_path(start, goal, clearance_radius);
    if (raw_packed.is_empty()) {
        return PackedInt32Array();
    }
    std::vector<int32_t> raw;
    raw.reserve(static_cast<size_t>(raw_packed.size() / 2));
    for (int64_t index = 0; index + 1 < raw_packed.size(); index += 2) {
        raw.push_back(raw_packed[index + 1] * width_ + raw_packed[index]);
    }
    if (raw.size() <= 2) {
        return pack_cells(raw);
    }
    std::vector<int32_t> smoothed;
    smoothed.reserve(raw.size());
    smoothed.push_back(raw.front());
    size_t anchor = 0;
    while (anchor + 1 < raw.size()) {
        size_t furthest = anchor + 1;
        for (size_t candidate = raw.size() - 1; candidate > anchor; --candidate) {
            if (direct_path(raw[anchor], raw[candidate], clearance_radius)) {
                furthest = candidate;
                break;
            }
        }
        smoothed.push_back(raw[furthest]);
        anchor = furthest;
    }
    return pack_cells(smoothed);
}

int64_t RoRPathKernel::get_walkability_version() const { return walkability_version_; }
int64_t RoRPathKernel::get_connectivity_rebuild_count() const { return connectivity_rebuild_count_; }

int64_t RoRPathKernel::get_revision() const {
    return revision_;
}

int32_t RoRPathKernel::get_last_expanded_nodes() const {
    return last_expanded_nodes_;
}

bool RoRPathKernel::get_last_path_was_direct() const {
    return last_path_was_direct_;
}

bool RoRPathKernel::is_configured() const {
    return width_ > 0 && height_ > 0 && walkable_->size() == static_cast<size_t>(width_) * static_cast<size_t>(height_);
}

bool RoRPathKernel::contains(int32_t x, int32_t y) const {
    return x >= 0 && y >= 0 && x < width_ && y < height_;
}

bool RoRPathKernel::cell_walkable(int32_t x, int32_t y) const {
    return contains(x, y) && (*walkable_)[static_cast<size_t>(y * width_ + x)] != 0;
}

bool RoRPathKernel::cell_walkable_for(int32_t x, int32_t y, double clearance_radius) const {
    // At a cell centre, circles up to half a cell fit entirely within it;
    // tangency with neighboring squares is legal under the shared geometry.
    if (clearance_radius <= 0.5) return cell_walkable(x, y);
    return position_walkable(Vector2(static_cast<double>(x) + 0.5, static_cast<double>(y) + 0.5), clearance_radius);
}

bool RoRPathKernel::can_step(int32_t current, int32_t next, double clearance_radius) const {
    const int32_t current_x = current % width_;
    const int32_t current_y = current / width_;
    const int32_t next_x = next % width_;
    const int32_t next_y = next / width_;
    if (!cell_walkable_for(next_x, next_y, clearance_radius)) {
        return false;
    }
    const int32_t delta_x = next_x - current_x;
    const int32_t delta_y = next_y - current_y;
    if (delta_x != 0 && delta_y != 0) {
        return cell_walkable_for(current_x + delta_x, current_y, clearance_radius)
            && cell_walkable_for(current_x, current_y + delta_y, clearance_radius);
    }
    return true;
}

bool RoRPathKernel::direct_path(int32_t start, int32_t goal, double clearance_radius, std::vector<int32_t> *result) const {
    const int32_t start_x = start % width_;
    const int32_t start_y = start / width_;
    const int32_t goal_x = goal % width_;
    const int32_t goal_y = goal / width_;
    double normalized_radius = clearance_radius <= 0.5 ? 0.0 : clearance_radius;
    uint64_t radius_key = 0;
    std::memcpy(&radius_key, &normalized_radius, sizeof(radius_key));
    const auto retained = components_by_radius_.find(radius_key);
    const std::vector<int32_t> *labels = retained == components_by_radius_.end() ? nullptr : retained->second.get();
    const auto accessible = [&](int32_t x, int32_t y) {
        return contains(x, y) && (labels ? (*labels)[y * width_ + x] >= 0 : cell_walkable_for(x, y, clearance_radius));
    };
    if (!accessible(start_x, start_y) || !accessible(goal_x, goal_y)) {
        return false;
    }
    if (result != nullptr) {
        result->clear();
        result->push_back(start);
    }
    if (start == goal) {
        return true;
    }
    const int32_t difference_x = goal_x - start_x;
    const int32_t difference_y = goal_y - start_y;
    const int32_t steps = std::max(std::abs(difference_x), std::abs(difference_y));
    int32_t previous = start;
    int32_t previous_x = start_x, previous_y = start_y;
    for (int32_t index = 1; index <= steps; ++index) {
        const double ratio = static_cast<double>(index) / static_cast<double>(steps);
        const int32_t current_x = static_cast<int32_t>(std::round(static_cast<double>(start_x) + static_cast<double>(difference_x) * ratio));
        const int32_t current_y = static_cast<int32_t>(std::round(static_cast<double>(start_y) + static_cast<double>(difference_y) * ratio));
        const int32_t current = current_y * width_ + current_x;
        if (current == previous) {
            continue;
        }
        if (!accessible(current_x, current_y) || (current_x != previous_x && current_y != previous_y &&
                (!accessible(current_x, previous_y) || !accessible(previous_x, current_y)))) {
            if (result != nullptr) {
                result->clear();
            }
            return false;
        }
        if (result != nullptr) {
            result->push_back(current);
        }
        previous = current;
        previous_x = current_x;
        previous_y = current_y;
    }
    return true;
}

PackedInt32Array RoRPathKernel::pack_cells(const std::vector<int32_t> &cells) const {
    PackedInt32Array result;
    result.resize(static_cast<int64_t>(cells.size()) * 2);
    int64_t output = 0;
    for (const int32_t cell : cells) {
        result.set(output++, cell % width_);
        result.set(output++, cell / width_);
    }
    return result;
}

double RoRPathKernel::heuristic(int32_t left, int32_t right) const {
    const int32_t dx = std::abs(left % width_ - right % width_);
    const int32_t dy = std::abs(left / width_ - right / width_);
    return static_cast<double>(std::max(dx, dy)) + (DIAGONAL_COST - 1.0) * static_cast<double>(std::min(dx, dy));
}

bool RoRPathKernel::frontier_less(const FrontierEntry &left, const FrontierEntry &right) const {
    if (!Math::is_equal_approx(left.score, right.score)) {
        return left.score < right.score;
    }
    // Valid cell indices are row-major: comparing them is exactly the same
    // y/x tie order, without two integer divisions at every heap comparison.
    return left.index < right.index;
}

void RoRPathKernel::frontier_push(const FrontierEntry &entry) {
    frontier_.push_back(entry);
    size_t index = frontier_.size() - 1;
    while (index > 0) {
        const size_t parent = (index - 1) / 2;
        if (!frontier_less(frontier_[index], frontier_[parent])) {
            break;
        }
        std::swap(frontier_[index], frontier_[parent]);
        index = parent;
    }
}

RoRPathKernel::FrontierEntry RoRPathKernel::frontier_pop() {
    const FrontierEntry first = frontier_.front();
    const FrontierEntry last = frontier_.back();
    frontier_.pop_back();
    if (frontier_.empty()) {
        return first;
    }
    frontier_.front() = last;
    size_t index = 0;
    while (true) {
        const size_t left = index * 2 + 1;
        if (left >= frontier_.size()) {
            break;
        }
        const size_t right = left + 1;
        size_t best = left;
        if (right < frontier_.size() && frontier_less(frontier_[right], frontier_[left])) {
            best = right;
        }
        if (!frontier_less(frontier_[best], frontier_[index])) {
            break;
        }
        std::swap(frontier_[best], frontier_[index]);
        index = best;
    }
    return first;
}

int64_t RoRPathKernel::movement_bucket_key(int32_t x, int32_t y) const {
    const uint64_t packed = (static_cast<uint64_t>(static_cast<uint32_t>(x)) << 32)
        | static_cast<uint32_t>(y);
    return static_cast<int64_t>(packed);
}

bool RoRPathKernel::position_walkable(const Vector2 &position, double radius) const {
    const int32_t center_x = static_cast<int32_t>(std::floor(position.x));
    const int32_t center_y = static_cast<int32_t>(std::floor(position.y));
    if (!cell_walkable(center_x, center_y)) return false;
    if (radius <= 0.0001) return true;
    const int32_t min_x = static_cast<int32_t>(std::floor(position.x - radius));
    const int32_t min_y = static_cast<int32_t>(std::floor(position.y - radius));
    const int32_t max_x = static_cast<int32_t>(std::floor(position.x + radius));
    const int32_t max_y = static_cast<int32_t>(std::floor(position.y + radius));
    const double radius_squared = radius * radius;
    // Match RoRNavigationGrid's circle-to-cell geometry, including diagonal
    // overlaps and interior cells of large footprints. Tangency is legal.
    for (int32_t y = min_y; y <= max_y; ++y) {
        const double dy = std::max(std::max(static_cast<double>(y) - position.y, 0.0), static_cast<double>(position.y) - (y + 1.0));
        for (int32_t x = min_x; x <= max_x; ++x) {
            if (x == center_x && y == center_y) continue;
            const double dx = std::max(std::max(static_cast<double>(x) - position.x, 0.0), static_cast<double>(position.x) - (x + 1.0));
            if (dx * dx + dy * dy < radius_squared && !cell_walkable(x, y)) return false;
        }
    }
    return true;
}

PackedInt32Array RoRPathKernel::corridor_widths(const TypedArray<Vector2i> &cells, int64_t maximum, double radius) const {
    PackedInt32Array widths; widths.resize(cells.size());
    for (int64_t i = 0; i < cells.size(); ++i) {
        const Vector2i cell = cells[i];
        const Vector2i direction = cells.size() <= 1 ? Vector2i(1, 0) : (i == cells.size() - 1 ? cell - Vector2i(cells[i - 1]) : Vector2i(cells[i + 1]) - cell);
        const Vector2 forward = Vector2(direction).normalized();
        const Vector2 lateral(-forward.y, forward.x), center = Vector2(cell) + Vector2(0.5, 0.5);
        double half_width = 0;
        for (int64_t step = 1; step <= maximum; ++step) {
            const Vector2 offset = lateral * double(step) * 0.5;
            if (!position_walkable(center + offset, radius) || !position_walkable(center - offset, radius)) break;
            half_width = double(step) * 0.5;
        }
        widths[i] = std::max<int64_t>(1, std::min<int64_t>(maximum, int64_t(std::floor(half_width * 2.0 + radius * 2.0))));
    }
    return widths;
}

PackedInt32Array RoRPathKernel::direct_cell_path(const Vector2i &start, const Vector2i &goal, double radius) const {
    std::vector<int32_t> cells;
    if (!contains(start.x, start.y) || !contains(goal.x, goal.y) || !cell_walkable_for(start.x, start.y, radius) || !cell_walkable_for(goal.x, goal.y, radius)) return PackedInt32Array();
    return direct_path(start.y * width_ + start.x, goal.y * width_ + goal.x, radius, &cells) ? pack_cells(cells) : PackedInt32Array();
}

Vector2i RoRPathKernel::nearest_walkable(const Vector2i &requested, double radius) const {
    if (cell_walkable_for(requested.x, requested.y, radius)) return requested;
    for (int ring = 1; ring <= std::max(width_, height_); ++ring) {
        Vector2i best(-1, -1);
        int64_t best_distance = std::numeric_limits<int64_t>::max();
        for (int y = requested.y - ring; y <= requested.y + ring; ++y) {
            const bool edge = std::abs(y - requested.y) == ring;
            for (int x = requested.x - ring; x <= requested.x + ring; x += edge ? 1 : ring * 2) {
                if (!cell_walkable_for(x, y, radius)) continue;
                const int64_t dx = int64_t(x) - requested.x, dy = int64_t(y) - requested.y;
                const int64_t distance = dx * dx + dy * dy;
                if (distance < best_distance || (distance == best_distance && (y < best.y || (y == best.y && x < best.x)))) {
                    best_distance = distance; best = Vector2i(x, y);
                }
            }
        }
        if (best.x >= 0) return best;
    }
    return Vector2i(-1, -1);
}

bool RoRPathKernel::is_segment_walkable(const Vector2 &start, const Vector2 &finish, double radius) const {
    if (!position_walkable(start, radius) || !position_walkable(finish, radius)) return false;
    const Vector2 delta = finish - start;
    const int steps = std::max(1, int(std::ceil(std::max(std::abs(double(delta.x)), std::abs(double(delta.y))))));
    const int margin = std::max(1, int(std::ceil(radius)));
    std::unordered_set<uint64_t> visited;
    const double radius_squared = radius * radius;
    auto point_distance = [](const Vector2 &point, int x, int y) {
        const double dx = std::max(std::max(double(x) - point.x, 0.0), double(point.x) - (x + 1.0));
        const double dy = std::max(std::max(double(y) - point.y, 0.0), double(point.y) - (y + 1.0));
        return dx * dx + dy * dy;
    };
    for (int i = 0; i <= steps; ++i) {
        const Vector2 center = start.lerp(finish, double(i) / steps).floor();
        for (int y = int(center.y) - margin; y <= int(center.y) + margin; ++y) {
            for (int x = int(center.x) - margin; x <= int(center.x) + margin; ++x) {
                const uint64_t key = (uint64_t(uint32_t(x)) << 32) | uint32_t(y);
                if (!visited.insert(key).second || cell_walkable(x, y)) continue;
                const Vector2 lower(x, y), upper(x + 1, y + 1);
                double enter = 0, leave = 1;
                for (int axis = 0; axis < 2; ++axis) {
                    if (Math::is_zero_approx(delta[axis])) {
                        if (start[axis] < lower[axis] || start[axis] > upper[axis]) { enter = 2; break; }
                    } else {
                        const double first = (double(lower[axis]) - start[axis]) / delta[axis];
                        const double last = (double(upper[axis]) - start[axis]) / delta[axis];
                        enter = std::max(enter, std::min(first, last));
                        leave = std::min(leave, std::max(first, last));
                    }
                }
                double distance = 0;
                if (enter > leave) {
                    distance = std::min(point_distance(start, x, y), point_distance(finish, x, y));
                    for (const Vector2 &corner : {lower, upper, Vector2(lower.x, upper.y), Vector2(upper.x, lower.y)}) {
                        const real_t length = delta.length_squared();
                        const real_t t = length > 0 ? std::max(real_t(0), std::min(real_t(1), (corner - start).dot(delta) / length)) : 0;
                        const Vector2 nearest = start + delta * t;
                        distance = std::min(distance, double(corner.distance_squared_to(nearest)));
                    }
                }
                if (distance < radius_squared || (radius <= 0.0001 && Math::is_zero_approx(distance))) return false;
            }
        }
    }
    return true;
}

Vector2 RoRPathKernel::walkable_alternative(int32_t unit_id, const Vector2 &desired, const Vector2 &position, double speed, double delta, double radius) const {
    if (desired.length_squared() <= 0.000001) {
        return Vector2();
    }
    const double positive_angles[4] = {PI / 4.0, -PI / 4.0, PI / 2.0, -PI / 2.0};
    const double negative_angles[4] = {-PI / 4.0, PI / 4.0, -PI / 2.0, PI / 2.0};
    const double *angles = unit_id % 2 == 0 ? negative_angles : positive_angles;
    for (int index = 0; index < 4; ++index) {
        const Vector2 candidate = desired.rotated(angles[index]).normalized() * speed;
        if (position_walkable(position + candidate * delta, radius)) {
            return candidate;
        }
    }
    return Vector2();
}

} // namespace godot
