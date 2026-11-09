extends RefCounted
## The worker owns the replacement match until take_result() joins it.
## No scene, texture, GUI callback or live simulation enters this worker.
const Catalog := preload("res://scripts/resource_catalog.gd")
const World := preload("res://scripts/simulation_world.gd")
const Lifecycle := preload("res://scripts/match_lifecycle_service.gd")
const Ai := preload("res://scripts/ai_player.gd")
const Navigation := preload("res://scripts/navigation_loading.gd")
const Autosave := preload("res://scripts/background_autosave.gd")
const Archive := preload("res://scripts/game_save_archive.gd")
const EnvironmentField := preload("res://scripts/environment_presentation_field.gd")
const FogRenderer := preload("res://scripts/match_fog_renderer.gd")

var _thread := Thread.new()
var _mutex := Mutex.new()
var _started := false
var _joined := false
var _cancelled := false
var _fraction := 0.0
var _stage := "Подготовка загрузки"
var _catalog


func start(path: String, autosave_enabled: bool = true, autosave_path: String = Archive.AUTOSAVE_PATH, previous_saves: RefCounted = null) -> bool:
	if _started: return false
	_started = _thread.start(_restore.bind(path, autosave_enabled, autosave_path, previous_saves)) == OK
	return _started


func snapshot() -> Dictionary:
	_mutex.lock()
	var value := {"complete": _started and not _joined and not _thread.is_alive(), "progress": _fraction, "stage": _stage}
	_mutex.unlock()
	return value


func take_result() -> Dictionary:
	if not _started or _joined or _thread.is_alive(): return {}
	var value: Variant = _thread.wait_to_finish()
	_joined = true
	return value if value is Dictionary else {"error": "load_worker_failed"}


func shutdown() -> void:
	_mutex.lock()
	_cancelled = true
	_mutex.unlock()
	if _started and not _joined:
		var value: Variant = _thread.wait_to_finish()
		_joined = true
		if value is Dictionary and String(value.get("error", "")).is_empty():
			value["autosave"].shutdown()
			value["world"].shutdown_derived_state()


func _report(value: float, stage: String) -> bool:
	_mutex.lock()
	_fraction = maxf(_fraction, clampf(value, 0.0, 1.0))
	_stage = stage
	var keep_loading := not _cancelled
	_mutex.unlock()
	return keep_loading


func _restore_progress(value: float, stage: String) -> bool:
	return _report(0.06 + value * 0.43, stage)


func _new_world(size: Vector2i):
	var world := World.new(size, true)
	world.set_gamespec(_catalog.gamespec_data)
	# The validated checkpoint immediately restores every terrain cell. Filling
	# a generated default map here is redundant and can take several seconds.
	world.set_terrain_catalog(_catalog.terrain_catalog_data, false)
	world.set_object_catalog(_catalog.object_catalog_data)
	world.set_graphics_catalog(_catalog.graphics_catalog_data)
	world.set_runtime_catalog(_catalog.runtime_catalog_data)
	return world


func _new_players(definition: Dictionary) -> Array:
	var players: Array = []
	for player in definition.get("players", []):
		if String(player.get("controller", "ai")) == "ai":
			var ai := Ai.new(player)
			if ai.enabled: players.append(ai)
	return players


func _configure_cadence(players: Array) -> void:
	Ai.configure_runtime_cadence(players)


func _restore(path: String, autosave_enabled: bool, autosave_path: String, previous_saves: RefCounted) -> Dictionary:
	# The paused previous scene and launcher stop polling this queue until the
	# job completes. Preserve the synchronous loader's save-before-read order,
	# including loading the slot that the user has just requested to save.
	if previous_saves != null:
		if not _report(0.005, "Завершение текущих сохранений"): return {"error": "load_cancelled"}
		previous_saves.drain()
	if not _report(0.01, "Чтение игровых данных"): return {"error": "load_cancelled"}
	_catalog = Catalog.new()
	# Metadata only: GPU resources are configured on the main thread later.
	_catalog.load_generated_data()
	if _catalog.gamespec_data.is_empty() or _catalog.object_catalog_data.is_empty() or _catalog.runtime_catalog_data.is_empty():
		return {"error": "catalogs_unavailable"}
	if not _report(0.04, "Подготовка игровых данных"): return {"error": "load_cancelled"}
	_catalog.prepare_presentation_metadata()
	var restored: Dictionary = Lifecycle.new().restore(path, _new_world, _new_players, _configure_cadence, Callable(), {}, _restore_progress)
	if not String(restored.get("error", "load_worker_failed")).is_empty(): return restored
	var world = restored["world"]
	var loading := Navigation.new()
	if not _report(0.50, "Подготовка карты"):
		world.shutdown_derived_state()
		return {"error": "load_cancelled"}
	loading.begin(world, restored["definition"].get("players", []))
	while not loading.poll(world):
		if not _report(0.50 + loading.progress_fraction() * 0.13, "Подготовка карты и игроков"):
			loading.shutdown()
			world.shutdown_derived_state()
			return {"error": "load_cancelled"}
		OS.delay_msec(1)
	loading.shutdown()
	if not _report(0.63, "Подготовка окружения"):
		world.shutdown_derived_state()
		return {"error": "load_cancelled"}
	var definition: Dictionary = restored["definition"]
	var map: Dictionary = restored["map"]
	var items: Array = definition.get("presentation_environment", []).duplicate(true)
	items.append_array(definition.get("static_obstructions", []))
	items.append_array(map.get("scenery", []))
	items.append_array(map.get("cliff_obstructions", []))
	var scenery := EnvironmentField.new()
	scenery.configure(items)
	if not _report(0.635, "Подготовка обзора"):
		world.shutdown_derived_state()
		return {"error": "load_cancelled"}
	var fog_mask: Dictionary = FogRenderer.new().prepare_load_mask(world, int(definition.get("local_team", 1)))
	var autosave := Autosave.new()
	autosave.enabled = autosave_enabled
	autosave.save_path = autosave_path
	if not _report(0.64, "Подготовка автосохранения"):
		world.shutdown_derived_state()
		return {"error": "load_cancelled"}
	if autosave.enabled:
		autosave.seed_from(world, restored["controller"], definition, map, {"gamespec": _catalog.gamespec_data, "terrain": _catalog.terrain_catalog_data, "objects": _catalog.object_catalog_data, "graphics": _catalog.graphics_catalog_data, "runtime": _catalog.runtime_catalog_data})
	if not _report(0.67, "Подготовка изображения"):
		autosave.shutdown()
		world.shutdown_derived_state()
		return {"error": "load_cancelled"}
	restored["catalog"] = _catalog
	restored["scenery"] = scenery
	restored["fog_mask"] = fog_mask
	restored["autosave"] = autosave
	_report(0.68, "Подготовка изображения")
	return restored


static func close_saves(owners: Array) -> void:
	for owner in owners: owner.shutdown()


static func release_retired(owners: Array) -> void:
	# Called only after the old scene has left the tree and joined its tasks.
	# Retaining CPU runtime owners across that frame keeps their large final
	# deallocation off the UI thread. No scene or GPU resource is handed here.
	owners.clear()
