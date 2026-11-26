# SPDX-License-Identifier: 0BSD
extends SceneTree
const Zombie=preload("res://addons/characters/runtime/zombie.gd")
var failures:=0
var checks:=0
var reducer:RefCounted
var stage:Node3D
func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures+=1
	print("PASS " if value else "FAIL ",label)
func verify(points:PackedVector3Array,label:String)->Dictionary:
	var result:Dictionary=reducer.prepare_collision_cloud(points,true)
	var retained:Dictionary={}
	for point:Vector3 in result.points:retained[point]=true
	var center:=[0.0,0.0,0.0];var valid:=true
	for index:int in result.supports:
		valid=valid and retained.has(points[index])
		for axis in 3:center[axis]+=float(points[index][axis])/result.supports.size()
	var removed:Dictionary={}
	for pair:Array in result.duplicates:
		var index:int=pair[0];var source:int=pair[1]
		valid=valid and source<index and points[index]==points[source] and retained.has(points[source]) and not removed.has(index)
		removed[index]=true
	for row:Array in result.witnesses:
		var index:int=row[0];var weights:Array=[1.0-float(row[4])-float(row[5])-float(row[6]),float(row[4]),float(row[5]),float(row[6])]
		valid=valid and not removed.has(index) and weights.all(func(w:float):return w>0.0 and w<1.0)
		removed[index]=true
		for vertex:int in [row[1],row[2],row[3]]:valid=valid and retained.has(points[vertex])
		for axis in 3:
			var reconstructed:float=center[axis]*weights[0]
			for i in 3:reconstructed+=float(points[int(row[i+1])][axis])*weights[i+1]
			valid=valid and absf(reconstructed-float(points[index][axis]))<1e-8*maxf(1.0,absf(points[index][axis]))
	var cursor:=0
	for index in points.size():
		if removed.has(index):continue
		valid=valid and cursor<result.points.size() and points[index]==result.points[cursor]
		cursor+=1
	check(valid and cursor==result.points.size(),label+": every discarded point has a convex or exact-equality certificate; output preserves first-source order/bytes")
	print("CLOUD ",label," input=",points.size()," retained=",result.points.size()," cells=",result.cells," prepare_us=",result.prepare_us)
	return result
func install(points:PackedVector3Array,position:Vector3)->Dictionary:
	var body:=StaticBody3D.new();body.position=position;body.collision_layer=2;body.collision_mask=0;stage.add_child(body)
	var shape:=ConvexPolygonShape3D.new();shape.margin=.003;shape.points=points
	var collision:=CollisionShape3D.new();collision.shape=shape
	var began:=Time.get_ticks_usec();body.add_child(collision)
	return {"body":body,"us":Time.get_ticks_usec()-began}
func contacts(points:PackedVector3Array,reduced:PackedVector3Array,label:String)->void:
	var original:=install(points,Vector3(-10,0,0));var candidate:=install(reduced,Vector3(10,0,0))
	await physics_frame
	var space:=stage.get_world_3d().direct_space_state;var bounds:=AABB(points[0],Vector3.ZERO)
	for p:Vector3 in points:bounds=bounds.expand(p)
	var matched:=true;var worst:=0.0
	for i in 96:
		var y:=1.0-2.0*(i+.5)/96.0;var radius:=sqrt(1-y*y);var angle:=i*2.399963229728653
		var direction:=Vector3(radius*cos(angle),y,radius*sin(angle))
		var start:=bounds.get_center()+direction*maxf(1,bounds.size.length()*2)
		var end:=bounds.get_center()-direction*maxf(1,bounds.size.length()*2)
		var query:=PhysicsRayQueryParameters3D.new();query.collision_mask=2
		query.from=start+original.body.position;query.to=end+original.body.position
		var a:Dictionary=space.intersect_ray(query)
		query.from=start+candidate.body.position;query.to=end+candidate.body.position
		var b:Dictionary=space.intersect_ray(query)
		if a.is_empty()!=b.is_empty():matched=false
		elif not a.is_empty():worst=maxf(worst,(a.position-original.body.position).distance_to(b.position-candidate.body.position))
	check(matched and worst<0.0005,label+": independent engine ray contacts match within 0.5 mm ("+str(worst)+")")
	print("CLOUD_INSTALL ",label," original_us=",original.us," reduced_us=",candidate.us)
	original.body.free();candidate.body.free()
func actor_clouds(actor:Node3D,label:String)->void:
	for part:String in actor._shape_cache:
		var key:="torso" if part=="pelvis" else part
		var bone:String="Hips" if part=="pelvis" else actor.PARTS[part].bone
		var info:Dictionary=actor._shape_cache[part]
		var to_local:Transform3D=(actor.skeleton.global_transform*actor.skeleton.get_bone_global_pose(actor.skeleton.find_bone(bone))*Transform3D(info.offset)).affine_inverse()
		var all_points:PackedVector3Array=actor.anatomy.sample_vertices(key,to_local)
		var points:=PackedVector3Array()
		if info.has("source_indices"):
			for index:int in info.source_indices:points.append(all_points[index])
		else:points=all_points
		if label=="rest":verify(points,part)
		var cached:Dictionary=actor.anatomy.prepare_collision_cloud(points)
		print("CLOUD_REVALIDATE ",label," ",part," input=",points.size()," retained=",cached.points.size()," prepare_us=",cached.prepare_us)
		await contacts(points,cached.points,label+" "+part)
		if part=="head" and OS.get_cmdline_user_args().has("--duplicate-cloud-probe"):
			var distinct:Dictionary={}
			for point:Vector3 in cached.points:distinct[point]=true
			var unique:=PackedVector3Array(distinct.keys());var pairs:Array=[]
			for repeat in 6:
				var pair:Dictionary={}
				for compact:bool in ([false,true] if repeat%2==0 else [true,false]):
					var trial:=install(unique if compact else cached.points,Vector3.ZERO)
					pair["unique_us" if compact else "original_us"]=trial.us;trial.body.free()
				pairs.append(pair)
			print("DUPLICATE_CLOUD_PROBE ",JSON.stringify({"pose":label,"input":cached.points.size(),"unique":unique.size(),"pairs":pairs,"scope":"Fresh engine hull installation; excludes duplicate detection"}))
			await contacts(cached.points,unique,label+" exact duplicate removal")
