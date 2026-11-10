#include "ror_actor_keys.hpp"
#include "ror_read_model_kernel.hpp"
#include <godot_cpp/core/math.hpp>
#include <godot_cpp/variant/utility_functions.hpp>
#include <godot_cpp/variant/vector4i.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_int64_array.hpp>
#include <algorithm>
#include <cmath>
#include <limits>
#include <unordered_map>

namespace godot {
namespace {
bool canonical(Object *object, const char *path) {
    if (!object) return false;
    const Variant value = object->call("get_script");
    Object *script = value.get_type() == Variant::OBJECT ? static_cast<Object *>(value) : nullptr;
    return script && String(script->get("resource_path")) == path;
}
int64_t mod(int64_t value, int64_t divisor) { return (value % divisor + divisor) % divisor; }
Vector2i cell(const Vector2 &position) { return Vector2i(int32_t(std::floor(double(position.x) / 4.0)), int32_t(std::floor(double(position.y) / 4.0))); }
Array tags(const Dictionary &row) { return row.get(ROR_FIELD("behavior_tags"), Array()); }
bool military(const Dictionary &row) { const Array value = tags(row); return value.has(ROR_FIELD("military")) || (value.has(ROR_FIELD("combatant")) && !value.has(ROR_FIELD("worker"))); }
bool static_entity(const Dictionary &row) {
    const Dictionary parts = row.get(ROR_FIELD("components"), Dictionary()), movement = parts.get(ROR_FIELD("movement"), Dictionary());
    return String(movement.get(ROR_FIELD("domain"), row.get(ROR_FIELD("movement_domain"), ROR_TEXT("land")))) == ROR_TEXT("static");
}
String stance_of(const Dictionary &row) { return bool(row.get(ROR_FIELD("combat_pursuit"), false)) ? ROR_TEXT("aggressive") : String(row.get(ROR_FIELD("stance"), ROR_TEXT("passive"))); }
bool due(const Dictionary &row, int64_t tick, const String &stance) {
    const String task = row.get(ROR_FIELD("task"), ROR_TEXT("idle"));
    if (int64_t(row.get(ROR_FIELD("retaliation_target_id"), -1)) >= 0 || task == ROR_TEXT("attack_move")) return true;
    if (task == ROR_TEXT("attack")) return mod(tick + int64_t(row.get(ROR_FIELD("id"), 0)), 2) == 0;
    const int64_t interval = stance == ROR_TEXT("aggressive") ? 4 : 2;
    const Vector2i position = cell(row.get(ROR_FIELD("pos"), Vector2()));
    return mod(tick, interval) == mod(int64_t(position.x) * 31 + int64_t(position.y) * 17 + (stance == ROR_TEXT("defensive") ? 0 : 1), interval);
}
double query_range(const Dictionary &row, const String &stance) {
    if (bool(row.get(ROR_FIELD("combat_pursuit"), false))) {
        const Dictionary parts = row.get(ROR_FIELD("components"), Dictionary()), vision = parts.get(ROR_FIELD("vision"), Dictionary());
        return std::max(double(row.get(ROR_FIELD("acquisition_range"), 0.0)), double(vision.get(ROR_FIELD("range"), 0.0)));
    }
    return stance == ROR_TEXT("stand_ground") ? std::max(0.85, double(row.get(ROR_FIELD("attack_range"), 0.0))) : std::max(0.0, double(row.get(ROR_FIELD("acquisition_range"), 0.0)));
}
double edge_distance(const Dictionary &attacker, const Dictionary &target) {
    const Vector2 origin = attacker.get(ROR_FIELD("pos"), Vector2()), position = target.get(ROR_FIELD("pos"), Vector2());
    const Dictionary footprint = target.get(ROR_FIELD("footprint"), Dictionary());
    const double radius = attacker.get(ROR_FIELD("footprint_radius"), 0.0);
    if (String(footprint.get(ROR_FIELD("shape"), String())) == ROR_TEXT("polygon")) {
        const Vector2 half = footprint.get(ROR_FIELD("half_size"), Vector2());
        Vector2 minimum = position - half, maximum = position + half;
        const Array occupied = target.get(ROR_FIELD("occupied_cells"), Array());
        if (!occupied.is_empty()) {
            minimum = Vector2(INFINITY, INFINITY); maximum = Vector2(-INFINITY, -INFINITY);
            for (int64_t index = 0; index < occupied.size(); ++index) {
                const Vector2 point = Vector2(Vector2i(occupied[index]));
                minimum.x = std::min(minimum.x, point.x); minimum.y = std::min(minimum.y, point.y);
                maximum.x = std::max(double(maximum.x), double(point.x) + 1.0); maximum.y = std::max(double(maximum.y), double(point.y) + 1.0);
            }
        }
        const Vector2 offset(std::max(std::max(double(minimum.x) - origin.x, 0.0), double(origin.x) - maximum.x),
                std::max(std::max(double(minimum.y) - origin.y, 0.0), double(origin.y) - maximum.y));
        return std::max(0.0, double(offset.length()) - radius);
    }
    return std::max(0.0, double(origin.distance_to(position)) - (radius + double(target.get(ROR_FIELD("footprint_radius"), 0.0))));
}
bool in_range(const Dictionary &attacker, const Dictionary &target) {
    const double maximum = attacker.get(ROR_FIELD("attack_range"), 0.0);
    const double distance = edge_distance(attacker, target);
    const Dictionary parts = attacker.get(ROR_FIELD("components"), Dictionary()), combat = parts.get(ROR_FIELD("combat"), Dictionary());
    const double minimum = std::max(0.0, double(combat.get(ROR_FIELD("range_min"), attacker.get(ROR_FIELD("attack_range_min"), 0.0))));
    return distance <= (maximum > 1.0 ? maximum : maximum + 0.08) + 0.0001 && !(minimum > 0.0 && distance + 0.0001 < minimum);
}
Array classification(const Dictionary &row) {
    Array result;
    result.append(double(row.get(ROR_FIELD("hp"), 0.0)) > 0.0); result.append(cell(row.get(ROR_FIELD("pos"), Vector2())));
    result.append(int64_t(row.get(ROR_FIELD("team"), 0))); result.append(bool(row.get(ROR_FIELD("combat_enabled"), false)));
    result.append(String(row.get(ROR_FIELD("task"), ROR_TEXT("idle")))); result.append(int64_t(row.get(ROR_FIELD("target_id"), -1)));
    result.append(int64_t(row.get(ROR_FIELD("retaliation_target_id"), -1))); result.append(bool(row.get(ROR_FIELD("combat_pursuit"), false)));
    result.append(String(row.get(ROR_FIELD("stance"), ROR_TEXT("passive")))); result.append(bool(row.get(ROR_FIELD("attack_autonomous"), false)));
    result.append(tags(row).duplicate()); result.append(double(row.get(ROR_FIELD("footprint_radius"), 0.0)));
    return result;
}

struct Rank {
    int64_t threat = INT32_MAX, assigned = INT32_MAX, category = INT32_MAX, id = INT64_MAX;
    double distance = INFINITY;
    bool precedes(const Rank &other) const {
        if (threat != other.threat) return threat < other.threat;
        if (assigned != other.assigned) return assigned < other.assigned;
        if (category != other.category) return category < other.category;
        if (!Math::is_equal_approx(distance, other.distance)) return distance < other.distance;
        return id < other.id;
    }
};

// One numeric summary per four-tile sector. A negative broad-phase answer
// never skips target ranking, fog or diplomacy for an occupied foreign sector.
class CombatSectorOccupancy {
    static constexpr uint64_t RETALIATION = uint64_t(1) << 62;
    static constexpr uint64_t OTHER_TEAMS = uint64_t(1) << 63;
    static constexpr int64_t MAX_SECTORS = 1024 * 1024;
    Vector2i size;
    PackedInt64Array masks;
    const int64_t *read = nullptr;
    std::vector<Vector2i> dirty;

