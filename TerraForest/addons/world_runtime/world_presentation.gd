# SPDX-License-Identifier: 0BSD
extends RefCounted
# Small launcher metadata only; never part of authoritative world storage.
static func metadata(slot:String,directory:String="user://worlds")->Dictionary:
 if not slot.is_valid_identifier() or slot.length()>48:return {}
 var path:=directory.path_join(slot+".presentation.json")
 if not FileAccess.file_exists(path):return {}
 var file:=FileAccess.open(path,FileAccess.READ)
 if file==null or file.get_length()>16384:return {}
 var result:Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
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

static func image_for(slot:String,directory:String="user://worlds")->Texture2D:
 if not slot.is_valid_identifier() or slot.length()>48:return null
 var candidates:PackedStringArray=[]
 for name in ["north","road","market"]:
  var path:=directory.path_join(slot+".preview").path_join(name+".png")
  if FileAccess.file_exists(path):candidates.append(path)
 if candidates.is_empty():return null
 var picture:=Image.load_from_file(candidates[randi()%candidates.size()])
 if picture==null or picture.is_empty():return null
 return ImageTexture.create_from_image(picture)

# Offline capture only: no per-frame readback or extra gameplay viewport.
static func capture(game:Node,viewport:Viewport,path:String)->Error:
 var layers:Array=[]
 var processing:bool=game.is_processing()
 game.set_process(false)
 var tool:Node3D=game.get("tool_view")
 var tool_visible:bool=tool!=null and tool.visible
 if tool!=null:tool.hide()
 for child:Node in game.find_children("*","CanvasLayer",true,false):
  if child.visible:layers.append(child);child.hide()
 await RenderingServer.frame_post_draw
 var picture:Image=viewport.get_texture().get_image()
 picture.resize(1280,720,Image.INTERPOLATE_LANCZOS)
 var result:=picture.save_png(path)
 for layer:CanvasLayer in layers:layer.show()
 if tool!=null:tool.visible=tool_visible
 game.set_process(processing)
 return result
