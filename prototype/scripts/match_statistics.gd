class_name RoRMatchStatistics
extends RefCounted

# Presentation history is owned by the match, independent of event-stream pruning.
# It does not participate in gameplay hashes or feed AI/visibility projections.
const SAMPLE_TICKS := 100
const MAX_SAMPLES := 2048
const MAX_MARKERS := 512
var teams: Dictionary = {}
var samples: Array = []
var markers: Array = []
var interval_ticks := SAMPLE_TICKS
var start_tick := 0
var last_tick := -1
var initialized := false
var partial := false
var finished_tick := -1

func reset() -> void:
	teams.clear()
	samples.clear()
	markers.clear()
	interval_ticks = SAMPLE_TICKS
	start_tick = 0
	last_tick = -1
	initialized = false
	partial = false
	finished_tick = -1

func _team(team: int) -> Dictionary:
	if not teams.has(team):
		teams[team] = {"produced": 0, "lost": 0, "kills": 0, "razed": 0, "buildings_lost": 0, "converted": 0, "gathered": [0.0, 0.0, 0.0, 0.0], "tribute_sent": 0, "tribute_received": 0, "research": 0, "population": 0, "peak_population": 0, "age": 100, "status": "active"}
	return teams[team]

func begin(world, tick: int = 0, legacy: bool = false) -> void:
	if initialized: return
	initialized = true
	partial = legacy
	start_tick = tick
	sample(world, tick, true)

func consume(world, event_type: String, payload: Dictionary, tick: int) -> void:
	var team := int(payload.get("team", 0))
	match event_type:
		"entity_created":
			if team > 0 and String(payload.get("entity_category", "")) == "unit":
				_team(team)["peak_population"] = maxi(int(_team(team)["peak_population"]), int(payload.get("population", world.get_population(team))))
		"unit_produced": _team(team)["produced"] += 1
		"death":
			if team <= 0: return
			var building := String(payload.get("entity_category", "")) == "building"
			_team(team)["buildings_lost" if building else "lost"] += 1
			var killer := int(payload.get("killer_team", 0))
			if killer > 0 and killer != team and not world.are_teams_allied(killer, team):
				_team(killer)["razed" if building else "kills"] += 1
		"resource_gathered":
			if team <= 0:
				var worker = world.find_unit(int(payload.get("worker_id", -1)))
				if worker == null: return
				team = int(worker.get("team", 0))
			var resource := int(payload.get("resource_type_id", -1))
			if team > 0 and resource >= 0 and resource < 4: _team(team)["gathered"][resource] += float(payload.get("amount", 0.0))
		"tribute_paid":
			_team(int(payload.get("sender_team", 0)))["tribute_sent"] += int(payload.get("amount_sent", 0))
			_team(int(payload.get("recipient_team", 0)))["tribute_received"] += int(payload.get("amount_received", 0))
		"ownership_changed":
			var new_team := int(payload.get("new_team", 0))
			if String(payload.get("ownership_reason", "")) == "conversion": _team(new_team)["converted"] += 1
			if new_team > 0: _team(new_team)["peak_population"] = maxi(int(_team(new_team)["peak_population"]), int(payload.get("new_population", world.get_population(new_team))))
		"research_complete":
			_team(team)["research"] += 1
			var technology := int(payload.get("technology_id", -1))
			if technology in [101, 102, 103]: _marker(tick, team, "age", technology)
		"player_resigned", "player_defeated", "match_completed":
			_marker(tick, team, event_type)
			if event_type == "match_completed": finished_tick = tick

func _marker(tick: int, team: int, kind: String, value: int = 0) -> void:
	if markers.size() < MAX_MARKERS: markers.append({"tick": tick, "team": team, "kind": kind, "value": value})

func sample(world, tick: int, force: bool = false) -> void:
	if not initialized: begin(world, tick); return
	if finished_tick >= 0 and tick > finished_tick: return
	if last_tick == tick or (not force and tick - last_tick < interval_ticks): return
	var values := {}
	for team_value in world.player_registry.all_teams():
		var team := int(team_value)
		var row := _team(team)
		row["population"] = world.get_population(team)
		row["peak_population"] = maxi(int(row["peak_population"]), int(row["population"]))
		row["age"] = world.technology_system.current_age(team)
		row["status"] = world.player_registry.status(team)
		values[team] = {"population": row["population"], "age": row["age"]}
	samples.append({"tick": tick, "teams": values})
	last_tick = tick
	if world.battle_over: finished_tick = tick
	if samples.size() > MAX_SAMPLES:
		var reduced: Array = []
		for i in range(0, samples.size(), 2): reduced.append(samples[i])
		samples = reduced
		interval_ticks *= 2

func state() -> Dictionary:
	return {"teams": teams.duplicate(true), "samples": samples.duplicate(true), "markers": markers.duplicate(true), "interval_ticks": interval_ticks, "start_tick": start_tick, "last_tick": last_tick, "finished_tick": finished_tick, "initialized": initialized, "partial": partial}

static func valid_state(data: Variant) -> bool:
	if not data is Dictionary: return false
	if not data.get("teams") is Dictionary or not data.get("samples") is Array or not data.get("markers") is Array: return false
	if data["teams"].size() > 16 or data["samples"].size() > MAX_SAMPLES or data["markers"].size() > MAX_MARKERS: return false
	for team in data["teams"]:
		var row: Variant = data["teams"][team]
		if not team is int or not row is Dictionary or not row.get("gathered") is Array or row["gathered"].size() != 4: return false
	var previous := -1
	for sample in data["samples"]:
		if not sample is Dictionary or not sample.get("tick") is int or int(sample["tick"]) <= previous or not sample.get("teams") is Dictionary: return false
		previous = int(sample["tick"])
		for team in sample["teams"]:
			var row: Variant = sample["teams"][team]
			if not team is int or not row is Dictionary or not row.get("population") is int or not row.get("age") is int: return false
	for marker in data["markers"]:
		if not marker is Dictionary or not marker.get("tick") is int or not marker.get("team") is int or not marker.get("kind") is String: return false
		if marker["kind"] == "age" and (not marker.get("value") is int or int(marker["value"]) not in [101,102,103]): return false
	return true

func restore(data: Dictionary) -> void:
	reset()
	if data.is_empty(): return
	teams = data.get("teams", {}).duplicate(true)
	samples = data.get("samples", []).duplicate(true)
	markers = data.get("markers", []).duplicate(true)
	interval_ticks = maxi(SAMPLE_TICKS, int(data.get("interval_ticks", SAMPLE_TICKS)))
	start_tick = int(data.get("start_tick", 0))
	last_tick = int(data.get("last_tick", -1))
	initialized = bool(data.get("initialized", false))
	partial = bool(data.get("partial", false))
	finished_tick = int(data.get("finished_tick", -1))
