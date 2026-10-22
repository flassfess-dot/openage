extends RefCounted

# Scene access is scoped to each call; this owner never retains the scene.
const Coordinates := preload("res://scripts/coordinates.gd")
const MinimapProjection := preload("res://scripts/minimap_projection.gd")
const MinimapTerrainRaster := preload("res://scripts/minimap_terrain_raster.gd")
const FogOfWar := preload("res://scripts/fog_of_war.gd")
const InterfaceLayout := preload("res://scripts/interface_layout.gd")
const MinimapResourceIndex := preload("res://scripts/minimap_resource_index.gd")

var cached_minimap_mesh: ArrayMesh
var cached_minimap_terrain_texture: ImageTexture
var cached_minimap_terrain_revision: int = -1
var cached_minimap_terrain_rectangle := Rect2()
var cached_minimap_fog_texture: ImageTexture
var cached_minimap_fog_image: Image
var cached_minimap_exploration_revision: int = -1
var cached_minimap_fog_tick := -1
var cached_minimap_fog_rectangle := Rect2()
var cached_minimap_mesh_tick: int = -1
var cached_minimap_mesh_rectangle := Rect2()
var minimap_resource_index := MinimapResourceIndex.new()

func draw_minimap(game, rectangle: Rect2) -> void:
	var geometry = game.minimap_geometry(rectangle)
	var center: Vector2 = geometry["center"]
	var scale: float = geometry["scale"]
	var aperture = PackedVector2Array([
		Vector2(rectangle.get_center().x, rectangle.position.y),
		Vector2(rectangle.end.x, rectangle.get_center().y),
		Vector2(rectangle.get_center().x, rectangle.end.y),
		Vector2(rectangle.position.x, rectangle.get_center().y),
	])
	game.draw_colored_polygon(aperture, Color.BLACK)
	var map_points = MinimapProjection.map_polygon(game.map_size, center, scale)
	# Tree depletion changes terrain artwork but not land/water geography. Rebuild
	# the small minimap raster only when navigable surface topology changes.
	var terrain_revision = int(game.render_terrain_view.surface_revision) if game.render_terrain_view != null else int(game.simulation_world.navigation_grid.surface_revision) if game.simulation_world != null else -1
	if cached_minimap_terrain_texture == null or cached_minimap_terrain_revision != terrain_revision or cached_minimap_terrain_rectangle != rectangle:
		var terrain_image = MinimapTerrainRaster.build(game.map_size, rectangle, center, scale, Callable(game, "terrain_id_at_cell"))
		cached_minimap_terrain_texture = ImageTexture.create_from_image(terrain_image)
		cached_minimap_terrain_revision = terrain_revision
		cached_minimap_terrain_rectangle = rectangle
	if cached_minimap_terrain_texture != null:
		game.draw_texture(cached_minimap_terrain_texture, rectangle.position)
	var snapshot_tick = int(game.presentation_snapshot.get("overview_tick", game.presentation_snapshot.get("tick", -1)))
	var exploration_revision = int(game.presentation_snapshot.get("fog_exploration_revision", game.presentation_snapshot.get("fog_revision", -1)))
	if cached_minimap_fog_texture == null or cached_minimap_fog_rectangle != rectangle or (cached_minimap_exploration_revision != exploration_revision and cached_minimap_fog_tick != snapshot_tick):
		var fog_image = MinimapTerrainRaster.build_fog(game.map_size, rectangle, center, scale, game.presentation_snapshot.get("fog", {}).get("cells", []))
		# Retain the bounded CPU raster as the authoritative upload payload. This
		# also makes headless verification independent of renderer-specific texture
		# readback behavior while the live view continues reusing one GPU texture.
		cached_minimap_fog_image = fog_image
		if cached_minimap_fog_texture == null or cached_minimap_fog_rectangle != rectangle:
			cached_minimap_fog_texture = ImageTexture.create_from_image(fog_image)
		else:
			cached_minimap_fog_texture.update(fog_image)
		cached_minimap_exploration_revision = exploration_revision
		cached_minimap_fog_tick = snapshot_tick
		cached_minimap_fog_rectangle = rectangle
	if cached_minimap_fog_texture != null:
		game.draw_texture(cached_minimap_fog_texture, rectangle.position)
	# Fog and markers share the overview cadence; world fog still updates each
	# frame. Rebuilding the entire minimap raster on every newly explored cell
	# otherwise adds a forest/map-size-dependent CPU spike while units move.
	# Keep resource and unit markers independent of changing visibility.
	if cached_minimap_mesh == null or cached_minimap_mesh_tick != snapshot_tick or cached_minimap_mesh_rectangle != rectangle:
		cached_minimap_mesh_rectangle = rectangle
		cached_minimap_mesh = game._build_minimap_mesh(center, scale)
		cached_minimap_mesh_tick = snapshot_tick
	if cached_minimap_mesh != null:
		game.draw_mesh(cached_minimap_mesh, null)
	game.draw_polyline(PackedVector2Array([map_points[0], map_points[1], map_points[2], map_points[3], map_points[0]]), Color("d2bd7d"), 1.0)
	# The visible-bounds query already resolved these exact terrain intersections.
	# Reuse them for the minimap instead of repeating 96 height-search iterations.
	game.visible_tile_bounds()
	var camera_world = PackedVector2Array([
		Coordinates.clamp_world(game.visible_world_corners[0], game.map_size),
		Coordinates.clamp_world(game.visible_world_corners[1], game.map_size),
		Coordinates.clamp_world(game.visible_world_corners[2], game.map_size),
		Coordinates.clamp_world(game.visible_world_corners[3], game.map_size),
	])
	var camera_points = PackedVector2Array()
	for world_point in camera_world:
		camera_points.append(MinimapProjection.world_to_minimap(world_point, center, scale))
	if camera_points.size() >= 3:
		camera_points.append(camera_points[0])
		game.draw_polyline(camera_points, Color("f5e28d"), 1.0, true)


