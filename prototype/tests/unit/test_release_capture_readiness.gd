extends SceneTree
const Verifier=preload("res://tests/manual/verify_packaged_startup.gd")
func _initialize() -> void:
	var image:=Image.create(512,256,false,Image.FORMAT_RGB8); image.fill(Color.BLACK)
	image.fill_rect(Rect2i(0,0,512,20),Color.WHITE); image.fill_rect(Rect2i(0,220,512,36),Color.WHITE)
	if Verifier.has_visible_world(image): push_error("HUD alone must not pass rendered-world readiness"); quit(1); return
	image.fill_rect(Rect2i(200,80,100,80),Color.FOREST_GREEN)
	if not Verifier.has_visible_world(image): push_error("A rendered terrain region must pass readiness"); quit(1); return
	print("Release capture readiness passed"); quit(0)
