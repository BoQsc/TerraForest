extends RefCounted
const DEFAULTS:={"biome":0,"settlements":2,"districts":1,"network":0,"trails":1,"road_grid":1}
var store:RefCounted
var ecosystem:Node
static func codec()->RefCounted:
 if not ClassDB.class_exists("NativeWorldRecipe"):
  GDExtensionManager.load_extension("res://addons/world_runtime/world_runtime.gdextension")
 return ClassDB.instantiate("NativeWorldRecipe")
static func encode(options:Dictionary)->PackedByteArray:
 return codec().encode(options)
static func from_arguments(arguments:PackedStringArray)->Dictionary:
 for argument:String in arguments:
  if argument.begins_with("--world-recipe="):
   var bytes:=Marshalls.base64_to_raw(argument.trim_prefix("--world-recipe="))
   var result:Dictionary=codec().decode(bytes)
   return {"ok":not result.is_empty(),"options":result}
 return {"ok":true,"options":{}}
func prepare(persistence:RefCounted,trees:Node)->bool:
 ecosystem=trees;store=codec()
 return store!=null and persistence.register_component("world_recipe_v1",store.capture_snapshot,restore_snapshot,store,PackedByteArray())
func restore_snapshot(bytes:PackedByteArray)->bool:
 if not store.restore_snapshot(bytes):return false
 ecosystem.biome_profile=int(store.decode(bytes).get("biome",0))
 return true
func configure(options:Dictionary)->bool:
 var bytes:=encode(options)
 return not bytes.is_empty() and restore_snapshot(bytes)
