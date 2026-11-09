#pragma once
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string_name.hpp>
#include <godot_cpp/variant/variant.hpp>
#include <atomic>
#include <optional>

namespace godot {
namespace RoRActorKeys {

// Only immutable literal names are retained. The owner pass lends its policy
// through synchronous domain callbacks; no entity or world reference is stored.
class Scope {
    inline static thread_local Scope *active = nullptr;
    inline static std::atomic<unsigned> overrides{0};
    Scope *previous = nullptr;
    bool installed = false;
    int64_t cached_fields = 0, fresh_fields = 0, cached_properties = 0, fresh_properties = 0;
public:
    bool cached = true, profile = false;
    Scope(bool enabled, bool measured) : cached(enabled), profile(measured) {
        if (enabled && !measured && !overrides.load(std::memory_order_relaxed)) return;
        previous = active;
        active = this;
        installed = true;
        overrides.fetch_add(1, std::memory_order_relaxed);
    }
    ~Scope() {
        if (!installed) return;
        active = previous;
        overrides.fetch_sub(1, std::memory_order_relaxed);
    }
    static bool use_cached(bool property) {
        // Most game frames use immutable keys with no profiling. Avoid the
        // MinGW thread-local runtime lookup on every field of every actor.
        if (!overrides.load(std::memory_order_relaxed)) return true;
        Scope *scope = active;
        const bool use = !scope || scope->cached;
        if (scope && scope->profile) {
            int64_t &count = property ? (use ? scope->cached_properties : scope->fresh_properties) :
                (use ? scope->cached_fields : scope->fresh_fields);
            ++count;
        }
        return use;
    }
    Dictionary stats() const {
        Dictionary result;
        result["cached_fields"] = cached_fields; result["fresh_fields"] = fresh_fields;
        result["cached_properties"] = cached_properties; result["fresh_properties"] = fresh_properties;
        return result;
    }
};

// The optional owns a fresh reference-mode name until the complete dictionary
// expression finishes. Cached mode constructs no temporary Godot value.
class Field {
    std::optional<Variant> owned;
    const Variant *value;
public:
    Field(const Variant &shared, const char *literal) : value(&shared) {
        if (!Scope::use_cached(false)) { owned.emplace(literal); value = &*owned; }
    }
    Field(const Field &) = delete;
    Field(Field &&) = delete;
    operator const Variant &() const { return *value; }
};
class Property {
    std::optional<StringName> owned;
    const StringName *value;
public:
    Property(const StringName &shared, const char *literal) : value(&shared) {
        if (!Scope::use_cached(true)) { owned.emplace(literal); value = &*owned; }
    }
    Property(const Property &) = delete;
    Property(Property &&) = delete;
    operator const StringName &() const { return *value; }
};

} // namespace RoRActorKeys
} // namespace godot

// Each call site initializes only after Godot's extension API is available.
#define ROR_FIELD(text) ([]() { static const ::godot::Variant shared(text); return ::godot::RoRActorKeys::Field(shared, text); }())
#define ROR_PROPERTY(text) ([]() { static const ::godot::StringName shared(text); return ::godot::RoRActorKeys::Property(shared, text); }())

// String's const-char comparison overload constructs a temporary Godot String.
// Literal values used by actor/render loops are immutable and can be shared.
// First use happens after the extension API is initialized, like the keys above.
#define ROR_TEXT(text) ([]() -> const ::godot::String & { static const ::godot::String shared(text); return shared; }())
