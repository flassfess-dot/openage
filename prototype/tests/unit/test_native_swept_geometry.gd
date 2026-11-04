extends SceneTree

const REFERENCE := "res://tests/fixtures/native_swept_geometry_reference.json"
var failures: Array[String] = []

func _initialize() -> void:
	if not ClassDB.class_exists("RoRPathKernel"):
		push_error("Native path kernel required")
		quit(1)
		return
	var reference: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(REFERENCE))
	var queries: Array=[]
	for radius in [0.0,0.3,0.5,0.7,1.1]:
		for index in range(64):
			var start:=Vector2(1.5+float(index%8)*0.2,3.5+float(index/8)*5.0)
			var finish:=Vector2(60.5-float(index%5)*2.0,4.5+float((index*5)%11)*4.5)
			queries.append([start,finish,radius])
			queries.append([finish,start,radius])
		for x in [-0.001,0.0,0.3,0.5,0.7,1.1,63.5,64.0]:
			queries.append([Vector2(x,32.5),Vector2(56.5,32.5),radius])
	if queries.size()!=int(reference.query_count):
		failures.append("Reference query count differs")
	var comparisons:=0
	for kind in ["clear","wall","scattered"]:
		var mask:=PackedByteArray()
		mask.resize(64*64)
		mask.fill(1)
		for y in range(64):
			for x in range(64):
				if (kind=="wall" and x==32 and y not in [40,41,42,43]) or (kind=="scattered" and (x*19+y*13)%37==0):
					mask[y*64+x]=0
		var kernel=ClassDB.instantiate("RoRPathKernel")
		kernel.configure(64,64,1,mask)
		var expected: String=reference.answers[kind]
		for index in range(queries.size()):
			var query: Array=queries[index]
			var actual: bool=kernel.is_segment_walkable(query[0],query[1],query[2])
			if actual!=(expected[index]=="1"):
				failures.append("Swept geometry differs: %s query %d %s" % [kind,index,query])
			comparisons+=1
	for failure in failures.slice(0,12):
		push_error(failure)
	print("Native swept geometry: %d comparisons, %d failures" % [comparisons,failures.size()])
	quit(0 if failures.is_empty() else 1)
