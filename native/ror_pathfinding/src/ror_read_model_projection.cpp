#include "ror_read_model_kernel.hpp"

#include <godot_cpp/classes/rendering_server.hpp>
#include <godot_cpp/variant/packed_int64_array.hpp>
#include <limits>
#include <algorithm>
#include <unordered_set>
#include <unordered_map>
#include <vector>
#include <map>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

namespace godot {

namespace {

bool retained_capture_child(const Variant &next, const Variant &previous) {
    // Packed buffers have explicit detachment semantics even where Variant's
    // identity helper may compare a value-equivalent duplicate as equal.
    if (previous.get_type() >= Variant::PACKED_BYTE_ARRAY && previous.get_type() <= Variant::PACKED_VECTOR4_ARRAY) return false;
    return UtilityFunctions::is_same(next, previous);
}

// Validate, detach and freeze in one traversal. A readonly flag or copied marker
// is not a certificate: only exact validated roots or scalar typed maps are shared.
struct Capture {
    const Array &trusted;
    std::vector<bool> shared;
    bool valid = true;
    bool take_ownership = false;

    explicit Capture(const Array &roots, bool owned = false) : trusted(roots), shared(roots.size(), false), take_ownership(owned) {}

    bool trusted_identity(const Variant &value) {
        for (int64_t i = 0; i < trusted.size(); ++i) {
            if (UtilityFunctions::is_same(value, trusted[i])) {
                shared[i] = true;
                return true;
            }
        }
        return false;
    }

