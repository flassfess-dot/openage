class_name RoRInputCommandRouter
extends RefCounted
# The scene owns input surfaces. This boundary owns command scheduling; both
# local and network commands retain the existing authoritative command pipeline.
static func route(command, controller, team: int, network_session, network_commands: Array, submitted_tick: int) -> void:
	if network_session == null:
		controller.enqueue_command(command, true, team)
	else:
		command.tick = maxi(int(command.tick), submitted_tick + 1)
		network_commands.append(command)