func _build_minimap_mesh(game, center: Vector2, scale: float) -> ArrayMesh:
	var probe: Variant = game._presentation_probe()
	var stage_started = Time.get_ticks_usec() if probe != null else 0
	var vertices = PackedVector3Array()
	var colors = PackedColorArray()
	# Imported campaigns may contain ten thousand individual trees. At minimap
	# scale many of them land on the same two-pixel cell, so drawing a circle for
	# every source entity only creates hundreds of thousands of overlapping
	# vertices. Collapse them into deterministic screen-space resource pixels.
	for pixel_center in game._minimap_resource_pixels(center, scale, cached_minimap_mesh_rectangle):
		game._append_colored_quad(vertices, colors, PackedVector2Array([
			pixel_center + Vector2(-1.0, -1.0),
			pixel_center + Vector2(1.0, -1.0),
			pixel_center + Vector2(1.0, 1.0),
			pixel_center + Vector2(-1.0, 1.0),
		]), Color("18591d"))
	if probe != null:
		probe.observe_microseconds("presentation.minimap.resources", Time.get_ticks_usec() - stage_started)
		stage_started = Time.get_ticks_usec()
	for unit in game.overview_units:
		if unit["hp"] > 0.0:
			game._append_colored_circle(vertices, colors, game.minimap_position(unit["pos"], center, scale), 2.0, game.resource_catalog.player_palette.color_for_team(int(unit["team"])))
	for building in game.overview_buildings:
		if building["hp"] > 0.0:
			game._append_colored_circle(vertices, colors, game.minimap_position(building["pos"], center, scale), 3.0, game.resource_catalog.player_palette.color_for_team(int(building["team"])))
	if probe != null:
		probe.observe_microseconds("presentation.minimap.entities", Time.get_ticks_usec() - stage_started)
		stage_started = Time.get_ticks_usec()
	if vertices.is_empty():
		return null
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if probe != null:
		probe.observe_microseconds("presentation.minimap.surface", Time.get_ticks_usec() - stage_started)
	return mesh


func _minimap_resource_pixels(game, center: Vector2, scale: float, rectangle: Rect2) -> Array[Vector2]:
	if game.simulation_owner.pending: return minimap_resource_index.pixels
	var changes: Variant = game.simulation_world.consume_known_resource_marker_changes(game.local_player_team) if game.simulation_world != null else null
	var probe: Variant = game._presentation_probe()
	return minimap_resource_index.synchronize(game.overview_resource_nodes, changes, center, scale, rectangle,
		func(position: Vector2): return game.presentation_fog_state_at(position) != FogOfWar.UNKNOWN, probe)


func _append_colored_quad(game, vertices: PackedVector3Array, colors: PackedColorArray, points: PackedVector2Array, color: Color) -> void:
	if points.size() < 4:
		return
	for index in [0, 1, 2, 0, 2, 3]:
		var point = points[index]
		vertices.append(Vector3(point.x, point.y, 0.0))
		colors.append(color)


func _append_colored_circle(game, vertices: PackedVector3Array, colors: PackedColorArray, center: Vector2, radius: float, color: Color) -> void:
	const SEGMENTS = 8
	for index in range(SEGMENTS):
		var first_angle = TAU * float(index) / float(SEGMENTS)
		var second_angle = TAU * float(index + 1) / float(SEGMENTS)
		for point in [center, center + Vector2(cos(first_angle), sin(first_angle)) * radius, center + Vector2(cos(second_angle), sin(second_angle)) * radius]:
			vertices.append(Vector3(point.x, point.y, 0.0))
			colors.append(color)


func minimap_position(game, world: Vector2, center: Vector2, scale: float) -> Vector2:
	return MinimapProjection.world_to_minimap(world, center, scale)


func minimap_rectangle(game) -> Rect2:
	return InterfaceLayout.for_viewport(game.get_viewport_rect().size)["minimap"]


func minimap_geometry(game, rectangle: Rect2 = Rect2()) -> Dictionary:
	var resolved = rectangle if rectangle.size != Vector2.ZERO else game.minimap_rectangle()
	var horizontal_padding = 8.0
	var vertical_padding = 6.0
	var span = maxf(1.0, float(game.map_size.x + game.map_size.y))
	return {
		"rectangle": resolved,
		"center": resolved.position + Vector2(resolved.size.x * 0.5, vertical_padding),
		"scale": minf((resolved.size.x - horizontal_padding * 2.0) / span, (resolved.size.y - vertical_padding * 2.0) * 2.0 / span),
	}


func _reset_minimap_fog_cache(game) -> void:
	cached_minimap_fog_texture = null
	cached_minimap_fog_image = null
	cached_minimap_exploration_revision = -1
	cached_minimap_fog_rectangle = Rect2()
