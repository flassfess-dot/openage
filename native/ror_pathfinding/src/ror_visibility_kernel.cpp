#include "ror_actor_keys.hpp"
#include "ror_visibility_kernel.hpp"

#include <algorithm>
#include <cmath>
#include <vector>

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/math.hpp>
#include <chrono>

namespace godot {

void RoRVisibilityKernel::_bind_methods() {
    ClassDB::bind_method(D_METHOD("configure", "width", "height"), &RoRVisibilityKernel::configure);
    ClassDB::bind_method(D_METHOD("vision_cells", "center", "radius"), &RoRVisibilityKernel::vision_cells);
    ClassDB::bind_method(D_METHOD("is_configured"), &RoRVisibilityKernel::is_configured);
    ClassDB::bind_method(D_METHOD("apply_source_deltas", "input"), &RoRVisibilityKernel::apply_source_deltas);
    ClassDB::bind_method(D_METHOD("apply_owned_source_deltas", "states_by_player", "counts_by_player", "observer", "input"), &RoRVisibilityKernel::apply_owned_source_deltas);
    ClassDB::bind_method(D_METHOD("apply_observer_source_deltas", "states_by_player", "counts_by_player", "input"), &RoRVisibilityKernel::apply_observer_source_deltas);
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
PackedInt32Array pack_visibility_indices(const std::vector<int32_t> &values) {
    PackedInt32Array result;
    if (values.empty()) return result;
    result.resize(static_cast<int64_t>(values.size()));
    std::copy(values.begin(), values.end(), result.ptrw());
    return result;
}

void append_visibility_history(Array history, int64_t before, const PackedInt32Array &indices, int width) {
    if (indices.is_empty()) return;
    Dictionary entry;
    if (!history.is_empty() && int64_t(Dictionary(history[history.size() - 1]).get(ROR_FIELD("from"), -1)) == before) entry = history[history.size() - 1];
    else {
        if (!history.is_empty() && int64_t(Dictionary(history[history.size() - 1]).get(ROR_FIELD("to"), -1)) != before) history.clear();
        entry[ROR_FIELD("from")] = before; entry[ROR_FIELD("to")] = before + 1;
        entry[ROR_FIELD("region")] = Rect2(); entry[ROR_FIELD("has_region")] = false;
        entry[ROR_FIELD("cells")] = Array(); entry[ROR_FIELD("cells_complete")] = true;
        history.append(entry);
    }
    Rect2 region = entry[ROR_FIELD("region")];
    bool has_region = entry[ROR_FIELD("has_region")], complete = entry[ROR_FIELD("cells_complete")];
    Array cells = entry[ROR_FIELD("cells")];
    const int32_t *data = indices.ptr();
    const int64_t index_count = indices.size();
    int64_t retained_cells = cells.size();
    for (int64_t i = 0; i < index_count; ++i) {
        const Vector2i cell(data[i] % width, data[i] / width);
        const Rect2 next(Vector2(cell), Vector2(1, 1));
        region = has_region ? region.merge(next) : next;
        has_region = true;
        if (complete) {
            if (retained_cells < 512) { cells.append(cell); ++retained_cells; }
            else { cells.clear(); complete = false; }
        }
    }
    entry[ROR_FIELD("region")] = region; entry[ROR_FIELD("has_region")] = has_region;
    entry[ROR_FIELD("cells_complete")] = complete;
    while (history.size() > 256) history.remove_at(0);
}

void publish_visibility_delta(const Dictionary &publication, const PackedInt32Array &visible, const PackedInt32Array &explored, const PackedInt32Array &newly_visible, int width) {
    const Dictionary changes = publication[ROR_FIELD("changes")];
    append_visibility_history(changes[ROR_FIELD("history")], changes[ROR_FIELD("revision")], visible, width);
    append_visibility_history(changes[ROR_FIELD("exploration_history")], changes[ROR_FIELD("exploration_revision")], explored, width);
    const Variant dirty_value = publication[ROR_FIELD("dirty")], navigation_value = publication[ROR_FIELD("navigation")], path_value = publication[ROR_FIELD("path")];
    const int64_t visible_count = visible.size(), explored_count = explored.size(), newly_visible_count = newly_visible.size();
    const int32_t *visible_data = visible.ptr(), *explored_data = explored.ptr(), *newly_visible_data = newly_visible.ptr();
    if (dirty_value.get_type() == Variant::DICTIONARY) {
        Dictionary dirty = dirty_value;
        for (int64_t i = 0; i < visible_count; ++i) dirty[visible_data[i]] = true;
    }
    Array discoveries = publication[ROR_FIELD("explored")];
    for (int64_t i = 0; i < explored_count; ++i) discoveries.append(explored_data[i]);
    if (navigation_value.get_type() == Variant::ARRAY) {
        Array navigation = navigation_value;
        for (int64_t i = 0; i < explored_count; ++i) navigation.append(explored_data[i]);
    }
    Dictionary seen = publication[ROR_FIELD("visible")];
    for (int64_t i = 0; i < newly_visible_count; ++i) seen[newly_visible_data[i]] = true;
    if (path_value.get_type() == Variant::DICTIONARY) {
        Dictionary path = path_value;
        for (int64_t i = 0; i < newly_visible_count; ++i) path[newly_visible_data[i]] = true;
    }
}
} // namespace
void RoRVisibilityKernel::publish_observer_visibility(const Dictionary &publication, const std::vector<int32_t> &visible,
        const std::vector<int32_t> &explored, const std::vector<int32_t> &newly_visible) const {
    publish_visibility_delta(publication, pack_visibility_indices(visible), pack_visibility_indices(explored),
        pack_visibility_indices(newly_visible), width_);
}
// Preserve source order, including transient visibility changes where one source
// leaves a cell before another enters it. Journals are published by the owner.
Dictionary RoRVisibilityKernel::apply_source_deltas(const Dictionary &input) const {
    PackedByteArray states = input[ROR_FIELD("states")];
    PackedInt32Array counts = input[ROR_FIELD("counts")];
    return apply_source_deltas_internal(input, states, counts);
}

Dictionary RoRVisibilityKernel::apply_owned_source_deltas(Dictionary states_by_player, Dictionary counts_by_player,
        int64_t observer, const Dictionary &input) const {
    // Synchronous owner only; the core below invokes no script/user callbacks.
    // Release just the owner's references before ptrw(). External snapshots keep
    // their references, so PackedArray COW still protects every old snapshot.
    // Keep the keys in place: erase/reinsert would change dictionary order.
    if (states_by_player.is_read_only() || counts_by_player.is_read_only() ||
        states_by_player.get_typed_value_builtin() != Variant::NIL || counts_by_player.get_typed_value_builtin() != Variant::NIL ||
        !states_by_player.has(observer) || !counts_by_player.has(observer) ||
        states_by_player[observer].get_type() != Variant::PACKED_BYTE_ARRAY ||
        counts_by_player[observer].get_type() != Variant::PACKED_INT32_ARRAY ||
        input.has(ROR_FIELD("states")) || input.has(ROR_FIELD("counts"))) return Dictionary();
    PackedByteArray states = states_by_player[observer];
    PackedInt32Array counts = counts_by_player[observer];
    if (!is_configured() || states.size() != int64_t(width_) * height_ || counts.size() != states.size()) return Dictionary();
    const uint8_t *previous_states = states.ptr();
    const int32_t *previous_counts = counts.ptr();
    states_by_player[observer] = Variant();
    counts_by_player[observer] = Variant();
    Dictionary result = apply_source_deltas_internal(input, states, counts);
    states_by_player[observer] = states;
    counts_by_player[observer] = counts;
    if (!result.is_empty()) {
        result[ROR_FIELD("states_reused")] = states.ptr() == previous_states;
        result[ROR_FIELD("counts_reused")] = counts.ptr() == previous_counts;
    }
    return result;
}

Dictionary RoRVisibilityKernel::apply_source_deltas_internal(const Dictionary &input, PackedByteArray &states, PackedInt32Array &counts) const {
    if (!is_configured() || states.size() != int64_t(width_) * height_ || counts.size() != states.size()) return Dictionary();
    const Dictionary allies = input[ROR_FIELD("allies")];
    const Array removed = input[ROR_FIELD("removed")], added = input[ROR_FIELD("added")];
    const Array previous = input[ROR_FIELD("previous")], current = input[ROR_FIELD("current")];
    if (previous.size() != current.size()) return Dictionary();
    uint8_t *state = states.ptrw();
    int32_t *count = counts.ptrw();
    const int64_t state_count = states.size();
    // Array lengths and pointers stay fixed throughout this synchronous pass.
    // Keep cell arithmetic and event accumulation in native storage, then
    // publish each packed array once. Preserve duplicate events and ordering:
    // one source leaving before another enters is observable in the journals.
    std::vector<int32_t> visible_events, explored_events, newly_visible_events;
    auto remove_cell = [&](int32_t index) {
        if (index < 0 || index >= state_count) return;
        count[index] = std::max(0, count[index] - 1);
        if (count[index] == 0 && state[index] == 2) {
            state[index] = 1;
            visible_events.push_back(index);
        }
    };
    auto add_cell = [&](int32_t index) {
        if (index < 0 || index >= state_count) return;
        if (count[index] == 0 && state[index] != 2) {
            newly_visible_events.push_back(index);
            if (state[index] == 0) explored_events.push_back(index);
            state[index] = 2;
            visible_events.push_back(index);
        }
        ++count[index];
    };
    auto allied = [&](const Dictionary &source) { return bool(allies.get(int64_t(source.get(ROR_FIELD("team"), 0)), false)); };
    auto remove_source = [&](const Dictionary &source) {
        const PackedInt32Array cells = source[ROR_FIELD("cells")];
        const int32_t *data = cells.ptr();
        const int64_t cell_count = cells.size();
        for (int64_t i = 0; i < cell_count; ++i) remove_cell(data[i]);
    };
    auto add_source = [&](const Dictionary &source) {
        const PackedInt32Array cells = source[ROR_FIELD("cells")];
        const int32_t *data = cells.ptr();
        const int64_t cell_count = cells.size();
        for (int64_t i = 0; i < cell_count; ++i) add_cell(data[i]);
    };
    for (int64_t i = 0; i < removed.size(); ++i) { const Dictionary source = removed[i]; if (allied(source)) remove_source(source); }
    for (int64_t i = 0; i < added.size(); ++i) { const Dictionary source = added[i]; if (allied(source)) add_source(source); }
    for (int64_t i = 0; i < previous.size(); ++i) {
        const Dictionary before = previous[i], after = current[i];
        if (int64_t(before[ROR_FIELD("team")]) != int64_t(after[ROR_FIELD("team")])) {
            if (allied(before)) remove_source(before);
            if (allied(after)) add_source(after);
            continue;
        }
        if (!allied(after)) continue;
        const PackedInt32Array old_cells = before[ROR_FIELD("cells")], new_cells = after[ROR_FIELD("cells")];
        const int32_t *old_data = old_cells.ptr(), *new_data = new_cells.ptr();
        const int64_t old_count = old_cells.size(), new_count = new_cells.size();
        int64_t a = 0, b = 0;
        while (a < old_count || b < new_count) {
            const int32_t old_cell = a < old_count ? old_data[a] : INT32_MAX;
            const int32_t new_cell = b < new_count ? new_data[b] : INT32_MAX;
            if (old_cell == new_cell) { ++a; ++b; }
            else if (old_cell < new_cell) remove_cell(old_data[a++]);
            else add_cell(new_data[b++]);
        }
    }
    const PackedInt32Array visible_changes = pack_visibility_indices(visible_events);
    const PackedInt32Array explored = pack_visibility_indices(explored_events);
    const PackedInt32Array newly_visible = pack_visibility_indices(newly_visible_events);
    if (input.has(ROR_FIELD("publication"))) publish_visibility_delta(input[ROR_FIELD("publication")], visible_changes, explored, newly_visible, width_);
    Dictionary result;
    result[ROR_FIELD("states")] = states;
    result[ROR_FIELD("counts")] = counts;
    result[ROR_FIELD("visibility")] = visible_changes;
    result[ROR_FIELD("exploration")] = explored;
    result[ROR_FIELD("newly_visible")] = newly_visible;
    return result;
}
Dictionary RoRVisibilityKernel::collect_source_deltas(const Dictionary &input) const {
    static const Variant hp("hp"), components_key("components"), vision_key("vision"), range("range"), enabled("enabled"), state("state");
    static const Variant team_key("team"), id_key("id"), pos("pos"), radius_key("radius"), center_key("center"), cells_key("cells");
    static const Variant seen_generation("seen_generation"), entity_key("entity"), source_revision("source_revision");
    const Array entities = input[ROR_FIELD("entities")];
    Dictionary sources = input[ROR_FIELD("sources")], states = input[ROR_FIELD("states")], personal = input[ROR_FIELD("personal")];
    Array added = input[ROR_FIELD("added")], previous_rows = input[ROR_FIELD("previous")], current_rows = input[ROR_FIELD("current")];
    const Callable ensure_player = input[ROR_FIELD("ensure_player")];
    const int64_t category = input[ROR_FIELD("category")], generation = input[ROR_FIELD("generation")];
    const int64_t buckets = std::max<int64_t>(1, input[ROR_FIELD("buckets")]), phase = input[ROR_FIELD("phase")];
    int64_t regenerated = 0, vision_us = 0;
    const bool profile = input.get(ROR_FIELD("profile"), false);
    for (int64_t index = 0; index < entities.size(); ++index) {
        const Dictionary entity = entities[index];
        if (double(entity.get(hp, 0.0)) <= 0.0 || String(entity.get(state, ROR_FIELD("complete"))) == "foundation") continue;
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
        const int64_t cell_count = cells.size(), old_count = old_cells.size();
        int64_t old_index = 0;
        for (int64_t i = 0; i < cell_count; ++i) {
            while (old_index < old_count && old_data[old_index] < data[i]) ++old_index;
            if (old_index >= old_count || old_data[old_index] != data[i]) explored[data[i]] = true;
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
    result[ROR_FIELD("regenerated")] = regenerated; result[ROR_FIELD("vision_us")] = vision_us;
    return result;
}
bool RoRVisibilityKernel::is_configured() const {
    return width_ > 0 && height_ > 0;
}

} // namespace godot
