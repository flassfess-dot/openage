class_name RoRShorelinePresentation
extends RefCounted
const Coordinates := preload("res://scripts/coordinates.gd")
const MAX_CACHED_MESHES := 256
static var meshes: Dictionary={}
static var prepared_cache_enabled := true
static var profile_prepared_cache := "--profile-shore-cache-alternatives" in OS.get_cmdline_user_args()
static var profile_frame := 0
static var prepared_cache_active := true

static func begin_frame(canvas: CanvasItem) -> void:
 profile_frame+=1
 prepared_cache_active=prepared_cache_enabled and (not profile_prepared_cache or profile_frame%2==0)
 # Canvas drawing commands retain RIDs, not the RefCounted mesh. Keep the
 # current and two previous command sets alive even when the cache evicts one.
 var frames: Array=canvas.get_meta("shore_mesh_frames",[{},{},{}])
 frames.push_front({});frames.resize(3)
 canvas.set_meta("shore_mesh_frames",frames)

static func retained_mesh(canvas: CanvasItem,feature: Dictionary,profile: int,probe = null,prepared_key: Variant=null) -> ArrayMesh:
 if prepared_key!=null:
  var key:=int(prepared_key)
  # Array/Dictionary values in metadata are shared references. Avoid building
  # unused default dictionaries, and update the retained command set in place.
  var value:Variant=canvas.get_meta("shore_mesh_frames",null)
  var frames:Array=value if value is Array else [{},{},{}]
  if not value is Array:canvas.set_meta("shore_mesh_frames",frames)
  var mesh:ArrayMesh=meshes.get(key)
  if mesh==null:mesh=frames[1].get(key)
  if mesh==null:mesh=frames[2].get(key)
  if mesh==null:
   mesh=_build_measured_mesh(feature,profile,probe)
   if meshes.size()>=MAX_CACHED_MESHES:meshes.erase(meshes.keys()[0])
   meshes[key]=mesh
  frames[0][key]=mesh
  return mesh
 var key:=hash([feature["position"],feature["shore_form"],profile])
 var frames:Array=canvas.get_meta("shore_mesh_frames",[{},{},{}])
 var mesh:ArrayMesh=meshes.get(key)
 if mesh==null:
  # An overview can show more strips than fit in the shared cache. Reuse
  # its visible command set instead of rebuilding every evicted strip.
  mesh=frames[1].get(key,frames[2].get(key))
  if mesh==null:
   mesh=_build_measured_mesh(feature,profile,probe)
  if meshes.size()>=MAX_CACHED_MESHES:meshes.erase(meshes.keys()[0])
  meshes[key]=mesh
 frames[0][key]=mesh;canvas.set_meta("shore_mesh_frames",frames)
 return mesh

static func _build_measured_mesh(feature: Dictionary,profile: int,probe) -> ArrayMesh:
 var started:=Time.get_ticks_usec() if probe!=null else 0
 var mesh:=_mesh(feature,profile)
 if probe!=null:
  probe.observe_microseconds("presentation.shore.mesh_build",Time.get_ticks_usec()-started)
  probe.increment("presentation.shore.mesh_builds")
 return mesh

static func visible(feature: Dictionary,elevation,zoom: float,offset: Vector2,viewport: Rect2) -> bool:
 # During preview startup/resizing the toolbar can fill the whole viewport.
 if zoom<=0.0 or viewport.size.x<=0.0 or viewport.size.y<=0.0:return false
 var bounds:Array=feature["presentation_bounds"]
 var origin:Vector2=feature["position"]
 var screen:=Rect2(elevation.world_to_screen(origin+Vector2(bounds[0],bounds[1]),zoom,offset),Vector2.ZERO)
 for corner in [Vector2(bounds[0],bounds[3]),Vector2(bounds[2],bounds[1]),Vector2(bounds[2],bounds[3])]:
  screen=screen.expand(elevation.world_to_screen(origin+corner,zoom,offset))
 return screen.grow(32.0*zoom).intersects(viewport)

static func frame_info(item: Dictionary,textures: Array) -> Dictionary:
 if textures.size()!=2 or textures[0]==null or textures[1]==null:return {}
 var form:Dictionary=item["shore_form"]
 var weights:PackedFloat32Array=form.get("marine_weights",PackedFloat32Array([1.0 if form["marine"] else 0.0]))
 var profiles:=PackedInt32Array()
 for profile in range(2):
  if (profile==0 and weights.count(1.0)==weights.size()) or (profile==1 and weights.count(0.0)==weights.size()):continue
  profiles.append(profile)
 # The frame descriptor is replaced when this immutable geometry changes.
 # Cache the exact existing hash rather than recomputing it on every draw.
 var keys:=PackedInt64Array([hash([item["position"],form,0]),hash([item["position"],form,1])])
 return {"shore_geometry":item,"shore_textures":textures,"shore_profiles":profiles,"shore_cache_keys":keys,"asset_name":"ror_shoreline","hotspot":Vector2.ZERO,"frame_index":0,"graphic_layer":0}

static func prepare_frame(info: Dictionary) -> Dictionary:
 var prepared: Dictionary = info.duplicate(false)
 var ready: Array = [null,null]
 for profile in info["shore_profiles"]:
  var key: int = info["shore_cache_keys"][profile]
  var mesh: ArrayMesh = meshes.get(key)
  if mesh == null:
   mesh = _mesh(info["shore_geometry"],profile)
   if meshes.size() >= MAX_CACHED_MESHES: meshes.erase(meshes.keys()[0])
   meshes[key] = mesh
  ready[profile] = mesh
 prepared["shore_prepared_meshes"] = ready
 var commands: Array = []
 for profile in prepared["shore_profiles"]:
  var mesh: ArrayMesh = ready[profile]
  var texture: Texture2D = prepared["shore_textures"][profile]
  commands.append([prepared["shore_cache_keys"][profile], mesh, mesh.get_rid(), texture.get_rid()])
 prepared["shore_draw_commands"] = commands
 return prepared

