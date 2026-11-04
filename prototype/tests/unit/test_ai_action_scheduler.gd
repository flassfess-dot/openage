extends SceneTree
const Scheduler=preload("res://scripts/ai_action_scheduler.gd")
const Commands=preload("res://scripts/commands.gd")
const State=preload("res://scripts/ai_strategy_state.gd")
const Operations=preload("res://scripts/ai_operations.gd")
const Policy=preload("res://scripts/skirmish_ai_policy.gd")
var failures: Array[String]=[]
func _initialize() -> void:
	for difficulty in ["easy","standard","hard"]:
		var parameters: Dictionary=Policy.resolve("random_map_balanced",difficulty)["competitive_parameters"]
		var scheduler=Scheduler.new(); var state=State.new(); var operations=Operations.new()
		var commands: Array=[]
		for n in range(12): commands.append(Commands.MoveCommand.new(0,[n+1],Vector2(4,4)))
		var total:=0; var restored=Scheduler.new()
		for tick in range(0,1201,4):
			var result: Array=scheduler.admit(commands,tick,parameters,state,operations)
			total+=result.size()
			if tick==600: check(restored.restore_state(scheduler.canonical_state()),"bucket restores")
			elif tick>600:
				check(restored.admit(commands,tick,parameters,State.new(),operations).size()==result.size(),"restored token bucket emits same actions")
		check(total<=int(parameters["commands_per_minute"])+int(parameters["command_burst"]),"one-minute action budget is enforced including the initial burst")
		var snapshot:={"units":[{"id":8,"team":2}],"buildings":[],"player_state":{"allies":[1]}}
		var delay:=int(parameters["reaction_ticks"])
		check(Scheduler.new().react(snapshot,0,1,parameters)["units"].is_empty(),"new enemy cannot be targeted instantly")
		var reaction=Scheduler.new(); reaction.react(snapshot,0,1,parameters)
		check(reaction.react(snapshot,delay-1,1,parameters)["units"].is_empty(),"reaction before threshold remains pending")
		check(reaction.react(snapshot,delay,1,parameters)["units"].size()==1,"reaction matures on a fixed simulation tick")
	var crowded:={"units":[],"buildings":[],"player_state":{"allies":[1]}}
	for id in range(1,5001): crowded["units"].append({"id":id,"team":2})
	var large=Scheduler.new()
	check(large.react(crowded,0,1,{"reaction_ticks":4})["units"].is_empty(),"large contact still has reaction delay")
	check(large.react(crowded,4,1,{"reaction_ticks":4})["units"].size()==5000,"high IDs do not starve when more than1024 enemies are visible")
	check(Scheduler.new().restore_state(large.canonical_state()),"large contact restores without resetting reactions")
	for failure in failures: push_error(failure)
	print("Action scheduler: ",failures.size()," failures"); quit(0 if failures.is_empty() else 1)
func check(value: bool,message: String) -> void:
	if not value: failures.append(message)
