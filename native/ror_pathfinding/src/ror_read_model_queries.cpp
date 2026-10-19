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

Dictionary RoRReadModelKernel::economy_resource_view(const Array &resources, const Array &buildings, int64_t team) const {
    static const Variant amount("amount"), id("id"), owner("team"), harvestable("harvestable"), type("resource_type_id");
    Array active;
    Dictionary by_id, types;
    for (int pass = 0; pass < 2; ++pass) {
        const Array &source = pass == 0 ? resources : buildings;
        for (int64_t i = 0; i < source.size(); ++i) {
            const Dictionary row = source[i];
            if (int64_t(row.get(amount, 0)) <= 0) continue;
            if (pass == 1 && (int64_t(row.get(owner, 0)) != team || !bool(row.get(harvestable, false)))) continue;
            active.append(row);
            by_id[int64_t(row.get(id, -1))] = row;
            types[int64_t(row.get(type, -1))] = true;
        }
    }
    Dictionary result;
    result["resources"] = active; result["by_id"] = by_id; result["types"] = types;
    return result;
}

Dictionary RoRReadModelKernel::reachable_cell_lookup(const Dictionary &navigation) const {
    Dictionary result;
    const Dictionary reachable = navigation.get("reachable", Dictionary());
    for (const char *domain : {"land", "water"}) {
        const Array values = reachable.get(domain, Array());
        if (values.is_empty()) continue;
        Dictionary cells;
        for (int64_t i = 0; i < values.size(); ++i) cells[Vector2i(Vector2(values[i]))] = true;
        result[domain] = cells;
    }
    return result;
}

Array RoRReadModelKernel::known_resources_in_bounds(const Dictionary &known, const Dictionary &chunks, const Rect2i &bounds, int32_t chunk_size) const {
    Array result;
    static const Variant position("pos"), id("id");
    if (chunk_size <= 0 || bounds.size.x <= 0 || bounds.size.y <= 0) { result.make_read_only(); return result; }
    const Vector2i end = bounds.get_end();
    const int first_x = int(std::floor(double(bounds.position.x) / chunk_size));
    const int first_y = int(std::floor(double(bounds.position.y) / chunk_size));
    const int last_x = int(std::floor(double(end.x - 1) / chunk_size));
    const int last_y = int(std::floor(double(end.y - 1) / chunk_size));
    std::vector<std::pair<int64_t, Dictionary>> selected;
    // These are legal last-seen records and their memory index. The live
    // resource/cell indices are deliberately not arguments to this query.
    for (int y = first_y; y <= last_y; ++y) for (int x = first_x; x <= last_x; ++x) {
        const Dictionary bucket = chunks.get(Vector2i(x, y), Dictionary());
        const Array keys = bucket.keys();
        for (int64_t i = 0; i < keys.size(); ++i) {
            const Variant value = known.get(int64_t(keys[i]), Variant());
            if (value.get_type() != Variant::DICTIONARY) continue;
            const Dictionary row = value;
            const Vector2 point = row.get(position, Vector2());
            const int cell_x = int(std::floor(double(point.x))), cell_y = int(std::floor(double(point.y)));
            if (cell_x >= bounds.position.x && cell_x < end.x && cell_y >= bounds.position.y && cell_y < end.y)
                selected.emplace_back(int64_t(row.get(id, -1)), row);
        }
    }
    std::stable_sort(selected.begin(), selected.end(), [](const auto &a, const auto &b) { return a.first < b.first; });
    for (const auto &entry : selected) result.append(entry.second);
    result.make_read_only();
    return result;
}

Dictionary RoRReadModelKernel::diff_resource_records(const Array &previous, const Array &current) const {
    static const Variant id("id"), tags("behavior_tags");
    Dictionary result;
    result["valid"] = false;
    if (!previous.is_read_only() || !current.is_read_only()) return result;
    Array changed, removed;
    int64_t old = 0;
    int64_t last_id = -1;
    for (int64_t i = 0; i < current.size(); ++i) {
        const Dictionary row = current[i];
        if (!row.is_read_only() || (row.has(tags) && (row[tags].get_type() != Variant::ARRAY || !Array(row[tags]).is_read_only()))) return result;
        const int64_t next = row[id];
        if (next <= last_id) return result;
        last_id = next;
        while (old < previous.size() && int64_t(Dictionary(previous[old])[id]) < next) {
            removed.append(Dictionary(previous[old++])[id]);
        }
        if (old < previous.size() && int64_t(Dictionary(previous[old])[id]) == next) {
            if (!UtilityFunctions::is_same(row, previous[old])) changed.append(row);
            ++old;
        } else changed.append(row);
    }
    while (old < previous.size()) removed.append(Dictionary(previous[old++])[id]);
    result["valid"] = true;
    result["changed"] = changed;
    result["removed"] = removed;
    return result;
}

