#include "ror_actor_keys.hpp"
#include "ror_visibility_kernel.hpp"

#include <algorithm>
#include <climits>
#include <vector>

namespace godot {

namespace {
struct CellTransition {
    int32_t index;
    bool added;
};
struct SourceTransition {
    int64_t team;
    size_t begin, end;
};
}

// Build a source transition once, then filter it for each observer. The old
// per-observer entry point remains the scalar reference. Journals still see
// source order and intermediate visibility changes, not just the final mask.
Dictionary RoRVisibilityKernel::apply_observer_source_deltas(Dictionary states_by_player,
        Dictionary counts_by_player, const Dictionary &input) const {
    if (!is_configured() || states_by_player.is_read_only() || counts_by_player.is_read_only() ||
            states_by_player.get_typed_value_builtin() != Variant::NIL ||
            counts_by_player.get_typed_value_builtin() != Variant::NIL) return Dictionary();
    const int64_t cell_count = int64_t(width_) * height_;
    if (cell_count > INT32_MAX || input.get(ROR_FIELD("publications"), Variant()).get_type() != Variant::DICTIONARY ||
            input.get(ROR_FIELD("allies"), Variant()).get_type() != Variant::DICTIONARY) return Dictionary();
    const Dictionary publications = input[ROR_FIELD("publications")], shared_vision = input[ROR_FIELD("allies")];
    const Array observers = states_by_player.keys();
    // Validate every buffer before relinquishing any owner reference. A rejected
    // batch has no writes, so its caller can safely use the reference path.
    for (int64_t i = 0; i < observers.size(); ++i) {
        const Variant observer = observers[i];
        if (!counts_by_player.has(observer) || !publications.has(observer) ||
                states_by_player[observer].get_type() != Variant::PACKED_BYTE_ARRAY ||
                counts_by_player[observer].get_type() != Variant::PACKED_INT32_ARRAY ||
                publications[observer].get_type() != Variant::DICTIONARY) return Dictionary();
        const PackedByteArray states = states_by_player[observer];
        const PackedInt32Array counts = counts_by_player[observer];
        if (states.size() != cell_count || counts.size() != cell_count) return Dictionary();
    }
    for (const char *name : {"removed", "added", "previous", "current"})
        if (input.get(name, Variant()).get_type() != Variant::ARRAY) return Dictionary();
    const Array removed = input[ROR_FIELD("removed")], added = input[ROR_FIELD("added")];
    const Array previous = input[ROR_FIELD("previous")], current = input[ROR_FIELD("current")];
    if (previous.size() != current.size()) return Dictionary();
    std::vector<CellTransition> cells;
    std::vector<SourceTransition> sources;
    int64_t footprint_cells = 0;
    const auto source_valid = [](const Variant &value) {
        if (value.get_type() != Variant::DICTIONARY) return false;
        const Dictionary row = value;
        return row.get(ROR_FIELD("team"), Variant()).get_type() == Variant::INT &&
            row.get(ROR_FIELD("cells"), Variant()).get_type() == Variant::PACKED_INT32_ARRAY;
    };
    const auto append_source = [&](const Dictionary &source, bool add) {
        const PackedInt32Array footprint = source[ROR_FIELD("cells")];
        const int32_t *indices = footprint.ptr();
        const int64_t count = footprint.size();
        const size_t begin = cells.size();
        footprint_cells += count;
        for (int64_t i = 0; i < count; ++i) cells.push_back({indices[i], add});
        if (begin != cells.size()) sources.push_back({int64_t(source[ROR_FIELD("team")]), begin, cells.size()});
    };
    for (int64_t i = 0; i < removed.size(); ++i) {
        if (!source_valid(removed[i])) return Dictionary();
        append_source(removed[i], false);
    }
    for (int64_t i = 0; i < added.size(); ++i) {
        if (!source_valid(added[i])) return Dictionary();
        append_source(added[i], true);
    }
    for (int64_t i = 0; i < previous.size(); ++i) {
        if (!source_valid(previous[i]) || !source_valid(current[i])) return Dictionary();
        const Dictionary before = previous[i], after = current[i];
        if (int64_t(before[ROR_FIELD("team")]) != int64_t(after[ROR_FIELD("team")])) {
            append_source(before, false); append_source(after, true);
            continue;
        }
        const PackedInt32Array old_cells = before[ROR_FIELD("cells")], new_cells = after[ROR_FIELD("cells")];
        const int32_t *old_data = old_cells.ptr(), *new_data = new_cells.ptr();
        const int64_t old_count = old_cells.size(), new_count = new_cells.size();
        footprint_cells += old_count + new_count;
        int64_t a = 0, b = 0;
        const size_t begin = cells.size();
        while (a < old_count || b < new_count) {
            const int32_t old_cell = a < old_count ? old_data[a] : INT32_MAX;
            const int32_t new_cell = b < new_count ? new_data[b] : INT32_MAX;
            if (old_cell == new_cell) { ++a; ++b; }
            else if (old_cell < new_cell) cells.push_back({old_data[a++], false});
            else cells.push_back({new_data[b++], true});
        }
        if (begin != cells.size()) sources.push_back({int64_t(after[ROR_FIELD("team")]), begin, cells.size()});
    }
    Dictionary changed, explored, results;
    int64_t states_reused = 0, counts_reused = 0, applications = 0;
    for (int64_t i = 0; i < observers.size(); ++i) {
        const Variant observer = observers[i];
        const Dictionary allies = shared_vision.get(observer, Dictionary());
        const Dictionary publication = publications[observer];
        // Borrow canonical buffers on the owner thread. Retained external
        // snapshots continue to trigger COW; no user callback runs in this span.
        PackedByteArray states = states_by_player[observer];
        PackedInt32Array counts = counts_by_player[observer];
        const uint8_t *old_states = states.ptr();
        const int32_t *old_counts = counts.ptr();
        states_by_player[observer] = Variant(); counts_by_player[observer] = Variant();
        // Delay writable access when this observer has no relevant transitions.
        uint8_t *state = nullptr;
        int32_t *count = nullptr;
        // Visibility events depend on interleaved remove/add order, so applying
        // separate aggregate removal/addition lists would be incorrect.
        std::vector<int32_t> visible_events, explored_events, newly_visible_events;
        for (const SourceTransition &source : sources) {
            if (!bool(allies.get(source.team, false))) continue;
            if (!state) { state = states.ptrw(); count = counts.ptrw(); }
            ++applications;
            for (size_t j = source.begin; j < source.end; ++j) {
                const CellTransition &event = cells[j];
                const int32_t index = event.index;
                if (index < 0 || index >= cell_count) continue;
                if (event.added) {
                    if (count[index] == 0 && state[index] != 2) {
                        newly_visible_events.push_back(index);
                        if (state[index] == 0) explored_events.push_back(index);
                        state[index] = 2; visible_events.push_back(index);
                    }
                    ++count[index];
                } else {
                    count[index] = std::max(0, count[index] - 1);
                    if (count[index] == 0 && state[index] == 2) {
                        state[index] = 1; visible_events.push_back(index);
                    }
                }
            }
        }
        states_by_player[observer] = states; counts_by_player[observer] = counts;
        states_reused += states.ptr() == old_states;
        counts_reused += counts.ptr() == old_counts;
        // The shared journal publisher lives with the scalar implementation.
        publish_observer_visibility(publication, visible_events, explored_events, newly_visible_events);
        if (!visible_events.empty()) changed[observer] = true;
        if (!explored_events.empty()) explored[observer] = true;
    }
    results[ROR_FIELD("changed")] = changed; results[ROR_FIELD("explored")] = explored;
    results[ROR_FIELD("states_reused")] = states_reused; results[ROR_FIELD("counts_reused")] = counts_reused;
    results[ROR_FIELD("observers")] = observers.size(); results[ROR_FIELD("source_transitions")] = int64_t(sources.size());
    results[ROR_FIELD("cell_operations")] = int64_t(cells.size()); results[ROR_FIELD("footprint_cells")] = footprint_cells;
    results[ROR_FIELD("observer_applications")] = applications;
    return results;
}

} // namespace godot
