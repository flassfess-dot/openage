class_name RoRMatchTimeline
extends Control

signal selection_changed
const Typography := preload("res://scripts/hud_typography.gd")
const Palette := preload("res://scripts/player_palette.gd")
const AGE_NAMES := ["Каменный век", "Эпоха орудий", "Бронзовый век", "Железный век"]
var history: Dictionary = {}
var hidden_teams: Dictionary = {}
var selected_index := -1
var proportional := true
var highlighted_team := -1
var band_meshes: Array[ArrayMesh] = []

func _init() -> void:
	custom_minimum_size = Vector2(220, 290)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	mouse_default_cursor_shape = Control.CURSOR_CROSS
	resized.connect(queue_redraw)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)

func configure(data: Dictionary) -> void:
	var was_latest: bool = selected_index < 0 or selected_index >= history.get("samples", []).size() - 1
	var old_tick := int(selected_sample().get("tick", 0))
	history = data
	selected_index = history.get("samples", []).size() - 1 if was_latest else _nearest_index(old_tick)
	queue_redraw()
	selection_changed.emit()

static func time_label(tick: int) -> String:
	var seconds := maxi(0, tick / 20)
	return "%02d:%02d:%02d" % [seconds / 3600, (seconds / 60) % 60, seconds % 60]

static func player_color(team: int) -> Color:
	return Palette.shade(clampi(team, 1, 8), 3)

func team_color(team: int) -> Color:
	return player_color(int(history.get("teams", {}).get(team, {}).get("color_index", team)))

func visible_teams() -> Array:
	var ids: Array = history.get("teams", {}).keys()
	ids.sort()
	return ids.filter(func(team): return not hidden_teams.has(team))

func selected_sample() -> Dictionary:
	var samples: Array = history.get("samples", [])
	return samples[clampi(selected_index, 0, samples.size() - 1)] if not samples.is_empty() else {}

func age_at(team: int, tick: int, fallback: int = 100) -> int:
	var age := fallback
	for marker in history.get("markers", []):
		if int(marker["team"]) == team and marker["kind"] == "age" and int(marker["tick"]) <= tick:
			age = int(marker["value"])
	return age

func _plot() -> Rect2:
	return Rect2(44, 32, maxf(20, size.x - 62), maxf(110, size.y - 84))

func _nearest_index(tick: int) -> int:
	var samples: Array = history.get("samples", [])
	var low := 0
	var high := samples.size()
	while low < high:
		var middle := (low + high) / 2
		if int(samples[middle]["tick"]) < tick: low = middle + 1
		else: high = middle
	if low > 0 and (low == samples.size() or tick - int(samples[low - 1]["tick"]) <= int(samples[low]["tick"]) - tick): low -= 1
	return low if not samples.is_empty() else -1

func _select(index: int) -> void:
	var next := clampi(index, 0, history.get("samples", []).size() - 1)
	if selected_index == next: return
	selected_index = next
	selection_changed.emit()
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_LEFT: _select(selected_index - 1)
			KEY_RIGHT: _select(selected_index + 1)
			KEY_HOME: _select(0)
			KEY_END: _select(history.get("samples", []).size() - 1)
			_: return
		accept_event()
	elif event is InputEventMouseMotion or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		var plot := _plot()
		if not plot.has_point(event.position): return
		if event is InputEventMouseButton: grab_focus()
		var start := int(history.get("start_tick", 0))
		var end := maxi(start + 1, int(history.get("current_tick", start)))
		_select(_nearest_index(start + roundi((event.position.x - plot.position.x) / plot.size.x * (end - start))))

func _total(sample: Dictionary, ids: Array) -> int:
	var total := 0
	for team in ids: total += int(sample.get("teams", {}).get(team, {}).get("population", 0))
	return total

func _bounds(sample: Dictionary, team: int, ids: Array, scale: float) -> Vector2:
	var below := 0.0
	for id in ids:
		var count := float(sample.get("teams", {}).get(id, {}).get("population", 0))
		if id == team: return Vector2(below, below + count) / scale
		below += count
	return Vector2.ZERO

