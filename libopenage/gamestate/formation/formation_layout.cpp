// Copyright 2026-2026 the openage authors. See copying.md for legal info.

#include "formation_layout.h"

#include <algorithm>
#include <cmath>
#include <limits>
#include <numbers>
#include <stdexcept>
#include <vector>


namespace openage::gamestate::formation {
namespace {

void validate(const FormationSpec &spec) {
	if ((spec.type == FormationType::RECTANGLE || spec.type == FormationType::STAGGERED)
	    && spec.front_width == 0) {
		throw std::invalid_argument{"Formation front width must be greater than zero"};
	}

	if (!std::isfinite(spec.lateral_spacing) || spec.lateral_spacing <= 0.0
	    || !std::isfinite(spec.longitudinal_spacing) || spec.longitudinal_spacing <= 0.0) {
		throw std::invalid_argument{"Formation spacing must be finite and greater than zero"};
	}

	if (!std::isfinite(spec.facing_degrees)
	    || !std::isfinite(spec.anchor.x)
	    || !std::isfinite(spec.anchor.y)) {
		throw std::invalid_argument{"Formation anchor and facing must be finite"};
	}
}

std::vector<size_t> row_widths(const FormationSpec &spec) {
	std::vector<size_t> widths;
	if (spec.member_count == 0) {
		return widths;
	}

	switch (spec.type) {
	case FormationType::LINE:
		widths.push_back(spec.member_count);
		break;
	case FormationType::COLUMN:
		widths.assign(spec.member_count, 1);
		break;
	case FormationType::WEDGE: {
		size_t remaining = spec.member_count;
		for (size_t width = 1; remaining > 0; width += 2) {
			const auto row_width = std::min(width, remaining);
			widths.push_back(row_width);
			remaining -= row_width;
		}
		break;
	}
	case FormationType::RECTANGLE:
	case FormationType::STAGGERED: {
		size_t remaining = spec.member_count;
		while (remaining > 0) {
			const auto row_width = std::min(spec.front_width, remaining);
			widths.push_back(row_width);
			remaining -= row_width;
		}
		break;
	}
	}

	return widths;
}

FormationPoint to_world(const FormationPoint &local,
	                     const FormationPoint &anchor,
	                     double facing_degrees) {
	const auto radians = facing_degrees * std::numbers::pi / 180.0;
	const FormationPoint forward{std::sin(radians), std::cos(radians)};
	const FormationPoint right{std::cos(radians), -std::sin(radians)};

	return FormationPoint{
		anchor.x + right.x * local.x + forward.x * local.y,
		anchor.y + right.y * local.x + forward.y * local.y,
	};
}

} // namespace

std::vector<FormationSlot> FormationLayout::calculate(const FormationSpec &spec) {
	validate(spec);

	const auto widths = row_widths(spec);
	std::vector<FormationSlot> slots;
	slots.reserve(spec.member_count);

	double minimum_lateral = std::numeric_limits<double>::infinity();
	double maximum_lateral = -std::numeric_limits<double>::infinity();

	for (size_t row = 0; row < widths.size(); ++row) {
		const auto width = widths[row];
		const auto forward = (static_cast<double>(widths.size() - 1) / 2.0
		                      - static_cast<double>(row))
		                     * spec.longitudinal_spacing;
		const auto stagger = spec.type == FormationType::STAGGERED && row % 2 == 1
		                       ? spec.lateral_spacing / 2.0
		                       : 0.0;

		for (size_t column = 0; column < width; ++column) {
			const auto lateral = (static_cast<double>(column)
			                      - static_cast<double>(width - 1) / 2.0)
			                         * spec.lateral_spacing
			                     + stagger;
			minimum_lateral = std::min(minimum_lateral, lateral);
			maximum_lateral = std::max(maximum_lateral, lateral);
			slots.push_back(FormationSlot{
				slots.size(),
				row,
				column,
				FormationPoint{lateral, forward},
				FormationPoint{0.0, 0.0},
			});
		}
	}

	if (slots.empty()) {
		return slots;
	}

	// Recenter staggered and partial layouts on the pathfinding anchor.
	const auto lateral_center = (minimum_lateral + maximum_lateral) / 2.0;
	for (auto &slot : slots) {
		slot.local.x -= lateral_center;
		slot.world = to_world(slot.local, spec.anchor, spec.facing_degrees);
	}

	return slots;
}

} // namespace openage::gamestate::formation
