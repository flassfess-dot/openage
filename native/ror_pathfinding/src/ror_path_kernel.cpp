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
constexpr int32_t DIRECTIONS[8][2] = {
    {-1, -1}, {0, -1}, {1, -1},
    {-1, 0},           {1, 0},
    {-1, 1},  {0, 1},  {1, 1},
};
}

void RoRPathKernel::_bind_methods() {
    ClassDB::bind_method(D_METHOD("configure", "width", "height", "revision", "walkable"), &RoRPathKernel::configure);
    ClassDB::bind_method(D_METHOD("find_cell_path", "start", "goal", "clearance_radius"), &RoRPathKernel::find_cell_path, DEFVAL(0.0));
    ClassDB::bind_method(D_METHOD("get_revision"), &RoRPathKernel::get_revision);
    ClassDB::bind_method(D_METHOD("get_last_expanded_nodes"), &RoRPathKernel::get_last_expanded_nodes);
    ClassDB::bind_method(D_METHOD("is_configured"), &RoRPathKernel::is_configured);
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

int64_t RoRPathKernel::get_revision() const {
    return revision_;
}

int32_t RoRPathKernel::get_last_expanded_nodes() const {
    return last_expanded_nodes_;
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

} // namespace godot
