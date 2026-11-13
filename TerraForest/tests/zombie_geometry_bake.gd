# SPDX-License-Identifier: 0BSD
extends "res://tests/zombie_geometry_cache.gd"

func run()->void:
	stage=Node3D.new();root.add_child(stage)
	var reference:=fresh()
	var baked:=Zombie.new();baked.process_mode=Node.PROCESS_MODE_DISABLED;stage.add_child(baked)
	check(baked.initialized and baked.geometry_source.statistics().baked and baked.initialization_us["anatomy readback"]==0,"baked collision anatomy avoids render-mesh readback")
	check(baked.anatomy.snapshot().limbs.size()==14 and baked.find_children("*","Area3D",true,false).is_empty() and baked.physical_bones.size()==15,"baked anatomy retains every hit region and physical bone")
	var same:=true
	for part:String in reference._shape_cache:
		var a:Dictionary=reference._shape_cache[part];var b:Dictionary=baked._shape_cache[part]
		same=same and a.shape.get_points()==b.shape.get_points() and a.offset==b.offset
	check(same,"baked and live sources produce identical convex points and offsets")
	for clip:String in ["Zombie_Idle","Zombie_Attack_Left","Zombie_Attack_Bite","Zombie_Crawl_Bite"]:
		baked.animation_player.play(baked._animation_key(clip));baked.animation_player.seek(0.65,true);baked.skeleton.force_update_all_bone_transforms()
		compare_pose(baked,"baked "+clip)
	compare_hand(baked,"hand_l");compare_hand(baked,"hand_r")
	for part:String in ["hand_l","hand_r","head"]:compare_contact(baked,part,[],true)
	var payload:Dictionary=reference.anatomy.capture_geometry_data()
	var corrupt:Dictionary=payload.duplicate(true)
	var vertices:PackedVector3Array=corrupt.parts[0].surfaces[0].vertices
	vertices[0].x=NAN;corrupt.parts[0].surfaces[0].vertices=vertices
	var retry:RefCounted=ClassDB.instantiate("NativeZombieAnatomy");retry.configure(Zombie.PARTS)
	check(not retry.set_hit_meshes(reference.skeleton,reference.part_meshes,null,corrupt),"nonfinite baked vertices reject before geometry publication")
	check(retry.set_hit_meshes(reference.skeleton,reference.part_meshes,null,payload) and retry.geometry_stats().baked,"rejected geometry can retry with a valid complete payload")
	var wrong:Dictionary=payload.duplicate(true);wrong.parts[0].mesh_path="res://different.mesh"
	var fallback:RefCounted=ClassDB.instantiate("NativeZombieAnatomy");fallback.configure(Zombie.PARTS)
	check(fallback.set_hit_meshes(reference.skeleton,reference.part_meshes,null,wrong) and not fallback.geometry_stats().baked and fallback.geometry_stats().surface_reads>0,"mismatched asset identity falls back to actual render geometry")
	var empty:Dictionary={"schema":1,"parts":[]}
	var malformed:RefCounted=ClassDB.instantiate("NativeZombieAnatomy");malformed.configure(Zombie.PARTS)
	check(malformed.set_hit_meshes(reference.skeleton,reference.part_meshes,null,empty) and not malformed.geometry_stats().baked,"incomplete bake cannot override live geometry")
	# Connect watchers on load, then edit before this bundle's first preparation.
	var early:Resource=ResourceLoader.load("res://addons/characters/runtime/assets/Zombie.geometry.res","",ResourceLoader.CACHE_MODE_IGNORE)
	reference.part_meshes.head.mesh.emit_changed()
	check(early.statistics().invalidated and baked.geometry_source.statistics().invalidated,"asset edits invalidate even a bundle with no prepared actors")
	var edited:RefCounted=early.prepare(reference.skeleton,reference.part_meshes,Zombie.PARTS)
	check(edited!=null and not edited.geometry_stats().baked and edited.geometry_stats().surface_reads>0,"changed mesh cannot reload stale baked geometry")
	var again:RefCounted=early.prepare(reference.skeleton,reference.part_meshes,Zombie.PARTS)
	check(again==edited and early.last_readback_us==0,"newly validated edited geometry remains reusable")
	var report:Dictionary={"checks":checks,"failures":failures,"reference_us":reference.initialization_us,"baked_us":baked.initialization_us,"baked_parts":payload.parts.size(),"baked_vertices":reference.anatomy.geometry_stats().vertices}
	var folder:String=evidence_directory if not evidence_directory.is_empty() else "res://reports/zombie_geometry_bake";DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	FileAccess.open(folder.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	retry=null;fallback=null;malformed=null;edited=null;again=null;early=null;stage.free();await process_frame;await process_frame
	print("ZOMBIE_GEOMETRY_BAKE_TEST checks=",checks," failures=",failures);quit(1 if failures else 0)
