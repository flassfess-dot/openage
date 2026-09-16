class_name RoRPlayerRegistry
extends RefCounted

const ACTIVE := "active"
const RESIGNED := "resigned"
const DEFEATED := "defeated"
const VICTORIOUS := "victorious"
const ALLY := "ally"
const NEUTRAL := "neutral"
const ENEMY := "enemy"
const VALID_RELATIONS := [ALLY, NEUTRAL, ENEMY]

var players: Dictionary = {}
var relations: Dictionary = {}


func _init() -> void:
	configure([
		{"team": 1, "controller": "human", "civilization_id": 13},
		{"team": 2, "controller": "ai", "civilization_id": 13},
	])


func configure(definitions: Array) -> void:
	players.clear()
	relations.clear()
	for definition_value in definitions:
		var definition: Dictionary = definition_value
		var team := int(definition.get("team", 0))
		if team <= 0:
			continue
		players[team] = {
			"team": team,
			"controller": String(definition.get("controller", "ai")),
			"civilization_id": int(definition.get("civilization_id", 13)),
			"status": ACTIVE,
		}
		relations[team] = {team: ALLY}


func ensure(team: int, civilization_id: int = 13, controller: String = "unknown") -> void:
	if team <= 0 or players.has(team):
		return
	players[team] = {"team": team, "controller": controller, "civilization_id": civilization_id, "status": ACTIVE}
	relations[team] = {team: ALLY}


func reset_match() -> void:
	reset_statuses()
	for team in players:
		relations[team] = {int(team): ALLY}


func reset_statuses() -> void:
	for team in players:
		players[team]["status"] = ACTIVE


func set_civilization(team: int, civilization_id: int) -> void:
	ensure(team, civilization_id)
	players[team]["civilization_id"] = civilization_id


func set_relation(first_team: int, second_team: int, relation: String) -> void:
	if first_team <= 0 or second_team <= 0:
		return
	ensure(first_team)
	ensure(second_team)
	var normalized := relation if relation in VALID_RELATIONS else ENEMY
	if first_team == second_team:
		normalized = ALLY
	relations[first_team][second_team] = normalized


func set_mutual_relation(first_team: int, second_team: int, relation: String) -> void:
	set_relation(first_team, second_team, relation)
	set_relation(second_team, first_team, relation)


func relation(first_team: int, second_team: int) -> String:
	if first_team <= 0 or second_team <= 0:
		return ENEMY
	if first_team == second_team:
		return ALLY
	return String(relations.get(first_team, {}).get(second_team, ENEMY))


func relations_for(team: int) -> Dictionary:
	var result: Dictionary = {}
	for other_team in all_teams():
		result[other_team] = relation(team, other_team)
	return result


func are_allied(first_team: int, second_team: int) -> bool:
	return relation(first_team, second_team) == ALLY


func resign(team: int) -> bool:
	if not players.has(team) or String(players[team].get("status", ACTIVE)) != ACTIVE:
		return false
	players[team]["status"] = RESIGNED
	return true


func defeat(team: int) -> bool:
	if not players.has(team) or String(players[team].get("status", ACTIVE)) != ACTIVE:
		return false
	players[team]["status"] = DEFEATED
	return true


func finalize(winner_team: int, loser_teams: Array) -> void:
	finalize_side([winner_team], loser_teams)


func finalize_side(winner_teams: Array, loser_teams: Array) -> void:
	for team_value in winner_teams:
		var team := int(team_value)
		if players.has(team) and String(players[team].get("status", ACTIVE)) == ACTIVE:
			players[team]["status"] = VICTORIOUS
	for team_value in loser_teams:
		var team := int(team_value)
		if players.has(team) and String(players[team].get("status", ACTIVE)) == ACTIVE:
			players[team]["status"] = DEFEATED


func status(team: int) -> String:
	return String(players.get(team, {}).get("status", "unknown"))


func all_teams() -> Array[int]:
	var result: Array[int] = []
	for team in players.keys():
		result.append(int(team))
	result.sort()
	return result


func active_teams() -> Array[int]:
	return all_teams().filter(func(team): return status(int(team)) == ACTIVE)


func allied_teams(team: int) -> Array[int]:
	var result: Array[int] = []
	for other_team in all_teams():
		if are_allied(team, other_team):
			result.append(other_team)
	return result


func public_states() -> Array:
	var result: Array = []
	for team in all_teams():
		result.append(players[team].duplicate(true))
	return result


func canonical_state() -> Dictionary:
	return {"players": players.duplicate(true), "relations": relations.duplicate(true)}
