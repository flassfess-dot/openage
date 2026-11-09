#pragma once

#include "ror_entity_change_journal.hpp"
#include <algorithm>

namespace godot {

// A synchronous owner-only borrow; no row pointer survives the caller's query.
// Legacy dictionaries remain supported without changing saved projection caches.
struct RoRJournalVersionReader {
    RoREntityChangeJournalKernel *native = nullptr;
    Dictionary legacy;
    bool supported = false;
    explicit RoRJournalVersionReader(const Variant &source) {
        if (source.get_type() == Variant::DICTIONARY) { legacy = source; supported = true; }
        else if (source.get_type() == Variant::OBJECT) {
            native = Object::cast_to<RoREntityChangeJournalKernel>(static_cast<Object *>(source));
            supported = native != nullptr;
        }
    }
    struct Row {
        const int64_t *values = nullptr;
        int64_t size = 0;
        PackedInt64Array storage;
        bool valid = false;
    };
    Row read(int64_t id) const {
        Row result;
        if (!supported) return result;
        result.valid = true;
        if (native) {
            const auto *row = native->version_row(id);
            if (row) { result.values = row->data(); result.size = 8; }
        } else {
            const Variant value = legacy.get(id, PackedInt64Array());
            if (value.get_type() != Variant::PACKED_INT64_ARRAY) { result.valid = false; return result; }
            result.storage = value; result.values = result.storage.ptr(); result.size = result.storage.size();
        }
        return result;
    }
    bool maximum(int64_t id, int64_t &revision) const {
        const Row row = read(id);
        if (!row.valid) return false;
        revision = -1;
        for (int64_t group = 0; group < std::min(int64_t(8), row.size); ++group)
            revision = std::max(revision, row.values[group]);
        return true;
    }
    PackedInt64Array retain(const Row &row) const {
        if (!native) return row.storage;
        PackedInt64Array result;
        result.resize(row.size);
        if (row.size) std::copy(row.values, row.values + row.size, result.ptrw());
        return result;
    }
};

} // namespace godot
