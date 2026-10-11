# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
var stage:Node3D
var front:MeshInstance3D
var back:MeshInstance3D
func check(ok:bool,label:String):
 print("PASS " if ok else "FAIL ",label)
 if not ok:failures+=1
func plane(y:float,material:Material) -> MeshInstance3D:
 var node:=MeshInstance3D.new();var geometry:=PlaneMesh.new();geometry.size=Vector2(8,8)
 node.mesh=geometry;node.material_override=material;node.position.y=y;stage.add_child(node);return node
func water_material(priority:int) -> ShaderMaterial:
 var material:=ShaderMaterial.new();material.shader=load("res://addons/volumetric_water/water.gdshader")
 material.render_priority=priority;material.set_shader_parameter("ripple_strength",0.0);return material
func pixels() -> Array[Color]:
 for frame in 8:await process_frame
 await RenderingServer.frame_post_draw
 var image:=root.get_texture().get_image();var result:Array[Color]=[]
 for x in [760,860,960,1060,1160]:result.append(image.get_pixel(x,540))
 return result
func difference(a:Array[Color],b:Array[Color]) -> float:
 var largest:=0.0
 for i in a.size():largest=maxf(largest,maxf(abs(a[i].r-b[i].r),maxf(abs(a[i].g-b[i].g),abs(a[i].b-b[i].b))))
 return largest
func _initialize():call_deferred("run")
func run():
 root.size=Vector2i(1920,1080);DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN);Engine.max_fps=60
 stage=Node3D.new();root.add_child(stage)
 var camera:=Camera3D.new();stage.add_child(camera);camera.position=Vector3(0,3,4);camera.look_at(Vector3.ZERO);camera.current=true
 var light:=DirectionalLight3D.new();stage.add_child(light);light.rotation_degrees=Vector3(-65,-20,0)
 var floor_material:=StandardMaterial3D.new();floor_material.albedo_color=Color(0.65,0.18,0.08)
 var floor_node:=plane(-2.0,floor_material)
 front=plane(0.0,water_material(0));back=plane(-0.5,water_material(-1));back.visible=false
 var single:Array[Color]=await pixels()
 back.visible=true
 var behind_first:Array[Color]=await pixels()
 back.material_override.render_priority=1
 var behind_last:Array[Color]=await pixels()
 check(difference(single,behind_first)<=2.0/255.0,"rear water face cannot double-tint nearest surface")
 check(difference(single,behind_last)<=2.0/255.0,"water compositing independent of region draw order")
 front.visible=false;back.visible=false
 var dry:Array[Color]=await pixels()
 check(difference(single,dry)>0.02,"water contributes visible depth absorption")
 check(single[2].r>single[2].b,"underwater floor colour remains visible through water")
 front.visible=true;floor_node.position.y=-0.1
 var shallow:Array[Color]=await pixels()
 front.visible=false
 var shallow_dry:Array[Color]=await pixels()
 check(difference(shallow,shallow_dry)<difference(single,dry),"shallow water absorbs less than deeper water")
 var marker_material:=StandardMaterial3D.new();marker_material.albedo_color=Color(0.05,0.8,0.1)
 plane(0.3,marker_material)
 var uncovered:Array[Color]=await pixels()
 front.visible=true;back.visible=true
 var foreground:Array[Color]=await pixels()
 check(difference(uncovered,foreground)<=2.0/255.0,"opaque object above water remains visible and untinted")
 DirAccess.make_dir_recursive_absolute("res://reports")
 var report=FileAccess.open("res://reports/water_compositing.json",FileAccess.WRITE)
 report.store_string(JSON.stringify({"failures":failures,"rear_first_difference":difference(single,behind_first),"rear_last_difference":difference(single,behind_last),"water_difference":difference(single,dry)}));report.close()
 print("WATER_COMPOSITING failures=",failures);quit(failures)
