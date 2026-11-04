extends RefCounted

static func candidates(facts: Dictionary) -> Array:
	var age = int(facts.get("age",100))
	var danger = float(facts.get("danger",0.0))
	var army = int(facts.get("army",0))
	var workers = int(facts.get("workers",0))
	var known = int(facts.get("known",0))
	return [
		{"id":"survive","utility":danger*12.0+maxf(0.0,6.0-workers)*4.0,"steps":["shelter_workers","produce_counters","rally_defenders","repel"]},
		{"id":"pressure","utility":float(army)*2.5+float(known)*1.5-danger*3.0,"steps":["scout_target","assemble","raid_economy","reinforce"]},
		{"id":"develop","utility":maxf(0.0,24.0-workers)*1.6+10.0-danger*4.0,"steps":["secure_food","grow_workers","add_drop_sites","expand"]},
		{"id":"advance","utility":(28.0 if age<103 and workers>=10 else 0.0)-danger*4.0,"steps":["satisfy_prerequisites","reserve_resources","advance_age","apply_upgrades"]},
		{"id":"siege","utility":(float(army)*2.0+20.0 if age>=102 and known>0 else -100.0)-danger*2.0,"steps":["train_siege","assign_screen","occupy_firing_position","break_defence"]},
		{"id":"naval","utility":float(facts.get("water",0))*2.0+(20.0 if bool(facts.get("needs_transport",false)) else -10.0),"steps":["secure_dock","build_escort","load","sail","land","reinforce"]}
	]