Dictionary RoRReadModelKernel::infrastructure_site_bonuses(const Array &resources, const Array &sites, const String &kind) const {
    std::vector<Vector2> positions;
    for (int64_t i = 0; i < resources.size(); ++i) {
        const Dictionary resource = resources[i];
        if (int64_t(resource.get("amount", 0)) <= 0) continue;
        const Array domains = resource.get("allowed_gatherer_domains", Array());
        if (!domains.is_empty() && !domains.has("land")) continue;
        const int64_t type = resource.get("resource_type_id", -1);
        if ((kind == "granary" && type != 0) || (kind == "storage_pit" && type == 0)) continue;
        positions.push_back(resource.get("pos", Vector2()));
    }
    Dictionary result;
    for (int64_t i = 0; i < sites.size(); ++i) {
        const Vector2 site = sites[i];
        double distance = std::numeric_limits<double>::infinity();
        for (const Vector2 &position : positions) distance = std::min(distance, double(site.distance_to(position)));
        result[site] = std::isfinite(distance) ? distance * 2.0 : 0.0;
    }
    return result;
}

Array RoRReadModelKernel::build_site_ring_cells(const Vector2i &center, int64_t radius, const Vector2i &size, Dictionary seen, const Dictionary &pages) const {
    Array result;
    const auto visit = [&](int x, int y) {
        const Vector2i cell(x, y);
        if (x < 0 || y < 0 || x >= size.x || y >= size.y || seen.has(cell)) return;
        seen[cell] = true;
        const Vector2i key(x / 16, y / 16);
        const PackedByteArray flags = pages.get(key, PackedByteArray());
        if (flags.size() == 256 && flags[(y % 16) * 16 + x % 16] == 2) return;
        result.append(cell);
    };
    for (int r = 1; r <= std::max<int64_t>(1, radius); ++r) {
        for (int y = center.y - r; y <= center.y + r; ++y) {
            if (std::abs(y - center.y) == r) for (int x = center.x - r; x <= center.x + r; ++x) visit(x, y);
            else { visit(center.x - r, y); visit(center.x + r, y); }
        }
    }
    return result;
}

Dictionary RoRReadModelKernel::build_resource_buckets(const Array &resources, const Array &movement_domains, bool unrestricted, bool typed, double cell_size) const {
    static const Variant position_key("pos"), allowed_key("allowed_gatherer_domains"), id_key("id"), type_key("resource_type_id");
    static const Variant resource_key("resource"), order_key("order"), cell_key("cell"), entries_key("entries");
    struct Resource { Dictionary row; Array allowed; Vector2i cell; int64_t id, type; };
    std::vector<Resource> rows;
    for (int64_t i = 0; i < resources.size(); ++i) {
        const Dictionary row = resources[i];
        const Vector2 position = row.get(position_key, Vector2());
        rows.push_back({row, row.get(allowed_key, Array()), Vector2i(std::floor(double(position.x) / cell_size), std::floor(double(position.y) / cell_size)), row.get(id_key, -1), row.get(type_key, -1)});
    }
    std::vector<String> domains;
    for (int64_t i = 0; i < movement_domains.size(); ++i) {
        const String domain = movement_domains[i];
        if (std::find(domains.begin(), domains.end(), domain) == domains.end()) domains.push_back(domain);
    }
    std::sort(domains.begin(), domains.end());
    Dictionary lists, types;
    Array references;
    references.resize(resources.size());
    for (const String &domain : domains) {
        std::map<std::pair<int,int>, std::vector<int64_t>> buckets;
        for (size_t i = 0; i < rows.size(); ++i) {
            const Resource &row = rows[i];
            if (!row.allowed.is_empty() && !row.allowed.has(domain)) continue;
            if (row.allowed.is_empty() && !unrestricted && domain != "land") continue;
            buckets[{row.cell.y, row.cell.x}].push_back(i);
        }
        Array list;
        Dictionary typed_lists;
        for (const auto &bucket : buckets) {
            const Vector2i cell(bucket.first.second, bucket.first.first);
            Array entries;
            Dictionary by_type;
            for (int64_t index : bucket.second) {
                Dictionary entry; entry[resource_key] = rows[index].row; entry[order_key] = index;
                // Most deposits belong to exactly one domain. Avoid allocating
                // an additional Array for every tree solely to hold one entry.
                if (references[index].get_type() == Variant::NIL) references[index] = entry;
                else if (references[index].get_type() == Variant::DICTIONARY) {
                    Array owners; owners.append(references[index]); owners.append(entry); references[index] = owners;
                } else {
                    Array owners = references[index]; owners.append(entry);
                }
                entries.append(entry);
                if (typed) {
                    const int64_t type = rows[index].type;
                    if (!by_type.has(type)) by_type[type] = Array();
                    Array selected = by_type[type]; selected.append(entry);
                }
            }
            Dictionary record; record[cell_key] = cell; record[entries_key] = entries; list.append(record);
            const Array keys = by_type.keys();
            for (int64_t i = 0; i < keys.size(); ++i) {
                const int64_t type = keys[i];
                const Array selected = by_type[type];
                struct Entry { Dictionary row; int64_t id; };
                std::vector<Entry> sorted;
                for (int64_t j = 0; j < selected.size(); ++j) {
                    const Dictionary row = selected[j], resource = row[resource_key];
                    sorted.push_back({row, resource.get(id_key, -1)});
                }
                std::stable_sort(sorted.begin(), sorted.end(), [](const Entry &a, const Entry &b) { return a.id < b.id; });
                Array ordered;
                for (const Entry &entry : sorted) ordered.append(entry.row);
                Dictionary typed_record; typed_record[cell_key] = cell; typed_record[entries_key] = ordered;
                if (!typed_lists.has(type)) typed_lists[type] = Array();
                Array destination = typed_lists[type]; destination.append(typed_record);
            }
        }
        lists[domain] = list;
        if (typed) types[domain] = typed_lists;
    }
    Dictionary result; result["lists"] = lists; result["types"] = types; result["row_references"] = references;
    return result;
}

