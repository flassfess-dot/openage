#include "ror_read_model_kernel.hpp"
#include <godot_cpp/classes/rendering_server.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <godot_cpp/variant/transform2d.hpp>
#include <cmath>

namespace godot {

RoRReadModelKernel::~RoRReadModelKernel() {
    if (selection_meshes.empty() && shadow_meshes.empty()) return;
    RenderingServer *server = RenderingServer::get_singleton();
    if (!server) return;
    for (const SelectionMesh &entry : selection_meshes) server->free_rid(entry.mesh);
    for (const auto &entry : shadow_meshes) server->free_rid(entry.second);
}

bool RoRReadModelKernel::submit_cached_shadow(const RID &canvas, const Vector2 &center, float radius,
        const Color &color) const {
    RenderingServer *server = RenderingServer::get_singleton();
    if (!server || !std::isfinite(radius) || radius <= 0.0f) return false;
    auto found = shadow_meshes.find(radius);
    if (found == shadow_meshes.end()) {
        if (shadow_meshes.size() >= 128) return false;
        // Match Godot 4.7's filled, non-antialiased ellipse. Store the circle
        // at its actual radius so the canvas applies the same vertical scale.
        constexpr int segments = 64;
        constexpr int center_index = segments + 1;
        PackedVector3Array vertices;
        PackedInt32Array indices;
        vertices.resize(segments + 2);
        indices.resize(segments * 3);
        Vector3 *points = vertices.ptrw();
        int32_t *triangles = indices.ptrw();
        const real_t step = real_t(6.283185307179586476925286766559 / segments);
        for (int i = 0; i <= segments; ++i) {
            const float angle = i * step;
            points[i] = Vector3(std::cos(angle) * radius, std::sin(angle) * radius, 0);
        }
        points[center_index] = Vector3();
        for (int i = 0; i < segments; ++i) {
            triangles[3 * i] = center_index;
            triangles[3 * i + 1] = i;
            triangles[3 * i + 2] = i + 1;
        }
        Array arrays;
        arrays.resize(RenderingServer::ARRAY_MAX);
        arrays[RenderingServer::ARRAY_VERTEX] = vertices;
        arrays[RenderingServer::ARRAY_INDEX] = indices;
        const RID mesh = server->mesh_create();
        server->mesh_add_surface_from_arrays(mesh, RenderingServer::PRIMITIVE_TRIANGLES, arrays);
        found = shadow_meshes.emplace(radius, mesh).first;
    }
    server->canvas_item_add_mesh(canvas, found->second, Transform2D(0.0, Vector2(1.0, 0.42), 0.0, center), color);
    ++shadow_mesh_draws;
    return true;
}

Dictionary RoRReadModelKernel::selection_mesh_stats() const {
    Dictionary result;
    result["enabled"] = selection_meshes_enabled;
    result["entries"] = int64_t(selection_meshes.size());
    result["hits"] = selection_mesh_hits;
    result["builds"] = selection_mesh_builds;
    result["fallbacks"] = selection_mesh_fallbacks;
    return result;
}

bool RoRReadModelKernel::submit_cached_selection_mesh(const RID &canvas, const Vector2 &center,
        const Color &color, const Vector2 &radius) const {
    RenderingServer *server = RenderingServer::get_singleton();
    if (!server) return false;
    for (const SelectionMesh &entry : selection_meshes) {
        if (entry.radius != radius) continue;
        ++selection_mesh_hits;
        server->canvas_item_add_mesh(canvas, entry.mesh, Transform2D(0, center), color);
        return true;
    }
    // Bound memory without freeing RIDs that a queued canvas command may use.
    // Unusual/tiny rings and excess zoom variants keep the scalar renderer.
    if (selection_meshes.size() >= 128 || !std::isfinite(radius.x) || !std::isfinite(radius.y) ||
            radius.x < 2.0 || radius.y < 2.0 || radius.x > 4096.0 || radius.y > 4096.0) {
        ++selection_mesh_fallbacks;
        return false;
    }
    constexpr int count = 32;
    constexpr double tau = 6.283185307179586476925286766559;
    Vector2 points[count];
    for (int i = 0; i < count; ++i) {
        const double angle = tau * double(i) / count;
        points[i] = Vector2(real_t(std::cos(angle) * radius.x), real_t(std::sin(angle) * radius.y));
    }
    PackedVector3Array vertices;
    PackedColorArray colors;
    PackedInt32Array indices;
    vertices.resize(count * 4);
    colors.resize(count * 4);
    indices.resize(count * 3 * 6);
    Vector3 *vertex = vertices.ptrw();
    Color *tint = colors.ptrw();
    int32_t *index = indices.ptrw();
    // Godot 4.7's AA width compensation: 1.5 * .5 base width and
    // 1.25 * .75 feather. Keep the perceived stroke width of draw_polyline.
    // https://github.com/godotengine/godot/blob/4.7/servers/rendering/renderer_canvas_cull.cpp
    // Mitered joins keep constant screen-space width around the ellipse.
    const real_t offsets[4] = {-1.3125f, -0.375f, 0.375f, 1.3125f};
    for (int i = 0; i < count; ++i) {
        const Vector2 before = (points[i] - points[(i + count - 1) % count]).normalized();
        const Vector2 after = (points[(i + 1) % count] - points[i]).normalized();
        const Vector2 normal_before(before.y, -before.x), normal_after(after.y, -after.x);
        const Vector2 bisector = (normal_before + normal_after).normalized();
        const real_t denominator = bisector.dot(normal_after);
        if (denominator < 0.1f) { ++selection_mesh_fallbacks; return false; }
        for (int ring = 0; ring < 4; ++ring) {
            const Vector2 point = points[i] + bisector * (offsets[ring] / denominator);
            vertex[ring * count + i] = Vector3(point.x, point.y, 0);
            tint[ring * count + i] = Color(1, 1, 1, ring == 0 || ring == 3 ? 0.0f : 1.0f);
        }
        for (int strip = 0; strip < 3; ++strip) {
            const int a = strip * count + i, b = strip * count + (i + 1) % count;
            const int c = a + count, d = b + count, first = (strip * count + i) * 6;
            index[first] = a; index[first + 1] = b; index[first + 2] = c;
            index[first + 3] = b; index[first + 4] = d; index[first + 5] = c;
        }
    }
    Array arrays;
    arrays.resize(RenderingServer::ARRAY_MAX);
    arrays[RenderingServer::ARRAY_VERTEX] = vertices;
    arrays[RenderingServer::ARRAY_COLOR] = colors;
    arrays[RenderingServer::ARRAY_INDEX] = indices;
    const RID mesh = server->mesh_create();
    server->mesh_add_surface_from_arrays(mesh, RenderingServer::PRIMITIVE_TRIANGLES, arrays);
    selection_meshes.push_back({radius, mesh});
    ++selection_mesh_builds;
    server->canvas_item_add_mesh(canvas, mesh, Transform2D(0, center), color);
    return true;
}

} // namespace godot
