extends "res://main.gd"

# Observe the actual CanvasItem dispatch while retaining production rendering.
var observed_outlines: Array[Dictionary] = []
var observed_selection_id := -1

func draw_unit_selection(item: Dictionary) -> void:
	observed_selection_id = int(item["stable_id"])
	super.draw_unit_selection(item)

func draw_building_selection_rectangle(building: Dictionary, color: Color) -> void:
	observed_outlines.append({"id": int(building["id"]), "color": color, "shape": "building"})
	if DisplayServer.get_name() != "headless":
		super.draw_building_selection_rectangle(building, color)

func draw_selection_ellipse(center: Vector2, color: Color, radius: Vector2 = Vector2(15.0, 6.5)) -> void:
	observed_outlines.append({"id": observed_selection_id, "color": color, "shape": "ellipse"})
	if DisplayServer.get_name() != "headless":
		super.draw_selection_ellipse(center, color, radius)
