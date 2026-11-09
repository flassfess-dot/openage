class_name RoRThreadedTextureQueue
extends RefCounted

const MAX_ACTIVE := 8
const MAX_QUEUED := 512
var queued: Array[String] = []
var queued_paths: Dictionary = {}
var active: Dictionary = {}
var completed: Dictionary = {}

func request(paths: Array[String]) -> void:
	# Headless runs have no presentation latency budget. Keep texture creation
	# on the caller thread for the dummy rendering server; graphical runs retain
	# the bounded background queue and its normal publication boundary.
	if DisplayServer.get_name()=="headless":
		for path in paths:
			if not completed.has(path): completed[path]=ResourceLoader.load(path,"Texture2D")
		return
	for path in paths:
		if completed.has(path) or active.has(path) or queued_paths.has(path):
			continue
		if queued.size() >= MAX_QUEUED:
			break
		queued.append(path)
		queued_paths[path] = true
	poll()

func poll() -> void:
	for path in active.keys():
		var status := ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			completed[path] = ResourceLoader.load_threaded_get(path)
			active.erase(path)
		elif status in [ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE]:
			completed[path] = null
			active.erase(path)
	while active.size() < MAX_ACTIVE and not queued.is_empty():
		var path: String = queued.pop_front()
		queued_paths.erase(path)
		var cached := ResourceLoader.get_cached_ref(path) as Texture2D
		if cached != null:
			completed[path] = cached
			continue
		var error := ResourceLoader.load_threaded_request(path, "Texture2D", false)
		if error in [OK, ERR_BUSY]:
			active[path] = true
		else:
			completed[path] = null

# A dedicated loader owns this queue for the whole window. Refill the eight
# I/O slots as files finish, independently of how often the loading UI draws.
func load_window(paths: Array[String]) -> Dictionary:
	var cursor := 0
	while cursor < paths.size() or not active.is_empty() or not queued.is_empty():
		var count := mini(MAX_QUEUED - queued.size(), paths.size() - cursor)
		if count > 0:
			request(paths.slice(cursor, cursor + count))
			cursor += count
		else:
			poll()
		if not active.is_empty(): OS.delay_msec(1)
	return completed

func is_complete(paths: Array[String]) -> bool:
	for path in paths:
		if not completed.has(path):
			return false
	return true

func texture(path: String) -> Texture2D:
	return completed.get(path) as Texture2D

func release(paths: Array[String]) -> void:
	for path in paths:
		completed.erase(path)

func shutdown() -> void:
	queued.clear()
	queued_paths.clear()
	# ResourceLoader has no cancellation API. Drain started requests and call
	# get only after LOADED, including when a registry is being reconfigured.
	while not active.is_empty():
		poll()
		if not active.is_empty():
			OS.delay_msec(1)
	completed.clear()
