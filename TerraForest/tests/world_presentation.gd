# SPDX-License-Identifier: 0BSD
extends SceneTree
func _initialize()->void:
 var directory:="user://presentation_test_%d"%Time.get_ticks_usec()
 DirAccess.make_dir_recursive_absolute(directory)
 for slot in ["alpha","beta","gamma"]:
  FileAccess.open(directory.path_join(slot+".trw"),FileAccess.WRITE).store_string("unchanged")
 for pair in [["alpha",100,300],["beta",300,100],["gamma",200,200]]:
  FileAccess.open(directory.path_join(pair[0]+".presentation.json"),FileAccess.WRITE).store_string(JSON.stringify({"last_played":pair[1],"created":pair[2]}))
 var launch=preload("res://demo/world_launch.gd")
 var failures:=0
 if launch.saved_slots(directory,false,"played")!=PackedStringArray(["beta","gamma","alpha"]):failures+=1
 if launch.saved_slots(directory,false,"created")!=PackedStringArray(["alpha","gamma","beta"]):failures+=1
 if launch.saved_slots(directory,false,"name")!=PackedStringArray(["alpha","beta","gamma"]):failures+=1
 FileAccess.open(directory.path_join("beta.diagnostic.json"),FileAccess.WRITE).store_string("{}")
 if launch.saved_slots(directory)!=PackedStringArray(["gamma","alpha"]) or "beta" in launch.saved_slots(directory,true):failures+=1
 if not launch.command("beta",false,29,1703,true,directory).ok or FileAccess.get_file_as_string(directory.path_join("beta.trw"))!="unchanged":failures+=1
 DirAccess.remove_absolute(directory.path_join("beta.diagnostic.json"))
 var presentation=preload("res://addons/world_runtime/world_presentation.gd")
 if not presentation.mark_played("alpha",directory) or launch.saved_slots(directory)[0]!="alpha":failures+=1
 if FileAccess.get_file_as_string(directory.path_join("alpha.trw"))!="unchanged":failures+=1
 if presentation.image_for("alpha",directory)!=null:failures+=1
 FileAccess.open(directory.path_join("alpha.generation.json"),FileAccess.WRITE).store_string(JSON.stringify({"seed":42,"generator":19,"version":2,"digest":"fixture"}))
 var details:Dictionary=presentation.details("alpha",directory)
 if details.get("seed")!=42 or details.get("generator")!=19 or details.get("created")!=300 or details.get("saved",0)<=0:failures+=1
 if presentation.details("../alpha",directory)!={}:failures+=1
 if presentation.details("gamma",directory).has("seed"):failures+=1
 if FileAccess.get_file_as_string(directory.path_join("alpha.trw"))!="unchanged":failures+=1
 var before:Dictionary=presentation.metadata("alpha",directory)
 DirAccess.make_dir_recursive_absolute(directory.path_join("alpha.preview"))
 var image:=Image.create(2,2,false,Image.FORMAT_RGB8);image.fill(Color.GREEN)
 image.save_png(directory.path_join("alpha.preview/north.png"))
 if not presentation.record_photographs("alpha",directory):failures+=1
 var updated:Dictionary=presentation.metadata("alpha",directory)
 if updated.get("preview_count")!=1 or updated.get("created")!=before.created or updated.get("last_played")!=before.last_played:failures+=1
 if presentation.image_for("alpha",directory)==null or FileAccess.get_file_as_string(directory.path_join("alpha.trw"))!="unchanged":failures+=1
 if presentation.record_photographs("../alpha",directory) or presentation.record_photographs("missing",directory):failures+=1
 print("WORLD_PRESENTATION failures=",failures);quit(1 if failures else 0)
