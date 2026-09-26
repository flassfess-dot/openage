class_name RoRTradeSystem
extends RefCounted

const AnimationController := preload("res://scripts/animation_controller.gd")
const FogOfWar := preload("res://scripts/fog_of_war.gd")
const OrderPipeline := preload("res://scripts/order_pipeline.gd")
const TradeProfitPolicy := preload("res://scripts/trade_profit_policy.gd")

const ARRIVAL_DISTANCE_SQUARED: float = 0.0144

var world_ref: WeakRef
var world:
	get:
		return world_ref.get_ref() if world_ref != null else null
var trade_goods_by_team: Dictionary = {}
var pool_policies_by_team: Dictionary = {}
var last_failure: String = ""


func _init(simulation_world) -> void:
	world_ref = weakref(simulation_world)


func reset() -> void:
	trade_goods_by_team.clear()
	pool_policies_by_team.clear()
	last_failure = ""


func initialize_team(team: int, policy: Dictionary = {}) -> void:
	if team <= 0 or trade_goods_by_team.has(team):
		return
	set_trade_goods(
		team,
		float(policy.get("pool_initial", 0.0)),
		float(policy.get("pool_maximum", 100.0)),
		float(policy.get("pool_recovery_per_second", 1.0))
	)


func is_trader(entity: Dictionary) -> bool:
	return bool(entity.get("components", {}).get("trade", {}).get("enabled", false))


func is_trade_dock(entity: Dictionary) -> bool:
	if entity == null:
		return false
	return float(entity.get("hp", 0.0)) > 0.0 and String(entity.get("state", "complete")) == "complete" and entity.get("unit_lineage", []).any(func(value): return int(value) == 45)


func set_resource(traders: Array, resource_type_id: int) -> String:
	if traders.is_empty():
		return "no_eligible_traders"
	for trader_value in traders:
		var trader: Dictionary = trader_value
		var trade: Dictionary = trader.get("components", {}).get("trade", {})
		if not is_trader(trader) or resource_type_id not in trade.get("allowed_input_resource_type_ids", []):
			return "invalid_trade_resource"
	for trader_value in traders:
		var trader: Dictionary = trader_value
		trader["components"]["trade"]["selected_input_resource_type_id"] = resource_type_id
		world.emit_domain_event("trade_resource_selected", {
			"trader_id": int(trader.get("id", -1)),
			"team": int(trader.get("team", 0)),
			"resource_type_id": resource_type_id,
		})
	return ""


func start_route(traders: Array, target_dock: Dictionary) -> String:
	last_failure = _validate_route_group(traders, target_dock)
	if not last_failure.is_empty():
		return last_failure
	var plans: Array = []
	for trader_value in traders:
		var trader: Dictionary = trader_value
		var trade: Dictionary = trader["components"]["trade"]
		var home: Variant = _nearest_home_dock(int(trader.get("team", 0)), target_dock, trade)
		if home == null:
			return "no_home_dock"
		plans.append({"trader": trader, "home": home})
		_register_pool(int(target_dock.get("team", 0)), trade)
	for plan_value in plans:
		var plan: Dictionary = plan_value
		var trader: Dictionary = plan["trader"]
		var trade: Dictionary = trader["components"]["trade"]
		world.halt_unit(trader, "new_trade_route")
		trade["target_dock_id"] = int(target_dock.get("id", -1))
		trade["home_dock_id"] = int(plan["home"].get("id", -1))
		trader["task"] = "trade"
		trader["target_id"] = int(target_dock.get("id", -1))
		OrderPipeline.begin(trader, "trade", int(target_dock.get("id", -1)), Vector2(target_dock.get("pos", trader.get("pos", Vector2.ZERO))), true)
		if int(trade.get("cargo_gold", 0)) > 0:
			_begin_leg(trader, plan["home"], "to_home")
		else:
			_begin_leg(trader, target_dock, "to_target")
		world.emit_domain_event("trade_route_started", {
			"trader_id": int(trader.get("id", -1)),
			"home_dock_id": int(trade.get("home_dock_id", -1)),
			"target_dock_id": int(trade.get("target_dock_id", -1)),
			"resource_type_id": int(trade.get("selected_input_resource_type_id", 1)),
		})
	return ""


