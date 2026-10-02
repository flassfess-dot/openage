extends SceneTree

const Catalog := preload("res://scripts/resource_catalog.gd")
const Layout := preload("res://scripts/interface_layout.gd")
const HUD := preload("res://scripts/hud_controls.gd")
const TopBar := preload("res://scripts/top_bar_controls.gd")
const Aperture := preload("res://scripts/minimap_aperture.gd")
var failures: Array[String] = []

func _initialize() -> void:
	var bare = HUD.StatusPanel.new()
	root.add_child(bare)
	bare.size = Vector2(720, 720)
	bare.set_layout(Layout.for_viewport(bare.size))
	await process_frame
	await process_frame
	bare.free()
	var catalog = Catalog.new()
	catalog.load()
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	root.add_child(viewport)
	var hud = HUD.new()
	var top = TopBar.new()
	viewport.add_child(hud)
	viewport.add_child(top)
	hud.configure_icons(catalog.interface_icons)
	for civilization_id in range(1, 17):
		var style: int = catalog.interface_skin.style_index_for_civilization(civilization_id, catalog.object_catalog_data)
		hud.configure_interface_skin(catalog.interface_skin, style)
		top.configure(catalog.interface_skin, style)
		assert_equal(hud.status_panel.style_index, top.style_index, "both panels follow civilization %d" % civilization_id)
		assert_equal(top.top_texture.get_height(), 32, "flat strip is 32px for civilization %d" % civilization_id)
		assert_true(top.population_glyph.texture != null and hud.status_panel.cancel_button.icon != null, "population and cancellation use real sprites")
		var frame: Image = hud.status_panel.frame_texture.get_image()
		assert_equal(frame.get_pixel(113, 60).a, 0.0, "minimap opening remains transparent")
		assert_equal(frame.get_pixel(0, 0).a, 1.0, "native outer frame stays opaque")
	var model := fixture_model()
	for width in [320, 430, 640, 720, 800, 840, 960, 1024, 1280, 2560]:
		viewport.size = Vector2i(width, 720)
		hud.size = Vector2(width, 720)
		hud.set_layout(Layout.for_viewport(hud.size))
		hud.set_view_model(model)
		top.set_viewport_size(hud.size)
		top.set_view_model(model)
		await process_frame
		var panel = hud.status_panel
		var production: Rect2 = panel.layout["production"]
		assert_true(is_equal_approx(top.age_label.get_rect().get_center().x, width * 0.5), "age is centered on the screen at %d" % width)
		assert_equal(top.population_well.size, Vector2(21, 21), "population well is square at %d" % width)
		assert_true(top.population_rectangle.end.x <= width, "top counters fit at %d" % width)
		assert_true(top.population_rectangle.end.x <= width * 0.5 - 50 if width >= 720 else true, "counters leave room for the centered age at %d" % width)
		for control in [panel.job_label, panel.percent_label, panel.time_label, panel.cancel_button]:
			assert_true(production.encloses(control.get_rect()), "production control fits at %d: %s" % [width, control.get_rect()])
		for button in panel.pending_buttons:
			if button.visible:
				assert_true(production.encloses(button.get_rect()), "queued icon fits at %d" % width)
				assert_true(not button.get_rect().intersects(panel.cancel_button.get_rect()), "queued icon does not touch Cancel at %d" % width)
		assert_true(panel.job_label.get_theme_font_size("font_size") >= 16, "research title remains readable at %d" % width)
		assert_equal(panel.portrait.size, Vector2(42, 42), "portrait fits its native card")
		assert_equal(panel.pending_groups.size(), 13, "adjacent matching units group without reordering research")
		assert_equal(panel.pending_groups[0]["count"], 2, "unit group carries its count")
		assert_true(panel.next_button.visible if width <= 960 else true, "long queue is paged at small widths")
		assert_equal(panel.job_label.text, "Орудия труда", "active title carries no help or confirmation text")
		assert_equal(panel.percent_label.text, "25%", "percentage corresponds to simulation progress")
	var panel = hud.status_panel
	var long_title := "Чешуйчатый доспех лучников и тяжёлой кавалерии"
	model["queue"][0]["label"] = long_title
	hud.size = Vector2(720, 720)
	hud.set_layout(Layout.for_viewport(hud.size))
	hud.set_view_model(model)
	await process_frame
	assert_true(panel.layout["production"].encloses(panel.job_label.get_rect()), "long title fits the narrow desktop production recess")
	assert_equal(panel.job_label.tooltip_text, long_title, "full long title remains accessible")
	var cancelled: Array = []
	panel.cancel_requested.connect(func(id: int, index: int): cancelled.append([id, index]))
	panel.cancel_button.emit_signal("pressed")
	assert_equal(cancelled.back(), [80, 0], "real Cancel button targets active order")
	panel.pending_buttons[0].emit_signal("pressed")
	assert_equal(cancelled.back(), [80, 1], "pending icon cancels its own FIFO index")
	var selected: Array = []
	panel.building_selected.connect(func(id: int): selected.append(id))
	panel.global_buttons[0].emit_signal("pressed")
	assert_equal(selected, [80], "global production selects the owning building")
	var old_button: int = panel.cancel_button.get_instance_id()
	model["queue"][0]["progress"] = 0.5
	model["queue"][0]["remaining_seconds"] = 60
	hud.update_dynamic_model(model)
	assert_equal(panel.percent_label.text, "50%", "progress updates without structural refresh")
	assert_equal(panel.cancel_button.get_instance_id(), old_button, "dynamic refresh preserves controls")
	model["queue"][0]["status"] = "blocked_population"
	hud.update_dynamic_model(model)
	assert_equal(panel.time_label.text, "Лимит населения", "completed blocked unit communicates its cause")
	assert_equal(hud.training_batch_size({"cost": {0: 50}}, true), 0, "Shift respects the shared queue limit")
	model["queue"] = []
	model["resources"]["food"] = 120
	hud.set_view_model(model)
	assert_equal(hud.training_batch_size({"cost": {0: 50}}, true), 2, "Shift adds only affordable units")
	assert_true(not panel.cancel_button.visible and not panel.job_label.visible, "empty queue shows no filler messages")
	var mask_count := 0
	for row in Aperture.mask_rows(): mask_count += int(row[1])
	assert_equal(mask_count, 11991, "mask retains every measured native minimap pixel")
	var rect := Rect2(10, 20, 219, 109)
	assert_true(Aperture.contains(rect.get_center(), rect), "aperture accepts its center")
	assert_true(not Aperture.contains(rect.position, rect), "decorative corner cannot move the camera")
	viewport.free()
	for failure in failures: push_error(failure)
	if failures.is_empty(): print("Native HUD panels, all civilizations and responsive queues passed")
	quit(0 if failures.is_empty() else 1)