    static uint64_t team_bit(int64_t team) {
        if (team <= 0) return 0;
        return team <= 62 ? uint64_t(1) << (team - 1) : OTHER_TEAMS;
    }
    bool contains(const Vector2i &point) const {
        return point.x >= 0 && point.x < size.x && point.y >= 0 && point.y < size.y;
    }
    bool may_contain(const Vector2i &point, uint64_t wanted) const {
        return !read || !contains(point) || (uint64_t(read[int64_t(point.y) * size.x + point.x]) & wanted) != 0;
    }
    void refresh_cell(int64_t *write, const Vector2i &point, const Dictionary &buckets, const Dictionary &retaliation) {
        if (!contains(point)) return;
        uint64_t mask = retaliation.has(point) ? RETALIATION : 0;
        if (buckets.has(point)) {
            const Dictionary teams = buckets[point];
            const Array keys = teams.keys();
            for (int64_t n = 0; n < keys.size(); ++n) mask |= team_bit(keys[n]);
        }
        write[int64_t(point.y) * size.x + point.x] = int64_t(mask);
    }
public:
    void changed(const Vector2i &point) { dirty.push_back(point); }
    bool may_have_target(const Vector2i &point, int64_t observer) const {
        // The overflow bit can represent multiple teams, including the observer.
        const uint64_t self = observer > 0 && observer <= 62 ? team_bit(observer) : 0;
        return may_contain(point, ~(RETALIATION | self));
    }
    bool may_have_retaliation(const Vector2i &point) const { return may_contain(point, RETALIATION); }