func cancel(trader: Dictionary, reason: String = "cancelled") -> void:
	if not is_trader(trader):
		return
	var trade: Dictionary = trader["components"]["trade"]
	if String(trade.get("stage", "idle")) == "idle":
		return
	trade["stage"] = "holding_gold" if int(trade.get("cargo_gold", 0)) > 0 else "idle"
	trade["approach_position"] = Vector2(trader.get("pos", Vector2.ZERO))
	world.emit_domain_event("trade_route_stopped", {
		"trader_id": int(trader.get("id", -1)),
		"reason": reason,
		"cargo_gold": int(trade.get("cargo_gold", 0)),
	})


func advance_goods(context: Dictionary) -> void:
	var delta := maxf(0.0, float(context.get("delta", 0.0)))
	var teams: Array = trade_goods_by_team.keys()
	teams.sort_custom(func(left, right): return int(left) < int(right))
	for team_value in teams:
		var team := int(team_value)
		var policy: Dictionary = pool_policies_by_team.get(team, {})
		var maximum := maxf(1.0, float(policy.get("maximum", 100.0)))
		var recovery := maxf(0.0, float(policy.get("recovery", 1.0)))
		trade_goods_by_team[team] = minf(maximum, float(trade_goods_by_team.get(team, 0.0)) + recovery * delta)


func advance_unit(trader: Dictionary, delta: float) -> Dictionary:
	if not is_trader(trader):
		return _idle_result()
	var trade: Dictionary = trader["components"]["trade"]
	var stage := String(trade.get("stage", "idle"))
	if stage in ["idle", "holding_gold"]:
		trader["task"] = "idle"
		return _idle_result()
	var target: Variant = world.find_building(int(trade.get("target_dock_id", -1)))
	if not _valid_dock(target, int(trade.get("target_building_source_id", -1))) or int(target.get("team", 0)) == int(trader.get("team", 0)):
		_finish(trader, "trade_target_unavailable")
		return _idle_result()
	if stage in ["waiting_goods", "waiting_resource"]:
		if _try_load_trade_goods(trader, target):
			var home: Variant = _resolve_home_dock(trader, target)
			if home == null:
				_finish(trader, "no_home_dock")
			else:
				_begin_leg(trader, home, "to_home")
		return _idle_result()
	var dock: Variant = target if stage == "to_target" else _resolve_home_dock(trader, target)
	if dock == null:
		_finish(trader, "no_home_dock")
		return _idle_result()
	var approach := Vector2(trade.get("approach_position", trader.get("pos", Vector2.ZERO)))
	if Vector2(trader.get("pos", Vector2.ZERO)).distance_squared_to(approach) > ARRIVAL_DISTANCE_SQUARED:
		world.ensure_navigation_destination(trader, approach)
		return {"moving": world.move_unit(trader, delta), "animation_state": AnimationController.MOVE}
	world.release_unit_destination(trader)
	world.face_unit_toward(trader, Vector2(dock.get("pos", trader.get("pos", Vector2.ZERO))))
	if stage == "to_target":
		if _try_load_trade_goods(trader, target):
			var home: Variant = _resolve_home_dock(trader, target)
			if home == null:
				_finish(trader, "no_home_dock")
			else:
				_begin_leg(trader, home, "to_home")
	elif stage == "to_home":
		_deposit_gold(trader, dock)
		_begin_leg(trader, target, "to_target")
	return _idle_result()


func trade_goods(team: int) -> float:
	return float(trade_goods_by_team.get(team, 0.0))


func set_trade_goods(team: int, amount: float, maximum: float = 100.0, recovery: float = 1.0) -> void:
	trade_goods_by_team[team] = clampf(amount, 0.0, maxf(1.0, maximum))
	pool_policies_by_team[team] = {"maximum": maxf(1.0, maximum), "recovery": maxf(0.0, recovery)}