bool RoRReadModelKernel::refresh_resource_bucket_rows(const Dictionary &index, const Array &previous, const Array &current) const {
    if (previous.size() != current.size() || !index.has("row_references")) return false;
    const Array references = index["row_references"];
    if (references.size() != current.size()) return false;
    static const Variant id("id"), pos("pos"), type("resource_type_id"), domains("allowed_gatherer_domains");
    std::vector<int64_t> changed;
    for (int64_t i = 0; i < current.size(); ++i) {
        const Dictionary old = previous[i], next = current[i];
        // Only immutable shape fields may use identity. Public/mutable inputs
        // always rebuild, including a readonly outer array with mutable rows.
        if (!old.is_read_only() || !next.is_read_only()) return false;
        const Array old_domains = old.get(domains, Array()), next_domains = next.get(domains, Array());
        if ((old.has(domains) && !old_domains.is_read_only()) || (next.has(domains) && !next_domains.is_read_only())) return false;
        if (UtilityFunctions::is_same(old, next)) continue;
        if (old.get(id, -1) != next.get(id, -1) || old.get(pos, Vector2()) != next.get(pos, Vector2()) ||
                old.get(type, -1) != next.get(type, -1) || old_domains != next_domains) return false;
        changed.push_back(i);
    }
    // Apply only after every shape is verified. Both typed and untyped buckets
    // retain the same private entry object; updating it preserves exact order.
    for (int64_t i : changed) {
        if (references[i].get_type() == Variant::DICTIONARY) {
            Dictionary entry = references[i]; entry["resource"] = current[i];
        } else if (references[i].get_type() == Variant::ARRAY) {
            const Array owners = references[i];
            for (int64_t j = 0; j < owners.size(); ++j) {
                Dictionary entry = owners[j]; entry["resource"] = current[i];
            }
        }
    }
    return true;
}

Array RoRReadModelKernel::query_resource_candidates(const Array &buckets, const Vector2 &position, int64_t resource_type, double cell_size, int64_t maximum) const {
    struct Bucket { Vector2i cell; Array entries; double distance; };
    std::vector<Bucket> ordered;
    ordered.reserve(buckets.size());
    for (int64_t i = 0; i < buckets.size(); ++i) {
        const Dictionary bucket = buckets[i];
        const Vector2i cell = bucket["cell"];
        const double x = double(cell.x) * cell_size, y = double(cell.y) * cell_size;
        const double dx = std::max(std::max(x - double(position.x), 0.0), double(position.x) - x - cell_size);
        const double dy = std::max(std::max(y - double(position.y), 0.0), double(position.y) - y - cell_size);
        ordered.push_back({cell, bucket["entries"], dx * dx + dy * dy});
    }
    const size_t count = std::min<size_t>(16, ordered.size());
    std::partial_sort(ordered.begin(), ordered.begin() + count, ordered.end(), [](const Bucket &a, const Bucket &b) {
        if (a.distance != b.distance) return a.distance < b.distance;
        return a.cell.y < b.cell.y || (a.cell.y == b.cell.y && a.cell.x < b.cell.x);
    });
    struct Candidate { Dictionary resource; double distance; int64_t id; };
    std::vector<Candidate> candidates;
    candidates.reserve(count * 64);
    for (size_t i = 0; i < count; ++i) {
        const Array &entries = ordered[i].entries;
        for (int64_t j = 0; j < std::min<int64_t>(64, entries.size()); ++j) {
            const Dictionary entry = entries[j], resource = entry["resource"];
            if (int64_t(resource.get("resource_type_id", -1)) != resource_type) continue;
            const Vector2 target = resource.get("pos", Vector2());
            candidates.push_back({resource, double(position.distance_squared_to(target)), resource.get("id", -1)});
        }
    }
    std::stable_sort(candidates.begin(), candidates.end(), [](const Candidate &a, const Candidate &b) {
        return a.distance != b.distance ? a.distance < b.distance : a.id < b.id;
    });
    Array result;
    const int64_t kept = std::min<int64_t>(std::max<int64_t>(1, maximum), candidates.size());
    result.resize(kept);
    for (int64_t i = 0; i < kept; ++i) result[i] = candidates[i].resource;
    return result;
}

} // namespace godot
