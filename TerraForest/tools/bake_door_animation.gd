# SPDX-License-Identifier: 0BSD
extends "res://tools/bake_bg5_runtime.gd"
## Preserve BG5 Open/Close timing and hardware motion; keep idle doors batched.
const DESTINATION="res://addons/structures/door_animation/bg5_motion.scn"

func combine(parts:Array,frame:Transform3D)->ArrayMesh:
	var builders:Dictionary={}
	for part:MeshInstance3D in parts:
		for surface in part.mesh.get_surface_count():
			var material=part.mesh.surface_get_material(surface)
			if not builders.has(material):
				var builder:=SurfaceTool.new();builder.begin(Mesh.PRIMITIVE_TRIANGLES);builder.set_material(material);builders[material]=builder
			builders[material].append_from(part.mesh,surface,frame*part.global_transform)
	var mesh:=ArrayMesh.new()
	for builder:SurfaceTool in builders.values():builder.index();builder.optimize_indices_for_cache();builder.commit(mesh)
	return mesh

func run()->void:
	var source_path:=SOURCE+"BG5.Door.Parts.glb"
	var document:=GLTFDocument.new();var state:=GLTFState.new()
	if document.append_from_file(source_path,state)!=OK:quit(1);return
	# The master is keyed at 60 Hz. Retain constant Close handle tracks too.
	var original:Node3D=document.generate_scene(state,60.0,false,false)
	if original==null:quit(1);return
	root.add_child(original)
	for animation_player:AnimationPlayer in original.find_children("*","AnimationPlayer",true,false):animation_player.stop();animation_player.active=false
	var door:Node3D=original.find_child("DoorPivot",true,false)
	var source_player:AnimationPlayer=original.find_children("*","AnimationPlayer",true,false)[0]
	var bake_receipt:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(OUTPUT+"bake.json"))
	var fit_data:Dictionary=bake_receipt.assets.door_leaf.transform
	var fit:=Transform3D(Basis(vec(fit_data.x),vec(fit_data.y),vec(fit_data.z)),vec(fit_data.origin))
	var parts:Array=door.find_children("*","MeshInstance3D",true,false)
	materials(parts,1024,false,true)
	var rig:=Node3D.new();rig.name="DoorMotion";root.add_child(rig)
	var groups:Dictionary={};var fixed:Array=[]
	for name:String in ["HandleFrontPivot","HandleBackPivot","LatchPivot"]:
		var source:Node3D=door.find_child(name,true,false)
		var centre:Vector3=fit*source.global_position
		var target:=Node3D.new();target.name=name;target.position=centre;rig.add_child(target);target.owner=rig
		var visual:=MeshInstance3D.new();visual.name="Visual";visual.mesh=combine(source.find_children("*","MeshInstance3D",true,false),Transform3D(Basis.IDENTITY,-centre)*fit)
		target.add_child(visual);visual.owner=rig
		groups[name]={"source":source,"target":target,"centre":centre}
	for part:MeshInstance3D in parts:
		var articulated:=false
		for group:Dictionary in groups.values():articulated=articulated or group.source.is_ancestor_of(part)
		if not articulated:fixed.append(part)
	var leaf:=MeshInstance3D.new();leaf.name="Leaf";leaf.mesh=combine(fixed,fit);rig.add_child(leaf);leaf.owner=rig
	var player:=AnimationPlayer.new();player.name="AnimationPlayer";player.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	rig.add_child(player);player.owner=rig
	var library:=AnimationLibrary.new();var curves:Dictionary={};var provenance:Dictionary={}
	var leaf_max:=0.0
	for clip_name:String in ["Open","Close"]:
		var source:Animation=source_player.get_animation(clip_name)
		if source==null:fail("Missing authored "+clip_name);quit(1);return
		for track in source.get_track_count():
			if str(source.track_get_path(track)).get_slice(":",0).get_file()!="DoorPivot":continue
			for key in source.track_get_key_count(track):
				var rotation:Quaternion=source.track_get_key_value(track,key)
				leaf_max=maxf(leaf_max,absf(2.0*atan2(rotation.y,rotation.w)))
	for clip_name:String in ["Open","Close"]:
		var source:Animation=source_player.get_animation(clip_name)
		var animation:=Animation.new();animation.length=source.length
		var curve:=PackedFloat32Array();var channels:Array=[]
		for track in source.get_track_count():
			var name:String=str(source.track_get_path(track)).get_slice(":",0).get_file()
			if name=="DoorPivot":
				for key in source.track_get_key_count(track):
					var rotation:Quaternion=source.track_get_key_value(track,key)
					curve.append(source.track_get_key_time(track,key));curve.append(clampf(2.0*atan2(rotation.y,rotation.w)/leaf_max,0,1))
			elif groups.has(name):
				var group:Dictionary=groups[name];var source_node:Node3D=group.source
				var target_track:=animation.add_track(Animation.TYPE_VALUE);animation.track_set_path(target_track,NodePath(name+":transform"))
				for key in source.track_get_key_count(track):
					var local:Transform3D=source_node.transform
					if source.track_get_type(track)==Animation.TYPE_ROTATION_3D:local.basis=Basis(source.track_get_key_value(track,key))
					elif source.track_get_type(track)==Animation.TYPE_POSITION_3D:local.origin=source.track_get_key_value(track,key)
					else:fail("Unexpected authored track");quit(1);return
					var delta:Transform3D=fit*door.global_transform*local*source_node.global_transform.affine_inverse()*fit.affine_inverse()
					animation.track_insert_key(target_track,source.track_get_key_time(track,key),delta*Transform3D(Basis.IDENTITY,group.centre))
			channels.append({"node":name,"keys":source.track_get_key_count(track)})
		if curve.size()<4 or animation.get_track_count()!=3:fail("Incomplete authored clip");quit(1);return
		# Exact endpoints retain legacy closed/open saves at the configured angle.
		curve[1]=0.0 if clip_name=="Open" else 1.0;curve[-1]=1.0 if clip_name=="Open" else 0.0
		curves[clip_name]=curve;library.add_animation(clip_name,animation);provenance[clip_name]={"seconds":source.length,"channels":channels}
	player.add_animation_library("",library)
	var packed:=PackedScene.new();packed.pack(rig)
	packed.set_meta("open_curve",curves.Open);packed.set_meta("close_curve",curves.Close)
	packed.set_meta("source_sha256",FileAccess.get_sha256(source_path));packed.set_meta("source_opening_degrees",rad_to_deg(leaf_max))
	DirAccess.make_dir_recursive_absolute(DESTINATION.get_base_dir())
	if ResourceSaver.save(packed,DESTINATION)!=OK:quit(1);return
	var record:Dictionary={"license":"CC0-1.0","source":source_path,"source_sha256":FileAccess.get_sha256(source_path),"clips":provenance,"source_opening_degrees":rad_to_deg(leaf_max),"retargeting":"Authored leaf timing mapped to the existing configured hinge angle; all three authored hardware channels retained in canonical fitted coordinates.","output":DESTINATION,"output_sha256":FileAccess.get_sha256(DESTINATION),"tool_sha256":FileAccess.get_sha256("res://tools/bake_door_animation.gd"),"base_tool_sha256":FileAccess.get_sha256("res://tools/bake_bg5_runtime.gd"),"base_receipt_sha256":FileAccess.get_sha256(OUTPUT+"bake.json")}
	FileAccess.open("res://addons/structures/door_animation/provenance.json",FileAccess.WRITE).store_string(JSON.stringify(record,"  ")+"\n")
	rig.free();original.free();print("DOOR_ANIMATION_BAKE authored Open/Close with three hardware channels each");quit()