func presentation_for_dock(dock: Dictionary) -> Dictionary:
	return {
		"trade_goods": floori(trade_goods(int(dock.get("team", 0)))),
		"profit_policy": TradeProfitPolicy.metadata(),
	}


func canonical_state() -> Dictionary:
	var pools: Array = []
	var teams: Array = trade_goods_by_team.keys()
	teams.sort_custom(func(left, right): return int(left) < int(right))
	for team_value in teams:
		var team := int(team_value)
		var policy: Dictionary = pool_policies_by_team.get(team, {})
		pools.append({
			"team": team,
			"amount": float(trade_goods_by_team.get(team, 0.0)),
			"maximum": float(policy.get("maximum", 100.0)),
			"recovery": float(policy.get("recovery", 1.0)),
		})
	return {"pools": pools, "profit_policy": TradeProfitPolicy.metadata()}


func _validate_route_group(traders: Array, target_dock: Dictionary) -> String:
	if traders.is_empty():
		return "no_eligible_traders"
	for trader_value in traders:
		var trader: Dictionary = trader_value
		if not is_trader(trader) or float(trader.get("hp", 0.0)) <= 0.0:
			return "no_eligible_traders"
		var trade: Dictionary = trader["components"]["trade"]
		if not _valid_dock(target_dock, int(trade.get("target_building_source_id", -1))):
			return "invalid_trade_dock"
		if int(target_dock.get("team", 0)) == int(trader.get("team", 0)):
			return "trade_requires_foreign_dock"
		if world.visibility_system.state_at_world(int(trader.get("team", 0)), Vector2(target_dock.get("pos", Vector2.ZERO))) == FogOfWar.UNKNOWN:
			return "trade_dock_unexplored"
		if _nearest_home_dock(int(trader.get("team", 0)), target_dock, trade) == null:
			return "no_home_dock"
	return ""


func _valid_dock(dock: Variant, source_id: int) -> bool:
	if dock == null or float(dock.get("hp", 0.0)) <= 0.0 or String(dock.get("state", "complete")) != "complete":
		return false
	return dock.get("unit_lineage", []).any(func(value): return int(value) == source_id)


func _nearest_home_dock(team: int, target: Dictionary, trade: Dictionary) -> Variant:
	var source_id := int(trade.get("target_building_source_id", -1))
	var candidates: Array = world.buildings.filter(func(building): return int(building.get("team", 0)) == team and _valid_dock(building, source_id))
	if candidates.is_empty():
		return null
	candidates.sort_custom(func(left, right):
		var left_distance := Vector2(left.get("pos", Vector2.ZERO)).distance_squared_to(Vector2(target.get("pos", Vector2.ZERO)))
		var right_distance := Vector2(right.get("pos", Vector2.ZERO)).distance_squared_to(Vector2(target.get("pos", Vector2.ZERO)))
		return left_distance < right_distance or (is_equal_approx(left_distance, right_distance) and int(left.get("id", -1)) < int(right.get("id", -1)))
	)
	return candidates[0]


func _resolve_home_dock(trader: Dictionary, target: Dictionary) -> Variant:
	var trade: Dictionary = trader["components"]["trade"]
	var home: Variant = world.find_building(int(trade.get("home_dock_id", -1)))
	if _valid_dock(home, int(trade.get("target_building_source_id", -1))) and int(home.get("team", 0)) == int(trader.get("team", 0)):
		return home
	home = _nearest_home_dock(int(trader.get("team", 0)), target, trade)
	if home != null:
		trade["home_dock_id"] = int(home.get("id", -1))
	return home


func _register_pool(team: int, trade: Dictionary) -> void:
	if trade_goods_by_team.has(team):
		return
	set_trade_goods(team, float(trade.get("pool_initial", 0.0)), float(trade.get("pool_maximum", 100.0)), float(trade.get("pool_recovery_per_second", 1.0)))