    void prepare(Dictionary index, const Dictionary &buckets, const Dictionary &retaliation,
            const Vector2i &map_size, int64_t previous, int64_t revision, bool full) {
        if (map_size.x <= 0 || map_size.y <= 0) return;
        size = Vector2i((int64_t(map_size.x) + 3) / 4, (int64_t(map_size.y) + 3) / 4);
        const int64_t count = int64_t(size.x) * size.y;
        if (count > MAX_SECTORS) return;
        const bool reuse = !full && index.get(ROR_FIELD("sector_map_size"), Vector2i()) == Variant(size) &&
                int64_t(index.get(ROR_FIELD("sector_revision"), -2)) == previous;
        if (reuse) masks = index.get(ROR_FIELD("sector_masks"), PackedInt64Array());
        if (masks.size() != count) {
            masks.resize(count);
            masks.fill(0);
            int64_t *write = masks.ptrw();
            for (const Dictionary *cells : {&buckets, &retaliation}) {
                const Array keys = cells->keys();
                for (int64_t n = 0; n < keys.size(); ++n) refresh_cell(write, keys[n], buckets, retaliation);
            }
        } else if (!dirty.empty()) {
            int64_t *write = masks.ptrw();
            for (const Vector2i &point : dirty) refresh_cell(write, point, buckets, retaliation);
        }
        index[ROR_FIELD("sector_masks")] = masks;
        index[ROR_FIELD("sector_map_size")] = size;
        index[ROR_FIELD("sector_revision")] = revision;
        read = masks.ptr();
    }
};

// All references and fog views are owner-pass scoped. The retained indexes are
// the existing awareness dictionaries, not a second actor/world representation.
class AwarenessPass {
    const RoRReadModelKernel *kernel;
    Object *world, *state, *fog = nullptr;
    Dictionary units, buildings, attackers, membership, metadata, classes, sources;
    Dictionary assigned_targets, retaliation, lanes_by_id, index, buckets;
    Dictionary relations, alliances, candidate_cache;
    CombatSectorOccupancy occupancy;
    int64_t candidate_sectors_skipped = 0, assistance_sectors_skipped = 0;
    Array lanes;
    bool order_dirty = false;
    struct Vision { PackedByteArray bytes; const uint8_t *data = nullptr; Vector2i size; };
    std::unordered_map<int64_t, Vision> vision;
    int64_t changed = 0, observers = 0, validations = 0, acquisitions = 0;
    int64_t tested = 0, reachability = 0, assistance = 0;
    int64_t position_checks = 0, full_classification_checks = 0;
    bool position_classification_enabled = false;
    bool compare_classification = false;
    int64_t classification_comparison_budget = 0, classification_comparisons = 0, classification_mismatches = 0;

