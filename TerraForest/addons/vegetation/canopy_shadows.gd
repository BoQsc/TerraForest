# SPDX-License-Identifier: 0BSD
extends Node
# Scene glue only. A private native snapshot rasterizes on one background worker.
var forest:Node3D
var camera:Camera3D
var material:ShaderMaterial
var texture:ImageTexture
var revision:=-1
var origin:=Vector3.INF
var sun:=Vector3.ZERO
var cooldown:=0.0
var rebuilds:=0
var last_native_us:=0
var max_native_us:=0
var last_native_frame:=-1
var last_snapshot_roots:=0
var worker:Thread
var job:RefCounted
var requested:Dictionary={}
var legacy_snapshot:=false # Diagnostic control; production uses native membership.
const SPAN:=1024.0
const SIZE:=256
func _process(delta:float):
 if forest==null or camera==null or material==null or not forest.ready_to_render:return
 var renderer=forest.renderer
 if renderer.native_selection==null:return
 var eye=camera.global_position
 var next_origin=Vector3(floor(eye.x/16)*16-SPAN*.5,0,floor(eye.z/16)*16-SPAN*.5)
 if worker!=null and not worker.is_alive():
  var pixels:PackedByteArray=worker.wait_to_finish();worker=null;job=null
  if pixels.size()==SIZE*SIZE and requested.revision==renderer.canopy_revision and requested.origin==next_origin and requested.sun==forest.sun_direction:
   var image=Image.create_from_data(SIZE,SIZE,false,Image.FORMAT_R8,pixels)
   if texture==null:texture=ImageTexture.create_from_image(image)
   else:texture.update(image)
   origin=requested.origin;revision=requested.revision;sun=requested.sun;rebuilds+=1
   material.set_shader_parameter("canopy_mask",texture)
   material.set_shader_parameter("canopy_region",Vector3(origin.x,origin.z,SPAN))
 material.set_shader_parameter("canopy_enabled",texture!=null and renderer.shadows_enabled and renderer.trees_enabled and forest.sun_direction.y>=.15)
 material.set_shader_parameter("canopy_eye",eye)
 material.set_shader_parameter("canopy_near",forest.shadow_distance+20.0)
 cooldown-=delta
 if worker!=null or cooldown>0 or (next_origin==origin and revision==renderer.canopy_revision and sun==forest.sun_direction):return
 if not renderer.shadows_enabled or not renderer.trees_enabled or forest.sun_direction.y<.15:return
 cooldown=.25
 job=ClassDB.instantiate("NativeVegetationSelection")
 var started=Time.get_ticks_usec()
 var prepared:bool=job.prepare_shadow_mask(renderer,next_origin,SPAN,SIZE,forest.sun_direction) if legacy_snapshot else job.prepare_shadow_snapshot(renderer.native_selection,next_origin,SPAN,SIZE,forest.sun_direction)
 last_native_us=Time.get_ticks_usec()-started;max_native_us=maxi(max_native_us,last_native_us)
 last_native_frame=Engine.get_process_frames();last_snapshot_roots=renderer.roots.size()
 if not prepared:job=null;return
 requested={"origin":next_origin,"revision":renderer.canopy_revision,"sun":forest.sun_direction}
 worker=Thread.new()
 if worker.start(job.build_shadow_mask)!=OK:worker=null;job=null
func snapshot_profile()->Dictionary:
 return {"available":true,"current":last_native_frame==Engine.get_process_frames(),"frame":last_native_frame,"snapshot_us":last_native_us,"roots":last_snapshot_roots,"rebuilds":rebuilds,"worker_active":worker!=null,"legacy_snapshot":legacy_snapshot}
func _exit_tree():
 if worker!=null:worker.wait_to_finish();worker=null;job=null
 if material!=null:material.set_shader_parameter("canopy_enabled",false)
