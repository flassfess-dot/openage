#include "ror_terrain_kernel.hpp"

#include <algorithm>
#include <array>
#include <cmath>
#include <vector>

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_color_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>

namespace godot {
namespace {
constexpr int MATERIAL_STRIDE = 7; // priority, water, imported, atlas x/y/width/height
struct Weights {
    std::array<int, 4> ids{};
    std::array<double, 4> values{};
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
    ClassDB::bind_method(D_METHOD("build_mesh", "bounds", "cells", "heights", "frames", "materials", "seed", "maximum_subdivisions"), &RoRTerrainKernel::build_mesh, DEFVAL(16));
}

Dictionary RoRTerrainKernel::build_mesh(const Rect2i &bounds, const PackedInt32Array &cells,
        const PackedFloat32Array &heights, const PackedInt32Array &frames,
        const PackedFloat32Array &materials, int64_t seed, int32_t maximum_subdivisions) const {
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
        const int n = uniform ? 1 : std::min(coast ? 16 : 8, std::clamp(maximum_subdivisions, 1, 16));
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
            const int32_t first = static_cast<int32_t>(vertices.size());
            for (int i = 0; i < count; ++i) {
                const double weight = weights[i].get(id);
                accumulated[i] += weight;
                const double alpha = first_layer ? 1.0 : (accumulated[i] > 0.00001 ? weight / accumulated[i] : 0.0);
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
                colors.emplace_back(lighting[i], lighting[i], lighting[i], alpha);
            }
            for (int y = 0; y < n; ++y) for (int x = 0; x < n; ++x) {
                const int32_t p = first + y * (n + 1) + x;
                const int32_t triangle[6] = {p, p + 1, p + n + 2, p, p + n + 2, p + n + 1};
                indices.insert(indices.end(), triangle, triangle + 6);
            }
            first_layer = false;
        }
    }
    result["vertices"] = pack<PackedVector3Array>(vertices);
    result["uvs"] = pack<PackedVector2Array>(uvs);
    result["colors"] = pack<PackedColorArray>(colors);
    result["indices"] = pack<PackedInt32Array>(indices);
    return result;
}
} // namespace godot