    void bind() {
        attackers = state->get("attackers_by_id"); membership = state->get("target_membership");
        metadata = state->get("metadata_by_id"); classes = state->get("classification_by_id"); sources = state->get("classification_sources");
        assigned_targets = state->get("assigned_targets"); retaliation = state->get("retaliation_buckets");
        lanes_by_id = state->get("lane_by_id"); lanes = state->get("wake_lanes");
        index = state->get("cached_candidate_index"); buckets = index.get(ROR_FIELD("buckets"), Dictionary());
        order_dirty = state->get("roster_order_dirty");
    }
    Variant find(int64_t id) const { return units.get(id, buildings.get(id, Variant())); }
    String relation(int64_t first, int64_t second) {
        const Vector2i key(first, second);
        if (!relations.has(key)) relations[key] = world->call("team_relation", first, second);
        return relations[key];
    }
    bool allied(int64_t first, int64_t second) {
        const Vector2i key(first, second);
        if (!alliances.has(key)) alliances[key] = world->call("are_teams_allied", first, second);
        return alliances[key];
    }
    bool visible(int64_t team, const Dictionary &row) {
        if (team <= 0 || int64_t(row.get(ROR_FIELD("team"), 0)) == team) return true;
        auto found = vision.find(team);
        if (found == vision.end()) {
            if (!fog) fog = world->call("get_fog_of_war");
            if (!fog) return bool(world->call("is_entity_visible_to", team, row));
            Dictionary buffers = fog->get("states_by_player");
            if (!buffers.has(team)) {
                world->call("get_fog_state_at", team, row.get(ROR_FIELD("pos"), Vector2()));
                buffers = fog->get("states_by_player");
            }
            const Variant bytes = buffers.get(team, Variant());
            const Vector2i size = fog->get("map_size");
            if (bytes.get_type() != Variant::PACKED_BYTE_ARRAY || size.x <= 0 || size.y <= 0 || PackedByteArray(bytes).size() != int64_t(size.x) * size.y)
                return bool(world->call("is_entity_visible_to", team, row));
            Vision view; view.bytes = bytes; view.size = size; view.data = view.bytes.ptr();
            found = vision.emplace(team, std::move(view)).first;
        }
        const Vector2 position = row.get(ROR_FIELD("pos"), Vector2());
        const int64_t x = int64_t(std::floor(position.x)), y = int64_t(std::floor(position.y));
        const Vision &view = found->second;
        return x >= 0 && y >= 0 && x < view.size.x && y < view.size.y && view.data[y * view.size.x + x] == 2;
    }
    void remove(int64_t id, bool retain = false) {
        classes.erase(id); sources.erase(id);
        if (membership.has(id)) {
            const Array old = membership[id];
            Dictionary bucket = buckets[old[0]];
            Array rows = bucket[old[1]]; rows.erase(old[2]);
            if (rows.is_empty()) { bucket.erase(old[1]); occupancy.changed(old[0]); }
            if (bucket.is_empty()) buckets.erase(old[0]);
            membership.erase(id);
        }
        if (!retain && attackers.erase(id)) order_dirty = true;
        if (metadata.has(id)) {
            const Dictionary previous = metadata[id];
            const int64_t target = previous[ROR_FIELD("assigned")];
            if (target >= 0) {
                const int64_t count = int64_t(assigned_targets.get(target, 0)) - 1;
                if (count <= 0) assigned_targets.erase(target); else assigned_targets[target] = count;
            }
            if (bool(previous[ROR_FIELD("retaliation")])) {
                Array rows = retaliation[previous[ROR_FIELD("cell")]]; rows.erase(previous[ROR_FIELD("row")]);
                if (rows.is_empty()) { retaliation.erase(previous[ROR_FIELD("cell")]); occupancy.changed(previous[ROR_FIELD("cell")]); }
            }
            metadata.erase(id);
        }
        const Array old_lanes = lanes_by_id.get(id, Array());
        for (int64_t n = 0; n < old_lanes.size(); ++n) { Dictionary lane = lanes[int64_t(old_lanes[n])]; lane.erase(id); }
        lanes_by_id.erase(id);
    }
    void update(const Dictionary &row) {
        ++changed;
        const int64_t id = row[ROR_FIELD("id")], team = row.get(ROR_FIELD("team"), 0);
        const Vector2i position = cell(row.get(ROR_FIELD("pos"), Vector2()));
        classes[id] = classification(row); sources[id] = row;
        if (double(row.get(ROR_FIELD("hp"), 0.0)) <= 0.0) { attackers.erase(id); order_dirty = true; return; }
        if (!tags(row).has(ROR_FIELD("noncombat_target"))) {
            if (!buckets.has(position)) buckets[position] = Dictionary();
            Dictionary bucket = buckets[position];
            if (!bucket.has(team)) { bucket[team] = Array(); occupancy.changed(position); }
            Array rows = bucket[team]; rows.append(row);
            Array entry; entry.append(position); entry.append(team); entry.append(row); membership[id] = entry;
            index[ROR_FIELD("maximum_radius")] = std::max(double(index.get(ROR_FIELD("maximum_radius"), 0.0)), double(row.get(ROR_FIELD("footprint_radius"), 0.0)));
        }
        if (!bool(row.get(ROR_FIELD("combat_enabled"), false))) { if (attackers.erase(id)) order_dirty = true; return; }
        if (!attackers.has(id)) order_dirty = true;
        attackers[id] = row;
        const String task = row.get(ROR_FIELD("task"), ROR_TEXT("idle"));
        const int64_t assigned = task == ROR_TEXT("attack") ? int64_t(row.get(ROR_FIELD("target_id"), -1)) : -1;
        if (assigned >= 0) assigned_targets[assigned] = int64_t(assigned_targets.get(assigned, 0)) + 1;
        const bool retaliating = int64_t(row.get(ROR_FIELD("retaliation_target_id"), -1)) >= 0;
        if (retaliating) {
            if (!retaliation.has(position)) { retaliation[position] = Array(); occupancy.changed(position); }
            Array rows = retaliation[position]; rows.append(row);
        }
        Dictionary entry; entry[ROR_FIELD("assigned")] = assigned; entry[ROR_FIELD("retaliation")] = retaliating; entry[ROR_FIELD("cell")] = position; entry[ROR_FIELD("row")] = row;
        metadata[id] = entry;
        const String stance = stance_of(row);
        if (stance == ROR_TEXT("passive") || (task != ROR_TEXT("idle") && task != ROR_TEXT("attack_move") && task != ROR_TEXT("attack")) || (task == ROR_TEXT("attack") && !bool(row.get(ROR_FIELD("attack_autonomous"), false)))) return;
        Array active_lanes;
        for (int64_t phase = 0; phase < 4; ++phase) if (due(row, phase, stance)) {
            Dictionary lane = lanes[phase]; lane[id] = row; active_lanes.append(phase);
        }
        lanes_by_id[id] = active_lanes;
    }
    void refresh(const Dictionary &delta, int64_t tick) {
        if (bool(delta[ROR_FIELD("full")])) {
            state->call("reset");
            Dictionary fresh; fresh[ROR_FIELD("buckets")] = Dictionary(); fresh[ROR_FIELD("maximum_radius")] = 0.0;
            state->set("cached_candidate_index", fresh); bind();
            const Array unit_rows = world->call("get_units"), building_rows = world->call("get_buildings");
            for (int64_t n = 0; n < unit_rows.size(); ++n) update(unit_rows[n]);
            for (int64_t n = 0; n < building_rows.size(); ++n) update(building_rows[n]);
        } else {
            const Array ids = delta[ROR_FIELD("ids")]; const Dictionary masks = delta[ROR_FIELD("masks")];
            for (int64_t n = 0; n < ids.size(); ++n) {
                const int64_t id = ids[n];
                const int64_t mask = masks[id];
                if (!(mask & 143)) continue; // lifecycle/position/activity/combat/ownership.
                const Variant row = find(id);
                if (row.get_type() == Variant::DICTIONARY) {
                    const Array previous = classes.get(id, Array());
                    if (UtilityFunctions::is_same(sources.get(id, Variant()), row)) {
                        // Task/target/stance/capability writers publish COMBAT;
                        // ordinary motion and timers do not alter those facts.
                        // Exact coordinates remain live in the spatial rows,
                        // while membership and wake lanes depend on a 4-tile cell.
                        if (position_classification_enabled && !(mask & 137) && previous.size() == 12) {
                            ++position_checks;
                            static const Variant position_key("pos");
                            if (Vector2i(previous[1]) == cell(Dictionary(row).get(position_key, Vector2()))) {
                                if (compare_classification && classification_comparisons < classification_comparison_budget &&
                                        (position_checks <= 16 || position_checks % 32 == 0)) {
                                    ++classification_comparisons;
                                    if (!kernel->matches_combat_classification(row, previous)) {
                                        ++classification_mismatches;
                                        UtilityFunctions::push_error("Combat classification change was not published in COMBAT group for entity ", id);
                                    }
                                }
                                continue;
                            }
                        } else {
                            ++full_classification_checks;
                            if (kernel->matches_combat_classification(row, previous)) continue;
                        }
                    }
                    remove(id, true); update(row);
                } else remove(id);
            }
        }
        Object *journal = world->get("entity_changes");
        state->set("cursor", delta[ROR_FIELD("revision")]); state->set("epoch", journal->get("epoch")); state->set("cached_roster_tick", tick);
        if (order_dirty) {
            std::vector<Dictionary> sorted;
            const Array rows = attackers.values(); sorted.reserve(rows.size());
            for (int64_t n = 0; n < rows.size(); ++n) sorted.push_back(rows[n]);
            std::sort(sorted.begin(), sorted.end(), [](const Dictionary &a, const Dictionary &b) { return int64_t(a[ROR_FIELD("id")]) < int64_t(b[ROR_FIELD("id")]); });
            Array ordered; for (const Dictionary &row : sorted) ordered.append(row);
            state->set("cached_attackers", ordered); order_dirty = false;
        }
        state->set("roster_order_dirty", order_dirty);
    }
    bool eligible(const Dictionary &row, bool battle_over) const {
        if (int64_t(row.get(ROR_FIELD("team"), 0)) <= 0 || battle_over || double(row.get(ROR_FIELD("hp"), 0.0)) <= 0.0 || !bool(row.get(ROR_FIELD("combat_enabled"), false))) return false;
        if (tags(row).has(ROR_FIELD("scout")) && int64_t(row.get(ROR_FIELD("retaliation_target_id"), -1)) < 0 && !bool(row.get(ROR_FIELD("combat_pursuit"), false))) return false;
        return !static_entity(row) || String(row.get(ROR_FIELD("state"), ROR_TEXT("complete"))) == ROR_TEXT("complete");
    }
    bool valid_target(const Dictionary &row, const Variant &target_value) {
        ++validations;
        if (target_value.get_type() != Variant::DICTIONARY) return false;
        const Dictionary target = target_value;
        if (double(target.get(ROR_FIELD("hp"), 0.0)) <= 0.0) return false;
        const int64_t team = row.get(ROR_FIELD("team"), 0), other = target.get(ROR_FIELD("team"), 0);
        if (allied(team, other)) return false;
        if (bool(row.get(ROR_FIELD("attack_autonomous"), false))) {
            const String disposition = relation(team, other);
            if (disposition != ROR_TEXT("enemy") && (disposition != ROR_TEXT("neutral") || (!static_entity(target) && !military(target)))) return false;
        }
        if (!visible(team, target)) return false;
        if (!bool(row.get(ROR_FIELD("combat_pursuit"), false)) && String(row.get(ROR_FIELD("stance"), ROR_TEXT("passive"))) == ROR_TEXT("stand_ground") && !in_range(row, target)) return false;
        if (bool(row.get(ROR_FIELD("attack_autonomous"), false))) {
            const Vector2 origin = row.get(ROR_FIELD("combat_leash_origin"), row.get(ROR_FIELD("pos"), Vector2()));
            if (origin.distance_to(Vector2(target.get(ROR_FIELD("pos"), Vector2()))) > double(row.get(ROR_FIELD("chase_range"), 0.0)) + 0.0001) return false;
        }
        return true;
    }
    int64_t assistance_target(const Dictionary &row) {
        ++assistance;
        int64_t best_target = -1, best_id = INT32_MAX;
        double best_distance = INFINITY;
        const int64_t team = row.get(ROR_FIELD("team"), 0), id = row.get(ROR_FIELD("id"), -1);
        const Vector2 position = row.get(ROR_FIELD("pos"), Vector2());
        const double radius = row.get(ROR_FIELD("acquisition_range"), 0.0);
        const Vector2i minimum = cell(position - Vector2(radius, radius)), maximum = cell(position + Vector2(radius, radius));
        for (int32_t y = minimum.y; y <= maximum.y; ++y) for (int32_t x = minimum.x; x <= maximum.x; ++x) {
            const Vector2i sector(x, y);
            if (!occupancy.may_have_retaliation(sector)) { ++assistance_sectors_skipped; continue; }
            const Array rows = retaliation.get(sector, Array());
            for (int64_t n = 0; n < rows.size(); ++n) {
                const Dictionary ally = rows[n]; const int64_t ally_id = ally.get(ROR_FIELD("id"), -1);
                if (ally_id == id || double(ally.get(ROR_FIELD("hp"), 0.0)) <= 0.0 || !allied(team, ally.get(ROR_FIELD("team"), 0))) continue;
                const int64_t target = ally.get(ROR_FIELD("retaliation_target_id"), -1);
                const Vector2 ally_position = ally.get(ROR_FIELD("pos"), Vector2());
                if (target < 0 || position.distance_to(ally_position) > radius || find(target).get_type() == Variant::NIL) continue;
                const double distance = position.distance_squared_to(ally_position);
                const bool same = Math::is_equal_approx(distance, best_distance);
                if ((!same && distance < best_distance) || (same && ally_id < best_id)) { best_target = target; best_id = ally_id; best_distance = distance; }
            }
        }
        return best_target;
    }
    Array candidates(const Dictionary &row, double radius) {
        const Vector2 position = row.get(ROR_FIELD("pos"), Vector2());
        const Vector2i bucket = cell(position);
        const int64_t milli = std::max(int64_t(0), int64_t(std::ceil(std::max(0.0, radius) * 1000.0)));
        const int64_t team = row.get(ROR_FIELD("team"), 0);
        const Vector4i key(bucket.x, bucket.y, milli, team);
        if (candidate_cache.has(key)) return candidate_cache[key];
        const Vector2 center = (Vector2(bucket) + Vector2(0.5, 0.5)) * 4.0;
        const double extent = double(milli) / 1000.0 + 4.0 * std::sqrt(2.0) * 0.5 + double(index.get(ROR_FIELD("maximum_radius"), 0.0));
        const Vector2i minimum = cell(center - Vector2(extent, extent)), maximum = cell(center + Vector2(extent, extent));
        Array result;
        for (int32_t y = minimum.y; y <= maximum.y; ++y) for (int32_t x = minimum.x; x <= maximum.x; ++x) {
            const Vector2i sector(x, y);
            if (!occupancy.may_have_target(sector, team)) { ++candidate_sectors_skipped; continue; }
            const Dictionary teams = buckets.get(sector, Dictionary()); const Array ids = teams.keys();
            for (int64_t n = 0; n < ids.size(); ++n) {
                const int64_t other = ids[n];
                if (other <= 0 || other == team) continue;
                const String disposition = relation(team, other);
                const Array rows = teams[ids[n]];
                if (disposition == ROR_TEXT("enemy")) result.append_array(rows);
                else if (disposition == ROR_TEXT("neutral")) for (int64_t r = 0; r < rows.size(); ++r) {
                    const Dictionary candidate = rows[r]; if (static_entity(candidate) || military(candidate)) result.append(candidate);
                }
            }
        }
        candidate_cache[key] = result; return result;
    }
    Variant best_pass(const Dictionary &observer, const Array &rows, const Dictionary &assigned, double radius,
            const String &stance, int64_t allowed, bool check_reachability) {
        const int64_t observer_id = observer.get(ROR_FIELD("id"), -1), team = observer.get(ROR_FIELD("team"), 0);
        const Vector2 position = observer.get(ROR_FIELD("pos"), Vector2()), leash = observer.get(ROR_FIELD("combat_leash_origin"), position);
        const double footprint = observer.get(ROR_FIELD("footprint_radius"), 0.0), chase = double(observer.get(ROR_FIELD("chase_range"), 0.0)) + 0.0001;
        const bool autonomous = observer.get(ROR_FIELD("attack_autonomous"), false);
        Variant best; Rank best_rank;
        for (int64_t n = 0; n < rows.size(); ++n) {
            ++tested;
            const Dictionary candidate = rows[n];
            const int64_t id = candidate.get(ROR_FIELD("id"), -1), other = candidate.get(ROR_FIELD("team"), 0);
            if (id < 0 || id == observer_id || double(candidate.get(ROR_FIELD("hp"), 0.0)) <= 0.0 ||
                    (allowed >= 0 && id != allowed) || other <= 0 || other == team || !visible(team, candidate)) continue;
            const Vector2 target_position = candidate.get(ROR_FIELD("pos"), Vector2());
            if (autonomous && leash.distance_squared_to(target_position) > chase * chase) continue;
            if (stance == ROR_TEXT("stand_ground") && !in_range(observer, candidate)) continue;
            const double distance = position.distance_squared_to(target_position);
            const double combined = std::max(0.0, radius) + footprint + double(candidate.get(ROR_FIELD("footprint_radius"), 0.0));
            if (distance > combined * combined + 0.000001) continue;
            Rank rank;
            rank.id = id; rank.distance = distance; rank.assigned = assigned.get(id, 0);
            rank.threat = String(candidate.get(ROR_FIELD("task"), ROR_TEXT("idle"))) == ROR_TEXT("attack") && int64_t(candidate.get(ROR_FIELD("target_id"), -1)) == observer_id ? 0 : 1;
            const Array behavior = tags(candidate);
            rank.category = military(candidate) ? 0 : behavior.has(ROR_FIELD("worker")) ? 1 : behavior.has(ROR_FIELD("static")) ? 2 : 1;
            if (!rank.precedes(best_rank)) continue;
            if (check_reachability) { ++reachability; if (!bool(world->call("can_unit_reach_entity", observer, candidate))) continue; }
            best = candidate; best_rank = rank;
        }
        return best;
    }
public:
    AwarenessPass(const RoRReadModelKernel *p_kernel, Object *p_world, Object *p_state) : kernel(p_kernel), world(p_world), state(p_state) {
        units = world->get("units_by_id"); buildings = world->get("buildings_by_id"); bind();
        position_classification_enabled = state->get("classification_shortcut_tick");
        compare_classification = state->get("compare_native_awareness");
        if (compare_classification) {
            const Dictionary accumulated = state->get("native_awareness_stats");
            classification_comparison_budget = std::max(int64_t(0), int64_t(1024) - int64_t(accumulated.get(ROR_FIELD("classification_comparisons"), 0)));
        }
    }
    Dictionary run(const Dictionary &delta, int64_t tick) {
        const int64_t previous = state->get("cursor");
        refresh(delta, tick);
        occupancy.prepare(index, buckets, retaliation, world->get(ROR_PROPERTY("map_size")), previous,
                delta[ROR_FIELD("revision")], bool(delta[ROR_FIELD("full")]));
        const Dictionary wake = lanes[mod(tick, 4)]; const Array rows = wake.values();
        std::vector<Dictionary> ordered; ordered.reserve(rows.size());
        for (int64_t n = 0; n < rows.size(); ++n) ordered.push_back(rows[n]);
        std::sort(ordered.begin(), ordered.end(), [](const Dictionary &a, const Dictionary &b) { return int64_t(a[ROR_FIELD("id")]) < int64_t(b[ROR_FIELD("id")]); });
        const bool battle_over = world->get("battle_over");
        std::vector<Dictionary> acquisition;
        for (const Dictionary &row : ordered) {
            const String task = row.get(ROR_FIELD("task"), ROR_TEXT("idle"));
            if (task != ROR_TEXT("idle") && task != ROR_TEXT("attack_move") && !(task == ROR_TEXT("attack") && bool(row.get(ROR_FIELD("attack_autonomous"), false)))) continue;
            const String stance = stance_of(row);
            if (stance == ROR_TEXT("passive")) continue;
            const Dictionary parts = row.get(ROR_FIELD("components"), Dictionary()), order = parts.get(ROR_FIELD("order"), Dictionary());
            if (!Array(order.get(ROR_FIELD("queued"), Array())).is_empty() || !due(row, tick, stance) || !eligible(row, battle_over)) continue;
            ++observers;
            const Variant target = find(row.get(ROR_FIELD("target_id"), -1));
            if (task == ROR_TEXT("attack") && valid_target(row, target)) continue;
            acquisition.push_back(row);
        }
        acquisitions = acquisition.size();
        Dictionary assigned = assigned_targets.duplicate();
        Array decisions;
        for (const Dictionary &row : acquisition) {
            const String stance = stance_of(row);
            const double radius = query_range(row, stance);
            int64_t allowed = -1;
            if (stance == ROR_TEXT("defensive")) {
                allowed = row.get(ROR_FIELD("retaliation_target_id"), -1);
                if (allowed < 0) allowed = assistance_target(row);
                if (allowed < 0) continue;
            } else if (stance != ROR_TEXT("stand_ground")) {
                const String task = row.get(ROR_FIELD("task"), ROR_TEXT("idle"));
                if (task != ROR_TEXT("idle") && task != ROR_TEXT("move") && task != ROR_TEXT("attack_move") && task != ROR_TEXT("attack")) continue;
            }
            const Array nearby = candidates(row, radius + double(row.get(ROR_FIELD("footprint_radius"), 0.0)));
            Variant best = best_pass(row, nearby, assigned, radius, stance, allowed, false);
            if (best.get_type() == Variant::NIL) continue;
            if (!static_entity(row)) {
                ++reachability;
                if (!bool(world->call("can_unit_reach_entity", row, best))) best = best_pass(row, nearby, assigned, radius, stance, allowed, true);
            }
            if (best.get_type() == Variant::NIL) continue;
            const Dictionary target = best;
            const int64_t target_id = target[ROR_FIELD("id")];
            Dictionary policy;
            policy[ROR_FIELD("autonomous")] = true; policy[ROR_FIELD("trigger")] = stance == ROR_TEXT("defensive") ? ROR_TEXT("retaliation") : ROR_TEXT("stance");
            const Vector2 origin = bool(row.get(ROR_FIELD("attack_autonomous"), false)) ? Vector2(row.get(ROR_FIELD("combat_leash_origin"), row.get(ROR_FIELD("pos"), Vector2()))) : Vector2(row.get(ROR_FIELD("pos"), Vector2()));
            policy[ROR_FIELD("leash_origin")] = origin;
            policy[ROR_FIELD("chase_range")] = double(row.get(ROR_FIELD("chase_range"), radius));
            Dictionary decision; decision[ROR_FIELD("unit_id")] = row[ROR_FIELD("id")]; decision[ROR_FIELD("target_id")] = target_id; decision[ROR_FIELD("policy")] = policy;
            decisions.append(decision); assigned[target_id] = int64_t(assigned.get(target_id, 0)) + 1;
        }
        Dictionary stats;
        stats[ROR_FIELD("calls")] = 1; stats[ROR_FIELD("roster_updates")] = changed; stats[ROR_FIELD("due_observers")] = observers;
        stats[ROR_FIELD("target_validations")] = validations; stats[ROR_FIELD("acquisitions")] = acquisitions;
        stats[ROR_FIELD("candidate_queries")] = candidate_cache.size(); stats[ROR_FIELD("candidates_tested")] = tested;
        stats[ROR_FIELD("candidate_sectors_skipped")] = candidate_sectors_skipped;
        stats[ROR_FIELD("assistance_sectors_skipped")] = assistance_sectors_skipped;
        stats[ROR_FIELD("reachability_queries")] = reachability; stats[ROR_FIELD("assistance_queries")] = assistance;
        stats[ROR_FIELD("commands")] = decisions.size();
        stats[ROR_FIELD("position_classification_checks")] = position_checks;
        stats[ROR_FIELD("full_classification_checks")] = full_classification_checks;
        stats[ROR_FIELD("classification_comparisons")] = classification_comparisons;
        stats[ROR_FIELD("classification_mismatches")] = classification_mismatches;
        Dictionary result; result[ROR_FIELD("decisions")] = decisions; result[ROR_FIELD("stats")] = stats; return result;
    }
};
}

Dictionary RoRReadModelKernel::collect_combat_awareness(Object *world, Object *awareness, int64_t tick, const Dictionary &delta) const {
    if (!canonical(world, "res://scripts/simulation_world.gd") || !canonical(awareness, "res://scripts/combat_awareness_system.gd") ||
            !delta.has(ROR_FIELD("full")) || !delta.has(ROR_FIELD("revision")) || !delta.has(ROR_FIELD("ids")) || !delta.has(ROR_FIELD("masks"))) return Dictionary();
    Object *perception = awareness->get("perception"), *visibility = world->get("visibility_system");
    if (!canonical(perception, "res://scripts/perception_service.gd") ||
            !canonical(visibility, "res://scripts/simulation_visibility_system.gd")) return Dictionary();
    Object *fog = world->call("get_fog_of_war");
    if (!canonical(fog, "res://scripts/fog_of_war.gd")) return Dictionary();
    const Array lanes = awareness->get("wake_lanes");
    if (lanes.size() != 4) return Dictionary();
    for (int64_t n = 0; n < 4; ++n) if (lanes[n].get_type() != Variant::DICTIONARY || Dictionary(lanes[n]).is_read_only()) return Dictionary();
    AwarenessPass pass(this, world, awareness);
    return pass.run(delta, tick);
}

} // namespace godot
