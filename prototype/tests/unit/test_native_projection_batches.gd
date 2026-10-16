extends SceneTree
const Cache := preload("res://scripts/render_entity_projection_cache.gd")
const Journal := preload("res://scripts/entity_change_journal.gd")
var failures: Array[String] = []
func _initialize() -> void:
	var fast := Cache.new()
	var reference := Cache.new()
	reference.native_kernel = null
	var journal := Journal.new()
	var rows: Array = []
	for id in range(1,25):
		rows.append({"id":id,"kind":"villager","entity_type":"unit","pos":Vector2(id*0.2,2),"previous_pos":Vector2.ZERO,"hp":100.0,"max_hp":100.0,"anim":0.0,"task":"idle","team":1,"components":{"ownership":{"civilization_id":3},"cargo":{"enabled":true,"capacity":5,"passenger_ids":[5,6]}},"path":[Vector2.ONE]})
		journal.mark(id,Journal.ALL)
	var old: Array = []
	for step in range(20):
		for row in rows:
			match step%8:
				0: row["pos"] += Vector2(0.1,0.2); journal.mark(row["id"],Journal.POSITION)
				1: row["work"] = step; journal.mark(row["id"],Journal.ACTIVITY|Journal.CONTROL)
				2: row["hp"] -= 1; journal.mark(row["id"],Journal.COMBAT)
				3: row["amount"] = step; journal.mark(row["id"],Journal.ECONOMY)
				4: row["source_unit_id"] = step; journal.mark(row["id"],Journal.APPEARANCE)
				5: row["team"] = 2; journal.mark(row["id"],Journal.OWNERSHIP)
				6: row["anim"] = step*0.05; row["previous_pos"] = row["pos"]
		var actual := fast.project_many(rows,journal)
		var expected: Array = []
		for row in rows: expected.append(reference.project(row,journal))
		check(actual==expected,"batch equals scalar projection at step %d"%step)
		check(actual.all(func(row): return row.is_read_only() and not row.has("path") and not row["components"]["cargo"].has("passenger_ids")),"readonly records preserve privacy")
		if step==0: old=actual.duplicate(true)
		if step>0: check(old[0]["hp"]==100.0,"new batches do not mutate old publications")
	journal.reset()
	for row in rows: journal.mark(row["id"],Journal.ALL)
	check(fast.project_many(rows,journal)==rows.map(func(row):return reference.project(row,journal)),"world reset invalidates batch versions")
	var kernel=fast.native_kernel
	var fog:=PackedByteArray()
	fog.resize(100)
	fog[22]=2
	var candidates:Array=[{"team":1,"pos":Vector2(-4,-4)},{"team":2,"pos":Vector2(2.5,2.5)},{"team":2,"pos":Vector2(3,3)},{"team":2,"pos":Vector2(-0.1,2)},{"team":2,"pos":Vector2(10,2)}]
	check(kernel.filter_visible_entities(candidates,1,fog,Vector2i(10,10))==candidates.slice(0,2),"visibility respects own, visible, hidden and outside cells")
	check(kernel.filter_visible_entities(candidates,0,fog,Vector2i(10,10))==candidates,"spectator includes every candidate")
	for failure in failures: push_error(failure)
	print("Native projection batches: %d failures"%failures.size())
	quit(0 if failures.is_empty() else 1)
func check(value:bool,message:String)->void:
	if not value: failures.append(message)