func run()->void:
	stage=Node3D.new();root.add_child(stage);reducer=ClassDB.instantiate("NativeZombieAnatomy")
	seed(1703)
	var cube:=PackedVector3Array()
	for x in [-1.,1.]:
		for y in [-1.,1.]:
			for z in [-1.,1.]:cube.append(Vector3(x,y,z))
	for i in 2000:cube.append(Vector3(randf_range(-.99,.99),randf_range(-.99,.99),randf_range(-.99,.99)))
	var reduced:=verify(cube,"cube")
	check(reduced.points.size()<cube.size()/4,"dense interior cloud eliminates actual hull input")
	await contacts(cube,reduced.points,"cube")
	var repeated:=cube.duplicate()
	for i in 40:
		for corner in 8:repeated.append(cube[corner])
	var duplicate_cloud:=verify(repeated,"repeated boundary positions")
	check(duplicate_cloud.duplicate_points==320 and duplicate_cloud.points==reduced.points,"render seams remove duplicate boundary positions without changing collision topology")
	await contacts(repeated,duplicate_cloud.points,"duplicate boundary positions")
	var close:=repeated.duplicate();var distinct:=cube[0]+Vector3(.000001,0,0);close.append(distinct)
	check(verify(close,"nearby distinct boundary point").points.has(distinct),"exact compaction never merges nearby distinct boundary vertices")
	close.append(Vector3(0,1,1));close.append(Vector3(-0.0,1,1))
	check(verify(close,"signed zero positions").duplicate_points==321,"signed zero positions share the same equality and hash")
	var changed:=cube.duplicate();var moved:int=reduced.witnesses[0][0];changed[moved]=Vector3(3,.17,.21)
	var revalidated:Dictionary=reducer.prepare_collision_cloud(changed)
	check(revalidated.points.has(changed[moved]),"a newly exterior point is retained")
	await contacts(changed,revalidated.points,"deformed cloud")
	var smaller:=PackedVector3Array([Vector3.ZERO,Vector3.RIGHT,Vector3.UP,Vector3.BACK])
	var resized:Dictionary=reducer.prepare_collision_cloud(smaller)
	check(resized.points==smaller,"small clouds preserve their original input")
	var plane:=PackedVector3Array();var line:=PackedVector3Array();var sphere:=PackedVector3Array()
	# Exceed the runtime cutoff so degeneracy/boundary checks exercise the
	# filter itself, rather than only its small-input fast path.
	for i in 2048:
		plane.append(Vector3(randf_range(-1,1),0,randf_range(-1,1)));line.append(Vector3(i*.01,0,0))
		var point:=Vector3(randf_range(-1,1),randf_range(-1,1),randf_range(-1,1)).normalized();sphere.append(point)
	check(verify(plane,"planar").points==plane and verify(line,"collinear").points==line,"degenerate cells preserve the original cloud")
	check(verify(sphere,"sphere boundary").points==sphere,"boundary-only samples are never removed")
	var transformed:=PackedVector3Array()
	for point:Vector3 in cube:transformed.append(Vector3(1700,-20,1200)+Basis(Vector3(1,2,3).normalized(),.7)*point*.01)
	verify(transformed,"small translated rotated cloud")
	var actor:=Zombie.new();actor.set_simulation_available(false);stage.add_child(actor)
	await actor_clouds(actor,"rest")
	var clone:=Zombie.new();clone.geometry_template=actor.anatomy;clone.set_simulation_available(false);stage.add_child(clone)
	actor.free()
	clone.animation_player.play(clone._animation_key("Zombie_Attack_Left"));clone.animation_player.seek(.65,true);clone.animation_player.pause();clone.skeleton.force_update_all_bone_transforms()
	await actor_clouds(clone,"attack after owner retirement")
	var head:MeshInstance3D=clone.part_meshes.head
	if head.mesh.get_blend_shape_count()>0:
		head.set_blend_shape_value(0,.8)
		await actor_clouds(clone,"morphed attack")
	else:
		# Exercise arbitrary per-vertex deformation even on assets without morphs.
		var deformed:=cube.duplicate()
		for index in deformed.size():deformed[index]+=Vector3(0,sin(index*.7)*.2,cos(index*.3)*.1)
		var cloud:Dictionary=reducer.prepare_collision_cloud(cube)
		cloud=reducer.prepare_collision_cloud(deformed)
		await contacts(deformed,cloud.points,"arbitrary vertex deformation")
	clone.part_meshes.head.mesh.emit_changed()
	check(not clone.anatomy.geometry_stats().valid,"asset invalidation still releases shared geometry")
	clone.free();stage.free();await process_frame
	print("ZOMBIE_COLLISION_CLOUD checks=",checks," failures=",failures);quit(failures)
