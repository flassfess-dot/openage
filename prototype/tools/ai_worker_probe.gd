extends SceneTree
const Fixture=preload("res://tests/integration/test_cooperative_worker_orders.gd")
const Catalog=preload("res://scripts/resource_catalog.gd")
class ReferenceFixture extends Fixture:
	func fixture(catalog,size: Vector2i=Vector2i(32,32)):
		var result=super.fixture(catalog,size)
		result.pathfinder.set_native_enabled(false)
		result.movement_system.native_integration_enabled=false
		result.gathering_system.native_recovery_enabled=false
		return result
func _initialize() -> void:
	var fixture=ReferenceFixture.new() if "--reference" in OS.get_cmdline_user_args() else Fixture.new(); var catalog=Catalog.new(); catalog.load()
	var kind:="gold_mine"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--resource="): kind=arg.trim_prefix("--resource=")
	fixture.verify_generated_shared_gather(catalog,kind)
	for failure in fixture.failures: push_error(failure)
	var passed: bool=fixture.failures.is_empty()
	fixture.free(); print("WORKER_PROBE ",kind," passed=",passed)
	quit(0 if passed else 1)
