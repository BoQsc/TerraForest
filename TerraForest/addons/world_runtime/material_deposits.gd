extends RefCounted
const KEYS:={8:"resources/iron_outcrop/v1",9:"resources/copper_outcrop/v1"}
const HEALTH:=360
const REWARD:=8
var store:RefCounted
func prepare(persistence:RefCounted,structures:Node3D)->bool:
 store=ClassDB.instantiate("NativeGeneratedRegion")
 var geometry:Mesh=preload("res://addons/world_ecosystem/woodland_mesh.gd").build(0)
 for material:int in KEYS:
  var mesh:Mesh=geometry.duplicate()
  var shader:=ShaderMaterial.new();shader.shader=preload("res://addons/world_ecosystem/mineral_stone.gdshader")
  shader.set_shader_parameter("stone_texture",preload("res://addons/world_ecosystem/art/boulder_granite_v1.png"))
  shader.set_shader_parameter("mineral_color",Color(.47,.51,.56) if material==8 else Color(.69,.47,.30))
  mesh.surface_set_material(0,shader)
  var collection:Node3D=structures.register_model(KEYS[material],mesh)
  if collection==null or not collection.configure_compound_collision([
   AABB(Vector3(-.22,-.14,-.18),Vector3(.44,.26,.36)),
   AABB(Vector3(-.29,-.08,-.12),Vector3(.58,.16,.24)),
   AABB(Vector3(-.16,-.08,-.235),Vector3(.32,.16,.47))],64,128,8,384,24):return false
 return persistence.register_component("material_deposits_v1",store.capture_snapshot,store.restore_snapshot,store,PackedByteArray())
func publish(seed_value:int,generator:int,deposits:Array,structures:Node3D)->bool:
 if store==null or store.get_plan().get("present",false) or deposits.is_empty():return false
 for material:int in KEYS:
  var identities:=PackedInt64Array();var poses:Array[Transform3D]=[]
  for deposit:Dictionary in deposits:
   if deposit.material==material:identities.append(deposit.id);poses.append(deposit.transform)
  if not identities.is_empty() and not structures.model(KEYS[material]).upsert_transforms(identities,poses):return false
 return store.set_plan(seed_value,generator,deposits,[])
func describe(seed_value:int,generator:int)->Array:
 if store==null:return []
 var result:Dictionary=store.get_plan()
 return result.places if result.get("present",false) and result.seed==seed_value and result.generator==generator else []
static func salvage_recipes()->Dictionary:
 return {KEYS[8]:PackedInt64Array([202,REWARD]),KEYS[9]:PackedInt64Array([203,REWARD])}
static func preview_pixels(pixels:PackedByteArray,deposits:Array)->PackedByteArray:
 if deposits.is_empty():return pixels
 var image:=Image.create_from_data(256,256,false,Image.FORMAT_RGBA8,pixels)
 for deposit:Dictionary in deposits:
  var center:=Vector2i(roundi(deposit.position.x*255/2000),roundi(deposit.position.z*255/2000))
  var color:=Color("a9bfd4") if deposit.material==8 else Color("e5a269")
  for row in range(-2,3):
   for column in range(-2,3):
    var point:=center+Vector2i(column,row)
    if absi(row)+absi(column)>2 or point.x<0 or point.y<0 or point.x>=256 or point.y>=256:continue
    image.set_pixelv(point,Color("10252b") if absi(row)+absi(column)==2 else color)
 return image.get_data()
