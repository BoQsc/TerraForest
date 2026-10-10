# SPDX-License-Identifier: 0BSD
# Read-only geometry census; no frame-cost claim and no world writes.
extends "res://tests/actor_population_cost.gd"
func run() -> void:
	game=load("res://demo/world.tscn").instantiate();root.add_child(game)
	game.terrain.backend.disable_snapshot_writes()
	var deadline:=Time.get_ticks_msec()+60000
	while game.loading_active and Time.get_ticks_msec()<deadline:await process_frame
	game.set_physics_process(false);game._clear_motion()
	var ends: PackedVector3Array=game.road_palette.prepared_streets[0].ends
	direction=(ends[1]-ends[0]).normalized();side=Vector3(-direction.z,0,direction.x);start=ends[0]+direction*5+Vector3.UP*0.95
	game.player.position=start+side*8;game.terrain.focus=start
	var idle:=0;deadline=Time.get_ticks_msec()+30000
	while idle<60 and Time.get_ticks_msec()<deadline:await process_frame;idle=idle+1 if settled() else 0
	check(idle==60,"world settled before collision census")
	var corridor:=AABB(start-Vector3.ONE,Vector3.ONE*2)
	for along in [0.0,15.0]:
		for across in [-2.0,2.0]:
			corridor=corridor.expand(start+direction*along+side*across-Vector3.UP*1.2)
	var stack: Array[Node]=[game.terrain];var rows: Array=[];var active_bodies:=0;var inactive_bodies:=0
	var duplicate_triangles:=0;var seen: Dictionary={}
	while not stack.is_empty():
		var node: Node=stack.pop_back()
		for child in node.get_children():stack.append(child)
		if not node is StaticBody3D:continue
		if node.collision_layer & 1 == 0:inactive_bodies+=1;continue
		active_bodies+=1
		for child in node.get_children():
			if not child is CollisionShape3D or child.disabled or not child.shape is ConcavePolygonShape3D:continue
			var faces: PackedVector3Array=child.shape.get_faces()
			if faces.is_empty():continue
			var bounds:=AABB(child.global_transform*faces[0],Vector3.ZERO)
			for vertex in faces:bounds=bounds.expand(child.global_transform*vertex)
			if not bounds.intersects(corridor):continue
			rows.append({"body":str(node.get_path()),"triangles":faces.size()/3,"bounds_position":str(bounds.position),"bounds_size":str(bounds.size)})
			for at in range(0,faces.size(),3):
				var triangle:=PackedVector3Array([child.global_transform*faces[at],child.global_transform*faces[at+1],child.global_transform*faces[at+2]])
				var key:=triangle.to_byte_array().hex_encode()
				if seen.has(key):duplicate_triangles+=1
				seen[key]=true
	check(not rows.is_empty(),"route intersects active terrain collision pieces")
	var result:={"failures":failures,"active_terrain_bodies":active_bodies,"inactive_terrain_bodies":inactive_bodies,"route_candidate_pieces":rows,"exact_ordered_duplicate_triangles":duplicate_triangles,"scope":"AABB candidates, not exact contact counts. Duplicate check requires identical world vertices and order; nonidentical overlapping triangles are not detected."}
	DirAccess.make_dir_recursive_absolute("res://reports/actor_collision_layout")
	var file:=FileAccess.open("res://reports/actor_collision_layout/result.json",FileAccess.WRITE);file.store_string(JSON.stringify(result,"  "));file.close()
	print(JSON.stringify(result))
	game.terrain.shutdown();game.free();await process_frame;quit(1 if failures else 0)
