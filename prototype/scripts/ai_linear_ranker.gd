extends RefCounted
const VERSION=1
const FEATURE_COUNT=8

static func features(candidate: Dictionary,facts: Dictionary) -> Array:
	return [1.0,clampf(float(candidate.get("utility",0.0))/100.0,-2.0,2.0),clampf(float(facts.get("danger",0.0))/20.0,0.0,2.0),clampf(float(facts.get("army",0))/100.0,0.0,5.0),clampf(float(facts.get("workers",0))/100.0,0.0,5.0),float(int(facts.get("age",100))-100)/3.0,clampf(float(facts.get("known",0))/100.0,0.0,10.0),1.0 if String(candidate.get("id","")) in ["survive","develop"] else 0.0]

static func score(candidate: Dictionary,facts: Dictionary,model: Dictionary) -> float:
	if not valid(model): return float(candidate.get("utility",0.0))
	var row:=features(candidate,facts); var total:=0.0
	for index in range(FEATURE_COUNT): total+=float(row[index])*float(model["weights"][index])
	return total

static func valid(model: Dictionary) -> bool:
	if int(model.get("version",-1))!=VERSION or not model.get("weights") is Array or model["weights"].size()!=FEATURE_COUNT: return false
	for weight in model["weights"]:
		if not (weight is float or weight is int) or not is_finite(float(weight)) or absf(float(weight))>1000.0: return false
	return String(model.get("provenance","")).length()>0