func fixture_model() -> Dictionary:
	var queue: Array = [{"type": "research", "technology_id": 101, "icon_kind": "technology", "icon_id": 65, "label": "Орудия труда", "progress": 0.25, "remaining_seconds": 90, "status": "researching"}]
	for index in range(14):
		queue.append({"type": "unit" if index < 2 else "research", "kind": "villager" if index < 2 else "", "label": "Крестьянин" if index < 2 else "Исследование %d" % index, "icon_kind": "unit" if index < 2 else "technology", "icon_id": 0 if index < 2 else index})
	return {"age": {"label": "Неолит"}, "resources": {"wood": 500, "food": 500, "gold": 200, "stone": 150}, "population": {"current": 200, "cap": 200}, "selection": {"category": "building", "count": 1, "leader": {"id": 80, "name": "Городской центр", "civilization_name": "Римляне", "hp": 350, "max_hp": 350, "icon_kind": "building_4", "icon_id": 3}}, "queue": queue, "global_queue": [{"building_id": 80, "building_label": "Городской центр", "label": "Орудия труда", "icon_kind": "technology", "icon_id": 65, "progress": 0.25}], "commands": []}

func assert_true(value: bool, context: String) -> void:
	if not value: failures.append(context)

func assert_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected: failures.append("%s: expected %s, got %s" % [context, expected, actual])