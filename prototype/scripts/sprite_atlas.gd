class_name RoRSpriteAtlas
extends RefCounted

# Render-only atlas. Source textures, hotspots and picking masks stay intact.
# Pages and membership belong to one renderer/match and have a strict bound.
const PAGE_SIZE := 2048
const MAX_PAGES := 8
var pages: Array = []
var entries: Dictionary = {}

func clear() -> void:
	pages.clear()
	entries.clear()

func texture_for(source: Texture2D) -> Texture2D:
	if source == null: return source
	var key := source.get_rid()
	if entries.has(key): return entries[key]
	var size := Vector2i(source.get_size())
	if size.x + 2 > PAGE_SIZE or size.y + 2 > PAGE_SIZE: return source
	var page: Dictionary = pages.back() if not pages.is_empty() else {}
	if not page.is_empty() and int(page.x) + size.x + 1 > PAGE_SIZE:
		page.x = 1
		page.y = int(page.y) + int(page.row)
		page.row = 0
	if page.is_empty() or int(page.y) + size.y + 1 > PAGE_SIZE:
		if pages.size() >= MAX_PAGES: return source
		var pixels := Image.create(PAGE_SIZE, PAGE_SIZE, false, Image.FORMAT_RGBA8)
		pixels.fill(Color.TRANSPARENT)
		page = {"image": pixels, "texture": ImageTexture.create_from_image(pixels), "x": 1, "y": 1, "row": 0, "dirty": false}
		pages.append(page)
	var pixels := source.get_image()
	if pixels == null or pixels.is_empty(): return source
	if pixels.is_compressed() and pixels.decompress() != OK: return source
	if pixels.get_format() != Image.FORMAT_RGBA8: pixels.convert(Image.FORMAT_RGBA8)
	var position := Vector2i(int(page.x), int(page.y))
	page.image.blit_rect(pixels, Rect2i(Vector2i.ZERO, size), position)
	page.dirty = true
	page.x = position.x + size.x + 2
	page.row = maxi(int(page.row), size.y + 2)
	var result := AtlasTexture.new()
	result.atlas = page.texture
	result.region = Rect2(Vector2(position), Vector2(size))
	result.filter_clip = true
	entries[key] = result
	return result

func flush() -> void:
	for page in pages:
		if bool(page.dirty):
			page.texture.update(page.image)
			page.dirty = false
