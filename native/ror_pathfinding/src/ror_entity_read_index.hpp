#pragma once
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <deque>
#include <map>
#include <set>
#include <unordered_map>
#include <vector>

namespace godot {

// Derived owner-thread index. Rows refer to the authoritative world; compact
// positions and memberships live between journal updates, never in UI DTOs.
class RoREntityReadIndexKernel : public RefCounted {
    GDCLASS(RoREntityReadIndexKernel, RefCounted)
    struct Record { Dictionary row; Vector2 position; Vector2i cell; int category = 0; };
    struct Member { Dictionary row; Vector2i cell; };
    struct Observer {
        int64_t fog = -1, cursor = -1, generation = -1, sector_epoch = 0;
        bool dirty = true;
        std::map<int64_t, Member> members;
        std::unordered_map<uint64_t, int64_t> sectors;
        Array arrays[3];
    };
    std::map<int64_t, Record> records;
    std::unordered_map<uint64_t, std::vector<int64_t>> buckets;
    std::map<int64_t, Observer> observers;
    std::deque<int64_t> observer_order;
    int64_t generation = 0, epoch = -1, cursor = -1;
    bool overflow = false;
    int64_t updates = 0, crossings = 0, queries = 0;
    static uint64_t key(const Vector2i &cell);
    static Vector2i unkey(uint64_t value);
    static Vector2i cell_for(const Vector2 &position);
    static int category_id(const String &name);
    void put(const Dictionary &row, int category);
    void erase(int64_t id);
    std::set<int64_t> bounded_ids(const Rect2 &bounds, int category) const;
    Array copy_array(const Array &source) const;
    void touch_sector(Observer &observer, const Vector2i &cell);
public:
    void clear();
    Dictionary synchronize(const Dictionary &input);
    Array all(const String &category) const;
    Array in_bounds(const Rect2 &bounds, const String &category) const;
    Array buildings_in_cells(const Array &cells) const;
    Array changed_buildings(const Array &ids) const;
    Variant cached_legal(int64_t team, const String &category, int64_t fog_revision) const;
    int64_t observer_entity_cursor(int64_t team) const;
    int64_t observer_fog_cursor(int64_t team) const;
    Array legal_entities(int64_t team, const String &category, const PackedByteArray &states,
        const Vector2i &map_size, const Dictionary &fog_delta, const Dictionary &entity_delta);
    Array scope_versions(int64_t team, const Array &keys) const;
    Dictionary build_query_scope(int64_t team, const PackedVector2Array &centers, int radius, const Array &changed_cells) const;
    Dictionary debug_view() const;
    Dictionary debug_observer(int64_t team) const;
    Dictionary stats() const;
protected:
    static void _bind_methods();
};
} // namespace godot
