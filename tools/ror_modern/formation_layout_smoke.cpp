// Copyright 2026-2026 the openage authors. See copying.md for legal info.

#include <cmath>
#include <iostream>
#include <stdexcept>
#include <string>
#include <string_view>

#include "gamestate/formation/formation_layout.h"


namespace formation = openage::gamestate::formation;

namespace {

void expect_near(double actual, double expected, std::string_view label) {
	if (std::abs(actual - expected) > 1e-9) {
		throw std::runtime_error{std::string{label} + " differs from expected value"};
	}
}

void rectangle_layout() {
	formation::FormationSpec spec;
	spec.member_count = 5;
	spec.front_width = 3;
	spec.lateral_spacing = 2.0;
	spec.longitudinal_spacing = 4.0;

	const auto slots = formation::FormationLayout::calculate(spec);
	if (slots.size() != 5 || slots[0].row != 0 || slots[3].row != 1) {
		throw std::runtime_error{"Rectangle member ordering is unstable"};
	}

	expect_near(slots[0].local.x, -2.0, "front-left x");
	expect_near(slots[0].local.y, 2.0, "front-left y");
	expect_near(slots[4].local.x, 1.0, "rear-right x");
	expect_near(slots[4].local.y, -2.0, "rear-right y");
}

void line_and_column_layouts() {
	formation::FormationSpec line;
	line.type = formation::FormationType::LINE;
	line.member_count = 4;
	const auto line_slots = formation::FormationLayout::calculate(line);
	expect_near(line_slots.front().local.x, -1.5, "line left edge");
	expect_near(line_slots.back().local.x, 1.5, "line right edge");
	expect_near(line_slots.front().local.y, 0.0, "line depth");

	formation::FormationSpec column;
	column.type = formation::FormationType::COLUMN;
	column.member_count = 3;
	const auto column_slots = formation::FormationLayout::calculate(column);
	expect_near(column_slots[0].local.y, 1.0, "column front");
	expect_near(column_slots[1].local.y, 0.0, "column center");
	expect_near(column_slots[2].local.y, -1.0, "column rear");
}

void clockwise_rotation() {
	formation::FormationSpec spec;
	spec.type = formation::FormationType::COLUMN;
	spec.member_count = 3;
	spec.facing_degrees = 90.0;
	spec.anchor = {10.0, 20.0};

	const auto slots = formation::FormationLayout::calculate(spec);
	expect_near(slots[0].world.x, 11.0, "rotated front x");
	expect_near(slots[0].world.y, 20.0, "rotated front y");
	expect_near(slots[2].world.x, 9.0, "rotated rear x");
}

void wedge_layout() {
	formation::FormationSpec spec;
	spec.type = formation::FormationType::WEDGE;
	spec.member_count = 7;
	const auto slots = formation::FormationLayout::calculate(spec);

	if (slots[0].row != 0 || slots[1].row != 1 || slots[4].row != 2) {
		throw std::runtime_error{"Wedge rows were not generated as 1, 3, 3"};
	}
	expect_near(slots[0].local.y, 1.0, "wedge tip depth");
	expect_near(slots[6].local.y, -1.0, "wedge rear depth");
}

void rejects_invalid_geometry() {
	formation::FormationSpec spec;
	spec.member_count = 2;
	spec.front_width = 0;

	try {
		formation::FormationLayout::calculate(spec);
	}
	catch (const std::invalid_argument &) {
		return;
	}
	throw std::runtime_error{"Invalid formation width was accepted"};
}

} // namespace

int main() {
	rectangle_layout();
	line_and_column_layouts();
	clockwise_rotation();
	wedge_layout();
	rejects_invalid_geometry();

	std::cout << "formation layout smoke tests passed\n";
	return 0;
}
