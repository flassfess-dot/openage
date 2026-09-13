// Copyright 2026-2026 the openage authors. See copying.md for legal info.

#pragma once

#include <cstddef>
#include <vector>


namespace openage::gamestate::formation {

/**
 * Geometric layouts supported by the first formation prototype.
 *
 * These values intentionally describe geometry only. Combat modifiers and
 * unit-class restrictions belong to game data and are not part of the MVP.
 */
enum class FormationType {
	RECTANGLE,
	LINE,
	COLUMN,
	STAGGERED,
	WEDGE,
};

/**
 * A point in the two-dimensional simulation plane.
 */
struct FormationPoint {
	double x;
	double y;
};

/**
 * Inputs for calculating stable member slots around a formation anchor.
 */
struct FormationSpec {
	FormationType type{FormationType::RECTANGLE};
	size_t member_count{0};
	size_t front_width{1};
	double lateral_spacing{1.0};
	double longitudinal_spacing{1.0};
	double facing_degrees{0.0};
	FormationPoint anchor{0.0, 0.0};
};

/**
 * One stable location in a formation.
 *
 * Members are ordered front-to-back and left-to-right. The local coordinate
 * system uses +y for forward and +x for right. Facing is clockwise from +y.
 */
struct FormationSlot {
	size_t member_index;
	size_t row;
	size_t column;
	FormationPoint local;
	FormationPoint world;
};

/**
 * Stateless formation geometry calculator.
 */
class FormationLayout final {
public:
	/**
	 * Calculate stable formation slots from a specification.
	 *
	 * @param spec Formation shape, size, spacing, anchor, and facing.
	 * @return Slots in deterministic member order.
	 * @throws std::invalid_argument for invalid width, spacing, or coordinates.
	 */
	static std::vector<FormationSlot> calculate(const FormationSpec &spec);
};

} // namespace openage::gamestate::formation