func _draw() -> void:
	band_meshes.clear()
	var font := Typography.body_font()
	var ink := Color("e9e1ce")
	var muted := Color("b6ad98")
	var plot := _plot()
	var samples: Array = history.get("samples", [])
	var ids := visible_teams()
	var start := int(history.get("start_tick", 0))
	var end := maxi(start + 1, int(history.get("current_tick", start)))
	draw_rect(plot, Color("141a1b"))
	if samples.is_empty() or ids.is_empty():
		draw_string(font, plot.position + Vector2(12, 30), "Нет данных" if samples.is_empty() else "Выберите игрока в таблице ниже", HORIZONTAL_ALIGNMENT_LEFT, plot.size.x - 24, 14, ink)
		return
	if samples.size() == 1 or int(history.get("current_tick", start)) <= start:
		draw_string(font, plot.position + Vector2(12, 34), "История ещё не накоплена", HORIZONTAL_ALIGNMENT_LEFT, plot.size.x - 24, 16, ink)
		draw_string(font, plot.position + Vector2(12, 59), "Продолжите матч, чтобы увидеть изменения.", HORIZONTAL_ALIGNMENT_LEFT, plot.size.x - 24, 13, muted)
		return
	var peak := 1
	for sample in samples: peak = maxi(peak, _total(sample, ids))
	var raw_step := peak / 4.0
	var magnitude := pow(10.0, floor(log(raw_step) / log(10.0)))
	var scaled := raw_step / magnitude
	var step := maxf(1, magnitude * (1 if scaled <= 1 else 2 if scaled <= 2 else 5 if scaled <= 5 else 10))
	peak = roundi(step * 4)
	# Both AoE and AoE I DE use stacked population shares. Absolute mode uses
	# the same bands with a common population scale, never crossing lines.
	for team in ids:
		var upper := PackedVector2Array()
		var lower := PackedVector2Array()
		var has_population := false
		for sample in samples:
			var scale := maxf(1, _total(sample, ids)) if proportional else float(peak)
			var bounds := _bounds(sample, team, ids, scale)
			var x := plot.position.x + plot.size.x * float(int(sample["tick"]) - start) / (end - start)
			upper.append(Vector2(x, plot.end.y - bounds.y * plot.size.y))
			lower.append(Vector2(x, plot.end.y - bounds.x * plot.size.y))
			if bounds.y > bounds.x: has_population = true
		if upper.size() == 1:
			upper.append(Vector2(plot.end.x, upper[0].y))
			lower.append(Vector2(plot.end.x, lower[0].y))
		if has_population:
			# A band may touch itself at zero population. Explicit triangles avoid
			# polygon triangulation failures after extinction or zero-pop starts.
			var vertices := PackedVector3Array()
			for i in range(1, upper.size()):
				if upper[i].y == lower[i].y and upper[i - 1].y == lower[i - 1].y: continue
				for point in [upper[i - 1], lower[i - 1], upper[i], upper[i], lower[i - 1], lower[i]]:
					vertices.append(Vector3(point.x, point.y, 0))
			if not vertices.is_empty():
				var arrays := []
				arrays.resize(Mesh.ARRAY_MAX)
				arrays[Mesh.ARRAY_VERTEX] = vertices
				var mesh := ArrayMesh.new()
				mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
				band_meshes.append(mesh)
				draw_mesh(mesh, null, Transform2D.IDENTITY, team_color(team))
			draw_polyline(upper, team_color(team).lightened(0.24), 1, true)
	for i in range(5):
		var y := plot.end.y - plot.size.y * i / 4.0
		draw_line(Vector2(plot.position.x, y), Vector2(plot.end.x, y), Color(1, 1, 1, 0.12))
		draw_string(font, Vector2(0, y + 5), "%d%%" % (25 * i) if proportional else str(peak * i / 4), HORIZONTAL_ALIGNMENT_RIGHT, 38, 12, muted)
	var divisions := 4 if plot.size.x >= 540 else 2
	for i in range(divisions + 1):
		var tick := start + (end - start) * i / divisions
		var x := plot.position.x + plot.size.x * i / divisions
		var sample: Dictionary = samples[maxi(0, _nearest_index(tick))]
		draw_string(font, Vector2(x - 20, 21), str(_total(sample, ids)), HORIZONTAL_ALIGNMENT_CENTER, 40, 13, ink)
		draw_string(font, Vector2(clampf(x - 32, 0, size.x - 66), plot.end.y + 23), time_label(tick), HORIZONTAL_ALIGNMENT_LEFT, 70, 12, muted)
	draw_string(font, Vector2(plot.position.x, size.y - 5), "Игровое время", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, muted)
	# Exact events remain in the table when badges would overlap.
	var occupied: Array[Rect2] = []
	for marker in history.get("markers", []):
		var team := int(marker.get("team", 0))
		var tick := int(marker.get("tick", -1))
		if team not in ids or tick < start or tick > end: continue
		var kind := String(marker.get("kind", ""))
		if kind not in ["age", "player_resigned", "player_defeated"]: continue
		if kind == "age" and team != highlighted_team: continue
		var sample: Dictionary = samples[maxi(0, _nearest_index(tick))]
		var bounds := _bounds(sample, team, ids, maxf(1, _total(sample, ids)) if proportional else float(peak))
		var x := plot.position.x + plot.size.x * float(tick - start) / (end - start)
		var y := plot.end.y - (bounds.x + bounds.y) * 0.5 * plot.size.y
		var badge := Rect2(clampf(x - 12, plot.position.x, plot.end.x - 26), clampf(y - 10, plot.position.y, plot.end.y - 20), 26, 20)
		var overlaps := false
		for used in occupied:
			if used.grow(3).intersects(badge): overlaps = true; break
		if overlaps: continue
		occupied.append(badge)
		draw_rect(badge, Color("202322"))
		draw_rect(badge, team_color(team).lightened(0.5), false, 1)
		var text: String = ["I", "II", "III", "IV"][clampi(int(marker.get("value", 100)) - 100, 0, 3)] if kind == "age" else "×"
		draw_string(font, badge.position + Vector2(0, 15), text, HORIZONTAL_ALIGNMENT_CENTER, 26, 13, ink)
	# Numbers connect each band to the named roster, independently of colour.
	for team in ids:
		var first: Dictionary = samples[0]
		var bounds := _bounds(first, team, ids, maxf(1, _total(first, ids)) if proportional else float(peak))
		if (bounds.y - bounds.x) * plot.size.y < 20: continue
		var y := plot.end.y - (bounds.x + bounds.y) * 0.5 * plot.size.y
		var badge := Rect2(plot.position.x + 5, y - 9, 20, 18)
		draw_rect(badge, Color("202322"))
		draw_string(font, badge.position + Vector2(0, 14), str(team), HORIZONTAL_ALIGNMENT_CENTER, 20, 12, ink)
	var selected := selected_sample()
	var cursor := plot.position.x + plot.size.x * float(int(selected.get("tick", start)) - start) / (end - start)
	draw_line(Vector2(cursor, plot.position.y), Vector2(cursor, plot.end.y), Color("fff2d1"), 2)
	draw_rect(plot, Color("a89774") if not has_focus() else Color("ffe0a1"), false, 1)
