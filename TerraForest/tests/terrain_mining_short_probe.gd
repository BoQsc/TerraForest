# SPDX-License-Identifier: 0BSD
extends "res://tests/terrain_worker_publication_probe.gd"

# Replay field history without rendering/waiting for a whole world, then measure
# the same real worker/publication path and requested fine collision refinements.
# This diagnoses the edit bottleneck; it does not certify graphical frame pacing.
func run() -> void:
	Engine.max_fps=60
	var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/mining_short_replay.json"))
	var results: Array=[]
	for scenario in ["legacy_cold","regional_cold","regional_resident","regional_active"]:
		var regions: bool=scenario!="legacy_cold"
		world=FixedCut.new();root.add_child(world);world.set_process(false)
		world.material=StandardMaterial3D.new()
		world.backend.region_terrain=regions
		world.backend.brick_terrain=false
		world.backend.profile_regions=true
		world.backend.cache_path="user://short_mining_probe/%d/%s"%[OS.get_process_id(),scenario]
		check(world.backend.start(true)==OK,"worker starts "+str(regions))
		check(await pump_until(func(): return world.world_ready),"world ready "+str(regions))
		# The worker is idle after startup; execute() also holds the native world
		# lock. Only replay setup bypasses presentation, never the measured edits.
		for edit: Dictionary in fixture.history:
			var p:=Vector3(edit.a[0],edit.a[1],edit.a[2])
			check_reply(world.backend.native.execute(Codec.brush(p,p,edit.radius,0,edit.add,1)))
		world._read_stats(world.backend.native.execute(Codec.command(0)))
		var key:=Vector3i(1152,1280,128)
		world.visible_cut=[key]
		check(world.backend.submit({"kind":"mesh","key":key,"epoch":world.epoch,"stamp":0,"base":false}),"coarse terrain admitted")
		check(await pump_until(func(): return world.tiles.has(key)),"coarse terrain resident")
		var rows: Array=[]
		for edit: Dictionary in fixture.measure:
			var event_begin:=worker_events.size()
			var writes_before: int=world.backend.disk_cache.writes
			var p:=Vector3(edit.a[0],edit.a[1],edit.a[2])
			world.focus=p
			world.requested_keys.clear()
			for z in range(floori((p.z-7.5)/16)*16,ceili(p.z+7.5)+1,16):
				for x in range(floori((p.x-7.5)/16)*16,ceili(p.x+7.5)+1,16):
					world.requested_keys[Vector3i(x,z,16)]=true
			var prepare_started:=Time.get_ticks_usec()
			var loaded_tiles:=0
			if scenario in ["regional_resident","regional_active"]:
				for fine: Vector3i in world.requested_keys:
					if world.tiles.has(fine) and not world.tiles[fine].dirty: continue
					check(world.backend.submit({"kind":"mesh","key":fine,"epoch":world.epoch,"stamp":int(world.stamps.get(fine,0)),"base":false}),"targeted fine load admitted")
					check(await pump_until(func(): return world.tiles.has(fine) and not world.tiles[fine].dirty),"targeted fine load completes")
					loaded_tiles+=1
			if scenario=="regional_active":
				# Isolate completed local LOD handover from mere residency.
				# FixedCut does not claim whole-world coverage or distant correctness.
				for previous: Vector3i in world.visible_cut:
					world._set_active(world.tiles[previous],false)
				world.visible_cut.clear()
				for fine: Vector3i in world.requested_keys:
					world.visible_cut.append(fine)
					world._set_active(world.tiles[fine],true)
			var preparation_ms: float=(Time.get_ticks_usec()-prepare_started)/1000.0
			event_begin=worker_events.size()
			writes_before=world.backend.disk_cache.writes
			var revision: int=world.published_revision
			var owners_before: Dictionary={}
			if scenario=="regional_resident":
				for fine: Vector3i in world.requested_keys:
					for id: int in world.tiles[fine].bricks:
						owners_before[Vector4i(fine.x,fine.y,fine.z,id)]=world.tiles[fine].bricks[id].node.get_instance_id()
			check(world.edit(Codec.brush(p,p,edit.radius,0,edit.add,1),p-Vector3.ONE*(edit.radius+5),p+Vector3.ONE*(edit.radius+5)),"measured edit admitted")
			check(await pump_until(func(): return not world.pending_edit),"measured edit published")
			check(world.published_revision==revision+1,"measured edit changes terrain")
			check(world.backend.disk_cache.writes==writes_before,"edit performs no synchronous derived-cache writes")
			if scenario=="regional_resident":
				var retained:=0
				var replaced:=0
				var exact:=true
				var build_epoch: int=world.backend.native.execute(Codec.command(13)).decode_u32(12)
				for owner: Vector4i in owners_before:
					var child: Dictionary=world.tiles[Vector3i(owner.x,owner.y,owner.z)].bricks[owner.w]
					if child.node.get_instance_id()==owners_before[owner]: retained+=1
					else: replaced+=1
					var bounds: AABB=child.region_bounds
					var fresh: Dictionary=Codec.decode_mesh(world.backend.native.build_owned_region(owner.x,owner.y,16,1,int(bounds.position.y),int(bounds.end.y),build_epoch))
					for channel: int in [Mesh.ARRAY_VERTEX,Mesh.ARRAY_NORMAL,Mesh.ARRAY_INDEX]:
						exact=exact and child.arrays[channel]==fresh.arrays[channel]
				check(retained>0 and replaced>0,"hidden fine refinement retains unaffected owners")
				check(exact,"hidden fine partial rebuild equals fresh geometry")
			rows.append({"preparation_ms":preparation_ms,"loaded_tiles":loaded_tiles,"point":edit.a,"publish_ms":world.last_latency_ms,"build_ms":world.last_total_build_ms,"patches":world.last_density_tiles,"work":worker_events.slice(event_begin)})
			world._retire_some()
		results.append({"scenario":scenario,"regions":regions,"rows":rows})
		world.shutdown();world.free();await process_frame
	var old_total:=0.0
	var new_total:=0.0
	for row: Dictionary in results[0].rows: old_total+=row.build_ms
	for row: Dictionary in results[1].rows: new_total+=row.build_ms
	check(new_total<old_total*.5,"regional rebuild uses less than half the legacy worker time on the same edits")
	var report: Dictionary={"checks":checks,"results":results,"scope":"Short fixed-cut worker/publication comparison using identical saved edit history. Resident case prepares requested fine tiles while retaining coarse visibility; active case manually switches local visibility to those fine tiles. Preparation latency is reported separately, not eliminated. This bypasses whole-world coverage and automatic scheduling: it does not verify distant correctness, predictive loading, graphical FPS or endurance."}
	DirAccess.make_dir_recursive_absolute("res://reports")
	var file:=FileAccess.open("res://reports/terrain_mining_short_probe.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "));file.close()
	for result: Dictionary in results:
		for row: Dictionary in result.rows: print("MINING_SHORT ",result.scenario," preparation_ms=",row.preparation_ms," build_ms=",row.build_ms," publish_ms=",row.publish_ms)
	quit(1 if failures else 0)

func check_reply(reply: PackedByteArray) -> void:
	if not Codec.reply_ok(reply): check(false,"replay mutation succeeds")