    Variant run(const Variant &value, int depth = 0, bool owned_path = true) {
        if (!valid || depth > 64) {
            valid = false;
            return Variant();
        }
        switch (value.get_type()) {
            case Variant::OBJECT:
            case Variant::CALLABLE:
            case Variant::RID:
            case Variant::SIGNAL:
                valid = false;
                return Variant();
            case Variant::DICTIONARY: {
                const Dictionary source = value;
                const auto value_type = source.get_typed_value_builtin();
                const bool scalar_cells = source.get_typed_key_builtin() == Variant::VECTOR2I &&
                        (value_type == Variant::BOOL || value_type == Variant::INT || value_type == Variant::STRING);
                if (source.is_read_only() && (scalar_cells || trusted_identity(value))) {
                    return value;
                }
                // A readonly parent is not itself proof, but once all children
                // have been validated and retained there is nothing to detach.
                // Copy lazily so expired certificates do not clone the complete
                // immutable actor/profile graph again for every AI portion.
                const bool owned = take_ownership && owned_path && !source.is_read_only();
                bool copied = !source.is_read_only() && !owned;
                Dictionary result;
                if (owned) result = source;
                else if (copied) result = source.duplicate(false);
                const Array keys = source.keys();
                for (int64_t i = 0; i < keys.size(); ++i) {
                    // A borrowed readonly parent does not transfer ownership of
                    // a mutable descendant. Clone that branch as usual.
                    Variant key = run(keys[i], depth + 1, owned);
                    Variant item = run(source[keys[i]], depth + 1, owned);
                    if (!valid) {
                        return Variant();
                    }
                    const bool same_key = retained_capture_child(key, keys[i]);
                    const bool same_item = retained_capture_child(item, source[keys[i]]);
                    if (!owned && !copied && (!same_key || !same_item)) {
                        result = source.duplicate(false);
                        copied = true;
                    }
                    // duplicate(false) already copied scalar/unchanged slots.
                    // Write only detached branches, preserving packed isolation.
                    if (!same_key || !same_item) {
                        if (!same_key) result.erase(keys[i]);
                        result[key] = item;
                    }
                }
                if (!copied && !owned) return value;
                result.make_read_only();
                return result;
            }
            case Variant::ARRAY: {
                const Array source = value;
                const bool scalar_points = source.is_typed() &&
                        (source.get_typed_builtin() == Variant::VECTOR2 || source.get_typed_builtin() == Variant::VECTOR2I);
                if (source.is_read_only() && (scalar_points || trusted_identity(value))) {
                    return value;
                }
                const bool owned = take_ownership && owned_path && !source.is_read_only();
                bool copied = !source.is_read_only() && !owned;
                Array result;
                if (owned) result = source;
                else if (copied) result = source.duplicate(false);
                for (int64_t i = 0; i < source.size(); ++i) {
                    Variant item = run(source[i], depth + 1, owned);
                    if (!valid) {
                        return Variant();
                    }
                    if (!owned && !copied && !retained_capture_child(item, source[i])) {
                        result = source.duplicate(false);
                        copied = true;
                    }
                    if (!retained_capture_child(item, source[i])) result[i] = item;
                }
                if (!copied && !owned) return value;
                result.make_read_only();
                return result;
            }
            // Packed arrays share their mutable reference through Variant. They
            // require an explicit duplicate even inside a readonly Dictionary.
            case Variant::PACKED_BYTE_ARRAY: return PackedByteArray(value).duplicate();
            case Variant::PACKED_INT32_ARRAY: return PackedInt32Array(value).duplicate();
            case Variant::PACKED_INT64_ARRAY: return PackedInt64Array(value).duplicate();
            case Variant::PACKED_FLOAT32_ARRAY: return PackedFloat32Array(value).duplicate();
            case Variant::PACKED_FLOAT64_ARRAY: return PackedFloat64Array(value).duplicate();
            case Variant::PACKED_STRING_ARRAY: return PackedStringArray(value).duplicate();
            case Variant::PACKED_VECTOR2_ARRAY: return PackedVector2Array(value).duplicate();
            case Variant::PACKED_VECTOR3_ARRAY: return PackedVector3Array(value).duplicate();
            case Variant::PACKED_VECTOR4_ARRAY: return PackedVector4Array(value).duplicate();
            case Variant::PACKED_COLOR_ARRAY: return PackedColorArray(value).duplicate();
            default: return value; // Remaining types have value semantics.
        }
    }
};

String entity_type(const Dictionary &source) {
    String declared = source.get("entity_type", "");
    if (!declared.is_empty()) {
        return declared;
    }
    if (source.has("production_queue")) {
        return "building";
    }
    if (source.has("resource_type_id") && (source.has("amount") || !source.has("team"))) {
        return "resource";
    }
    return "unit";
}

} // namespace

Dictionary RoRReadModelKernel::patch_render(const Dictionary &source, const Dictionary &previous, int64_t mask, const Dictionary &groups) const {
    Dictionary result = previous;
    bool edited = false;
    const auto put = [&](const Variant &key, const Variant &value) {
        if (previous.has(key) && previous[key] == value) return;
        if (!edited) { result = previous.duplicate(); edited = true; }
        result[key] = value;
    };
    const Array keys = groups.keys();
    for (int64_t i = 0; i < keys.size(); ++i) {
        if (!(mask & int64_t(keys[i]))) continue;
        const Array fields = groups[keys[i]];
        for (int64_t field = 0; field < fields.size(); ++field) {
            const Variant key = fields[field];
            if (source.has(key)) put(key, source[key]);
            else if (result.has(key)) {
                if (!edited) { result = previous.duplicate(); edited = true; }
                result.erase(key);
            }
        }
    }
    static const Variant anim("anim"), previous_pos("previous_pos");
    put(anim, double(source.get(anim, 0.0)));
    if (source.has(previous_pos)) put(previous_pos, source[previous_pos]);
    if (edited) result.make_read_only();
    return result;
}

Dictionary RoRReadModelKernel::project_render(const Dictionary &source, const Dictionary &previous,
        const Array &fields, const Array &nested_fields, int64_t schema) const {
    static const Variant k_entity_type("entity_type");
    static const Variant k__ror_render_schema("_ror_render_schema");
    static const Variant k_components("components");
    static const Variant k_ownership("ownership");
    static const Variant k_civilization_id("civilization_id");
    static const Variant k_enabled("enabled");
    static const Variant k_cargo("cargo");
    static const Variant k_capacity("capacity");
    static const Variant k_trade("trade");
    static const Variant k_target_building_source_id("target_building_source_id");
    Dictionary result;
    for (int64_t i = 0; i < fields.size(); ++i) {
        if (source.has(fields[i])) {
            result[fields[i]] = source[fields[i]];
        }
    }
    result[k_entity_type] = entity_type(source);
    result[k__ror_render_schema] = schema;
    for (int64_t i = 0; i < nested_fields.size(); ++i) {
        if (source.has(nested_fields[i])) {
            result[nested_fields[i]] = source[nested_fields[i]];
        }
    }
    const Dictionary components = source.get(k_components, Dictionary());
    Dictionary projected;
    const Dictionary ownership = components.get(k_ownership, Dictionary());
    if (!ownership.is_empty()) {
        Dictionary row;
        row[k_civilization_id] = int64_t(ownership.get(k_civilization_id, 13));
        projected[k_ownership] = row;
    }
    for (const char *name : {"worker", "conversion", "healing"}) {
        const Dictionary input = components.get(name, Dictionary());
        if (!input.is_empty()) {
            Dictionary row;
            row[k_enabled] = bool(input.get(k_enabled, false));
            projected[name] = row;
        }
    }
    const Dictionary cargo = components.get(k_cargo, Dictionary());
    if (!cargo.is_empty()) {
        Dictionary row;
        row[k_enabled] = bool(cargo.get(k_enabled, false));
        row[k_capacity] = std::max(int64_t(0), int64_t(cargo.get(k_capacity, 0)));
        projected[k_cargo] = row;
    }
    const Dictionary trade = components.get(k_trade, Dictionary());
    if (!trade.is_empty()) {
        Dictionary row;
        row[k_enabled] = bool(trade.get(k_enabled, false));
        row[k_target_building_source_id] = int64_t(trade.get(k_target_building_source_id, -1));
        projected[k_trade] = row;
    }
    result[k_components] = projected;
    if (previous.is_read_only() && previous == result) {
        return previous;
    }
    // Unchanged children remain immutable. Only changed containers are detached.
    const Array keys = result.keys();
    const Array no_trusted_roots;
    Capture capture(no_trusted_roots);
    for (int64_t i = 0; i < keys.size(); ++i) {
        Variant key = keys[i];
        Variant item = result[key];
        if (previous.is_read_only() && previous.has(key) && previous[key] == item) {
            result[key] = previous[key];
        } else if (item.get_type() == Variant::DICTIONARY || item.get_type() == Variant::ARRAY || item.get_type() >= Variant::PACKED_BYTE_ARRAY) {
            result[key] = capture.run(item);
            if (!capture.valid) {
                return Dictionary();
            }
        }
    }
    result.make_read_only();
    return result;
}

Dictionary RoRReadModelKernel::project_ai(const Dictionary &source, const Dictionary &previous,
        int64_t observer_team, const Array &fields, const Array &array_fields, const Array &private_trade_fields) const {
    static const Variant k_team("team");
    static const Variant k_components("components");
    static const Variant k_worker("worker");
    static const Variant k_enabled("enabled");
    static const Variant k_order("order");
    static const Variant k_type("type");
    static const Variant k_target_entity_id("target_entity_id");
    static const Variant k_completed("completed");
    static const Variant k_completion_reason("completion_reason");
    static const Variant k_healing("healing");
    static const Variant k_combat("combat");
    static const Variant k_projectile_id("projectile_id");
    static const Variant k_blast_range("blast_range");
    static const Variant k_cargo("cargo");
    static const Variant k_capacity("capacity");
    static const Variant k_allow_allied("allow_allied");
    static const Variant k_allow_artifacts("allow_artifacts");
    static const Variant k_passenger_ids("passenger_ids");
    static const Variant k_trade("trade");
    static const Variant k_production_queue("production_queue");
    static const Variant k_order_type("order_type");
    static const Variant k_kind("kind");
    static const Variant k_technology_id("technology_id");
    static const Variant k_status("status");
    static const Variant k_population_cost("population_cost");
    static const Variant k_entity_type("entity_type");
    Dictionary result;
    for (int64_t i = 0; i < fields.size(); ++i) {
        if (source.has(fields[i])) result[fields[i]] = source[fields[i]];
    }
    const bool own = observer_team <= 0 || int64_t(source.get(k_team, 0)) == observer_team;
    if (own) {
        for (const char *field : {"resource_id", "path_request_id"}) {
            if (source.has(field)) result[field] = int64_t(source[field]);
        }
    }
    for (int64_t i = 0; i < array_fields.size(); ++i) {
        if (source.has(array_fields[i])) result[array_fields[i]] = source[array_fields[i]];
    }
    const Dictionary components = source.get(k_components, Dictionary());
    Dictionary projected;
    const Dictionary worker = components.get(k_worker, Dictionary());
    Dictionary worker_row;
    worker_row[k_enabled] = bool(worker.get(k_enabled, false));
    projected[k_worker] = worker_row;
    if (own) {
        const Dictionary order = components.get(k_order, Dictionary());
        if (!order.is_empty()) {
            Dictionary row;
            row[k_type] = String(order.get(k_type, "none"));
            row[k_target_entity_id] = int64_t(order.get(k_target_entity_id, -1));
            row[k_completed] = bool(order.get(k_completed, true));
            row[k_completion_reason] = String(order.get(k_completion_reason, ""));
            projected[k_order] = row;
        }
    }
    const Dictionary healing = components.get(k_healing, Dictionary());
    if (bool(healing.get(k_enabled, false))) {
        Dictionary row;
        row[k_enabled] = true;
        projected[k_healing] = row;
    }
    const Dictionary combat = components.get(k_combat, Dictionary());
    if (!combat.is_empty()) {
        Dictionary row;
        row[k_projectile_id] = int64_t(source.get(k_projectile_id, combat.get(k_projectile_id, -1)));
        row[k_blast_range] = double(source.get(k_blast_range, combat.get(k_blast_range, 0.0)));
        projected[k_combat] = row;
    }
    const Dictionary cargo = components.get(k_cargo, Dictionary());
    if (bool(cargo.get(k_enabled, false))) {
        Dictionary row;
        row[k_enabled] = true;
        row[k_capacity] = std::max(int64_t(0), int64_t(cargo.get(k_capacity, 0)));
        row[k_allow_allied] = bool(cargo.get(k_allow_allied, true));
        row[k_allow_artifacts] = bool(cargo.get(k_allow_artifacts, true));
        if (own) row[k_passenger_ids] = cargo.get(k_passenger_ids, Array());
        projected[k_cargo] = row;
    }
    const Dictionary trade = components.get(k_trade, Dictionary());
    if (bool(trade.get(k_enabled, false))) {
        Dictionary row;
        row[k_enabled] = true;
        if (own) {
            for (int64_t i = 0; i < private_trade_fields.size(); ++i) {
                if (trade.has(private_trade_fields[i])) row[private_trade_fields[i]] = trade[private_trade_fields[i]];
            }
        }
        projected[k_trade] = row;
    }
    result[k_components] = projected;
    if (own && source.has(k_production_queue)) {
        const Array source_queue = source[k_production_queue];
        Array queue;
        for (int64_t i = 0; i < source_queue.size(); ++i) {
            const Dictionary order = source_queue[i];
            Dictionary row;
            row[k_order_type] = String(order.get(k_order_type, "unit"));
            row[k_kind] = String(order.get(k_kind, ""));
            row[k_technology_id] = int64_t(order.get(k_technology_id, -1));
            row[k_status] = String(order.get(k_status, "queued"));
            row[k_population_cost] = int64_t(order.get(k_population_cost, 0));
            queue.push_back(row);
        }
        result[k_production_queue] = queue;
    }
    result[k_entity_type] = entity_type(source);
    if (previous.is_read_only() && previous == result) return previous;
    // Unchanged children remain immutable. Only changed containers are detached.
    const Array keys = result.keys();
    const Array no_trusted_roots;
    Capture capture(no_trusted_roots);
    for (int64_t i = 0; i < keys.size(); ++i) {
        Variant key = keys[i];
        Variant item = result[key];
        if (previous.is_read_only() && previous.has(key) && previous[key] == item) {
            result[key] = previous[key];
        } else if (item.get_type() == Variant::DICTIONARY || item.get_type() == Variant::ARRAY || item.get_type() >= Variant::PACKED_BYTE_ARRAY) {
            result[key] = capture.run(item);
            if (!capture.valid) {
                return Dictionary();
            }
        }
    }
    result.make_read_only();
    return result;
}

namespace {
// Exact legacy JSON shape. Ambiguous stringified keys fall back to the reference.
Variant encode_replay_value(const Variant &source, bool quantize, bool &valid, int depth) {
    if (depth > 64) { valid = false; return Variant(); }
    if (source.get_type() == Variant::VECTOR2) {
        const Vector2 point = source;
        Array values;
        values.push_back(quantize ? UtilityFunctions::snappedf(point.x, 0.000001) : double(point.x));
        values.push_back(quantize ? UtilityFunctions::snappedf(point.y, 0.000001) : double(point.y));
        Dictionary result; result["__vector2"] = values; return result;
    }
    if (source.get_type() == Variant::VECTOR2I) {
        const Vector2i point = source;
        Array values; values.push_back(int64_t(point.x)); values.push_back(int64_t(point.y));
        Dictionary result; result["__vector2i"] = values; return result;
    }
    if (source.get_type() == Variant::DICTIONARY) {
        const Dictionary input = source;
        const Array keys = input.keys();
        std::vector<std::pair<String, Variant>> sorted;
        sorted.reserve(static_cast<size_t>(keys.size()));
        for (int64_t i = 0; i < keys.size(); ++i) sorted.emplace_back(UtilityFunctions::str(keys[i]), keys[i]);
        std::sort(sorted.begin(), sorted.end(), [](const std::pair<String, Variant> &a, const std::pair<String, Variant> &b) { return a.first < b.first; });
        Dictionary result;
        for (const auto &item : sorted) {
            if (result.has(item.first)) { valid = false; return Variant(); }
            result[item.first] = encode_replay_value(input[item.second], quantize, valid, depth + 1);
            if (!valid) return Variant();
        }
        return result;
    }
    if (source.get_type() == Variant::ARRAY) {
        const Array input = source;
        Array result; result.resize(input.size());
        for (int64_t i = 0; i < input.size(); ++i) {
            result[i] = encode_replay_value(input[i], quantize, valid, depth + 1);
            if (!valid) return Variant();
        }
        return result;
    }
    if (source.get_type() == Variant::FLOAT && quantize) return UtilityFunctions::snappedf(double(source), 0.000001);
    return source;
}
}

Dictionary RoRReadModelKernel::encode_replay_variant(const Variant &source, bool quantize_numbers) const {
    bool valid = true;
    const Variant value = encode_replay_value(source, quantize_numbers, valid, 0);
    Dictionary result; result["valid"] = valid; result["value"] = value; return result;
}

Dictionary RoRReadModelKernel::capture_frozen(const Variant &source, const Array &trusted) const {
    Capture capture(trusted);
    const Variant value = capture.run(source);
    PackedInt32Array shared_indices;
    for (int64_t i = 0; i < trusted.size(); ++i) {
        if (capture.shared[i]) {
            shared_indices.push_back(int32_t(i));
        }
    }
    Dictionary result;
    result["valid"] = capture.valid;
    result["value"] = capture.valid ? value : Variant();
    result["shared_indices"] = shared_indices;
    return result;
}

Dictionary RoRReadModelKernel::capture_owned_frozen(const Variant &source, const Array &trusted) const {
    // Internal producer handoff. The caller relinquishes every mutable
    // container reachable through mutable parents, even if validation fails.
    Capture capture(trusted, true);
    const Variant value = capture.run(source);
    PackedInt32Array shared_indices;
    for (int64_t i = 0; i < trusted.size(); ++i)
        if (capture.shared[i]) shared_indices.push_back(int32_t(i));
    Dictionary result;
    result["valid"] = capture.valid;
    result["value"] = capture.valid ? value : Variant();
    result["shared_indices"] = shared_indices;
    return result;
}

} // namespace godot
