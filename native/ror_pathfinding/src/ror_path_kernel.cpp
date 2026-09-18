#include "ror_path_kernel.hpp"

#include <algorithm>
#include <cmath>
#include <limits>

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
    ClassDB::bind_method(D_METHOD("configure", "width", "height", "revision", "walkable"), &RoRPathKernel::configure);
    ClassDB::bind_method(D_METHOD("find_cell_path", "start", "goal", "clearance_radius"), &RoRPathKernel::find_cell_path, DEFVAL(0.0));
    ClassDB::bind_method(D_METHOD("find_smoothed_cell_path", "start", "goal", "clearance_radius"), &RoRPathKernel::find_smoothed_cell_path, DEFVAL(0.0));
    ClassDB::bind_method(D_METHOD("configure_movement_snapshot", "ids", "positions", "radii", "clearances", "priorities", "health"), &RoRPathKernel::configure_movement_snapshot);
    ClassDB::bind_method(D_METHOD("calculate_movement", "unit_id", "target", "speed", "cohesion_scale", "delta"), &RoRPathKernel::calculate_movement);
    ClassDB::bind_method(D_METHOD("get_revision"), &RoRPathKernel::get_revision);
    ClassDB::bind_method(D_METHOD("get_last_expanded_nodes"), &RoRPathKernel::get_last_expanded_nodes);
    ClassDB::bind_method(D_METHOD("get_last_path_was_direct"), &RoRPathKernel::get_last_path_was_direct);
    ClassDB::bind_method(D_METHOD("is_configured"), &RoRPathKernel::is_configured);
}

void RoRPathKernel::configure_movement_snapshot(
        const PackedInt32Array &ids,
        const PackedVector2Array &positions,
        const PackedFloat32Array &radii,
        const PackedFloat32Array &clearances,
        const PackedInt32Array &priorities,
        const PackedFloat32Array &health) {
    const int64_t count = std::min({ids.size(), positions.size(), radii.size(), clearances.size(), priorities.size(), health.size()});
    movement_ids_.resize(static_cast<size_t>(count));
    movement_positions_.resize(static_cast<size_t>(count));
    movement_radii_.resize(static_cast<size_t>(count));
    movement_clearances_.resize(static_cast<size_t>(count));
    movement_priorities_.resize(static_cast<size_t>(count));
    movement_health_.resize(static_cast<size_t>(count));
    movement_index_by_id_.clear();
    movement_buckets_.clear();
    maximum_movement_radius_ = 0.0f;
    maximum_movement_clearance_ = 0.0f;
    for (int64_t index = 0; index < count; ++index) {
        const size_t stored = static_cast<size_t>(index);
        movement_ids_[stored] = ids[index];
        movement_positions_[stored] = positions[index];
        movement_radii_[stored] = std::max(0.0f, radii[index]);
        movement_clearances_[stored] = std::max(0.0f, clearances[index]);
        movement_priorities_[stored] = priorities[index];
        movement_health_[stored] = health[index];
        movement_index_by_id_[movement_ids_[stored]] = static_cast<int32_t>(index);
        if (movement_health_[stored] <= 0.0f) {
            continue;
        }
        maximum_movement_radius_ = std::max(maximum_movement_radius_, movement_radii_[stored]);
        maximum_movement_clearance_ = std::max(maximum_movement_clearance_, movement_clearances_[stored]);
        const int32_t bucket_x = static_cast<int32_t>(std::floor(movement_positions_[stored].x / 2.0));
        const int32_t bucket_y = static_cast<int32_t>(std::floor(movement_positions_[stored].y / 2.0));
        movement_buckets_[movement_bucket_key(bucket_x, bucket_y)].push_back(static_cast<int32_t>(index));
    }
}

