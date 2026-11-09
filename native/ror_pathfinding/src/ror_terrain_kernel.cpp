#include "ror_terrain_kernel.hpp"

#include <algorithm>
#include <array>
#include <cmath>
#include <vector>
#include <limits>

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_color_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>

namespace godot {
namespace {
constexpr int MATERIAL_STRIDE = 7; // priority, water, imported, atlas x/y/width/height
// Mesh.ArrayType from the pinned 4.7 API. Mesh is deliberately absent from
// this CPU-only extension's generated class profile.
enum MeshArray { ARRAY_VERTEX = 0, ARRAY_COLOR = 3, ARRAY_TEX_UV = 4, ARRAY_INDEX = 12, ARRAY_MAX = 13 };
struct Weights {
    std::array<int, 12> ids{};
    std::array<double, 12> values{};
    int count = 0;
    void add(int id, double value) {
        for (int i = 0; i < count; ++i) {
            if (ids[i] == id) { values[i] += value; return; }
        }
        ids[count] = id;
        values[count++] = value;
    }
    double get(int id) const {
        for (int i = 0; i < count; ++i) if (ids[i] == id) return values[i];
        return 0.0;
    }
};
double smooth(double start, double end, double value) {
    const double t = std::clamp((value - start) / (end - start), 0.0, 1.0);
    return t * t * (3.0 - 2.0 * t);
}
int positive_mod(int64_t value, int divisor) {
    return static_cast<int>((value % divisor + divisor) % divisor);
}
template<class Packed, class Value>
Packed pack(const std::vector<Value> &values) {
    Packed result;
    result.resize(static_cast<int64_t>(values.size()));
    if (!values.empty()) std::copy(values.begin(), values.end(), result.ptrw());
    return result;
}
}

void RoRTerrainKernel::_bind_methods() {
    ClassDB::bind_method(D_METHOD("supports_planar_base_compaction"), &RoRTerrainKernel::supports_planar_base_compaction);
    ClassDB::bind_method(D_METHOD("build_mesh", "bounds", "cells", "heights", "frames", "materials", "seed", "maximum_subdivisions", "river", "compact_planar_base"), &RoRTerrainKernel::build_mesh, DEFVAL(16), DEFVAL(PackedFloat32Array()), DEFVAL(true));
    ClassDB::bind_method(D_METHOD("split_mesh_arrays", "arrays", "maximum_vertices"), &RoRTerrainKernel::split_mesh_arrays, DEFVAL(16384));
    ClassDB::bind_method(D_METHOD("capture_cached_sample_arrays", "bounds", "cache"), &RoRTerrainKernel::capture_cached_sample_arrays);
    ClassDB::bind_method(D_METHOD("build_fog_arrays", "bounds", "size", "levels"), &RoRTerrainKernel::build_fog_arrays);
    ClassDB::bind_method(D_METHOD("capture_river_samples", "bounds", "shape"), &RoRTerrainKernel::capture_river_samples);
}

PackedFloat32Array RoRTerrainKernel::capture_river_samples(const Rect2i &bounds, const Dictionary &shape) const {
    PackedFloat32Array result;
    // The renderer samples at half-cell coordinates, exactly on the existing
    // resolution-two field. Copy those samples; no interpolation or map scan.
    if (bounds.size.x <= 0 || bounds.size.y <= 0 || int64_t(shape.get("resolution", 0)) != 2 ||
        shape.get("size", Variant()).get_type() != Variant::VECTOR2I ||
        shape.get("samples", Variant()).get_type() != Variant::PACKED_FLOAT32_ARRAY) return result;
    const Vector2i size = shape["size"];
    const PackedFloat32Array samples = shape["samples"];
    const int64_t width = int64_t(bounds.size.x) * 2 + 1, height = int64_t(bounds.size.y) * 2 + 1;
    if (size.x <= 0 || size.y <= 0 || samples.size() != int64_t(size.x) * size.y * 4 ||
        width > 32768 || height > 32768 || width * height > 4194304) return result;
    result.resize(width * height * 4);
    const float *source = samples.ptr();
    float *destination = result.ptrw();
    const int64_t first_x = int64_t(bounds.position.x) * 2, first_y = int64_t(bounds.position.y) * 2;
    for (int64_t y = 0; y < height; ++y) {
        const int64_t source_y = std::clamp<int64_t>(first_y + y, 0, size.y - 1);
        float *row = destination + y * width * 4;
        if (first_x >= 0 && first_x + width <= size.x) {
            std::copy_n(source + (source_y * size.x + first_x) * 4, width * 4, row);
        } else {
            for (int64_t x = 0; x < width; ++x) {
                const int64_t source_x = std::clamp<int64_t>(first_x + x, 0, size.x - 1);
                std::copy_n(source + (source_y * size.x + source_x) * 4, 4, row + x * 4);
            }
        }
    }
    return result;
}

Array RoRTerrainKernel::split_mesh_arrays(const Array &arrays, int32_t maximum_vertices) const {
    Array result;
    if (arrays.size() != ARRAY_MAX || arrays[ARRAY_VERTEX].get_type() != Variant::PACKED_VECTOR3_ARRAY ||
        arrays[ARRAY_TEX_UV].get_type() != Variant::PACKED_VECTOR2_ARRAY ||
        arrays[ARRAY_COLOR].get_type() != Variant::PACKED_COLOR_ARRAY ||
        arrays[ARRAY_INDEX].get_type() != Variant::PACKED_INT32_ARRAY) return result;
    const PackedVector3Array source_vertices = arrays[ARRAY_VERTEX];
    const PackedVector2Array source_uvs = arrays[ARRAY_TEX_UV];
    const PackedColorArray source_colors = arrays[ARRAY_COLOR];
    const PackedInt32Array source_indices = arrays[ARRAY_INDEX];
    if (source_vertices.is_empty() || source_indices.is_empty() || source_indices.size() % 3 ||
        source_uvs.size() != source_vertices.size() || source_colors.size() != source_vertices.size()) return result;
    const int limit = std::clamp(maximum_vertices, 3, 65536);
    const auto *positions = source_vertices.ptr();
    const auto *uvs = source_uvs.ptr();
    const auto *colors = source_colors.ptr();
    const auto *indices = source_indices.ptr();
    for (int64_t i = 0; i < source_indices.size(); ++i) {
        if (indices[i] < 0 || indices[i] >= source_vertices.size()) return Array();
    }
    if (source_vertices.size() <= limit) { result.append(arrays); return result; }
    std::vector<int32_t> remap(source_vertices.size(), -1), originals, local_indices;
    std::vector<Vector3> local_vertices;
    std::vector<Vector2> local_uvs;
    std::vector<Color> local_colors;
    originals.reserve(limit); local_vertices.reserve(limit); local_uvs.reserve(limit); local_colors.reserve(limit);
    auto flush = [&]() {
        if (local_indices.empty()) return;
        Array chunk;
        chunk.resize(ARRAY_MAX);
        chunk[ARRAY_VERTEX] = pack<PackedVector3Array>(local_vertices);
        chunk[ARRAY_TEX_UV] = pack<PackedVector2Array>(local_uvs);
        chunk[ARRAY_COLOR] = pack<PackedColorArray>(local_colors);
        chunk[ARRAY_INDEX] = pack<PackedInt32Array>(local_indices);
        result.append(chunk);
        for (auto original : originals) remap[original] = -1;
        originals.clear(); local_vertices.clear(); local_uvs.clear(); local_colors.clear(); local_indices.clear();
    };
    // Keep triangle order and exact attribute values, duplicating only vertices
    // shared by neighbouring chunks. No GPU or scene object is touched here.
    for (int64_t i = 0; i < source_indices.size(); i += 3) {
        int needed = 0;
        for (int corner = 0; corner < 3; ++corner) needed += remap[indices[i + corner]] < 0;
        if (local_vertices.size() + needed > size_t(limit)) flush();
        for (int corner = 0; corner < 3; ++corner) {
            const int original = indices[i + corner];
            if (remap[original] < 0) {
                remap[original] = int32_t(local_vertices.size());
                originals.push_back(original);
                local_vertices.push_back(positions[original]); local_uvs.push_back(uvs[original]); local_colors.push_back(colors[original]);
            }
            local_indices.push_back(remap[original]);
        }
    }
    flush();
    return result;
}

Dictionary RoRTerrainKernel::build_mesh(const Rect2i &bounds, const PackedInt32Array &cells,
        const PackedFloat32Array &heights, const PackedInt32Array &frames,
        const PackedFloat32Array &materials, int64_t seed, int32_t maximum_subdivisions,
        const PackedFloat32Array &river, bool compact_planar_base) const {
    Dictionary result;
    const int width = bounds.size.x;
    const int height = bounds.size.y;
    const int64_t area = static_cast<int64_t>(width) * height;
    if (width <= 0 || height <= 0 || width > 1024 || height > 1024 || area > 1048576 ||
        cells.size() != static_cast<int64_t>(width + 2) * (height + 2) ||
        heights.size() != static_cast<int64_t>(width + 1) * (height + 1) ||
        frames.size() != area || materials.is_empty() || materials.size() % MATERIAL_STRIDE != 0) return result;
    const int material_count = static_cast<int>(materials.size() / MATERIAL_STRIDE);
    const int32_t *cell_data = cells.ptr();
    const float *height_data = heights.ptr();
    const int32_t *frame_data = frames.ptr();
    const float *material_data = materials.ptr();
    for (int64_t i = 0; i < cells.size(); ++i) if (cell_data[i] < -1 || cell_data[i] >= material_count) return result;
    for (int64_t i = 0; i < heights.size(); ++i) if (!std::isfinite(height_data[i])) return result;
    for (int64_t i = 0; i < materials.size(); ++i) if (!std::isfinite(material_data[i])) return result;
    const int river_width = width * 2 + 1, river_height = height * 2 + 1;
    const bool has_river = !river.is_empty();
    const int river_header = 6;
    if (has_river && river.size() != river_header + int64_t(river_width) * river_height * 4) return result;
    const float *river_data = river.ptr();
    if (has_river) {
        for (int64_t i = 0; i < river.size(); ++i) if (!std::isfinite(river_data[i])) return result;
        for (int i = 0; i < river_header; ++i) if (river_data[i] < 0 || river_data[i] >= material_count || river_data[i] != int(river_data[i])) return result;
        for (int64_t i = river_header; i < river.size(); i += 4) if (river_data[i + 1] < 0 || river_data[i + 1] > 1 || river_data[i + 2] < -0.5 || river_data[i + 2] > 3 || river_data[i + 3] < 0 || river_data[i + 3] > 1) return result;
    }
    auto river_at = [&](const Vector2 &point) {
        const Vector2 local = (point - Vector2(bounds.position)) * 2.0;
        const int ox = std::clamp(int(std::floor(local.x)), 0, river_width - 1);
        const int oy = std::clamp(int(std::floor(local.y)), 0, river_height - 1);
        const int nx = std::min(ox + 1, river_width - 1), ny = std::min(oy + 1, river_height - 1);
        const double fx = local.x - ox, fy = local.y - oy;
        std::array<double, 4> field;
        for (int i = 0; i < 4; ++i) {
            const double a = river_data[river_header + (oy * river_width + ox) * 4 + i];
            const double b = river_data[river_header + (oy * river_width + nx) * 4 + i];
            const double c = river_data[river_header + (ny * river_width + ox) * 4 + i];
            const double d = river_data[river_header + (ny * river_width + nx) * 4 + i];
            field[i] = (a + (b - a) * fx) + ((c + (d - c) * fx) - (a + (b - a) * fx)) * fy;
        }
        return field;
    };
    auto cell_at = [&](int x, int y) {
        const int lx = x - bounds.position.x + 1;
        const int ly = y - bounds.position.y + 1;
        if (lx < 0 || ly < 0 || lx >= width + 2 || ly >= height + 2) return -1;
        return static_cast<int>(cell_data[ly * (width + 2) + lx]);
    };
    auto water = [&](int id) { return material_data[id * MATERIAL_STRIDE + 1] != 0.0f; };
    auto sample_weights = [&](const Vector2 &point, int fallback) {
        // Match the float Vector2 perturbation and double scalar interpolation
        // of the reference, including map-edge renormalization and the coast contour.
        const Vector2 bend = Vector2(std::sin(point.y * 7.1 + std::sin(point.x * 3.7)),
            std::cos(point.x * 6.3 + std::sin(point.y * 4.1))) * 0.035;
        const Vector2 sample = point + bend - Vector2(0.5, 0.5);
        const int ox = static_cast<int>(std::floor(sample.x));
        const int oy = static_cast<int>(std::floor(sample.y));
        const Vector2 linear = sample - Vector2(ox, oy);
        const Vector2 fraction(smooth(0.30, 0.70, linear.x), smooth(0.30, 0.70, linear.y));
        Weights weights;
        double linear_land = 0.0, linear_total = 0.0, land_sum = 0.0, water_sum = 0.0;
        for (int y = 0; y < 2; ++y) for (int x = 0; x < 2; ++x) {
            const int id = cell_at(ox + x, oy + y);
            if (id < 0) continue;
            const double value = (x ? static_cast<double>(fraction.x) : 1.0 - fraction.x) *
                (y ? static_cast<double>(fraction.y) : 1.0 - fraction.y);
            const double linear_value = (x ? static_cast<double>(linear.x) : 1.0 - linear.x) *
                (y ? static_cast<double>(linear.y) : 1.0 - linear.y);
            linear_total += linear_value;
            if (water(id)) water_sum += value;
            else { land_sum += value; linear_land += linear_value; }
            weights.add(id, value);
        }
        if (land_sum + water_sum < 0.000001) { weights = Weights(); weights.add(fallback, 1.0); return weights; }
        const double coverage = land_sum > 0.0 && water_sum > 0.0 ?
            smooth(0.495, 0.535, linear_land / std::max(linear_total, 0.000001)) : (land_sum > 0.0 ? 1.0 : 0.0);
        for (int i = 0; i < weights.count; ++i) {
            weights.values[i] *= water(weights.ids[i]) ? (water_sum > 0.0 ? (1.0 - coverage) / water_sum : 0.0) :
                (land_sum > 0.0 ? coverage / land_sum : 0.0);
        }
        if (has_river) {
            const auto field = river_at(point);
            if (field[1] > 0.0) {
                double land = 0.0;
                for (int i=0;i<weights.count;++i) if(!water(weights.ids[i])) land+=weights.values[i];
                const double influence=field[1];
                const double wet=smooth(-0.08,0.10,field[0])*smooth(-0.035,0.10,field[2]);
                const double target_land=land+(1.0-wet-land)*influence,target_water=1.0-target_land;
                const double exposed=target_land*influence*smooth(-0.8,0.1,field[0]);
                const double edge=target_land*influence*(1.0-smooth(0.15,0.8,-field[0]))*0.65;
                const double bed_land=std::max(exposed,edge),gravel=std::clamp(field[3],0.0,1.0);
                for(int i=0;i<weights.count;++i)weights.values[i]*= !water(weights.ids[i])&&land>0?(target_land-bed_land)/land:0;
                if(land<=0)weights.add(int(river_data[0]),target_land-bed_land);
                weights.add(int(river_data[1]),bed_land*(1.0-gravel));
                weights.add(int(river_data[4]),bed_land*gravel);
                const double shallow=target_water*influence*(1.0-smooth(0.10,0.95,field[2]))*0.85;
                const double deep=target_water*influence*smooth(0.95,1.65,field[2])*0.55;
                weights.add(int(river_data[2]),target_water-shallow-deep);
                weights.add(int(river_data[3]),shallow);
                weights.add(int(river_data[5]),deep);
            }
        }
        return weights;
    };
    std::vector<Vector3> vertices;
    std::vector<Vector2> uvs;
    std::vector<Color> colors;
    std::vector<int32_t> indices;
    vertices.reserve(static_cast<size_t>(area) * 8);
    uvs.reserve(static_cast<size_t>(area) * 8);
    colors.reserve(static_cast<size_t>(area) * 8);
    indices.reserve(static_cast<size_t>(area) * 12);
    const Vector2 phase(positive_mod(seed, 10), positive_mod(seed / 10, 10));
    int64_t unchanged_river_land_cells = 0;
    int64_t potential_vertices = 0, discarded_transparent_triangles = 0;
    int64_t planar_base_cells = 0, planar_base_triangles_saved = 0;
    for (int cy = 0; cy < height; ++cy) for (int cx = 0; cx < width; ++cx) {
        const int wx = bounds.position.x + cx, wy = bounds.position.y + cy;
        const int center = cell_at(wx, wy);
        if (center < 0) continue;
        const int hp = cy * (width + 1) + cx;
        const std::array<double, 4> h = {height_data[hp], height_data[hp + 1], height_data[hp + width + 2], height_data[hp + width + 1]};
        bool uniform = h[0] == h[1] && h[0] == h[2] && h[0] == h[3];
        bool coast = false;
        for (int dy = -1; dy <= 1; ++dy) for (int dx = -1; dx <= 1; ++dx) {
            const int neighbor = cell_at(wx + dx, wy + dy);
            if (neighbor >= 0 && neighbor != center) {
                uniform = false;
                if (water(neighbor) != water(center)) coast = true;
            }
        }
        if (has_river) {
            bool influenced = false;
            bool unchanged_land = uniform && !water(center);
            for (int y = 0; y < 3; ++y) for (int x = 0; x < 3; ++x) {
                const float *field = river_data + river_header + ((cy * 2 + y) * river_width + cx * 2 + x) * 4;
                influenced |= field[1] > 0;
                // Bilinear interpolation stays below the maximum of these
                // nine field samples. On uniform land at distance <= -0.8,
                // wet, exposed and edge are all zero: every generated vertex
                // has exactly the original material, height and lighting.
                unchanged_land &= field[0] <= -0.8;
            }
            if (influenced) {
                if (unchanged_land) ++unchanged_river_land_cells;
                else { uniform = false; coast = true; }
            }
        }
        // The preview budget may simplify soil blends, but the land/water
        // contour must stay identical when the asynchronous mesh is published.
        const int n = uniform ? 1 : coast ? 16 : std::min(8, std::clamp(maximum_subdivisions, 1, 16));
        const int count = (n + 1) * (n + 1);
        std::array<Weights, 289> weights;
        std::array<Vector2, 289> local;
        std::array<Vector3, 289> points;
        std::array<float, 289> lighting;
        std::array<float, 289> accumulated{};
        std::vector<int> ids;
        ids.reserve(9);
        for (int y = 0; y <= n; ++y) for (int x = 0; x <= n; ++x) {
            const int i = y * (n + 1) + x;
            const Vector2 uv(static_cast<double>(x) / n, static_cast<double>(y) / n);
            const Vector2 world = Vector2(wx, wy) + uv;
            local[i] = uv;
            if (uniform) weights[i].add(center, 1.0); else weights[i] = sample_weights(world, center);
            for (int k = 0; k < weights[i].count; ++k) {
                const int id = weights[i].ids[k];
                if (weights[i].values[k] > 0.00001 && std::find(ids.begin(), ids.end(), id) == ids.end()) ids.push_back(id);
            }
            const double top = h[0] + (h[1] - h[0]) * uv.x;
            const double bottom = h[3] + (h[2] - h[3]) * uv.x;
            const double elevation = top + (bottom - top) * uv.y;
            const Vector2 screen = Vector2((world.x - world.y) * 32.0, (world.x + world.y) * 16.0) + Vector2(0.0, -elevation * 16.0);
            points[i] = Vector3(screen.x, screen.y, 0.0);
            const double dx = (h[1] - h[0]) + ((h[2] - h[3]) - (h[1] - h[0])) * uv.y;
            const double dy = (h[3] - h[0]) + ((h[2] - h[1]) - (h[3] - h[0])) * uv.x;
            lighting[i] = static_cast<float>(std::clamp(1.0 - dx * 0.11 - dy * 0.06, 0.8, 1.16));
        }
        std::stable_sort(ids.begin(), ids.end(), [&](int a, int b) {
            const float pa = material_data[a * MATERIAL_STRIDE], pb = material_data[b * MATERIAL_STRIDE];
            return pa == pb ? a < b : pa < pb;
        });
        const int frame = positive_mod(frame_data[cy * width + cx], 9);
        bool first_layer = true;
        for (const int id : ids) {
            const float *m = material_data + id * MATERIAL_STRIDE;
            potential_vertices += count;
            std::array<float, 289> alphas;
            std::array<int32_t, 289> remap;
            remap.fill(-1);
            for (int i = 0; i < count; ++i) {
                const double weight = weights[i].get(id);
                accumulated[i] += weight;
                alphas[i] = static_cast<float>(first_layer ? 1.0 : (accumulated[i] > 0.00001 ? weight / accumulated[i] : 0.0));
            }
            const auto vertex = [&](int i) {
                if (remap[i] >= 0) return remap[i];
                const int32_t output = static_cast<int32_t>(vertices.size());
                remap[i] = output;
                vertices.push_back(points[i]);
                Vector2 uv;
                if (m[2] != 0.0f) {
                    const Vector2 pixel = (Vector2(positive_mod(wx + static_cast<int>(phase.x), 10), positive_mod(wy + static_cast<int>(phase.y), 10)) + local[i]) * 32.0;
                    uv = Vector2(std::clamp(pixel.x, 0.5f, 319.5f), std::clamp(pixel.y, 0.5f, 319.5f)) / 320.0;
                } else {
                    const Vector2 pixel = local[i] * 32.0;
                    uv = (Vector2(frame % 3, frame / 3) * 32.0 + Vector2(std::clamp(pixel.x, 0.5f, 31.5f), std::clamp(pixel.y, 0.5f, 31.5f))) / 96.0;
                }
                uvs.push_back(Vector2(m[3], m[4]) + uv * Vector2(m[5], m[6]));
                colors.emplace_back(lighting[i], lighting[i], lighting[i], alphas[i]);
                return output;
            };
            const auto triangle = [&](int a, int b, int c) {
                // Canvas terrain uses ordinary alpha blending and no depth
                // writes. Exactly zero alpha at every vertex contributes no
                // pixel. Keep every nonzero triangle and its original order.
                if (alphas[a] == 0.0f && alphas[b] == 0.0f && alphas[c] == 0.0f) {
                    ++discarded_transparent_triangles;
                    return;
                }
                const int32_t ia = vertex(a), ib = vertex(b), ic = vertex(c);
                indices.push_back(ia); indices.push_back(ib); indices.push_back(ic);
            };
            if (compact_planar_base && first_layer && n > 1 && h[0] + h[2] == h[1] + h[3]) {
                // This opaque layer has constant lighting on an affine plane.
                // UV is affine too, except at the original texture-clamp edge
                // intervals. Retain those first/last grid intervals exactly.
                // The blended overlays keep every original vertex/triangle.
                const bool imported = m[2] != 0.0f;
                const int texture_x = positive_mod(wx + static_cast<int>(phase.x), 10);
                const int texture_y = positive_mod(wy + static_cast<int>(phase.y), 10);
                const auto knots = [&](bool low, bool high) {
                    std::vector<int> result{0};
                    if (low && n > 1) result.push_back(1);
                    if (high && n - 1 > result.back()) result.push_back(n - 1);
                    result.push_back(n);
                    return result;
                };
                const auto xs = knots(!imported || texture_x == 0, !imported || texture_x == 9);
                const auto ys = knots(!imported || texture_y == 0, !imported || texture_y == 9);
                for (size_t y = 0; y + 1 < ys.size(); ++y) for (size_t x = 0; x + 1 < xs.size(); ++x) {
                    const int a = ys[y] * (n + 1) + xs[x], b = ys[y] * (n + 1) + xs[x + 1];
                    const int c = ys[y + 1] * (n + 1) + xs[x + 1], d = ys[y + 1] * (n + 1) + xs[x];
                    triangle(a, b, c); triangle(a, c, d);
                }
                ++planar_base_cells;
                planar_base_triangles_saved += int64_t(2) * (n * n - (xs.size() - 1) * (ys.size() - 1));
            } else {
                for (int y = 0; y < n; ++y) for (int x = 0; x < n; ++x) {
                    const int i = y * (n + 1) + x;
                    triangle(i, i + 1, i + n + 2);
                    triangle(i, i + n + 2, i + n + 1);
                }
            }
            first_layer = false;
        }
    }
    result["vertices"] = pack<PackedVector3Array>(vertices);
    result["uvs"] = pack<PackedVector2Array>(uvs);
    result["colors"] = pack<PackedColorArray>(colors);
    result["indices"] = pack<PackedInt32Array>(indices);
    result["unchanged_river_land_cells"] = unchanged_river_land_cells;
    result["discarded_transparent_triangles"] = discarded_transparent_triangles;
    result["avoided_vertices"] = potential_vertices - int64_t(vertices.size());
    result["planar_base_cells"] = planar_base_cells;
    result["planar_base_triangles_saved"] = planar_base_triangles_saved;
    return result;
}

Dictionary RoRTerrainKernel::capture_cached_sample_arrays(const Rect2i &bounds, const Dictionary &cache) const {
    Dictionary result;
    const int64_t w = bounds.size.x, h = bounds.size.y;
    if (w <= 0 || h <= 0 || (w + 2) * (h + 2) > std::numeric_limits<int32_t>::max()) return result;
    const Variant old_bounds_value = cache.get("bounds", Variant());
    const Rect2i old_bounds = old_bounds_value.get_type() == Variant::RECT2I ? Rect2i(old_bounds_value) : Rect2i();
    const Variant old_cells_value = cache.get("cells", Variant()), old_heights_value = cache.get("heights", Variant()), old_frames_value = cache.get("frames", Variant());
    const PackedInt32Array old_cells = old_cells_value.get_type() == Variant::PACKED_INT32_ARRAY ? PackedInt32Array(old_cells_value) : PackedInt32Array();
    const PackedFloat32Array old_heights = old_heights_value.get_type() == Variant::PACKED_FLOAT32_ARRAY ? PackedFloat32Array(old_heights_value) : PackedFloat32Array();
    const PackedInt32Array old_frames = old_frames_value.get_type() == Variant::PACKED_INT32_ARRAY ? PackedInt32Array(old_frames_value) : PackedInt32Array();
    const int64_t ow = old_bounds.size.x, oh = old_bounds.size.y;
    const bool cell_cache = ow > 0 && oh > 0 && old_cells.size() == (ow+2)*(oh+2);
    const bool height_cache = ow > 0 && oh > 0 && old_heights.size() == (ow+1)*(oh+1);
    const bool frame_cache = ow > 0 && oh > 0 && old_frames.size() == ow*oh;
    const Rect2i old_cell_bounds = old_bounds.grow(1), old_height_bounds(old_bounds.position, old_bounds.size+Vector2i(1,1));
    const int32_t *oc = cell_cache ? old_cells.ptr() : nullptr, *of = frame_cache ? old_frames.ptr() : nullptr;
    const float *ov = height_cache ? old_heights.ptr() : nullptr;
    PackedInt32Array cells, frames; PackedFloat32Array heights;
    cells.resize((w+2)*(h+2)); heights.resize((w+1)*(h+1)); frames.resize(w*h);
    int32_t *c = cells.ptrw(), *f = frames.ptrw(); float *v = heights.ptrw();
    Array missing_cells, missing_heights, missing_frames;
    int64_t index = 0;
    for (int64_t y=bounds.position.y-1; y<int64_t(bounds.position.y)+h+1; ++y) for (int64_t x=bounds.position.x-1; x<int64_t(bounds.position.x)+w+1; ++x) {
        const Vector2i point(x,y);
        const int32_t value = oc && old_cell_bounds.has_point(point) ? oc[(y-old_bounds.position.y+1)*(ow+2)+x-old_bounds.position.x+1] : -2;
        c[index++] = value; if (value == -2) missing_cells.append(point);
    }
    index = 0;
    for (int64_t y=bounds.position.y; y<=int64_t(bounds.position.y)+h; ++y) for (int64_t x=bounds.position.x; x<=int64_t(bounds.position.x)+w; ++x) {
        const Vector2i point(x,y); const bool known = ov && old_height_bounds.has_point(point);
        v[index++] = known ? ov[(y-old_bounds.position.y)*(ow+1)+x-old_bounds.position.x] : 0.0f;
        if (!known) missing_heights.append(point);
    }
    index = 0;
    for (int64_t y=bounds.position.y; y<int64_t(bounds.position.y)+h; ++y) for (int64_t x=bounds.position.x; x<int64_t(bounds.position.x)+w; ++x) {
        const Vector2i point(x,y);
        const int32_t value = of && old_bounds.has_point(point) ? of[(y-old_bounds.position.y)*ow+x-old_bounds.position.x] : -1;
        f[index++] = value; if (value < 0) missing_frames.append(point);
    }
    result["cells"] = cells; result["heights"] = heights; result["frames"] = frames;
    result["missing_cells"] = missing_cells; result["missing_heights"] = missing_heights; result["missing_frames"] = missing_frames;
    return result;
}

Array RoRTerrainKernel::build_fog_arrays(const Rect2i &bounds, const Vector2i &size, const Dictionary &levels) const {
    Array result;
    const int64_t w = bounds.size.x, h = bounds.size.y;
    if (w <= 0 || h <= 0 || size.x <= 0 || size.y <= 0 || (w + 1) * (h + 1) > std::numeric_limits<int32_t>::max() || w * h > std::numeric_limits<int32_t>::max() / 6) return result;
    PackedVector3Array vertices; PackedVector2Array uvs; PackedInt32Array indices;
    vertices.resize((w + 1) * (h + 1)); uvs.resize(vertices.size()); indices.resize(w * h * 6);
    Vector3 *v = vertices.ptrw(); Vector2 *uv = uvs.ptrw(); int32_t *idx = indices.ptrw();
    for (int64_t y = 0; y <= h; ++y) {
        for (int64_t x = 0; x <= w; ++x) {
            const Vector2 world(bounds.position.x + x, bounds.position.y + y);
            const Vector2 clamped(std::clamp(double(world.x), 0.0, double(size.x) - 0.0001), std::clamp(double(world.y), 0.0, double(size.y) - 0.0001));
            const Vector2i cell(int32_t(std::floor(clamped.x)), int32_t(std::floor(clamped.y)));
            const Vector2 local = clamped - Vector2(cell);
            const double a = int64_t(levels.get(cell, 0)), b = int64_t(levels.get(cell + Vector2i(1,0), 0));
            const double c = int64_t(levels.get(cell + Vector2i(0,1), 0)), d = int64_t(levels.get(cell + Vector2i(1,1), 0));
            const double top = a + (b - a) * double(local.x), bottom = c + (d - c) * double(local.x);
            const double elevation = top + (bottom - top) * double(local.y);
            const Vector2 projected = Vector2((world.x - world.y) * 32.0, (world.x + world.y) * 16.0) + Vector2(0.0, -elevation * 16.0);
            const int64_t index = y * (w + 1) + x;
            v[index] = Vector3(std::round(projected.x), std::round(projected.y), 0.0);
            uv[index] = Vector2(std::clamp(double(world.x)/size.x, 0.5/size.x, 1.0-0.5/size.x), std::clamp(double(world.y)/size.y, 0.5/size.y, 1.0-0.5/size.y));
        }
    }
    int64_t cursor = 0;
    for (int64_t y = 0; y < h; ++y) {
        for (int64_t x = 0; x < w; ++x) {
            const int32_t tl = int32_t(y * (w + 1) + x), tr = tl + 1, bl = tl + int32_t(w + 1), br = bl + 1;
            idx[cursor++] = tl; idx[cursor++] = tr; idx[cursor++] = br;
            idx[cursor++] = tl; idx[cursor++] = br; idx[cursor++] = bl;
        }
    }
    result.resize(ARRAY_MAX); result[ARRAY_VERTEX] = vertices; result[ARRAY_TEX_UV] = uvs; result[ARRAY_INDEX] = indices;
    return result;
}

} // namespace godot
