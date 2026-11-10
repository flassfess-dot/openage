#include "ror_actor_keys.hpp"
#include "ror_read_model_kernel.hpp"
#include "ror_journal_version_reader.hpp"

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
    bool track_identity = true;

    explicit Capture(const Array &roots, bool owned = false, bool identity = true) : trusted(roots), shared(roots.size(), false), take_ownership(owned), track_identity(identity) {}

    bool trusted_identity(const Variant &value) {
        for (int64_t i = 0; i < trusted.size(); ++i) {
            if (UtilityFunctions::is_same(value, trusted[i])) {
                shared[i] = true;
                return true;
            }
        }
        return false;
    }

    Variant run(const Variant &value, int depth = 0, bool owned_path = true, bool *identity_preserved = nullptr) {
        if (identity_preserved) *identity_preserved = false;
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
                    if (identity_preserved) *identity_preserved = true;
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
                    bool same_key = false, same_item = false;
                    Variant key = run(keys[i], depth + 1, owned, track_identity ? &same_key : nullptr);
                    Variant item = run(source[keys[i]], depth + 1, owned, track_identity ? &same_item : nullptr);
                    if (!valid) {
                        return Variant();
                    }
                    if (!track_identity) {
                        same_key = retained_capture_child(key, keys[i]);
                        same_item = retained_capture_child(item, source[keys[i]]);
                    }
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
                if (identity_preserved) *identity_preserved = !copied;
                if (!copied && !owned) return value;
                result.make_read_only();
                return result;
            }
            case Variant::ARRAY: {
                const Array source = value;
                const bool scalar_points = source.is_typed() &&
                        (source.get_typed_builtin() == Variant::VECTOR2 || source.get_typed_builtin() == Variant::VECTOR2I);
                if (source.is_read_only() && (scalar_points || trusted_identity(value))) {
                    if (identity_preserved) *identity_preserved = true;
                    return value;
                }
                const bool owned = take_ownership && owned_path && !source.is_read_only();
                bool copied = !source.is_read_only() && !owned;
                Array result;
                if (owned) result = source;
                else if (copied) result = source.duplicate(false);
                for (int64_t i = 0; i < source.size(); ++i) {
                    bool same_item = false;
                    Variant item = run(source[i], depth + 1, owned, track_identity ? &same_item : nullptr);
                    if (!valid) {
                        return Variant();
                    }
                    if (!track_identity) same_item = retained_capture_child(item, source[i]);
                    if (!owned && !copied && !same_item) {
                        result = source.duplicate(false);
                        copied = true;
                    }
                    if (!same_item) result[i] = item;
                }
                if (identity_preserved) *identity_preserved = !copied;
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
            default:
                // Value types are returned without conversion. Containers keep
                // identity precisely when this pass did not clone them; packed
                // buffers above always detach. No engine equality query needed.
                if (identity_preserved) *identity_preserved = true;
                return value;
        }
    }
};

