# SPDX-License-Identifier: 0BSD
extends RefCounted
# Small launcher metadata only; never part of authoritative world storage.
# Bundled stand-in for worlds without a photograph of their own. Provenance:
# assets/general_world.json (window_flow world, seed 1703, generator 1).
const GENERAL_IMAGE:="res://addons/world_runtime/assets/general_world.png"
static var general_cache:Image
static func metadata(slot:String,directory:String="user://worlds")->Dictionary:
 if not slot.is_valid_identifier() or slot.length()>48:return {}
 var path:=directory.path_join(slot+".presentation.json")
 if not FileAccess.file_exists(path):return {}
 var file:=FileAccess.open(path,FileAccess.READ)
 if file==null or file.get_length()>16384:return {}
 var result:Variant=JSON.parse_string(file.get_as_text())
 return result if result is Dictionary else {}

static func mark_played(slot:String,directory:String="user://worlds")->bool:
 if not slot.is_valid_identifier() or slot.length()>48:return false
 if not FileAccess.file_exists(directory.path_join(slot+".trw")):return false
 var state:=metadata(slot,directory)
 state["last_played"]=int(Time.get_unix_time_from_system())
 var path:=directory.path_join(slot+".presentation.json")
 var file:=FileAccess.open(path+".tmp",FileAccess.WRITE)
 if file==null:return false
 file.store_string(JSON.stringify(state));file.close()
 return DirAccess.rename_absolute(path+".tmp",path)==OK

static func record_photographs(slot:String,directory:String="user://worlds")->bool:
 if not slot.is_valid_identifier() or slot.length()>48:return false
 if not FileAccess.file_exists(directory.path_join(slot+".trw")):return false
 var state:=metadata(slot,directory)
 var count:=0
 for name:String in ["north","road","market","arrival"]:
  if FileAccess.file_exists(directory.path_join(slot+".preview/"+name+".png")):count+=1
 state["preview_count"]=count
 var path:=directory.path_join(slot+".presentation.json")
 var file:=FileAccess.open(path+".tmp",FileAccess.WRITE)
 if file==null:return false
 file.store_string(JSON.stringify(state));file.close()
 return DirAccess.rename_absolute(path+".tmp",path)==OK

static func read_image(slot:String,directory:String="user://worlds",maximum:Vector2i=Vector2i.ZERO,random_order:bool=false)->Image:
 if not slot.is_valid_identifier() or slot.length()>48:return null
 var candidates:PackedStringArray=[]
 for name in ["north","road","market","arrival"]:
  var path:=directory.path_join(slot+".preview").path_join(name+".png")
  if FileAccess.file_exists(path):candidates.append(path)
 if random_order and candidates.size()>1:
  var first:=randi()%candidates.size();var chosen:=candidates[first];candidates.remove_at(first);candidates.insert(0,chosen)
 for path:String in candidates:
  var picture:=Image.load_from_file(path)
  if picture==null or picture.is_empty():continue
  if maximum.x>0 and maximum.y>0:
   var factor:=minf(1.,minf(float(maximum.x)/picture.get_width(),float(maximum.y)/picture.get_height()))
   if factor<1.:picture.resize(maxi(1,roundi(picture.get_width()*factor)),maxi(1,roundi(picture.get_height()*factor)),Image.INTERPOLATE_BILINEAR)
  return picture
 return null

static func image_for(slot:String,directory:String="user://worlds")->Texture2D:
 var picture:=read_image(slot,directory,Vector2i.ZERO,true)
 return ImageTexture.create_from_image(picture) if picture!=null else null

## The general picture is displayed like a photograph but never counts as one,
## so a world still receives its own arrival capture when it has none.
static func general_image(maximum:Vector2i=Vector2i.ZERO)->Image:
 if general_cache==null and FileAccess.file_exists(GENERAL_IMAGE):general_cache=Image.load_from_file(GENERAL_IMAGE)
 if general_cache==null:return null
 var picture:Image=general_cache.duplicate()
 if maximum.x>0 and maximum.y>0:
  var factor:=minf(1.,minf(float(maximum.x)/picture.get_width(),float(maximum.y)/picture.get_height()))
  if factor<1.:picture.resize(maxi(1,roundi(picture.get_width()*factor)),maxi(1,roundi(picture.get_height()*factor)),Image.INTERPOLATE_BILINEAR)
 return picture

static func display_image(slot:String,directory:String="user://worlds",maximum:Vector2i=Vector2i.ZERO)->Image:
 var picture:=read_image(slot,directory,maximum)
 return picture if picture!=null else general_image(maximum)

static func display_texture(slot:String,directory:String="user://worlds")->Texture2D:
 var picture:=display_image(slot,directory)
 return ImageTexture.create_from_image(picture) if picture!=null else null

static func has_photograph(slot:String,directory:String="user://worlds")->bool:
 return read_image(slot,directory,Vector2i(1,1))!=null

# Explicit snapshots only: no per-frame readback or extra gameplay viewport.
static func capture(game:Node,viewport:Viewport,path:String)->Error:
 var picture:Image=await capture_image(game,viewport)
 return picture.save_png(path) if picture!=null else ERR_UNAVAILABLE

static func capture_image(game:Node,viewport:Viewport)->Image:
 var layers:Array=[]
 var processing:bool=game.is_processing()
 game.set_process(false)
 var tool:Node3D=game.get("tool_view")
 var tool_visible:bool=tool!=null and tool.visible
 if tool!=null:tool.hide()
 for child:Node in game.find_children("*","CanvasLayer",true,false):
  if child.visible:layers.append(child);child.hide()
 await RenderingServer.frame_post_draw
 if not is_instance_valid(game) or not is_instance_valid(viewport):return null
 var picture:Image=null if popup_visible(game) else viewport.get_texture().get_image()
 # Preserve every rendered pixel (1920x1080 under the fullscreen policy).
 # PNG is lossless; the loading background displays this image at native size.
 for layer:CanvasLayer in layers:
  if is_instance_valid(layer):layer.show()
 if is_instance_valid(tool):tool.visible=tool_visible
 game.set_process(processing)
 return picture

static func popup_visible(game:Node)->bool:
 for window:Window in game.find_children("*","Window",true,false):
  if window.visible:return true
 return false

# Informational sidecars only. Missing old metadata stays unknown, never inferred
# from the generator currently selected in the create-world UI.
static func details(slot:String,directory:String="user://worlds")->Dictionary:
 if not slot.is_valid_identifier() or slot.length()>48:return {}
 var state:=metadata(slot,directory)
 var path:=directory.path_join(slot+".generation.json")
 var file:=FileAccess.open(path,FileAccess.READ) if FileAccess.file_exists(path) else null
 if file!=null and file.get_length()<=16384:
  var identity=JSON.parse_string(file.get_as_text())
  if identity is Dictionary:
   for key in ["seed","generator","version","digest"]:
    if identity.has(key):state[key]=identity[key]
 var saved:=FileAccess.get_modified_time(directory.path_join(slot+".trw"))
 state["saved"]=saved
 return state
