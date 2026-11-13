# SPDX-License-Identifier: 0BSD
extends SceneTree
const Zombie=preload("res://addons/characters/runtime/zombie.gd")
const Reference=preload("res://tests/zombie_bake_reference.gd")
var failures:=0
var comparisons:=0
var native_us:=0
var reference_us:=0
func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	if not value:failures+=1;push_error(label)
func compare(actor:Node3D,source:MeshInstance3D,to_local:Transform3D)->void:
	var began:=Time.get_ticks_usec()
	var expected:ArrayMesh=Reference.bake(actor,source,to_local)
	reference_us+=Time.get_ticks_usec()-began
	began=Time.get_ticks_usec()
	var actual:ArrayMesh=actor._bake_cpu(source,to_local)
	native_us+=Time.get_ticks_usec()-began
	check(actual.get_surface_count()==expected.get_surface_count(),"surface count: "+source.name)
	for surface in mini(actual.get_surface_count(),expected.get_surface_count()):
		var a:Array=actual.surface_get_arrays(surface);var b:Array=expected.surface_get_arrays(surface)
		check(actual.surface_get_material(surface)==expected.surface_get_material(surface),"active material preserved")
		check(actual.surface_get_format(surface)==expected.surface_get_format(surface),"surface/custom channel formats preserved")
		for channel in Mesh.ARRAY_MAX:
			if channel in [Mesh.ARRAY_VERTEX,Mesh.ARRAY_NORMAL,Mesh.ARRAY_TANGENT] and a[channel]!=null and b[channel]!=null:
				check(a[channel].size()==b[channel].size(),"geometry attribute count")
				var worst:=0.0
				for i in mini(a[channel].size(),b[channel].size()):
					worst=maxf(worst,absf(a[channel][i]-b[channel][i]) if channel==Mesh.ARRAY_TANGENT else a[channel][i].distance_to(b[channel][i]))
				check(worst<.0005,"skin/morph attribute equality: "+source.name+" channel="+str(channel)+" error="+str(worst))
			else:check(a[channel]==b[channel],"unchanged non-skinned attribute: "+str(channel))
		comparisons+=1
func synthetic(actor:Node3D)->void:
	for influences:int in [4,8]:
		for relative:bool in [false,true]:
			var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3.RIGHT,Vector3.RIGHT])
			arrays[Mesh.ARRAY_NORMAL]=PackedVector3Array([Vector3.UP,Vector3.UP])
			arrays[Mesh.ARRAY_TANGENT]=PackedFloat32Array([1,0,0,-1,1,0,0,1])
			arrays[Mesh.ARRAY_TEX_UV]=PackedVector2Array([Vector2.ZERO,Vector2.ONE])
			var bones:=PackedInt32Array();bones.resize(influences*2);bones[1]=1;bones[2]=99
			var weights:=PackedFloat32Array();weights.resize(influences*2);weights[0]=.25;weights[1]=.25;weights[2]=.5
			arrays[Mesh.ARRAY_BONES]=bones;arrays[Mesh.ARRAY_WEIGHTS]=weights
			var shape:Array=[];shape.resize(Mesh.ARRAY_MAX);shape[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3(5,0,0),Vector3(5,0,0)])
			var snapshot:Array=arrays.duplicate(true)
			var binds:Array[Transform3D]=[Transform3D(Basis.IDENTITY,Vector3(10,0,0)),Transform3D(Basis.IDENTITY,Vector3(20,0,0))]
			var actual:Array=actor.anatomy.bake_surface(arrays,[shape],PackedFloat64Array([.25]),relative,binds,Transform3D(Basis.IDENTITY,Vector3(30,0,0)))
			check(not actual.is_empty(),"four/eight-weight input accepted")
			if actual.is_empty():continue
			check(actual[Mesh.ARRAY_VERTEX][0].is_equal_approx(Vector3(17.25 if relative else 17,0,0)),"weighted position renormalizes valid influences")
			check(actual[Mesh.ARRAY_VERTEX][1].is_equal_approx(Vector3(32.25 if relative else 32,0,0)),"zero-weight vertex uses unskinned transform")
			check(actual[Mesh.ARRAY_TANGENT]==snapshot[Mesh.ARRAY_TANGENT] and actual[Mesh.ARRAY_NORMAL]==snapshot[Mesh.ARRAY_NORMAL],"directions and tangent handedness preserved")
			check(actual[Mesh.ARRAY_TEX_UV]==snapshot[Mesh.ARRAY_TEX_UV] and arrays==snapshot,"source packet and untouched attributes remain immutable")
			check(actual[Mesh.ARRAY_BONES]==null and actual[Mesh.ARRAY_WEIGHTS]==null,"baked surface is unskinned")
func run()->void:
	var actor:=Zombie.new();actor.process_mode=Node.PROCESS_MODE_DISABLED;root.add_child(actor)
	check(actor.initialized,"actor initialized")
	check(actor.render_bake_surface_reads==0,"first default actor uses offline render packets without GPU readback")
	synthetic(actor)
	actor.transform=Transform3D(Basis(Vector3.UP,.7),Vector3(1008,43,590))
	var camera:=Camera3D.new();root.add_child(camera);camera.position=actor.position+Vector3(0,1.2,3);camera.look_at(actor.position+Vector3.UP);camera.make_current()
	if DisplayServer.get_name()!="headless":await RenderingServer.frame_post_draw
	for pose:String in ["Zombie_Idle","Zombie_Walk_Drag_Right","Zombie_Attack_Left","morph"]:
		var clip:String=actor._animation_key("Zombie_Idle" if pose=="morph" else pose)
		check(actor.animation_player.has_animation(clip),"authored pose exists")
		actor.animation_player.play(clip);actor.animation_player.seek(.45,true);actor.animation_player.advance(0)
		for mesh:MeshInstance3D in actor.part_meshes.values():
			if pose=="morph":
				for index in mesh.get_blend_shape_count():mesh.set_blend_shape_value(index,.35)
			compare(actor,mesh,actor.global_transform.affine_inverse())
		for pair:Dictionary in actor.caps.values():
			for mesh:MeshInstance3D in pair.values():compare(actor,mesh,Transform3D(Basis(Vector3.UP,.4),Vector3(.1,.2,.3))*actor.global_transform.affine_inverse())
	# A resource edit invalidates a warmed packet; replacing an asset cannot reuse it.
	var source:=MeshInstance3D.new();var asset:=ArrayMesh.new();var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3.ZERO,Vector3.RIGHT,Vector3.UP])
	asset.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays);source.mesh=asset;root.add_child(source)
	compare(actor,source,Transform3D.IDENTITY)
	asset.clear_surfaces();arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3.ZERO,Vector3.RIGHT*2,Vector3.UP*2]);asset.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	compare(actor,source,Transform3D.IDENTITY)
	source.mesh=asset.duplicate();source.mesh.clear_surfaces();arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3.ZERO,Vector3.RIGHT*3,Vector3.UP*3]);source.mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays);compare(actor,source,Transform3D.IDENTITY)
	actor.die();await process_frame;await process_frame
	compare(actor,actor.part_meshes.head,actor.global_transform.affine_inverse())
	print("ZOMBIE_MESH_BAKE surfaces=",comparisons," reference_us=",reference_us," native_us=",native_us," failures=",failures)
	source.free();actor.free();camera.free();await process_frame
	quit(0 if failures==0 else 1)
