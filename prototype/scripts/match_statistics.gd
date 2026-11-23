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
	if tick % SAMPLE_TICKS == 0 or force:
		update_scores(world)
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

# The categories and weights are recorded in doc/reverse_engineering/scoring.md.
# Count the roster once per sample, independently of viewport size and HUD refresh.
func update_scores(world) -> void:
	var metrics := {}
	for team in world.player_registry.all_teams():
		var row := _team(team)
		metrics[team] = {"workers": 0, "military": 0, "temples": 0,
			"explored": world.get_fog_of_war().personally_explored_by_player.get(team, {}).size(),
			"converted": row["converted"], "research": row["research"]}
	for unit in world.get_all_units_including_embarked():
		var counts: Dictionary = metrics.get(int(unit.get("team", 0)), {})
		if counts.is_empty() or float(unit.get("hp", 0)) <= 0: continue
		if world.entity_is_worker(unit) or unit["kind"] in ["trade_boat", "transport"]:
			counts["workers"] += 1
		elif unit.get("combat_enabled", false):
			counts["military"] += 1
	for building in world.get_buildings():
		var counts: Dictionary = metrics.get(int(building.get("team", 0)), {})
		if counts.is_empty() or float(building.get("hp", 0)) <= 0 or building.get("state") != "complete": continue
		if building["kind"] == "tower": counts["military"] += 1
		if building["kind"] == "temple": counts["temples"] += 1
	var age_leaders := {}
	for marker in markers:
		if marker["kind"] == "age" and marker["value"] in [102, 103] and not age_leaders.has(marker["value"]):
			age_leaders[marker["value"]] = marker["team"]
	for team in metrics:
		var row: Dictionary = teams[team]
		var counts: Dictionary = metrics[team]
		var kills := int(row["kills"])
		var ledger: Dictionary = world.economy_system.resource_ledger_by_team.get(team, {})
		var points := floori(kills * 0.5) + int(row["razed"]) + maxi(0, kills - int(row["lost"]))
		var gold := int(ledger.get("income", [0, 0, 0, 0])[3])
		gold += int(ledger.get("categories", {}).get("trade_in", [0, 0, 0, 0])[3])
		points += floori(gold / 100.0)
		points += floori(maxi(0, int(row["tribute_sent"]) - int(row["tribute_received"])) / 60.0)
		points += int(counts["workers"]) + floori(int(counts["explored"]) * 100.0 / maxi(1, world.map_size.x * world.map_size.y) / 3.0)
		points += 2 * int(row["converted"]) + 3 * int(counts["temples"]) + 2 * int(row["research"])
		for category in ["ruin", "artifact", "wonder"]:
			var summary: Dictionary = world.victory_system.objective_summary.get(category, {})
			var owned := int(summary.get("completed_by_team", {}).get(team, 0))
			points += owned * (100 if category == "wonder" else 10)
			if category != "wonder" and owned > 0 and owned == int(summary.get("total", 0)): points += 50
		for first in age_leaders.values():
			if first == team: points += 25
		if world.player_registry.status(team) in ["active", "victorious"]: points += 100
		row["score"] = points
	var bonuses := {"military": 25, "workers": 25, "explored": 25, "converted": 25, "research": 50}
	for category in bonuses:
		var leader := -1
		var highest := 0
		for team in metrics:
			var value := int(metrics[team][category])
			var previous: bool = teams[team].get("score_leads", {}).has(category)
			if value > highest or (value > 0 and value == highest and previous):
				highest = value
				leader = team
		for team in metrics:
			var bonuses_held: Dictionary = teams[team].get_or_add("score_leads", {})
			if team == leader:
				teams[team]["score"] += int(bonuses[category])
				bonuses_held[category] = true
			else: bonuses_held.erase(category)

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