func _begin_leg(trader: Dictionary, dock: Dictionary, stage: String) -> bool:
	var trade: Dictionary = trader["components"]["trade"]
	trade["stage"] = stage
	trade["approach_position"] = world.dropoff_approach_position(trader, dock)
	trader["task"] = "trade"
	trader["target_id"] = int(dock.get("id", -1))
	OrderPipeline.begin(trader, "trade", int(dock.get("id", -1)), trade["approach_position"], true)
	if not world.assign_unit_destination(trader, trade["approach_position"], false):
		_finish(trader, "trade_route_unreachable")
		return false
	return true


func _try_load_trade_goods(trader: Dictionary, target: Dictionary) -> bool:
	var trade: Dictionary = trader["components"]["trade"]
	var amount := int(trade.get("transaction_amount", 20))
	var input_resource := int(trade.get("selected_input_resource_type_id", 1))
	var owner := int(trader.get("team", 0))
	var target_team := int(target.get("team", 0))
	if world.get_resource_amount(owner, input_resource) < amount:
		trade["stage"] = "waiting_resource"
		trader["diagnostic_reason"] = "trade_waiting_resource"
		return false
	if trade_goods(target_team) + 0.0001 < float(amount):
		trade["stage"] = "waiting_goods"
		trader["diagnostic_reason"] = "trade_waiting_goods"
		return false
	var home: Variant = _resolve_home_dock(trader, target)
	if home == null:
		return false
	world.economy_system.change_resource_amount(owner, input_resource, -amount)
	trade_goods_by_team[target_team] = maxf(0.0, trade_goods(target_team) - float(amount))
	var base_gold := TradeProfitPolicy.profit_between(Vector2(home.get("pos", Vector2.ZERO)), Vector2(target.get("pos", Vector2.ZERO)), world.map_size)
	var profit_multiplier: float = float(world.technology_system.trade_profit_multiplier(owner))
	var gold := maxi(0, roundi(float(base_gold) * profit_multiplier))
	trade["cargo_goods"] = amount
	trade["cargo_gold"] = gold
	trader["diagnostic_reason"] = "trade_returning_gold"
	world.emit_domain_event("trade_goods_loaded", {
		"trader_id": int(trader.get("id", -1)),
		"target_dock_id": int(target.get("id", -1)),
		"resource_type_id": input_resource,
		"resource_spent": amount,
		"gold_value": gold,
		"base_gold_value": base_gold,
		"profit_multiplier": profit_multiplier,
		"target_trade_goods": trade_goods(target_team),
		"profit_policy": TradeProfitPolicy.POLICY_ID,
	})
	return true


func _deposit_gold(trader: Dictionary, home: Dictionary) -> void:
	var trade: Dictionary = trader["components"]["trade"]
	var gold := int(trade.get("cargo_gold", 0))
	var output_resource := int(trade.get("output_resource_type_id", 3))
	if gold > 0:
		world.economy_system.change_resource_amount(int(trader.get("team", 0)), output_resource, gold)
	trade["cargo_goods"] = 0
	trade["cargo_gold"] = 0
	trade["trip_count"] = int(trade.get("trip_count", 0)) + 1
	trader["diagnostic_reason"] = "trade_trip_complete"
	world.emit_domain_event("trade_gold_deposited", {
		"trader_id": int(trader.get("id", -1)),
		"home_dock_id": int(home.get("id", -1)),
		"gold": gold,
		"trip_count": int(trade.get("trip_count", 0)),
		"stockpile": world.get_resource_amount(int(trader.get("team", 0)), output_resource),
	})


func _finish(trader: Dictionary, reason: String) -> void:
	cancel(trader, reason)
	world.release_unit_destination(trader)
	trader["task"] = "idle"
	trader["target_id"] = -1
	trader["diagnostic_reason"] = reason
	OrderPipeline.complete(trader, reason)


func _idle_result() -> Dictionary:
	return {"moving": false, "animation_state": AnimationController.IDLE}
