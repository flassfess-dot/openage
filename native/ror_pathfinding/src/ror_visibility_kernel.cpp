#include "ror_visibility_kernel.hpp"

#include <algorithm>
#include <cmath>

#include <godot_cpp/core/class_db.hpp>

namespace godot {

void RoRVisibilityKernel::_bind_methods() {
    ClassDB::bind_method(D_METHOD("configure", "width", "height"), &RoRVisibilityKernel::configure);
    ClassDB::bind_method(D_METHOD("vision_cells", "center", "radius"), &RoRVisibilityKernel::vision_cells);
    ClassDB::bind_method(D_METHOD("is_configured"), &RoRVisibilityKernel::is_configured);
}

void RoRVisibilityKernel::configure(int32_t width, int32_t height) {
    width_ = std::max<int32_t>(1, width);
    height_ = std::max<int32_t>(1, height);
}

PackedInt32Array RoRVisibilityKernel::vision_cells(const Vector2 &center, double radius) const {
    PackedInt32Array result;
    if (!is_configured() || radius < 0.0) {
        return result;
    }
    const int32_t minimum_x = std::max<int32_t>(0, static_cast<int32_t>(std::floor(center.x - radius)));
    const int32_t minimum_y = std::max<int32_t>(0, static_cast<int32_t>(std::floor(center.y - radius)));
    const int32_t maximum_x = std::min<int32_t>(width_ - 1, static_cast<int32_t>(std::floor(center.x + radius)));
    const int32_t maximum_y = std::min<int32_t>(height_ - 1, static_cast<int32_t>(std::floor(center.y + radius)));
    const double radius_squared = radius * radius + 0.000001;
    for (int32_t y = minimum_y; y <= maximum_y; ++y) {
        for (int32_t x = minimum_x; x <= maximum_x; ++x) {
            const double nearest_x = std::clamp(static_cast<double>(center.x), static_cast<double>(x), static_cast<double>(x + 1));
            const double nearest_y = std::clamp(static_cast<double>(center.y), static_cast<double>(y), static_cast<double>(y + 1));
            const double difference_x = static_cast<double>(center.x) - nearest_x;
            const double difference_y = static_cast<double>(center.y) - nearest_y;
            if (difference_x * difference_x + difference_y * difference_y <= radius_squared) {
                result.append(y * width_ + x);
            }
        }
    }
    return result;
}

bool RoRVisibilityKernel::is_configured() const {
    return width_ > 0 && height_ > 0;
}

} // namespace godot
