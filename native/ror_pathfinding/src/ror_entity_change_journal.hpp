#pragma once

#include <array>
#include <deque>
#include <unordered_map>
#include <unordered_set>
#include <vector>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_int64_array.hpp>

namespace godot {

// Owner-thread derived state. Canonical gameplay/save data remains in World.
// Native producers update typed versions directly; script consumers receive
// detached deltas or a lazily materialized compatibility version index.
class RoREntityChangeJournalKernel : public RefCounted {
    GDCLASS(RoREntityChangeJournalKernel, RefCounted)
public:
    void reset();
    void mark(int64_t id, int64_t mask);
    void remove(int64_t id);
    void flush();
    int64_t get_epoch() const { return epoch_; }
    int64_t get_revision() const { return revision_; }
    int64_t revision_for(int64_t id, int64_t mask = 255) const;
    const std::array<int64_t, 8> *version_row(int64_t id) const;
    bool is_dirty() const { return full_ || !pending_.empty(); }
    bool is_full() const { return full_; }
    int64_t retained_ids() const { return retained_ids_; }
    Dictionary changes_since(int64_t before);
    Dictionary read_changes_since(int64_t before);
    Dictionary export_versions();
    Dictionary export_pending() const;
    Dictionary export_removed() const;
    Array export_history() const;
    Dictionary export_state();
    Dictionary stats() const;
    void set_reference_capture(bool enabled);
    Dictionary take_reference_events();
protected:
    static void _bind_methods();
private:
    using Masks = std::unordered_map<int64_t, int64_t>;
    struct Batch {
        int64_t from = 0, to = 0;
        bool full = false;
        Masks masks;
        std::unordered_set<int64_t> removed;
    };
    int64_t epoch_ = 0, revision_ = 0, retained_ids_ = 0;
    bool full_ = false;
    std::unordered_map<int64_t, std::array<int64_t, 8>> versions_;
    Masks pending_;
    std::unordered_set<int64_t> removed_, changed_versions_;
    std::deque<Batch> history_;
    Dictionary version_view_;
    std::unordered_map<int64_t, Dictionary> delta_cache_;
    // Owned descriptors with immutable scalar-only collections. Public
    // changes_since() retains its independently mutable copy contract.
    std::unordered_map<int64_t, Dictionary> read_delta_cache_;
    int64_t marks_ = 0, exported_rows_ = 0, delta_hits_ = 0, delta_builds_ = 0;
    int64_t shared_reads_ = 0, shared_hits_ = 0;
    mutable int64_t direct_version_reads_ = 0;
    bool reference_capture_ = false, reference_overflow_ = false;
    std::vector<int64_t> reference_events_;
    void mark_internal(int64_t id, int64_t mask);
    void record_reference(int64_t operation, int64_t id = 0, int64_t mask = 0);
    Dictionary full_delta(const char *reason) const;
    Dictionary collect_since(int64_t before) const;
};

} // namespace godot