String entity_type(const Dictionary &source) {
    String declared = source.get(ROR_FIELD("entity_type"), ROR_FIELD(""));
    if (!declared.is_empty()) {
        return declared;
    }
    if (source.has(ROR_FIELD("production_queue"))) {
        return "building";
    }
    if (source.has(ROR_FIELD("resource_type_id")) && (source.has(ROR_FIELD("amount")) || !source.has(ROR_FIELD("team")))) {
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
            row[k_type] = String(order.get(k_type, ROR_FIELD("none")));
            row[k_target_entity_id] = int64_t(order.get(k_target_entity_id, -1));
            row[k_completed] = bool(order.get(k_completed, true));
            row[k_completion_reason] = String(order.get(k_completion_reason, ROR_FIELD("")));
            if (order.has(ROR_FIELD("revision"))) row[ROR_FIELD("revision")] = int64_t(order[ROR_FIELD("revision")]);
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
            row[k_order_type] = String(order.get(k_order_type, ROR_FIELD("unit")));
            row[k_kind] = String(order.get(k_kind, ROR_FIELD("")));
            row[k_technology_id] = int64_t(order.get(k_technology_id, -1));
            row[k_status] = String(order.get(k_status, ROR_FIELD("queued")));
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
        Dictionary result; result[ROR_FIELD("__vector2")] = values; return result;
    }
    if (source.get_type() == Variant::VECTOR2I) {
        const Vector2i point = source;
        Array values; values.push_back(int64_t(point.x)); values.push_back(int64_t(point.y));
        Dictionary result; result[ROR_FIELD("__vector2i")] = values; return result;
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
    Dictionary result; result[ROR_FIELD("valid")] = valid; result[ROR_FIELD("value")] = value; return result;
}

Dictionary RoRReadModelKernel::capture_frozen(const Variant &source, const Array &trusted, bool track_identity) const {
    Capture capture(trusted, false, track_identity);
    const Variant value = capture.run(source);
    PackedInt32Array shared_indices;
    for (int64_t i = 0; i < trusted.size(); ++i) {
        if (capture.shared[i]) {
            shared_indices.push_back(int32_t(i));
        }
    }
    Dictionary result;
    result[ROR_FIELD("valid")] = capture.valid;
    result[ROR_FIELD("value")] = capture.valid ? value : Variant();
    result[ROR_FIELD("shared_indices")] = shared_indices;
    return result;
}

Dictionary RoRReadModelKernel::project_ui_control(const Dictionary &source, const Dictionary &rendered,
        int64_t observer, const Array &fields, const Dictionary &component_fields, const Array &private_trade_fields,
        Dictionary entry, Dictionary counters) const {
    if (entry.is_read_only() || counters.is_read_only() || fields.size() > 64 || component_fields.size() > 16) return Dictionary();
    static const Dictionary empty = []() { Dictionary row; row.make_read_only(); return row; }();
    static const Array no_roots;
    static const Variant record_key("ui_record"), components_key("components"), team_key("team");
    static const Variant schema_key("ui_components_schema"), fields_key("ui_fields_schema"), private_key("ui_private_schema"), own_key("ui_own");
    const bool own = observer <= 0 || int64_t(source.get(team_key, 0)) == observer;
    const bool same_schema = entry.has(schema_key) && Dictionary(entry[schema_key]) == component_fields &&
        entry.has(fields_key) && Array(entry[fields_key]) == fields &&
        entry.has(private_key) && Array(entry[private_key]) == private_trade_fields;
    const Dictionary previous = same_schema && entry.has(own_key) && bool(entry[own_key]) == own ? Dictionary(entry.get(record_key, empty)) : empty;
    Dictionary result = previous;
    bool edited = false;
    Capture capture(no_roots);
    int64_t changed_fields = 0;
    const auto put = [&](Dictionary &row, bool &writable, const Variant &key, const Variant &value, bool present) {
        if (!present) {
            if (!row.has(key)) return;
            if (!writable) { row = row.duplicate(false); writable = true; }
            row.erase(key); ++changed_fields; return;
        }
        if (row.has(key) && row[key] == value) return;
        const Variant frozen = capture.run(value);
        if (!capture.valid) return;
        if (!writable) { row = row.duplicate(false); writable = true; }
        row[key] = frozen; ++changed_fields;
    };
    for (const char *name : {"id", "team", "kind", "entity_type", "behavior_tags", "movement_domain", "task"}) {
        const Variant key(name);
        put(result, edited, key, rendered.get(key, Variant()), rendered.has(key));
    }
    static const Array private_root = []() {
        Array values;
        for (const char *name : {"production_progress", "rally_point", "rally_point_set", "resource_id", "dropoff_id", "worker_role_source_unit_id", "diagnostic_reason"}) values.append(String(name));
        return values;
    }();
    for (int64_t index = 0; index < fields.size(); ++index) {
        const Variant key = fields[index];
        const bool visible = own || !private_root.has(key);
        put(result, edited, key, source.get(key, Variant()), visible && source.has(key));
    }
    const Dictionary originals = source.get(components_key, empty);
    Dictionary components = previous.get(components_key, empty);
    bool components_edited = false;
    const Array names = component_fields.keys();
    for (int64_t index = 0; index < names.size(); ++index) {
        const Variant name = names[index];
        const Variant requested = component_fields[name];
        if (requested.get_type() != Variant::ARRAY || Array(requested).size() > 64) return Dictionary();
        const Dictionary original = originals.get(name, empty);
        Dictionary component = components.get(name, empty);
        bool component_edited = false;
        const Array keys = requested;
        for (int64_t field = 0; field < keys.size(); ++field) {
            const Variant key = keys[field];
            const bool hidden = !own && ((String(name) == ROR_TEXT("cargo") && String(key) == ROR_TEXT("passenger_ids")) ||
                (String(name) == ROR_TEXT("trade") && private_trade_fields.has(key)));
            Variant value = original.get(key, Variant());
            bool present = original.has(key) && !hidden;
            if (String(name) == ROR_TEXT("resource_carrier")) {
                const Variant runtime_key = String(key) == ROR_TEXT("amount") ? Variant("carried_amount") :
                    String(key) == ROR_TEXT("resource_type_id") ? Variant("carried_resource_type_id") : Variant();
                if (runtime_key.get_type() != Variant::NIL && source.has(runtime_key)) {
                    value = source[runtime_key]; present = !hidden;
                }
            }
            put(component, component_edited, key, value, present);
        }
        if (!capture.valid) return Dictionary();
        if (component_edited) component.make_read_only();
        // Every child has just been captured or comes from this factory's
        // previous record. Do not recursively capture that owned graph again.
        if (component.is_empty()) {
            if (components.has(name)) {
                if (!components_edited) { components = components.duplicate(false); components_edited = true; }
                components.erase(name);
            }
        } else if (!components.has(name) || components[name] != Variant(component)) {
            if (!components_edited) { components = components.duplicate(false); components_edited = true; }
            components[name] = component;
        }
    }
    if (!capture.valid) return Dictionary();
    if (components_edited) components.make_read_only();
    if (!result.has(components_key) || result[components_key] != Variant(components)) {
        if (!edited) { result = result.duplicate(false); edited = true; }
        result[components_key] = components;
    }
    if (!capture.valid) return Dictionary();
    if (edited) result.make_read_only();
    if (result.is_empty() || !result.is_read_only()) return Dictionary();
    if (!same_schema) {
        const Variant schema = capture.run(component_fields), root_fields = capture.run(fields), hidden_fields = capture.run(private_trade_fields);
        if (!capture.valid) return Dictionary();
        entry[schema_key] = schema; entry[fields_key] = root_fields; entry[private_key] = hidden_fields;
    }
    entry[own_key] = own;
    entry[record_key] = result;
    counters[ROR_FIELD("ui_calls")] = int64_t(counters.get(ROR_FIELD("ui_calls"), 0)) + 1;
    counters[ROR_FIELD("ui_records_shared")] = int64_t(counters.get(ROR_FIELD("ui_records_shared"), 0)) + int64_t(!edited);
    counters[ROR_FIELD("ui_changed_fields")] = int64_t(counters.get(ROR_FIELD("ui_changed_fields"), 0)) + changed_fields;
    return result;
}

Dictionary RoRReadModelKernel::project_retained_control(const Dictionary &source, const Dictionary &rendered,
        int64_t observer, const Array &fields, const Array &private_trade_fields, Dictionary entry, Dictionary counters, bool metadata_only) const {
    static const Dictionary empty_dictionary;
    static const Variant ck_acquisition_range("acquisition_range");
    static const Variant ck_amount("amount");
    static const Variant ck_behavior_tags("behavior_tags");
    static const Variant ck_cargo("cargo");
    static const Variant ck_carried_amount("carried_amount");
    static const Variant ck_carried_resource_type_id("carried_resource_type_id");
    static const Variant ck_chase_range("chase_range");
    static const Variant ck_combat("combat");
    static const Variant ck_component_base("component_base");
    static const Variant ck_components("components");
    static const Variant ck_conversion("conversion");
    static const Variant ck_cooldown("cooldown");
    static const Variant ck_diagnostic_reason("diagnostic_reason");
    static const Variant ck_dropoff_id("dropoff_id");
    static const Variant ck_entity_type("entity_type");
    static const Variant ck_has_amount("has_amount");
    static const Variant ck_has_carried("has_carried");
    static const Variant ck_has_type("has_type");
    static const Variant ck_healing("healing");
    static const Variant ck_id("id");
    static const Variant ck_input("input");
    static const Variant ck_kind("kind");
    static const Variant ck_metadata_only("metadata_only");
    static const Variant ck_movement_domain("movement_domain");
    static const Variant ck_own("own");
    static const Variant ck_parts("parts");
    static const Variant ck_passenger_ids("passenger_ids");
    static const Variant ck_production_progress("production_progress");
    static const Variant ck_production_queue("production_queue");
    static const Variant ck_projected_components("projected_components");
    static const Variant ck_queue("queue");
    static const Variant ck_rally_point("rally_point");
    static const Variant ck_rally_point_set("rally_point_set");
    static const Variant ck_record("record");
    static const Variant ck_rendered("rendered");
    static const Variant ck_resource_carrier("resource_carrier");
    static const Variant ck_resource_id("resource_id");
    static const Variant ck_resource_type_id("resource_type_id");
    static const Variant ck_retaliation_target_id("retaliation_target_id");
    static const Variant ck_stance("stance");
    static const Variant ck_target_id("target_id");
    static const Variant ck_task("task");
    static const Variant ck_team("team");
    static const Variant ck_trade("trade");
    static const Variant ck_value("value");
    static const Variant ck_worker_role_source_unit_id("worker_role_source_unit_id");
    if (!rendered.is_read_only() || entry.is_read_only()) return Dictionary();
    const bool own = observer <= 0 || int64_t(source.get(ck_team, 0)) == observer;
    static const Variant ck_fields("fields"), ck_private_trade_fields("private_trade_fields");
    const bool same_schema = entry.has(ck_fields) && Array(entry[ck_fields]) == fields &&
        entry.has(ck_private_trade_fields) && Array(entry[ck_private_trade_fields]) == private_trade_fields;
    const bool same_policy = same_schema && entry.has(ck_own) && bool(entry[ck_own]) == own;
    const Dictionary originals = source.get(ck_components, empty_dictionary);
    const Variant part_values = entry.get(ck_parts, Variant());
    Dictionary parts = part_values.get_type() == Variant::DICTIONARY ? Dictionary(part_values) : Dictionary();
    static const Array no_roots;
    Capture capture(no_roots);
    const Dictionary base_components = rendered.get(ck_components, empty_dictionary);
    const bool same_base = entry.has(ck_component_base) && entry.has(ck_projected_components) && Dictionary(entry[ck_component_base]) == base_components;
    Dictionary components = same_base ? Dictionary(entry[ck_projected_components]) : base_components.duplicate(false);
    bool components_editable = !same_base;
    int64_t increments[6] = {};
    for (const Variant &name : {ck_combat, ck_conversion, ck_healing, ck_resource_carrier, ck_cargo, ck_trade}) {
        const Dictionary original = originals.get(name, empty_dictionary);
        const Variant retained_value = parts.get(name, Variant());
        Dictionary retained = retained_value.get_type() == Variant::DICTIONARY ? Dictionary(retained_value) : Dictionary();
        const bool same_input = retained.has(ck_input) && Dictionary(retained[ck_input]) == original;
        Dictionary input = same_input ? Dictionary(retained[ck_input]) : Dictionary(capture.run(original));
        if (!capture.valid) return Dictionary();
        ++increments[same_input ? 0 : 1];
        Dictionary component = same_input && same_policy ? Dictionary(retained.get(ck_value, input)) : input;
        bool edited = false;
        auto put = [&](const Variant &key, const Variant &next) {
            if (component.has(key) && component[key] == next) return;
            if (!edited) { component = component.duplicate(false); edited = true; }
            component[key] = next;
        };
        auto erase = [&](const Variant &key) {
            if (!component.has(key)) return;
            if (!edited) { component = component.duplicate(false); edited = true; }
            component.erase(key);
        };
        if (name == ck_combat) {
            put(ck_target_id, int64_t(source.get(ck_target_id, input.get(ck_target_id, -1))));
            put(ck_cooldown, double(source.get(ck_cooldown, input.get(ck_cooldown, 0.0))));
            put(ck_stance, String(source.get(ck_stance, input.get(ck_stance, ROR_FIELD("passive")))));
            put(ck_acquisition_range, double(source.get(ck_acquisition_range, input.get(ck_acquisition_range, 0.0))));
            put(ck_chase_range, double(source.get(ck_chase_range, input.get(ck_chase_range, 0.0))));
            put(ck_retaliation_target_id, int64_t(source.get(ck_retaliation_target_id, input.get(ck_retaliation_target_id, -1))));
        } else if (name == ck_resource_carrier) {
            // Rebase when an optional compatibility field disappears.
            if (same_input && same_policy && (bool(retained.get(ck_has_amount, false)) != source.has(ck_amount) ||
                    bool(retained.get(ck_has_carried, false)) != source.has(ck_carried_amount) ||
                    bool(retained.get(ck_has_type, false)) != source.has(ck_carried_resource_type_id))) component = input;
            if (source.has(ck_amount)) put(ck_amount, double(source[ck_amount]));
            if (source.has(ck_carried_amount)) put(ck_amount, double(source[ck_carried_amount]));
            if (source.has(ck_carried_resource_type_id)) put(ck_resource_type_id, int64_t(source[ck_carried_resource_type_id]));
            retained[ck_has_amount] = source.has(ck_amount);
            retained[ck_has_carried] = source.has(ck_carried_amount);
            retained[ck_has_type] = source.has(ck_carried_resource_type_id);
        } else if (!own && name == ck_cargo) erase(ck_passenger_ids);
        else if (!own && name == ck_trade) for (int64_t i = 0; i < private_trade_fields.size(); ++i) erase(private_trade_fields[i]);
        if (edited) { component.make_read_only(); ++increments[2]; }
        const Variant desired = component.is_empty() ? base_components.get(name, Variant()) : Variant(component);
        const Variant current = components.get(name, Variant());
        if (desired != current) {
            if (!components_editable) { components = components.duplicate(false); components_editable = true; }
            if (desired.get_type() == Variant::NIL) components.erase(name);
            else components[name] = desired;
        }
        retained[ck_input] = input; retained[ck_value] = component;
        parts[name] = retained;
    }
    components.make_read_only();
    const Dictionary previous = entry.get(ck_record, empty_dictionary);
    const bool same_layout = bool(entry.get(ck_metadata_only, !metadata_only)) == metadata_only;
    const bool reuse_record = same_policy && same_layout && !previous.is_empty() &&
        (metadata_only || (entry.has(ck_rendered) && Dictionary(entry[ck_rendered]) == rendered));
    Dictionary result = reuse_record ? previous : metadata_only ? Dictionary() : rendered.duplicate(false);
    bool record_editable = !reuse_record;
    const auto put_record = [&](const Variant &key, const Variant &value) {
        if (result.has(key) && result[key] == value) return;
        if (!record_editable) { result = result.duplicate(false); record_editable = true; }
        result[key] = value;
    };
    const auto erase_record = [&](const Variant &key) {
        if (!result.has(key)) return;
        if (!record_editable) { result = result.duplicate(false); record_editable = true; }
        result.erase(key);
    };
    if (metadata_only) {
        for (const Variant &key : {ck_id, ck_team, ck_kind, ck_entity_type, ck_behavior_tags, ck_movement_domain, ck_task}) {
            if (rendered.has(key)) put_record(key, rendered[key]);
            else erase_record(key);
        }
    }
    for (int64_t i = 0; i < fields.size(); ++i) {
        const Variant key = fields[i];
        if (source.has(key)) {
            const Variant value = capture.run(source[key]);
            if (!capture.valid) return Dictionary();
            put_record(key, value);
        } else if (!metadata_only && rendered.has(key)) put_record(key, rendered[key]);
        else erase_record(key);
    }
    if (own && source.has(ck_production_queue)) {
        const Array queue = source[ck_production_queue];
        const Variant old_queue = entry.get(ck_queue, Variant());
        Array published = old_queue.get_type() == Variant::ARRAY ? Array(old_queue) : Array();
        if (old_queue.get_type() != Variant::ARRAY || published != queue) {
            published = capture.run(queue);
            if (!capture.valid) return Dictionary();
            entry[ck_queue] = published;
            ++increments[3];
        }
        put_record(ck_production_queue, published);
    } else if (!metadata_only && rendered.has(ck_production_queue)) put_record(ck_production_queue, rendered[ck_production_queue]);
    else erase_record(ck_production_queue);
    if (!own) for (const Variant &key : {ck_production_progress, ck_rally_point, ck_rally_point_set, ck_resource_id, ck_dropoff_id, ck_worker_role_source_unit_id, ck_diagnostic_reason}) erase_record(key);
    put_record(ck_components, components);
    entry[ck_component_base] = base_components;
    entry[ck_projected_components] = components;
    entry[ck_metadata_only] = metadata_only;
    entry[ck_rendered] = rendered;
    if (!previous.is_empty() && previous == result) { result = previous; ++increments[4]; }
    else { result.make_read_only(); ++increments[5]; }
    if (!same_schema) {
        const Variant frozen_fields = capture.run(fields), frozen_private = capture.run(private_trade_fields);
        if (!capture.valid) return Dictionary();
        entry[ck_fields] = frozen_fields; entry[ck_private_trade_fields] = frozen_private;
    }
    entry[ck_parts] = parts; entry[ck_own] = own; entry[ck_record] = result;
    // Keep an exact factory output as proof for the later UI enrichment pass.
    // Unit metadata has its own aggregate certificate and needs no entry here.
    if (!metadata_only && source.has(ck_production_queue)) {
        const int64_t id = source.get(ck_id, -1);
        if (id >= 0 && (control_row_certificates.size() < 8192 || control_row_certificates.count(id)))
            control_row_certificates[id] = result;
    }
    static const Variant counter_keys[] = {Variant("component_hits"), Variant("component_captures"), Variant("component_patches"),
        Variant("queue_captures"), Variant("record_hits"), Variant("record_patches")};
    for (int i = 0; i < 6; ++i) if (increments[i]) counters[counter_keys[i]] = int64_t(counters.get(counter_keys[i], 0)) + increments[i];
    return result;
}

Array RoRReadModelKernel::capture_building_control_rows(const Array &rows, Dictionary counters) const {
    if (rows.size() > 8192 || counters.is_read_only()) return Array();
    static const Variant id_key("id");
    static const Array no_roots;
    Capture capture(no_roots);
    Array result;
    result.resize(rows.size());
    std::unordered_map<int64_t, Dictionary> next_rows;
    next_rows.reserve(rows.size());
    int64_t shared_children = 0, checked_children = 0, reused = 0;
    for (int64_t index = 0; index < rows.size(); ++index) {
        const Variant value = rows[index];
        if (value.get_type() != Variant::DICTIONARY) return Array();
        const Dictionary source = value;
        const int64_t id = source.get(id_key, -1);
        // Menus are still priced against the current stocks and queues. If
        // enrichment produced the same record, reuse the already isolated
        // output. No live or caller-owned container enters this cache.
        auto previous = published_building_rows.find(id);
        if (previous != published_building_rows.end() && previous->second == source) {
            result[index] = previous->second;
            next_rows.emplace(id, previous->second);
            ++reused;
            continue;
        }
        const auto certificate = control_row_certificates.find(id);
        const Dictionary base = certificate != control_row_certificates.end() ? certificate->second : Dictionary();
        // The caller transfers its detached enriched rows. A readonly row is
        // borrowed; clone it lazily if a mutable descendant needs detaching.
        const bool owned = !source.is_read_only();
        Dictionary completed = source;
        bool editable = owned;
        const Array keys = source.keys();
        for (int64_t key_index = 0; key_index < keys.size(); ++key_index) {
            const Variant key = keys[key_index], original = source[key];
            const Variant frozen_key = capture.run(key);
            Variant frozen;
            const auto type = original.get_type();
            const bool container = type == Variant::DICTIONARY || type == Variant::ARRAY;
            if (container && base.has(key) && UtilityFunctions::is_same(original, base[key])) {
                // Exact child of a private, recursively detached factory output.
                // A readonly marker supplied by a caller is never sufficient.
                frozen = original;
                ++shared_children;
            } else {
                frozen = capture.run(original);
                ++checked_children;
            }
            if (!capture.valid) return Array();
            if (!retained_capture_child(frozen_key, key) || !retained_capture_child(frozen, original)) {
                if (!editable) { completed = source.duplicate(false); editable = true; }
                if (!retained_capture_child(frozen_key, key)) completed.erase(key);
                completed[frozen_key] = frozen;
            }
        }
        completed.make_read_only();
        result[index] = completed;
        next_rows.emplace(id, completed);
    }
    result.make_read_only();
    for (auto it = control_row_certificates.begin(); it != control_row_certificates.end();) {
        if (!next_rows.count(it->first)) it = control_row_certificates.erase(it);
        else ++it;
    }
    published_building_rows.swap(next_rows);
    counters[ROR_FIELD("building_row_calls")] = int64_t(counters.get(ROR_FIELD("building_row_calls"), 0)) + 1;
    counters[ROR_FIELD("building_rows")] = int64_t(counters.get(ROR_FIELD("building_rows"), 0)) + rows.size();
    counters[ROR_FIELD("building_rows_reused")] = int64_t(counters.get(ROR_FIELD("building_rows_reused"), 0)) + reused;
    counters[ROR_FIELD("building_shared_children")] = int64_t(counters.get(ROR_FIELD("building_shared_children"), 0)) + shared_children;
    counters[ROR_FIELD("building_checked_children")] = int64_t(counters.get(ROR_FIELD("building_checked_children"), 0)) + checked_children;
    return result;
}

Dictionary RoRReadModelKernel::capture_owned_frozen(const Variant &source, const Array &trusted, bool track_identity) const {
    // Internal producer handoff. The caller relinquishes every mutable
    // container reachable through mutable parents, even if validation fails.
    Capture capture(trusted, true, track_identity);
    const Variant value = capture.run(source);
    PackedInt32Array shared_indices;
    for (int64_t i = 0; i < trusted.size(); ++i)
        if (capture.shared[i]) shared_indices.push_back(int32_t(i));
    Dictionary result;
    result[ROR_FIELD("valid")] = capture.valid;
    result[ROR_FIELD("value")] = capture.valid ? value : Variant();
    result[ROR_FIELD("shared_indices")] = shared_indices;
    return result;
}

namespace {

// The journal and legal source arrays belong to the pinned owner generation.
// These helpers neither query the live world nor borrow it into a worker.
bool ai_projection_revision(const RoRJournalVersionReader &versions, int64_t id, int64_t &result) {
    return versions.maximum(id, result);
}

bool ai_projection_memory(const Dictionary &source, const Dictionary &schema) {
    return source.is_read_only() && int64_t(source.get(schema[ROR_FIELD("render_key")], -1)) == int64_t(schema[ROR_FIELD("render_version")]);
}

bool ai_projection_cache_supported(const Dictionary &cache, const Dictionary &schema) {
    if (cache.is_read_only()) return false;
    for (const char *key : {"fields", "visible_fields", "array_fields", "private_trade_fields", "categories"}) {
        if (schema.get(key, Variant()).get_type() != Variant::ARRAY) return false;
    }
    if (!schema.has(ROR_FIELD("render_key")) || !schema.has(ROR_FIELD("render_version")) ||
            int64_t(schema.get(ROR_FIELD("max_records"), 0)) <= 0 || int64_t(schema.get(ROR_FIELD("max_bytes"), 0)) <= 0) return false;
    const Array categories = schema[ROR_FIELD("categories")];
    for (int64_t i = 0; i < categories.size(); ++i) {
        const Variant rows = cache.get(categories[i], Variant());
        if (rows.get_type() != Variant::DICTIONARY || Dictionary(rows).is_read_only()) return false;
    }
    for (const char *key : {"versions", "retained"}) {
        const Variant value = cache.get(key, Dictionary());
        if (value.get_type() != Variant::DICTIONARY || Dictionary(value).is_read_only()) return false;
    }
    return true;
}

} // namespace

Dictionary RoRReadModelKernel::collect_ai_projection_changes(const Array &legal_sets, const Array &categories,
        const Dictionary &cache, const Variant &entity_versions, const Dictionary &schema) const {
    Dictionary result;
    result[ROR_FIELD("supported")] = false;
    const RoRJournalVersionReader source_versions(entity_versions);
    if (!source_versions.supported || legal_sets.size() != categories.size() || !ai_projection_cache_supported(cache, schema)) return result;
    const Dictionary versions = cache.get(ROR_FIELD("versions"), Dictionary());
    Array changed;
    for (int64_t category_index = 0; category_index < categories.size(); ++category_index) {
        const Variant category = categories[category_index];
        if (!cache.has(category) || legal_sets[category_index].get_type() != Variant::ARRAY) return result;
        const Dictionary retained = cache[category];
        const Array sources = legal_sets[category_index];
        for (int64_t i = 0; i < sources.size(); ++i) {
            const Variant value = sources[i];
            if (value.get_type() != Variant::DICTIONARY) return result;
            const Dictionary source = value;
            const int64_t id = source.get(ROR_FIELD("id"), -1);
            int64_t version = -1;
            const bool memory = ai_projection_memory(source, schema);
            if (!memory && !ai_projection_revision(source_versions, id, version)) return result;
            if (!memory && retained.has(id) && int64_t(versions.get(Vector2i(id, 0), -2)) == version) continue;
            Dictionary row;
            row[ROR_FIELD("source")] = source;
            row[ROR_FIELD("category")] = category;
            changed.push_back(row);
        }
    }
    result[ROR_FIELD("supported")] = true;
    result[ROR_FIELD("rows")] = changed;
    return result;
}

bool RoRReadModelKernel::retain_ai_projection_portion(const Array &rows, int64_t begin, int64_t end,
        int64_t observer_team, Dictionary cache, const Variant &entity_versions, const Dictionary &schema) const {
    const RoRJournalVersionReader source_versions(entity_versions);
    if (!source_versions.supported || begin < 0 || end < begin || end > rows.size() || !ai_projection_cache_supported(cache, schema)) return false;
    // Reject unsupported input before writing any cache entry. The caller can
    // then process exactly this portion through the canonical script path.
    for (int64_t i = begin; i < end; ++i) {
        const Variant value = rows[i];
        if (value.get_type() != Variant::DICTIONARY) return false;
        const Dictionary row = value;
        if (row.get(ROR_FIELD("source"), Variant()).get_type() != Variant::DICTIONARY || !cache.has(row.get(ROR_FIELD("category"), Variant()))) return false;
        const Dictionary source = row[ROR_FIELD("source")];
        int64_t version;
        if (!ai_projection_memory(source, schema) && !ai_projection_revision(source_versions, int64_t(source.get(ROR_FIELD("id"), -1)), version)) return false;
    }
    if (begin == end) return true;
    const Array fields = schema[ROR_FIELD("fields")], visible_fields = schema[ROR_FIELD("visible_fields")];
    const Array array_fields = schema[ROR_FIELD("array_fields")], private_trade_fields = schema[ROR_FIELD("private_trade_fields")];
    const int64_t max_records = schema[ROR_FIELD("max_records")], max_bytes = schema[ROR_FIELD("max_bytes")];
    Dictionary versions = cache.get(ROR_FIELD("versions"), Dictionary());
    Dictionary bookkeeping = cache.get(ROR_FIELD("retained"), Dictionary());
    cache[ROR_FIELD("versions")] = versions;
    cache[ROR_FIELD("retained")] = bookkeeping;
    int64_t total = cache.get(ROR_FIELD("bytes"), 0);
    for (int64_t i = begin; i < end; ++i) {
        const Dictionary row = rows[i];
        const Dictionary source = row[ROR_FIELD("source")];
        const Variant category = row[ROR_FIELD("category")];
        Dictionary retained = cache[category];
        const int64_t id = source.get(ROR_FIELD("id"), -1);
        const bool memory = ai_projection_memory(source, schema);
        int64_t version = -1;
        if (!memory) ai_projection_revision(source_versions, id, version);
        const Vector2i version_key(id, memory ? 1 : 0);
        const Dictionary previous = retained.get(id, Dictionary());
        Dictionary immutable;
        if (!memory && retained.has(id) && int64_t(versions.get(version_key, -2)) == version) {
            immutable = previous;
        } else {
            const bool own = observer_team <= 0 || int64_t(source.get(ROR_FIELD("team"), 0)) == observer_team;
            immutable = project_ai(source, previous, observer_team, own ? fields : visible_fields, array_fields, private_trade_fields);
            versions[version_key] = version;
        }
        if (id < 0 || UtilityFunctions::is_same(retained.get(id, Variant()), immutable)) continue;
        // Keep byte accounting and insertion/eviction order identical to the
        // existing bounded cache. Older observations retain immutable records.
        const int64_t bytes = UtilityFunctions::var_to_bytes(immutable).size() + 96;
        const Dictionary old = bookkeeping.get(id, Dictionary());
        total -= int64_t(old.get(ROR_FIELD("bytes"), 0));
        bookkeeping.erase(id);
        retained.erase(id);
        while (!bookkeeping.is_empty() && (bookkeeping.size() >= max_records || total + bytes > max_bytes)) {
            const Variant evicted = bookkeeping.keys()[0];
            const Dictionary record = bookkeeping[evicted];
            Dictionary evicted_category = cache[record[ROR_FIELD("category")]];
            evicted_category.erase(evicted);
            total -= int64_t(record.get(ROR_FIELD("bytes"), 0));
            bookkeeping.erase(evicted);
            versions.erase(Vector2i(int64_t(evicted), 0));
            versions.erase(Vector2i(int64_t(evicted), 1));
        }
        if (bytes <= max_bytes) {
            retained[id] = immutable;
            Dictionary record;
            record[ROR_FIELD("bytes")] = bytes;
            record[ROR_FIELD("category")] = category;
            bookkeeping[id] = record;
            total += bytes;
        } else {
            versions.erase(Vector2i(id, 0));
            versions.erase(Vector2i(id, 1));
        }
        cache[ROR_FIELD("bytes")] = total;
    }
    return true;
}

} // namespace godot
