class_name RoRVictorySystem
extends RefCounted

var rules: Array = [{"type": "conquest"}]
var elapsed_seconds: float = 0.0
var hold_seconds: Dictionary = {}
var result: Dictionary = {"over": false, "winner_team": -1, "winner_teams": [], "loser_teams": [], "reason": ""}


func configure(new_rules: Array) -> void:
	rules = new_rules.duplicate(true) if not new_rules.is_empty() else [{"type": "conquest"}]
	reset()


func reset() -> void:
	elapsed_seconds = 0.0
	hold_seconds.clear()
	result = {"over": false, "winner_team": -1, "winner_teams": [], "loser_teams": [], "reason": ""}


func update(delta: float, context: Dictionary) -> Dictionary:
	if bool(result.get("over", false)):
		return result
	elapsed_seconds += maxf(0.0, delta)
	var all_teams: Array = context.get("teams", [])
	var states: Dictionary = context.get("player_states", {})
	var teams: Array = all_teams.filter(func(team): return String(states.get(int(team), {}).get("status", "active")) == "active")
	for rule_value in rules:
		var rule: Dictionary = rule_value
		var rule_type := String(rule.get("type", "conquest"))
		match rule_type:
			"conquest":
				var winners := conquest_winners(teams, context)
				if not winners.is_empty():
					return finish_side(winners, all_teams, "conquest")
			"artifacts", "ruins":
				var winner := held_object_winner(rule_type.trim_suffix("s"), rule, teams, context, delta)
				if winner >= 0:
					return finish(winner, all_teams, rule_type)
			"wonder":
				var winner := wonder_winner(rule, teams, context, delta)
				if winner >= 0:
					return finish(winner, all_teams, "wonder")
			"score":
				var winner := score_winner(rule, teams, context)
				if winner >= 0:
					return finish(winner, all_teams, "score")
			"scenario":
				var winner := scenario_winner(rule, teams, context)
				if winner >= 0:
					return finish(winner, all_teams, "scenario")
			"scenario_definition":
				var winner := int(context.get("scenario_result", {}).get("winner_team", -1))
				if bool(context.get("scenario_result", {}).get("over", false)) and winner >= 0:
					return finish(winner, all_teams, "scenario")
	return result


func conquest_winner(teams: Array, context: Dictionary) -> int:
	var winners := conquest_winners(teams, context)
	return -1 if winners.is_empty() else int(winners[0])


func conquest_winners(teams: Array, context: Dictionary) -> Array[int]:
	var active: Array[int] = []
	var conquest_presence: Variant = context.get("conquest_presence")
	for team_value in teams:
		var team := int(team_value)
		var has_units: bool = bool(conquest_presence.get(team, false)) if conquest_presence != null else context.get("units", []).any(func(unit): return int(unit.get("team", 0)) == team and float(unit.get("hp", 0.0)) > 0.0)
		var has_buildings: bool = false if conquest_presence != null else context.get("buildings", []).any(func(building): return int(building.get("team", 0)) == team and float(building.get("hp", 0.0)) > 0.0 and bool(building.get("counts_for_conquest", true)))
		if has_units or has_buildings:
			active.append(team)
	if active.is_empty() or int(context.get("participant_count", teams.size())) <= 1:
		return []
	active.sort()
	if active.size() == 1:
		return active
	var relations: Dictionary = context.get("relations", {})
	for first_index in range(active.size()):
		for second_index in range(first_index + 1, active.size()):
			var first := active[first_index]
			var second := active[second_index]
			if String(relations.get(first, {}).get(second, "enemy")) != "ally" or String(relations.get(second, {}).get(first, "enemy")) != "ally":
				return []
	return active


func held_object_winner(category: String, rule: Dictionary, teams: Array, context: Dictionary, delta: float) -> int:
	var objectives: Array = context.get("objectives", []).filter(func(item): return String(item.get("category", "")) == category and bool(item.get("active", true)))
	var required_count := int(rule.get("required_count", objectives.size()))
	if required_count <= 0:
		return -1
	for team_value in teams:
		var team := int(team_value)
		var owned := objectives.filter(func(item): return int(item.get("team", 0)) == team).size()
		var key := "%s:%d" % [category, team]
		hold_seconds[key] = float(hold_seconds.get(key, 0.0)) + delta if owned >= required_count else 0.0
		if owned >= required_count and float(hold_seconds[key]) + 0.000001 >= float(rule.get("hold_seconds", 0.0)):
			return team
	return -1


