extends Control

const Typography := preload("res://scripts/hud_typography.gd")
const Palette := preload("res://scripts/player_palette.gd")
const ROW_HEIGHT := 19

var players: Array = []

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	hide()

func set_players(rows: Array) -> void:
	if players != rows:
		players = rows
		queue_redraw()

func fit_above(bottom: Rect2) -> void:
	size = Vector2(minf(196, bottom.size.x - 8), 8 + ROW_HEIGHT * (1 + players.size()))
	position = Vector2(bottom.end.x - size.x - 4, bottom.position.y - size.y - 4)

func _draw() -> void:
	var panel := Rect2(Vector2.ZERO, size)
	draw_rect(panel, Color("201b17ee"))
	draw_rect(panel, Color("a99873"), false, 1)
	var title := Typography.title_font()
	var font := Typography.body_font()
	var left := 10.0
	var right := size.x - 10
	var baseline := 18.0
	draw_string(title, Vector2(left, baseline), "Игрок", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("e3cf9e"))
	draw_string(title, Vector2(left, baseline), "Очки", HORIZONTAL_ALIGNMENT_RIGHT, right - left, 14, Color("e3cf9e"))
	for row in players:
		baseline += ROW_HEIGHT
		var color := Palette.shade(int(row["color_index"]), 3)
		draw_rect(Rect2(left, baseline - 10, 8, 8), color.lightened(0.22))
		draw_string(font, Vector2(left + 14, baseline), "Игрок %d" % row["team"], HORIZONTAL_ALIGNMENT_LEFT, -1, 14)
		draw_string(title, Vector2(left, baseline), str(row["score"]), HORIZONTAL_ALIGNMENT_RIGHT, right - left, 14)
