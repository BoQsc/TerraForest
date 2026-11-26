# SPDX-License-Identifier: 0BSD
extends RefCounted
## Data-only pack discovery. Native collections own rendering, collision and saves.
const ROOT := "res://addons/structures/packs"
const MAX_PACKS := 64
const MAX_OBJECTS := 192
static var _loaded := false
static var packs: Array[Dictionary] = []
static var objects: Dictionary = {}
static var by_item: Dictionary = {}
static var by_title: Dictionary = {}
static var errors: Array[String] = []
static var _atlases: Dictionary = {}
static var _icons: Dictionary = {}

static func slug(value: Variant) -> bool:
	if not value is String or value.is_empty() or value.length()>80: return false
	for letter: String in value:
		if letter not in "abcdefghijklmnopqrstuvwxyz0123456789_": return false
	return true

static func integer(value: Variant, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(value) and value==floor(value) and value>=low and value<=high

static func recipe_valid(value: Variant, empty: bool=false) -> bool:
	if not value is Array or value.size()%2!=0 or value.size()>16 or (value.is_empty() and not empty): return false
	var seen := {}
	for index in range(0,value.size(),2):
		if not (integer(value[index],101,104) or integer(value[index],201,228)) or not integer(value[index+1],1,10000) or seen.has(value[index]): return false
		seen[value[index]]=true
	return true

static func validate(value: Variant, folder: String, known_items: Dictionary={}, known_keys: Dictionary={}) -> String:
	if not value is Dictionary or value.get("schema")!=1: return "Expected pack schema 1"
	if not slug(folder) or value.get("id")!="terraforest."+folder: return "Pack id must match its folder: terraforest."+folder
	if not value.get("name") is String or value.name.is_empty() or value.name.length()>64: return "Missing pack name"
	if value.get("asset_license")!="CC0-1.0" or value.get("code_license")!="0BSD": return "Pack terms need explicit intake review"
	if not value.get("objects") is Array or value.objects.is_empty() or value.objects.size()>128: return "Expected 1–128 objects"
	var ids := known_items.duplicate(); var keys := known_keys.duplicate()
	for row: Variant in value.objects:
		if not row is Dictionary or not slug(row.get("id")): return "Invalid object slug"
		var key: String="packs/"+folder+"/"+row.id+"/v1"
		if not integer(row.get("item"),720,1000000) or ids.has(int(row.item)) or keys.has(key): return "Duplicate or invalid item/model identity: "+row.id
		if not row.get("name") is String or row.name.is_empty() or row.name.length()>96: return "Invalid object name"
		if not recipe_valid(row.get("recipe")) or not recipe_valid(row.get("salvage"),true): return "Invalid recipes: "+row.id
		var costs := {}
		for i in range(0,row.recipe.size(),2): costs[int(row.recipe[i])]=int(row.recipe[i+1])
		for i in range(0,row.salvage.size(),2):
			if int(row.salvage[i+1])>costs.get(int(row.salvage[i]),0): return "Salvage exceeds recipe: "+row.id
		if not integer(row.get("health"),1,100000) or row.get("material") not in ["wood","stone","other"]: return "Invalid durability: "+row.id
		if row.get("mount","floor") not in ["floor","wall"]: return "Invalid mounting: "+row.id
		if row.has("container") and not integer(row.container,1,32): return "Invalid container slots: "+row.id
		if row.has("light"):
			var light: Variant=row.light
			if not light is Dictionary or not light.get("offset") is Array or light.offset.size()!=3 or not light.get("color") is String or not Color.html_is_valid(light.color): return "Invalid light: "+row.id
			for component: Variant in light.offset:
				if not (component is int or component is float) or not is_finite(component) or absf(component)>16: return "Invalid light offset"
			for field: String in ["energy","range"]:
				if not (light.get(field) is int or light.get(field) is float) or not is_finite(light[field]) or light[field]<=0 or light[field]>16: return "Invalid light limits"
			if not light.get("shadows") is bool: return "Invalid light shadows"
		ids[int(row.item)]=true; keys[key]=true
	return ""

static func discover() -> bool:
	if _loaded: return errors.is_empty()
	_loaded=true
	var folders := DirAccess.get_directories_at(ROOT); folders.sort()
	var pending: Array[Dictionary]=[]; var pending_items := {}; var pending_keys := {}
	for folder: String in folders:
		var path := ROOT.path_join(folder).path_join("pack.json")
		if not FileAccess.file_exists(path): continue
		var file := FileAccess.open(path,FileAccess.READ)
		if file==null or file.get_length()>262144: errors.append("Missing or oversized "+path); continue
		var value: Variant=JSON.parse_string(file.get_as_text())
		var problem := validate(value,folder,pending_items,pending_keys)
		if not problem.is_empty(): errors.append(folder+": "+problem); continue
		if pending.size()>=MAX_PACKS or pending_items.size()+value.objects.size()>MAX_OBJECTS: errors.append("Object pack capacity exceeded"); break
		var pack: Dictionary=value.duplicate(true); pack.directory=ROOT.path_join(folder); pack.folder=folder
		for index in pack.objects.size():
			var row: Dictionary=pack.objects[index]
			row.item=int(row.item); row.key="packs/"+folder+"/"+row.id+"/v1"
			row.pack=pack.name; row.pack_id=pack.id; row.directory=pack.directory; row.icon_index=index
			row.title=pack.name+" · "+row.name.trim_prefix(pack.get("name_prefix","Homestead ")).capitalize()
			pending_items[row.item]=row; pending_keys[row.key]=row
		pending.append(pack)
	# A malformed pack never publishes a partial inventory or save schema.
	if not errors.is_empty():
		push_error("Object packs: "+"; ".join(errors)); return false
	packs=pending; objects=pending_keys; by_item=pending_items
	for row: Dictionary in objects.values(): by_title[row.title]=row
	return true

static func item_names(titles: bool=false) -> Dictionary:
	discover(); var result := {}
	for item: int in by_item: result[item]=by_item[item].title if titles else by_item[item].name
	return result

static func recipes(salvage: bool=false) -> Dictionary:
	discover(); var result := {}
	for key: String in objects:
		var values: Array=objects[key].salvage if salvage else objects[key].recipe
		if not values.is_empty(): result[key]=PackedInt64Array(values)
	return result

static func profile(key: String) -> Dictionary:
	discover()
	if not objects.has(key): return {}
	var row: Dictionary=objects[key]
	return {"name":row.name,"health":int(row.health),"material":row.material}

static func icon(value: Variant) -> Texture2D:
	discover()
	var row: Dictionary=by_item.get(int(value),{}) if str(value).is_valid_int() else by_title.get(str(value),{})
	if row.is_empty(): return null
	if _icons.has(row.item): return _icons[row.item]
	if not _atlases.has(row.pack_id):
		var pixels := Image.new()
		if pixels.load_png_from_buffer(FileAccess.get_file_as_bytes(row.directory+"/icons.trtex"))!=OK: return null
		if pixels.get_width()!=1280 or pixels.get_height()<int(ceil(objects_for_pack(row.pack_id).size()/5.0))*256: return null
		_atlases[row.pack_id]=ImageTexture.create_from_image(pixels)
	var tile := AtlasTexture.new(); tile.atlas=_atlases[row.pack_id]
	tile.region=Rect2((row.icon_index%5)*256,(int(row.icon_index)/5)*256,256,256); tile.filter_clip=true
	_icons[row.item]=tile
	return tile

static func objects_for_pack(id: String) -> Array:
	discover()
	for pack: Dictionary in packs:
		if pack.id==id: return pack.objects
	return []

static func register(world: Node3D) -> Array[Dictionary]:
	var entries: Array[Dictionary]=[]
	if not discover(): return entries
	var meshes := {}
	for key: String in objects:
		var row: Dictionary=objects[key]
		var path: String=row.directory+"/models/"+row.id+".tres"
		if not ResourceLoader.exists(path): push_error("Missing pack model: "+path); return []
		var mesh := load(path) as Mesh
		var boxes: Variant=mesh.get_meta("collision_boxes",[]) if mesh!=null else []
		if not boxes is Array or boxes.is_empty() or boxes.size()>64: push_error("Invalid pack collision: "+path); return []
		for box: Variant in boxes:
			if not box is AABB or not box.position.is_finite() or not box.size.is_finite() or box.size.x<=0 or box.size.y<=0 or box.size.z<=0: push_error("Invalid pack collision box: "+path); return []
		# Authored static props share bounded visual pages; canonical collision and
		# storage retain their 32 m regions and individual object identities.
		mesh.set_meta("world_render_region_span",4)
		meshes[key]=mesh
	preload("res://addons/structures/pack_render_mesh.gd").configure(meshes.values())
	for key: String in meshes:
		meshes[key]=preload("res://addons/structures/pack_render_mesh.gd").prepare(meshes[key])
		# A preview may have cached this geometry before world admission.
		meshes[key].set_meta("world_render_region_span",4)
	for key: String in objects:
		var row: Dictionary=objects[key]; var mesh: Mesh=meshes[key]
		var collection: Node3D=world.register_model(key,mesh)
		if collection==null or not collection.configure_compound_collision(mesh.get_meta("collision_boxes"),64,256,8,1792,56): return []
		entries.append({"id":key,"item":row.item,"pack":row.pack,"pack_id":row.pack_id,"mount":row.get("mount","floor"),"title":row.title,"mesh":mesh,"collection":collection,"scale":Vector3.ONE,"costs":PackedInt64Array(row.recipe),"cost_label":"Pack recipe"})
	return entries

static func light_sources(world: Node3D) -> Array[Dictionary]:
	discover(); var result: Array[Dictionary]=[]
	for key: String in objects:
		var row: Dictionary=objects[key]
		if not row.has("light") or world.model(key)==null: continue
		var light: Dictionary=row.light
		result.append({"collection":world.model(key),"offset":Vector3(light.offset[0],light.offset[1],light.offset[2]),"color":Color(light.color),"energy":float(light.energy),"range":float(light.range),"shadows":bool(light.shadows)})
	return result