func wonder_winner(rule: Dictionary, teams: Array, context: Dictionary, delta: float) -> int:
	for team_value in teams:
		var team := int(team_value)
		var owns_wonder: bool = context.get("objectives", []).any(func(item): return String(item.get("category", "")) == "wonder" and int(item.get("team", 0)) == team and bool(item.get("active", true)) and bool(item.get("completed", false)))
		var key := "wonder:%d" % team
		hold_seconds[key] = float(hold_seconds.get(key, 0.0)) + delta if owns_wonder else 0.0
		if owns_wonder and float(hold_seconds[key]) + 0.000001 >= float(rule.get("hold_seconds", 0.0)):
			return team
	return -1


func score_winner(rule: Dictionary, teams: Array, context: Dictionary) -> int:
	var scores: Dictionary = context.get("scores", {})
	var limit := int(rule.get("score_limit", 0))
	var time_limit := float(rule.get("time_limit_seconds", 0.0))
	var eligible: Array[int] = []
	for team_value in teams:
		var team := int(team_value)
		if limit > 0 and int(scores.get(team, 0)) >= limit:
			eligible.append(team)
	if eligible.is_empty() and time_limit > 0.0 and elapsed_seconds + 0.000001 >= time_limit:
		eligible.assign(teams)
	if eligible.is_empty():
		return -1
	eligible.sort_custom(func(left, right):
		var left_score := int(scores.get(left, 0))
		var right_score := int(scores.get(right, 0))
		return left_score > right_score or (left_score == right_score and left < right)
	)
	return eligible[0]


func scenario_winner(rule: Dictionary, teams: Array, context: Dictionary) -> int:
	var team := int(rule.get("winner_team", teams[0] if not teams.is_empty() else -1))
	if team < 0:
		return -1
	for condition_value in rule.get("conditions", []):
		if not scenario_condition_met(condition_value, team, context):
			return -1
	return team


func scenario_condition_met(condition_value: Variant, default_team: int, context: Dictionary) -> bool:
	var condition: Dictionary = condition_value
	var team := int(condition.get("team", default_team))
	match String(condition.get("type", "")):
		"elapsed":
			return elapsed_seconds >= float(condition.get("seconds", 0.0))
		"score":
			return int(context.get("scores", {}).get(team, 0)) >= int(condition.get("amount", 0))
		"resource":
			return int(context.get("resources", {}).get(team, {}).get(int(condition.get("resource_id", 0)), 0)) >= int(condition.get("amount", 0))
		"technology":
			return context.get("technologies", {}).get(team, []).has(int(condition.get("technology_id", -1)))
		"destroy_team":
			var target := int(condition.get("target_team", -1))
			var target_units: bool = context.get("units", []).any(func(unit): return int(unit.get("team", 0)) == target and float(unit.get("hp", 0.0)) > 0.0)
			var target_buildings: bool = context.get("buildings", []).any(func(building): return int(building.get("team", 0)) == target and float(building.get("hp", 0.0)) > 0.0)
			return not target_units and not target_buildings
		"own_object":
			return context.get("objectives", []).any(func(item): return int(item.get("id", -1)) == int(condition.get("object_id", -1)) and int(item.get("team", 0)) == team and bool(item.get("active", true)))
	return false


func finish(winner_team: int, teams: Array, reason: String) -> Dictionary:
	return finish_side([winner_team], teams, reason)


func finish_side(winner_teams_value: Array, teams: Array, reason: String) -> Dictionary:
	var winners: Array[int] = []
	for team_value in winner_teams_value:
		var team := int(team_value)
		if team >= 0 and team not in winners:
			winners.append(team)
	winners.sort()
	if winners.is_empty():
		return result
	var losers: Array[int] = []
	for team_value in teams:
		if int(team_value) not in winners:
			losers.append(int(team_value))
	result = {"over": true, "winner_team": winners[0], "winner_teams": winners, "loser_teams": losers, "reason": reason}
	return result