static func draw(canvas: CanvasItem,info: Dictionary,screen: Vector2,zoom: float,opacity: float=1.0,probe = null) -> void:
 var feature:Dictionary=info["shore_geometry"]
 canvas.draw_set_transform(screen,0,Vector2.ONE*zoom)
 if info.has("shore_prepared_meshes"):
  # Canvas commands keep RIDs. Retain their meshes for the same current/two
  # previous command sets as the lazy path, including a reset or map load.
  var value: Variant = canvas.get_meta("shore_mesh_frames", null)
  var frames: Array = value if value is Array else [{},{},{}]
  if not value is Array: canvas.set_meta("shore_mesh_frames", frames)
  for profile in info["shore_profiles"]:
   var mesh: ArrayMesh = info["shore_prepared_meshes"][profile]
   frames[0][info["shore_cache_keys"][profile]] = mesh
   canvas.draw_mesh(mesh,info["shore_textures"][profile],Transform2D.IDENTITY,Color(1,1,1,opacity))
  canvas.draw_set_transform(Vector2.ZERO)
  return
 if prepared_cache_active and info.has("shore_profiles") and info.has("shore_cache_keys"):
  for profile in info["shore_profiles"]:
   canvas.draw_mesh(retained_mesh(canvas,feature,profile,probe,info["shore_cache_keys"][profile]),info["shore_textures"][profile],Transform2D.IDENTITY,Color(1,1,1,opacity))
  canvas.draw_set_transform(Vector2.ZERO)
  return
 var weights:PackedFloat32Array=feature["shore_form"].get("marine_weights",PackedFloat32Array([1.0 if feature["shore_form"]["marine"] else 0.0]))
 for profile in range(2):
  if (profile==0 and weights.count(1.0)==weights.size()) or (profile==1 and weights.count(0.0)==weights.size()):continue
  canvas.draw_mesh(retained_mesh(canvas,feature,profile,probe),info["shore_textures"][profile],Transform2D.IDENTITY,Color(1,1,1,opacity))
 canvas.draw_set_transform(Vector2.ZERO)

static func _mesh(feature: Dictionary,profile: int=-1) -> ArrayMesh:
 var form:Dictionary=feature["shore_form"]
 var points:PackedVector2Array=form["points"]
 var distances:PackedFloat32Array=form["distances"]
 var normals:PackedVector2Array=form["normals"]
 var heights:PackedFloat32Array=form["heights"]
 var opacity:PackedFloat32Array=form["opacity"]
 var vertices:=PackedVector3Array()
 var uvs:=PackedVector2Array()
 var colors:=PackedColorArray()
 var indices:=PackedInt32Array()
 var marine_weights:PackedFloat32Array=form.get("marine_weights",PackedFloat32Array())
 for i in range(1,points.size()):
  if points[i].distance_squared_to(points[i-1])<0.000001:continue
  # A UV wrap is an explicit seam with duplicate vertices. No triangle can
  # interpolate backwards across the whole texture or expose a straight cut.
  var begin:=0.0
  var u:=fposmod(distances[i-1],2.0)/2.0
  var delta:float=(distances[i]-distances[i-1])/2.0
  while begin<0.99999:
   var end:=minf(1.0,begin+(1.0-u)/maxf(delta,0.000001))
   var first:=vertices.size()
   for fraction in [begin,end]:
    var point:Vector2=points[i-1].lerp(points[i],fraction)
    var normal:Vector2=normals[i-1].lerp(normals[i],fraction).normalized()
    var h0:=lerpf(heights[(i-1)*2],heights[i*2],fraction)
    var h1:=lerpf(heights[(i-1)*2+1],heights[i*2+1],fraction)
    var alpha:=lerpf(opacity[i-1],opacity[i],fraction)
    var marine:=lerpf(marine_weights[i-1],marine_weights[i],fraction) if not marine_weights.is_empty() else (1.0 if form["marine"] else 0.0)
    var width:=lerpf(0.78,1.0,marine)
    if profile>=0:alpha*=marine if profile==1 else 1.0-marine
    for side in range(2):
     var across:=lerpf(-0.18,0.42,float(side))*width
     var h:=lerpf(h0,h1,0.3+(float(side)-0.3)*width)
     var screen:=Coordinates.iso_raw(point+normal*across-Vector2(feature["position"]))
     screen.y-=(h-float(form["anchor_height"]))*16.0
     vertices.append(Vector3(screen.x,screen.y,0))
     uvs.append(Vector2(u+(fraction-begin)*delta,float(side)))
     colors.append(Color(1,1,1,alpha))
   indices.append_array(PackedInt32Array([first,first+2,first+3,first,first+3,first+1]))
   begin=end;u=0.0
 var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX)
 arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_TEX_UV]=uvs
 arrays[Mesh.ARRAY_COLOR]=colors;arrays[Mesh.ARRAY_INDEX]=indices
 var mesh:=ArrayMesh.new()
 mesh.set_meta("ror_geometry_bytes",vertices.size()*12+uvs.size()*8+colors.size()*16+indices.size()*4)
 if not vertices.is_empty():mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
 return mesh
