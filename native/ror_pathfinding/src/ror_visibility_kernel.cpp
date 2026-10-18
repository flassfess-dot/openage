#include "ror_visibility_kernel.hpp"

#include <algorithm>
#include <cmath>

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/math.hpp>
#include <chrono>

namespace godot {

void RoRVisibilityKernel::_bind_methods() {
    ClassDB::bind_method(D_METHOD("configure", "width", "height"), &RoRVisibilityKernel::configure);
    ClassDB::bind_method(D_METHOD("vision_cells", "center", "radius"), &RoRVisibilityKernel::vision_cells);
    ClassDB::bind_method(D_METHOD("is_configured"), &RoRVisibilityKernel::is_configured);
    ClassDB::bind_method(D_METHOD("apply_source_deltas", "input"), &RoRVisibilityKernel::apply_source_deltas);
    ClassDB::bind_method(D_METHOD("collect_source_deltas", "input"), &RoRVisibilityKernel::collect_source_deltas);
}

void RoRVisibilityKernel::configure(int32_t width, int32_t height) {
    width_ = std::max<int32_t>(1, width);
    height_ = std::max<int32_t>(1, height);
}

PackedInt32Array RoRVisibilityKernel::vision_cells(const Vector2 &center, double radius) const {
    PackedInt32Array result;
    if (!is_configured() || radius < 0.0) {
        return result;
    }
    const int32_t minimum_x = std::max<int32_t>(0, static_cast<int32_t>(std::floor(center.x - radius)));
    const int32_t minimum_y = std::max<int32_t>(0, static_cast<int32_t>(std::floor(center.y - radius)));
    const int32_t maximum_x = std::min<int32_t>(width_ - 1, static_cast<int32_t>(std::floor(center.x + radius)));
    const int32_t maximum_y = std::min<int32_t>(height_ - 1, static_cast<int32_t>(std::floor(center.y + radius)));
    if (minimum_x > maximum_x || minimum_y > maximum_y) return result;
    // One bounded buffer allocation instead of a GDExtension append per tile.
    result.resize(int64_t(maximum_x - minimum_x + 1) * (maximum_y - minimum_y + 1));
    int32_t *indices = result.ptrw();
    int64_t count = 0;
    const double radius_squared = radius * radius + 0.000001;
    for (int32_t y = minimum_y; y <= maximum_y; ++y) {
        for (int32_t x = minimum_x; x <= maximum_x; ++x) {
            const double nearest_x = std::clamp(static_cast<double>(center.x), static_cast<double>(x), static_cast<double>(x + 1));
            const double nearest_y = std::clamp(static_cast<double>(center.y), static_cast<double>(y), static_cast<double>(y + 1));
            const double difference_x = static_cast<double>(center.x) - nearest_x;
            const double difference_y = static_cast<double>(center.y) - nearest_y;
            if (difference_x * difference_x + difference_y * difference_y <= radius_squared) {
                indices[count++] = y * width_ + x;
            }
        }
    }
    result.resize(count);
    return result;
}

namespace {
void append_visibility_history(Array history, int64_t before, const PackedInt32Array &indices, int width) {
    if (indices.is_empty()) return;
    Dictionary entry;
    if (!history.is_empty() && int64_t(Dictionary(history[history.size() - 1]).get("from", -1)) == before) entry = history[history.size() - 1];
    else {
        if (!history.is_empty() && int64_t(Dictionary(history[history.size() - 1]).get("to", -1)) != before) history.clear();
        entry["from"] = before; entry["to"] = before + 1;
        entry["region"] = Rect2(); entry["has_region"] = false;
        entry["cells"] = Array(); entry["cells_complete"] = true;
        history.append(entry);
    }
    Rect2 region = entry["region"];
    bool has_region = entry["has_region"], complete = entry["cells_complete"];
    Array cells = entry["cells"];
    const int32_t *data = indices.ptr();
    for (int64_t i = 0; i < indices.size(); ++i) {
        const Vector2i cell(data[i] % width, data[i] / width);
        const Rect2 next(Vector2(cell), Vector2(1, 1));
        region = has_region ? region.merge(next) : next;
        has_region = true;
        if (complete) {
            if (cells.size() < 512) cells.append(cell);
            else { cells.clear(); complete = false; }
        }
    }
    entry["region"] = region; entry["has_region"] = has_region;
    entry["cells_complete"] = complete;
    while (history.size() > 256) history.remove_at(0);
}

void publish_visibility_delta(const Dictionary &publication, const PackedInt32Array &visible, const PackedInt32Array &explored, const PackedInt32Array &newly_visible, int width) {
    const Dictionary changes = publication["changes"];
    append_visibility_history(changes["history"], changes["revision"], visible, width);
    append_visibility_history(changes["exploration_history"], changes["exploration_revision"], explored, width);
    const Variant dirty_value = publication["dirty"], navigation_value = publication["navigation"], path_value = publication["path"];
    if (dirty_value.get_type() == Variant::DICTIONARY) {
        Dictionary dirty = dirty_value;
        for (int64_t i = 0; i < visible.size(); ++i) dirty[visible[i]] = true;
    }
    Array discoveries = publication["explored"];
    for (int64_t i = 0; i < explored.size(); ++i) discoveries.append(explored[i]);
    if (navigation_value.get_type() == Variant::ARRAY) {
        Array navigation = navigation_value;
        for (int64_t i = 0; i < explored.size(); ++i) navigation.append(explored[i]);
    }
    Dictionary seen = publication["visible"];
    for (int64_t i = 0; i < newly_visible.size(); ++i) seen[newly_visible[i]] = true;
    if (path_value.get_type() == Variant::DICTIONARY) {
        Dictionary path = path_value;
        for (int64_t i = 0; i < newly_visible.size(); ++i) path[newly_visible[i]] = true;
    }
}
} // namespace
// Preserve source order, including transient visibility changes where one source
// leaves a cell before another enters it. Journals are published by the owner.
Dictionary RoRVisibilityKernel::apply_source_deltas(const Dictionary &input) const {
    PackedByteArray states = input["states"];
    PackedInt32Array counts = input["counts"];
    if (!is_configured() || states.size() != int64_t(width_) * height_ || counts.size() != states.size()) return Dictionary();
    const Dictionary allies = input["allies"];
    const Array removed = input["removed"], added = input["added"];
    const Array previous = input["previous"], current = input["current"];
    if (previous.size() != current.size()) return Dictionary();
    uint8_t *state = states.ptrw();
    int32_t *count = counts.ptrw();
    PackedInt32Array visible_changes, explored, newly_visible;
    auto remove_cell = [&](int32_t index) {
        if (index < 0 || index >= states.size()) return;
        count[index] = std::max(0, count[index] - 1);
        if (count[index] == 0 && state[index] == 2) {
            state[index] = 1;
            visible_changes.append(index);
        }
    };
    auto add_cell = [&](int32_t index) {
        if (index < 0 || index >= states.size()) return;
        if (count[index] == 0 && state[index] != 2) {
            newly_visible.append(index);
            if (state[index] == 0) explored.append(index);
            state[index] = 2;
            visible_changes.append(index);
        }
        ++count[index];
    };
    auto allied = [&](const Dictionary &source) { return bool(allies.get(int64_t(source.get("team", 0)), false)); };
    auto remove_source = [&](const Dictionary &source) {
        const PackedInt32Array cells = source["cells"];
        const int32_t *data = cells.ptr();
        for (int64_t i = 0; i < cells.size(); ++i) remove_cell(data[i]);
    };
    auto add_source = [&](const Dictionary &source) {
        const PackedInt32Array cells = source["cells"];
        const int32_t *data = cells.ptr();
        for (int64_t i = 0; i < cells.size(); ++i) add_cell(data[i]);
    };
    for (int64_t i = 0; i < removed.size(); ++i) { const Dictionary source = removed[i]; if (allied(source)) remove_source(source); }
    for (int64_t i = 0; i < added.size(); ++i) { const Dictionary source = added[i]; if (allied(source)) add_source(source); }
    for (int64_t i = 0; i < previous.size(); ++i) {
        const Dictionary before = previous[i], after = current[i];
        if (int64_t(before["team"]) != int64_t(after["team"])) {
            if (allied(before)) remove_source(before);
            if (allied(after)) add_source(after);
            continue;
        }
        if (!allied(after)) continue;
        const PackedInt32Array old_cells = before["cells"], new_cells = after["cells"];
        const int32_t *old_data = old_cells.ptr(), *new_data = new_cells.ptr();
        int64_t a = 0, b = 0;
        while (a < old_cells.size() || b < new_cells.size()) {
            const int32_t old_cell = a < old_cells.size() ? old_data[a] : INT32_MAX;
            const int32_t new_cell = b < new_cells.size() ? new_data[b] : INT32_MAX;
            if (old_cell == new_cell) { ++a; ++b; }
            else if (old_cell < new_cell) remove_cell(old_data[a++]);
            else add_cell(new_data[b++]);
        }
    }
    if (input.has("publication")) publish_visibility_delta(input["publication"], visible_changes, explored, newly_visible, width_);
    Dictionary result;
    result["states"] = states;
    result["counts"] = counts;
    result["visibility"] = visible_changes;
    result["exploration"] = explored;
    result["newly_visible"] = newly_visible;
    return result;
}
Dictionary RoRVisibilityKernel::collect_source_deltas(const Dictionary &input) const {
    static const Variant hp("hp"), components_key("components"), vision_key("vision"), range("range"), enabled("enabled");
    static const Variant team_key("team"), id_key("id"), pos("pos"), radius_key("radius"), center_key("center"), cells_key("cells");
    static const Variant seen_generation("seen_generation"), entity_key("entity"), source_revision("source_revision");
    const Array entities = input["entities"];
    Dictionary sources = input["sources"], states = input["states"], personal = input["personal"];
    Array added = input["added"], previous_rows = input["previous"], current_rows = input["current"];
    const Callable ensure_player = input["ensure_player"];
    const int64_t category = input["category"], generation = input["generation"];
    const int64_t buckets = std::max<int64_t>(1, input["buckets"]), phase = input["phase"];
    int64_t regenerated = 0, vision_us = 0;
    const bool profile = input.get("profile", false);
    for (int64_t index = 0; index < entities.size(); ++index) {
        const Dictionary entity = entities[index];
        if (double(entity.get(hp, 0.0)) <= 0.0) continue;
        const Dictionary components = entity.get(components_key, Dictionary()), vision = components.get(vision_key, Dictionary());
        const double radius = std::max(0.0, double(vision.get(range, 0.0)));
        if (radius <= 0.0 || !bool(vision.get(enabled, false))) continue;
        const int64_t team = entity.get(team_key, 0);
        if (team <= 0) continue;
        if (!states.has(team)) ensure_player.call(team);
        const int64_t id = entity.get(id_key, -1), stable = id >= 0 ? id : index;
        const int64_t key = (stable << 1) | (category & 1);
        const Vector2 center = entity[pos];
        const Variant old_value = sources.get(key, Variant());
        const bool has_previous = old_value.get_type() == Variant::DICTIONARY;
        Dictionary previous = has_previous ? Dictionary(old_value) : Dictionary();
        const bool same_owner = has_previous && int64_t(previous[team_key]) == team;
        const bool same_definition = same_owner && Math::is_equal_approx(double(previous[radius_key]), radius);
        const auto positive_mod = [](int64_t value, int64_t divisor) { return (value % divisor + divisor) % divisor; };
        if (same_definition && (Vector2(previous[center_key]).is_equal_approx(center) || (buckets > 1 && positive_mod(stable, buckets) != positive_mod(phase, buckets)))) {
            previous[seen_generation] = generation;
            continue;
        }
        const auto started = profile ? std::chrono::steady_clock::now() : std::chrono::steady_clock::time_point();
        const PackedInt32Array cells = vision_cells(center, radius);
        Dictionary explored = personal[team];
        const int32_t *data = cells.ptr();
        // The previous footprint was recorded for this owner when published.
        // Personal exploration is monotonic until reset, which also retires all
        // sources. Visit the sorted fringe, including radius changes/teleports.
        const PackedInt32Array old_cells = same_owner ? PackedInt32Array(previous[cells_key]) : PackedInt32Array();
        const int32_t *old_data = old_cells.ptr();
        int64_t old_index = 0;
        for (int64_t i = 0; i < cells.size(); ++i) {
            while (old_index < old_cells.size() && old_data[old_index] < data[i]) ++old_index;
            if (old_index >= old_cells.size() || old_data[old_index] != data[i]) explored[data[i]] = true;
        }
        if (profile) {
            vision_us += std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now() - started).count();
            ++regenerated;
        }
        Dictionary current;
        current[team_key] = team; current[center_key] = center; current[radius_key] = radius;
        current[cells_key] = cells; current[entity_key] = entity;
        current[source_revision] = has_previous ? int64_t(previous.get(source_revision, 0)) + 1 : 1;
        current[seen_generation] = generation;
        sources[key] = current;
        if (has_previous) { previous_rows.append(previous); current_rows.append(current); }
        else added.append(current);
    }
    Dictionary result;
    result["regenerated"] = regenerated; result["vision_us"] = vision_us;
    return result;
}
bool RoRVisibilityKernel::is_configured() const {
    return width_ > 0 && height_ > 0;
}

} // namespace godot
