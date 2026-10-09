#include "ror_read_model_kernel.hpp"

#include <algorithm>
#include <vector>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

namespace godot {
namespace {

// Validate, detach and freeze in one traversal. A readonly flag or copied marker
// is not a certificate: only exact validated roots or scalar typed maps are shared.
struct Capture {
    const Array &trusted;
    std::vector<bool> shared;
    bool valid = true;

    explicit Capture(const Array &roots) : trusted(roots), shared(roots.size(), false) {}

    bool trusted_identity(const Variant &value) {
        for (int64_t i = 0; i < trusted.size(); ++i) {
            if (UtilityFunctions::is_same(value, trusted[i])) {
                shared[i] = true;
                return true;
            }
        }
        return false;
    }

    Variant run(const Variant &value, int depth = 0) {
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
                Dictionary result = source.duplicate(false);
                result.clear();
                const Array keys = source.keys();
                for (int64_t i = 0; i < keys.size(); ++i) {
                    Variant key = run(keys[i], depth + 1);
                    Variant item = run(source[keys[i]], depth + 1);
                    if (!valid) {
                        return Variant();
                    }
                    result[key] = item;
                }
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
                Array result = source.duplicate(false);
                for (int64_t i = 0; i < source.size(); ++i) {
                    Variant item = run(source[i], depth + 1);
                    if (!valid) {
                        return Variant();
                    }
                    result[i] = item;
                }
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

void RoRReadModelKernel::_bind_methods() {
    ClassDB::bind_method(D_METHOD("project_render", "source", "previous", "fields", "nested_fields", "schema"), &RoRReadModelKernel::project_render);
    ClassDB::bind_method(D_METHOD("capture_frozen", "source", "trusted"), &RoRReadModelKernel::capture_frozen);
}

Dictionary RoRReadModelKernel::project_render(const Dictionary &source, const Dictionary &previous,
        const Array &fields, const Array &nested_fields, int64_t schema) const {
    Dictionary result;
    for (int64_t i = 0; i < fields.size(); ++i) {
        if (source.has(fields[i])) {
            result[fields[i]] = source[fields[i]];
        }
    }
    result["entity_type"] = entity_type(source);
    result["_ror_render_schema"] = schema;
    for (int64_t i = 0; i < nested_fields.size(); ++i) {
        if (source.has(nested_fields[i])) {
            result[nested_fields[i]] = source[nested_fields[i]];
        }
    }
    const Dictionary components = source.get("components", Dictionary());
    Dictionary projected;
    const Dictionary ownership = components.get("ownership", Dictionary());
    if (!ownership.is_empty()) {
        Dictionary row;
        row["civilization_id"] = int64_t(ownership.get("civilization_id", 13));
        projected["ownership"] = row;
    }
    for (const char *name : {"worker", "conversion", "healing"}) {
        const Dictionary input = components.get(name, Dictionary());
        if (!input.is_empty()) {
            Dictionary row;
            row["enabled"] = bool(input.get("enabled", false));
            projected[name] = row;
        }
    }
    const Dictionary cargo = components.get("cargo", Dictionary());
    if (!cargo.is_empty()) {
        Dictionary row;
        row["enabled"] = bool(cargo.get("enabled", false));
        row["capacity"] = std::max(int64_t(0), int64_t(cargo.get("capacity", 0)));
        projected["cargo"] = row;
    }
    const Dictionary trade = components.get("trade", Dictionary());
    if (!trade.is_empty()) {
        Dictionary row;
        row["enabled"] = bool(trade.get("enabled", false));
        row["target_building_source_id"] = int64_t(trade.get("target_building_source_id", -1));
        projected["trade"] = row;
    }
    result["components"] = projected;
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

} // namespace godot
