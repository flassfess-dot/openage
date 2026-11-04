# Evaluator only: exercise the opening selector on actual public dev seeds.
extends SceneTree
const Macro = preload("res://scripts/ai_macro_plan.gd")
const Policy = preload("res://scripts/skirmish_ai_policy.gd")

func _initialize() -> void:
	var output := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): output = argument.trim_prefix("--output=")
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/ai/arena/manifests/dev.json"))
	if output.is_empty() or not manifest is Dictionary or manifest.get("rows",[]).size() < 20:
		push_error("Twenty dev seeds and an output path are required")
		quit(1)
		return
	var policy: Dictionary = Policy.resolve("random_map_balanced","standard")
	policy.merge(policy.get("competitive_parameters",{}),true)
	var counts: Dictionary = {}
	var rows: Array = []
	var repeated := true
	var immutable_inputs := true
	for case in manifest["rows"].slice(0,20):
		for team in [1,2]:
			var snapshot := {"match_seed":int(case["settings"]["seed"]),"observer_team":team}
			var before := var_to_bytes([snapshot,policy])
			var style: String = Macro.opening(snapshot,policy)
			repeated = repeated and style == Macro.opening(snapshot.duplicate(true),policy.duplicate(true))
			immutable_inputs = immutable_inputs and before == var_to_bytes([snapshot,policy])
			counts[style] = int(counts.get(style,0))+1
			rows.append({"base_id":case["id"],"seed":snapshot["match_seed"],"team":team,
				"map_type":case["settings"]["map_type_id"],"civilization":case["civilizations"][0],"style":style})
	var passed: bool = rows.size()==40 and counts.size()==4 and repeated and immutable_inputs
	var file := FileAccess.open(output,FileAccess.WRITE)
	if file == null:
		push_error("Opening diversity output is not writable")
		quit(1)
		return
	file.store_string(JSON.stringify({"passed":passed,"dev_seeds":20,"positions":40,"style_counts":counts,
		"same_seed_repeats":repeated,"inputs_unchanged":immutable_inputs,"rows":rows,
		"scope":"Opening-family selector on the first20 actual dev seeds, both seats, standard competitive parameters. Does not establish full first-command diversity or context-sensitive map/civilization choice."},"\t"))
	file.close()
	print("DEV_OPENING_DIVERSITY ",rows.size()," positions; styles=",counts," repeat=",repeated," pure=",immutable_inputs)
	quit(0 if passed else 1)