Vector4 RoRPathKernel::calculate_movement(int32_t unit_id, const Vector2 &target, double speed, double cohesion_scale, double delta) {
    const auto own_entry = movement_index_by_id_.find(unit_id);
    if (own_entry == movement_index_by_id_.end() || !is_configured()) {
        return Vector4(0.0, 0.0, -1.0, 0.0);
    }
    const int32_t own_index = own_entry->second;
    const Vector2 position = movement_positions_[static_cast<size_t>(own_index)];
    const Vector2 difference = target - position;
    const double resolved_speed = std::max(0.0, speed * cohesion_scale);
    const Vector2 desired = difference.length_squared() > 0.000001 ? difference.normalized() * resolved_speed : Vector2();
    const bool has_desired = desired.length_squared() > 0.0;
    const Vector2 desired_normalized = has_desired ? desired.normalized() : Vector2();
    const Vector2 lateral_normalized = has_desired ? Vector2(-desired.y, desired.x).normalized() : Vector2();
    const double own_radius = movement_radii_[static_cast<size_t>(own_index)];
    const double own_clearance = movement_clearances_[static_cast<size_t>(own_index)];
    const int32_t own_priority = movement_priorities_[static_cast<size_t>(own_index)];
    const double query_radius = 1.6 * own_radius + 0.6 * maximum_movement_radius_ + 1.6 * maximum_movement_clearance_;
    const double bucket_radius = query_radius + maximum_movement_radius_;
    const int32_t minimum_x = static_cast<int32_t>(std::floor((position.x - bucket_radius) / 2.0));
    const int32_t maximum_x = static_cast<int32_t>(std::floor((position.x + bucket_radius) / 2.0));
    const int32_t minimum_y = static_cast<int32_t>(std::floor((position.y - bucket_radius) / 2.0));
    const int32_t maximum_y = static_cast<int32_t>(std::floor((position.y + bucket_radius) / 2.0));
    movement_candidates_.clear();
    for (int32_t y = minimum_y; y <= maximum_y; ++y) {
        for (int32_t x = minimum_x; x <= maximum_x; ++x) {
            const auto bucket = movement_buckets_.find(movement_bucket_key(x, y));
            if (bucket == movement_buckets_.end()) {
                continue;
            }
            for (const int32_t candidate_index : bucket->second) {
                if (candidate_index == own_index) {
                    continue;
                }
                const double allowed_distance = query_radius + movement_radii_[static_cast<size_t>(candidate_index)];
                if (position.distance_squared_to(movement_positions_[static_cast<size_t>(candidate_index)]) <= allowed_distance * allowed_distance) {
                    movement_candidates_.push_back(candidate_index);
                }
            }
        }
    }
    std::sort(movement_candidates_.begin(), movement_candidates_.end(), [this](int32_t left, int32_t right) {
        return movement_ids_[static_cast<size_t>(left)] < movement_ids_[static_cast<size_t>(right)];
    });

    Vector2 avoidance;
    for (const int32_t candidate_index : movement_candidates_) {
        const size_t candidate = static_cast<size_t>(candidate_index);
        if (movement_health_[candidate] <= 0.0f) {
            continue;
        }
        Vector2 gap = position - movement_positions_[candidate];
        double distance = gap.length();
        const double safe_distance = own_radius + movement_radii_[candidate] + std::max(own_clearance, static_cast<double>(movement_clearances_[candidate]));
        if (distance <= 0.0001) {
            const double sign_value = unit_id < movement_ids_[candidate] ? -1.0 : 1.0;
            gap = Vector2(0.0, sign_value);
            distance = 0.0001;
        }
        if (distance < safe_distance * 1.6) {
            const double strength = std::clamp((safe_distance * 1.6 - distance) / (safe_distance * 1.6), 0.0, 1.0);
            const Vector2 gap_normalized = gap.normalized();
            const int32_t other_priority = movement_priorities_[candidate];
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
    return Vector4(velocity.x, velocity.y, static_cast<double>(state), static_cast<double>(movement_candidates_.size()));
}

void RoRPathKernel::configure(int32_t width, int32_t height, int64_t revision, const PackedByteArray &walkable) {
    width_ = std::max<int32_t>(0, width);
    height_ = std::max<int32_t>(0, height);
    revision_ = revision;
    last_expanded_nodes_ = 0;
    search_generation_ = 0;
    const int64_t expected_size = static_cast<int64_t>(width_) * static_cast<int64_t>(height_);
    walkable_.assign(static_cast<size_t>(expected_size), 0);
    const int64_t copy_size = std::min<int64_t>(expected_size, walkable.size());
    for (int64_t index = 0; index < copy_size; ++index) {
        walkable_[static_cast<size_t>(index)] = walkable[index] == 0 ? 0 : 1;
    }
    costs_.resize(static_cast<size_t>(expected_size));
    parents_.resize(static_cast<size_t>(expected_size));
    seen_generation_.assign(static_cast<size_t>(expected_size), 0);
    frontier_.clear();
}

PackedInt32Array RoRPathKernel::find_cell_path(const Vector2i &start, const Vector2i &goal, double clearance_radius) {
    PackedInt32Array result;
    last_expanded_nodes_ = 0;
    if (!is_configured() || !contains(start.x, start.y) || !contains(goal.x, goal.y) || !cell_walkable_for(goal.x, goal.y, clearance_radius)) {
        return result;
    }

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
            if (!can_step(current, next, clearance_radius)) {
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
    return width_ > 0 && height_ > 0 && walkable_.size() == static_cast<size_t>(width_) * static_cast<size_t>(height_);
}

bool RoRPathKernel::contains(int32_t x, int32_t y) const {
    return x >= 0 && y >= 0 && x < width_ && y < height_;
}

bool RoRPathKernel::cell_walkable(int32_t x, int32_t y) const {
    return contains(x, y) && walkable_[static_cast<size_t>(y * width_ + x)] != 0;
}

bool RoRPathKernel::cell_walkable_for(int32_t x, int32_t y, double clearance_radius) const {
    if (!cell_walkable(x, y)) {
        return false;
    }
    if (clearance_radius <= 0.0001) {
        return true;
    }
    const double center_x = static_cast<double>(x) + 0.5;
    const double center_y = static_cast<double>(y) + 0.5;
    return cell_walkable(static_cast<int32_t>(std::floor(center_x + clearance_radius)), y)
        && cell_walkable(static_cast<int32_t>(std::floor(center_x - clearance_radius)), y)
        && cell_walkable(x, static_cast<int32_t>(std::floor(center_y + clearance_radius)))
        && cell_walkable(x, static_cast<int32_t>(std::floor(center_y - clearance_radius)));
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
    if (!cell_walkable_for(start_x, start_y, clearance_radius) || !cell_walkable_for(goal_x, goal_y, clearance_radius)) {
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
    for (int32_t index = 1; index <= steps; ++index) {
        const double ratio = static_cast<double>(index) / static_cast<double>(steps);
        const int32_t current_x = static_cast<int32_t>(std::round(static_cast<double>(start_x) + static_cast<double>(difference_x) * ratio));
        const int32_t current_y = static_cast<int32_t>(std::round(static_cast<double>(start_y) + static_cast<double>(difference_y) * ratio));
        const int32_t current = current_y * width_ + current_x;
        if (current == previous) {
            continue;
        }
        if (!can_step(previous, current, clearance_radius)) {
            if (result != nullptr) {
                result->clear();
            }
            return false;
        }
        if (result != nullptr) {
            result->push_back(current);
        }
        previous = current;
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
    const int32_t left_y = left.index / width_;
    const int32_t right_y = right.index / width_;
    return left_y < right_y || (left_y == right_y && left.index % width_ < right.index % width_);
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
    const int32_t x = static_cast<int32_t>(std::floor(position.x));
    const int32_t y = static_cast<int32_t>(std::floor(position.y));
    if (!cell_walkable(x, y)) {
        return false;
    }
    if (radius <= 0.0001) {
        return true;
    }
    return cell_walkable(static_cast<int32_t>(std::floor(position.x + radius)), y)
        && cell_walkable(static_cast<int32_t>(std::floor(position.x - radius)), y)
        && cell_walkable(x, static_cast<int32_t>(std::floor(position.y + radius)))
        && cell_walkable(x, static_cast<int32_t>(std::floor(position.y - radius)));
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
