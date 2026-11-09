#include "ror_entity_change_journal.hpp"
#include <algorithm>
#include <godot_cpp/core/class_db.hpp>

namespace godot {
namespace {
Dictionary masks_dictionary(const std::unordered_map<int64_t, int64_t> &masks) {
    Dictionary result;
    for (const auto &entry : masks) result[entry.first] = entry.second;
    return result;
}
Dictionary removed_dictionary(const std::unordered_set<int64_t> &removed) {
    Dictionary result;
    for (int64_t id : removed) result[id] = true;
    return result;
}
template<class Collection> Array sorted_ids(const Collection &values) {
    std::vector<int64_t> ids(values.begin(), values.end());
    std::sort(ids.begin(), ids.end());
    Array result; result.resize(ids.size());
    for (size_t i = 0; i < ids.size(); ++i) result[int64_t(i)] = ids[i];
    return result;
}
}

void RoREntityChangeJournalKernel::record_reference(int64_t op, int64_t id, int64_t mask) {
    if (!reference_capture_ || reference_overflow_) return;
    if (reference_events_.size() >= 16384 * 3) { reference_overflow_ = true; return; }
    reference_events_.push_back(op); reference_events_.push_back(id); reference_events_.push_back(mask);
}
void RoREntityChangeJournalKernel::reset() {
    ++epoch_; revision_ = 0; retained_ids_ = 0; full_ = false;
    versions_.clear(); pending_.clear(); removed_.clear(); changed_versions_.clear(); history_.clear();
    version_view_.clear(); delta_cache_.clear(); read_delta_cache_.clear();
    marks_ = exported_rows_ = delta_hits_ = delta_builds_ = 0;
    direct_version_reads_ = 0;
    shared_reads_ = shared_hits_ = 0;
    reference_events_.clear(); reference_overflow_ = false;
    record_reference(3);
}
void RoREntityChangeJournalKernel::mark(int64_t id, int64_t mask) {
    record_reference(0, id, mask);
    mark_internal(id, mask);
}
void RoREntityChangeJournalKernel::mark_internal(int64_t id, int64_t mask) {
    mask &= 255;
    if (id < 0 || mask == 0) return;
    const auto pending = pending_.find(id);
    if (pending != pending_.end() && (pending->second & mask) == mask) return;
    auto found = versions_.find(id);
    if (found == versions_.end()) {
        if (versions_.size() >= 262144) {
            pending_.clear(); removed_.clear(); full_ = true;
            return;
        }
        found = versions_.emplace(id, std::array<int64_t, 8>{}).first;
    }
    const int64_t next = revision_ + 1;
    for (int group = 0; group < 8; ++group)
        if (mask & (int64_t(1) << group)) found->second[group] = next;
    changed_versions_.insert(id); ++marks_;
    if (full_) return;
    pending_[id] |= mask;
    if (pending_.size() > 8192) { pending_.clear(); removed_.clear(); full_ = true; }
}
void RoREntityChangeJournalKernel::remove(int64_t id) {
    record_reference(1, id);
    mark_internal(id, 255);
    versions_.erase(id); changed_versions_.insert(id);
    if (!full_) removed_.insert(id);
}
void RoREntityChangeJournalKernel::flush() {
    if (pending_.empty() && !full_) return;
    record_reference(2);
    delta_cache_.clear();
    read_delta_cache_.clear();
    Batch batch; batch.from = revision_; batch.to = ++revision_; batch.full = full_;
    batch.masks.swap(pending_); batch.removed.swap(removed_);
    retained_ids_ += batch.masks.size();
    history_.push_back(std::move(batch)); full_ = false;
    while (history_.size() > 256 || retained_ids_ > 32768) {
        retained_ids_ -= history_.front().masks.size(); history_.pop_front();
    }
}
int64_t RoREntityChangeJournalKernel::revision_for(int64_t id, int64_t mask) const {
    const auto found = versions_.find(id);
    if (found == versions_.end()) return -1;
    int64_t result = -1;
    for (int group = 0; group < 8; ++group)
        if (mask & (int64_t(1) << group)) result = std::max(result, found->second[group]);
    return result;
}
const std::array<int64_t, 8> *RoREntityChangeJournalKernel::version_row(int64_t id) const {
    ++direct_version_reads_;
    const auto found = versions_.find(id);
    return found == versions_.end() ? nullptr : &found->second;
}
Dictionary RoREntityChangeJournalKernel::full_delta(const char *reason) const {
    Dictionary result;
    result["revision"] = revision_; result["full"] = true; result["exact"] = false;
    result["ids"] = Array(); result["masks"] = Dictionary(); result["removed_ids"] = Array(); result["reason"] = String(reason);
    return result;
}
Dictionary RoREntityChangeJournalKernel::collect_since(int64_t before) const {
    Dictionary result;
    result["revision"] = revision_; result["full"] = false; result["exact"] = true;
    result["ids"] = Array(); result["masks"] = Dictionary(); result["removed_ids"] = Array(); result["reason"] = String();
    if (before == revision_) return result;
    if (before < 0 || before > revision_) return full_delta("new_consumer");
    int64_t covered = before;
    Masks masks;
    std::unordered_set<int64_t> removed;
    size_t first = 0, last = history_.size();
    while (first < last) {
        const size_t middle = (first + last) / 2;
        if (history_[middle].to <= before) first = middle + 1; else last = middle;
    }
    for (size_t i = first; i < history_.size(); ++i) {
        const Batch &entry = history_[i];
        if (entry.from != covered) return full_delta("history_overflow");
        if (entry.full) return full_delta("pending_overflow");
        for (const auto &change : entry.masks) masks[change.first] |= change.second;
        removed.insert(entry.removed.begin(), entry.removed.end()); covered = entry.to;
    }
    if (covered != revision_) return full_delta("history_overflow");
    std::vector<int64_t> ids;
    ids.reserve(masks.size());
    for (const auto &entry : masks) ids.push_back(entry.first);
    std::sort(ids.begin(), ids.end());
    Array id_values; id_values.resize(ids.size());
    for (size_t i = 0; i < ids.size(); ++i) id_values[int64_t(i)] = ids[i];
    result["ids"] = id_values; result["masks"] = masks_dictionary(masks); result["removed_ids"] = sorted_ids(removed);
    return result;
}
Dictionary RoREntityChangeJournalKernel::changes_since(int64_t before) {
    flush();
    const auto cached = delta_cache_.find(before);
    if (cached != delta_cache_.end()) { ++delta_hits_; return cached->second.duplicate(true); }
    ++delta_builds_;
    Dictionary result = collect_since(before);
    if (Array(result["ids"]).size() <= 1024) {
        if (delta_cache_.size() >= 8) delta_cache_.clear();
        delta_cache_[before] = result.duplicate(true);
    }
    return result;
}
Dictionary RoREntityChangeJournalKernel::read_changes_since(int64_t before) {
    flush();
    ++shared_reads_;
    const auto cached = read_delta_cache_.find(before);
    if (cached != read_delta_cache_.end()) {
        ++shared_hits_;
        return cached->second.duplicate(false);
    }
    // collect_since materializes detached scalar containers. A read-only
    // request must not also populate the separate mutable-copy cache.
    ++delta_builds_;
    Dictionary result = collect_since(before);
    Array ids = result["ids"], removed = result["removed_ids"];
    Dictionary masks = result["masks"];
    ids.make_read_only(); removed.make_read_only(); masks.make_read_only();
    result.make_read_only();
    if (ids.size() <= 1024) {
        if (read_delta_cache_.size() >= 8) read_delta_cache_.clear();
        read_delta_cache_[before] = result;
    }
    // CacheDependency and other readers may add their own descriptor fields.
    // Only the three immutable collections are shared, not the mutable root.
    return result.duplicate(false);
}
Dictionary RoREntityChangeJournalKernel::export_versions() {
    for (int64_t id : changed_versions_) {
        const auto found = versions_.find(id);
        if (found == versions_.end()) { version_view_.erase(id); continue; }
        PackedInt64Array row; row.resize(8);
        std::copy(found->second.begin(), found->second.end(), row.ptrw());
        version_view_[id] = row; ++exported_rows_;
    }
    changed_versions_.clear();
    return version_view_;
}
Dictionary RoREntityChangeJournalKernel::export_pending() const { return masks_dictionary(pending_); }
Dictionary RoREntityChangeJournalKernel::export_removed() const { return removed_dictionary(removed_); }
Array RoREntityChangeJournalKernel::export_history() const {
    Array result;
    for (const Batch &batch : history_) {
        Dictionary entry;
        entry["from"] = batch.from; entry["to"] = batch.to; entry["full"] = batch.full;
        entry["masks"] = masks_dictionary(batch.masks); entry["removed"] = removed_dictionary(batch.removed);
        result.append(entry);
    }
    return result;
}
Dictionary RoREntityChangeJournalKernel::export_state() {
    Dictionary result;
    result["epoch"] = epoch_; result["revision"] = revision_; result["retained_ids"] = retained_ids_;
    result["versions_by_id"] = export_versions().duplicate(false); result["pending"] = export_pending();
    result["pending_removed"] = export_removed(); result["pending_full"] = full_; result["history"] = export_history();
    return result;
}
Dictionary RoREntityChangeJournalKernel::stats() const {
    Dictionary result;
    result["epoch"] = epoch_; result["revision"] = revision_; result["records"] = int64_t(versions_.size());
    result["pending"] = int64_t(pending_.size()); result["history"] = int64_t(history_.size());
    result["retained_ids"] = retained_ids_; result["marks"] = marks_; result["exported_rows"] = exported_rows_;
    result["delta_hits"] = delta_hits_; result["delta_builds"] = delta_builds_;
    result["direct_version_reads"] = direct_version_reads_;
    result["shared_reads"] = shared_reads_; result["shared_hits"] = shared_hits_;
    result["shared_delta_entries"] = int64_t(read_delta_cache_.size());
    return result;
}
void RoREntityChangeJournalKernel::set_reference_capture(bool enabled) {
    reference_capture_ = enabled; reference_overflow_ = false; reference_events_.clear();
}
Dictionary RoREntityChangeJournalKernel::take_reference_events() {
    PackedInt64Array events; events.resize(reference_events_.size());
    if (!reference_events_.empty()) std::copy(reference_events_.begin(), reference_events_.end(), events.ptrw());
    Dictionary result; result["events"] = events; result["overflow"] = reference_overflow_;
    reference_events_.clear(); reference_overflow_ = false;
    return result;
}
void RoREntityChangeJournalKernel::_bind_methods() {
    ClassDB::bind_method(D_METHOD("reset"), &RoREntityChangeJournalKernel::reset);
    ClassDB::bind_method(D_METHOD("mark", "id", "mask"), &RoREntityChangeJournalKernel::mark);
    ClassDB::bind_method(D_METHOD("remove", "id"), &RoREntityChangeJournalKernel::remove);
    ClassDB::bind_method(D_METHOD("flush"), &RoREntityChangeJournalKernel::flush);
    ClassDB::bind_method(D_METHOD("get_epoch"), &RoREntityChangeJournalKernel::get_epoch);
    ClassDB::bind_method(D_METHOD("get_revision"), &RoREntityChangeJournalKernel::get_revision);
    ClassDB::bind_method(D_METHOD("revision_for", "id", "mask"), &RoREntityChangeJournalKernel::revision_for, DEFVAL(255));
    ClassDB::bind_method(D_METHOD("is_dirty"), &RoREntityChangeJournalKernel::is_dirty);
    ClassDB::bind_method(D_METHOD("is_full"), &RoREntityChangeJournalKernel::is_full);
    ClassDB::bind_method(D_METHOD("retained_ids"), &RoREntityChangeJournalKernel::retained_ids);
    ClassDB::bind_method(D_METHOD("changes_since", "before"), &RoREntityChangeJournalKernel::changes_since);
    ClassDB::bind_method(D_METHOD("read_changes_since", "before"), &RoREntityChangeJournalKernel::read_changes_since);
    ClassDB::bind_method(D_METHOD("export_versions"), &RoREntityChangeJournalKernel::export_versions);
    ClassDB::bind_method(D_METHOD("export_pending"), &RoREntityChangeJournalKernel::export_pending);
    ClassDB::bind_method(D_METHOD("export_removed"), &RoREntityChangeJournalKernel::export_removed);
    ClassDB::bind_method(D_METHOD("export_history"), &RoREntityChangeJournalKernel::export_history);
    ClassDB::bind_method(D_METHOD("export_state"), &RoREntityChangeJournalKernel::export_state);
    ClassDB::bind_method(D_METHOD("stats"), &RoREntityChangeJournalKernel::stats);
    ClassDB::bind_method(D_METHOD("set_reference_capture", "enabled"), &RoREntityChangeJournalKernel::set_reference_capture);
    ClassDB::bind_method(D_METHOD("take_reference_events"), &RoREntityChangeJournalKernel::take_reference_events);
}

} // namespace godot
