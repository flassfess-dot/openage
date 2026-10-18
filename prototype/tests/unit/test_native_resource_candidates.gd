extends SceneTree
const Economy := preload("res://scripts/ai_adaptive_economy.gd")
const Index := preload("res://scripts/ai_resource_spatial_index.gd")
const Legacy := preload("res://scripts/ai_economic_planner.gd")
const Data := preload("res://scripts/isolated_task_data.gd")
var failures: Array[String] = []
func _initialize() -> void:
	var index := Index.new()
	if index.native_kernel == null or not index.native_kernel.has_method("query_resource_candidates") or not index.native_kernel.has_method("build_resource_buckets") or not index.native_kernel.has_method("infrastructure_site_bonuses"):
		push_error("Native resource candidate kernel is required")
		quit(1)
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 19091998
	var resources: Array = []
	for id in range(1, 2401):
		resources.append({"id":id,"pos":Vector2(rng.randf_range(-128,400),rng.randf_range(-128,400)),"resource_type_id":id % 4,"allowed_gatherer_domains":[[],["land"],["water"],["land","water"]][id % 4],"amount":100})
	var sites: Array = [Vector2.ZERO,Vector2(15.5,16.5),Vector2(-10,22),Vector2(400,400)]
	if not index.native_kernel.has_method("economy_resource_view"): failures.append("Native economy view is required")
	var deposits: Array = resources.duplicate(true)
	deposits[0]["amount"] = 0
	deposits[1]["amount"] = -1
	var farms: Array = [{"id":9001,"amount":50,"harvestable":true,"team":1,"resource_type_id":0},{"id":9002,"amount":50,"harvestable":true,"team":2},{"id":9003,"amount":0,"harvestable":true,"team":1},{"id":9004,"amount":50,"team":1},deposits[10].duplicate()]
	farms[-1].merge({"team":1,"harvestable":true,"resource_type_id":3},true)
	for team in [0,1,2]:
		var expected_view := Economy._economy_resources(deposits,farms,team,false)
		var actual_view := Economy._economy_resources(deposits,farms,team,true)
		if actual_view != expected_view: failures.append("Active deposits, farm ownership, order or duplicate IDs changed")
	if not index.native_kernel.has_method("reachable_cell_lookup"): failures.append("Native reachable lookup is required")
	for navigation in [{},{"reachable":{"land":[],"water":[]}},{"reachable":{"land":[Vector2(2.8,-3.2),Vector2i(5,7),Vector2(2.1,-3.8)],"water":[Vector2(-0.9,0.8)]}}]:
		Legacy.native_reachable_lookup_enabled = false
		var expected_reach := Legacy._reachable_cells_by_domain(navigation)
		Legacy.native_reachable_lookup_enabled = true
		if Legacy._reachable_cells_by_domain(navigation) != expected_reach: failures.append("Reachable cells changed for empty domains, duplicates or fractional coordinates")
	var retained_index := Index.new()
	var reference_index := Index.new()
	reference_index.native_enabled = false
	var retained_rows: Array = resources.slice(0,100).duplicate(true)
	var previous_buckets: Dictionary = {}
	for change in range(8):
		match change:
			1: retained_rows[5]["amount"] = 73
			2: retained_rows[5]["pos"] += Vector2(8,0)
			3: retained_rows[5]["resource_type_id"] = 2
			4: retained_rows[5]["allowed_gatherer_domains"] = ["water"]
			5: retained_rows.remove_at(5)
			6: retained_rows.reverse()
			7: retained_rows.append({"id":9000,"amount":100,"pos":Vector2(2,3),"resource_type_id":1})
		var frozen: Array = Data.capture_frozen({"rows":retained_rows})["rows"]
		retained_index.rebuild(frozen,["land","water"],false,true)
		reference_index.rebuild(frozen,["land","water"],false,true)
		if retained_index.bucket_lists_by_domain != reference_index.bucket_lists_by_domain or retained_index.buckets_by_resource_type != reference_index.buckets_by_resource_type: failures.append("Retained resource index differs after change "+str(change))
		if change == 1 and not is_same(previous_buckets,retained_index.bucket_lists_by_domain): failures.append("Amount-only updates rebuilt the spatial index")
		for domain in ["land","water"]:
			for type_id in range(4):
				if retained_index.candidates(Vector2(4,7),domain,type_id,12) != reference_index.candidates(Vector2(4,7),domain,type_id,12): failures.append("Retained candidate order or row data changed")
		previous_buckets = retained_index.bucket_lists_by_domain
	if not retained_index.native_kernel.has_method("refresh_resource_bucket_rows"): failures.append("Native retained resource updates are required")
	for kind in ["granary","storage_pit","town_center"]:
		if Economy._site_resource_bonuses(resources,sites,kind,false) != Economy._site_resource_bonuses(resources,sites,kind,true): failures.append("Infrastructure resource distances differ for "+kind)
		if Economy._site_resource_bonuses([],sites,kind,false) != Economy._site_resource_bonuses([],sites,kind,true): failures.append("Empty infrastructure score differs")
	for reverse in [false,true]:
		if reverse: resources.reverse()
		for unrestricted in [false,true]:
			for typed in [false,true]:
				index.native_enabled = false
				index.rebuild(resources,["land","water","land"],unrestricted,typed)
				var lists: Dictionary = index.bucket_lists_by_domain
				var types: Dictionary = index.buckets_by_resource_type
				index.native_enabled = true
				index.rebuild(resources,["land","water","land"],unrestricted,typed)
				if index.bucket_lists_by_domain != lists or index.buckets_by_resource_type != types: failures.append("Native bucket rebuild differs")
		index.rebuild(resources,["land","water"],false,true)
		for sample in range(40):
			var position := Vector2(rng.randf_range(-150,450),rng.randf_range(-150,450))
			_compare(index,position,"land",sample % 4,12)
			_compare(index,position,"water",sample % 4,1 + sample % 15)
			_compare(index,position,"air",sample % 4,0)
	var dense: Array = []
	for id in range(180,0,-1):
		dense.append({"id":id,"pos":Vector2(float(id % 8),float(id % 7)),"resource_type_id":1})
	index.rebuild(dense,["land"],true,true)
	for position in [Vector2.ZERO,Vector2(4,4),Vector2(8,8),Vector2(8.00001,7.99999),Vector2(-8,-8)]:
		for maximum in [0,1,12,100,1000]: _compare(index,position,"land",1,maximum)
	index.rebuild([],["land","water"],false,true)
	_compare(index,Vector2.ZERO,"land",0,12)
	for message in failures: push_error(message)
	print("Native resource candidates: %d failures" % failures.size())
	quit(0 if failures.is_empty() else 1)
func _compare(index, position: Vector2, domain: String, type_id: int, maximum: int) -> void:
	index.native_enabled = false
	var expected: Array = index.candidates(position,domain,type_id,maximum)
	index.native_enabled = true
	var actual: Array = index.candidates(position,domain,type_id,maximum)
	if actual != expected:
		failures.append("Native candidate order differs at %s domain=%s type=%d max=%d" % [position,domain,type_id,maximum])
	for i in range(mini(actual.size(),expected.size())):
		if not is_same(actual[i],expected[i]): failures.append("Candidate query copied or replaced the observer's legal resource record")
