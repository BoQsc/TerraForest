# SPDX-License-Identifier: 0BSD
extends RefCounted
## Real barrel chain in an owned default-world clone. No production quality limits change.
var failures:Array[String]=[]
var peak_bodies:=0
var peak_jobs:=0
var samples:Array[Dictionary]=[]
var game:Node
var driver:SceneTree
var debris_profiles:Array[Dictionary]=[]
var publication_profiles:Array[Dictionary]=[]
var wrapped_connections:Array[Dictionary]=[]
class PublicationProbe extends RefCounted:
	var original:Callable
	var label:String
	var driver:SceneTree
	var samples:Array[Dictionary]
	func zero()->void:
		var began:=Time.get_ticks_usec();original.call();record(began)
	func one(value:Variant)->void:
		var began:=Time.get_ticks_usec();original.call(value);record(began)
	func record(began:int)->void:
		samples.append({"frame":Engine.get_process_frames(),"phase":driver.label,"callback":label,"us":Time.get_ticks_usec()-began})
func profile_publication(owner:Object,event:String,arguments:int,prefix:String)->void:
	var connections:Array=owner.get_signal_connection_list(event)
	for connection:Dictionary in connections:
		# Only synchronous persistent connections are interchangeable here.
		if connection.flags!=0:continue
		owner.disconnect(event,connection.callable)
	for connection:Dictionary in connections:
		if connection.flags!=0:continue
		var original:Callable=connection.callable
		var source:Object=original.get_object()
		var script:Script=source.get_script() if is_instance_valid(source) else null
		var name:String=prefix+":"+(script.resource_path if script!=null else "native")+"."+str(original.get_method())
		# Signal duplicate checks ignore bound arguments; a separate observer
		# identity per original callback retains every subscriber and its order.
		var probe:=PublicationProbe.new();probe.original=original;probe.label=name;probe.driver=driver;probe.samples=publication_profiles
		var replacement:Callable=probe.zero if arguments==0 else probe.one
		var connected:int=owner.connect(event,replacement)
		check(connected==OK,"publication observer retains "+name)
		if connected==OK:wrapped_connections.append({"owner":owner,"event":event,"original":original,"replacement":replacement,"probe":probe})
		else:owner.connect(event,original)
func restore_publication()->void:
	for connection:Dictionary in wrapped_connections:
		if is_instance_valid(connection.owner) and connection.owner.is_connected(connection.event,connection.replacement):
			connection.owner.disconnect(connection.event,connection.replacement)
			connection.owner.connect(connection.event,connection.original)
	wrapped_connections.clear()
func check(ok:bool,message:String)->void:
	print("PASS " if ok else "FAIL ",message)
	if not ok:failures.append(message)
func sample()->void:
	peak_bodies=maxi(peak_bodies,game.combat.effects.fragments.size())
	peak_jobs=maxi(peak_jobs,game.combat.blast_jobs.size())
	samples.append({"frame":Engine.get_process_frames(),"phase":driver.label,"bodies":game.combat.effects.fragments.size(),"flashes":game.combat.effects.flashes.size(),"jobs":game.combat.blast_jobs.size(),"explosions":game.combat.explosions,"destroyed":game.combat.destroyed_blocks,"pending_edit":game.terrain.pending_edit})
func debris_profile(profile:Dictionary)->void:
	debris_profiles.append(profile.merged({"frame":Engine.get_process_frames(),"phase":driver.label}))
func picture(output:String,name:String)->void:
	var prior:String=driver.label;driver.label="test_screenshot"
	await RenderingServer.frame_post_draw
	driver.root.get_texture().get_image().save_png(output.path_join(name+".png"))
	await RenderingServer.frame_post_draw;await RenderingServer.frame_post_draw
	driver.label=prior
func run(owner:SceneTree,host:Node,output:String)->Dictionary:
	driver=owner;game=host;driver.label="destruction_preparation"
	var original_integrity:bool=game.combat.state.integrity_enabled()
	game.combat.set_integrity(false)
	var base:=Vector3.INF
	# Choose resident open terrain; fixture blocks must never overwrite another building.
	for offset:Vector3 in [Vector3(0,0,-14),Vector3(14,0,0),Vector3(-14,0,0),Vector3(0,0,14)]:
		var desired:Vector3=game.player.global_position+offset
		var hit:Dictionary=game.structures.blocks.raycast_scene(desired+Vector3.UP*12,desired-Vector3.UP*16,1,[])
		if hit.is_empty():continue
		var candidate:Vector3=Vector3(Vector3i(hit.position.floor()))
		var ready:=AABB(candidate-Vector3(10,6,10),Vector3(20,20,20))
		if not game._actor_collision_ready(ready):continue
		var occupied:=false
		for x in range(-4,5):
			for y in range(1,6):
				for z in range(-4,5):
					if game.structures.blocks.get_cell(Vector3i(candidate)+Vector3i(x,y,z))!=0:occupied=true
		if not occupied:base=candidate;break
	if not base.is_finite():
		game.combat.set_integrity(original_integrity)
		return {"ok":false,"reason":"no ready open terrain for the owned destructive fixture"}
	var word:int=game.structures.blocks.encode_block(1,0,1)
	var records:=PackedInt32Array()
	for x in range(-4,5):
		for y in range(1,4):
			for z in range(-4,5):
				if absi(x)!=4 and absi(z)!=4 and y!=3 and not (absi(x)==1 and absi(z)==1):continue
				var cell:=Vector3i(base)+Vector3i(x,y,z)
				records.append_array(PackedInt32Array([cell.x,cell.y,cell.z,word]))
	check(game.structures.blocks.set_cells(records),"dense shell installs without replacing existing blocks")
	var barrel_ids:=PackedInt64Array();var centers:=PackedVector3Array()
	for offset:Vector3 in [Vector3(-2,0,0),Vector3(2,0,0),Vector3(0,0,-3)]:
		var point:=base+offset+Vector3.UP*.02
		var identity:int=game.combat.barrels.insert_instance(game.model_tool.records(Transform3D(Basis.IDENTITY,point),game.combat.barrels),AABB())
		barrel_ids.append(identity);centers.append(point+Vector3.UP*.5)
	check(barrel_ids.size()==3 and barrel_ids[0]>0 and barrel_ids[1]>0 and barrel_ids[2]>0,"three persistent barrels install for a real chain")
	game.fly=true;game._clear_motion()
	game.player.global_position=base+Vector3(11,4,12)
	game.camera.look_at(base+Vector3.UP*2)
	game.yaw=game.player.rotation.y;game.pitch=game.camera.rotation.x
	check(await driver.wait_for(func():return game._actor_collision_ready(AABB(base-Vector3(7,1,7),Vector3(14,9,14))),20),"normal publication makes the shell and barrel neighborhood ready")
	await driver.wait_for(func():return false,2)
	await picture(output,"destruction_before")
	var initial_explosions:int=game.combat.explosions
	var initial_destroyed:int=game.combat.destroyed_blocks
	var initial_density_revision:int=game.terrain.density_revision
	var initial_convex_builds:int=game.combat.effects.convex_builds
	var setup_started:=Time.get_ticks_usec()
	var trace:Node=driver.root.get_node_or_null("WorldSession/FrameTrace")
	if trace!=null:
		game.combat.effects.block_profiled.connect(debris_profile)
		profile_publication(game.structures.blocks,"cells_changed",1,"blocks.cells_changed")
		profile_publication(game.structures.blocks,"changed",0,"blocks.changed")
		profile_publication(game.structures,"vegetation_changed",1,"structures.vegetation_changed")
		profile_publication(game.structures,"obstacles_changed",1,"structures.obstacles_changed")
		trace.mark("three-barrel dense building chain")
	var setup_us:int=Time.get_ticks_usec()-setup_started
	RenderingServer.frame_post_draw.connect(sample)
	# Observer setup/console output and marker collection belong to preparation.
	# Drain them before measuring the first actual gameplay blast interval.
	await RenderingServer.frame_post_draw;await RenderingServer.frame_post_draw
	driver.label="destruction_chain"
	var ignition_started:=Time.get_ticks_usec()
	var ignited:bool=game.combat.damage_barrel(barrel_ids[0],50)
	var ignition_us:int=Time.get_ticks_usec()-ignition_started
	var started:=Time.get_ticks_usec()
	var finished:bool=await driver.wait_for(func():return game.combat.explosions>=initial_explosions+3 and game.combat.blast_jobs.is_empty() and game.combat.detonations.is_empty() and not game.terrain.pending_edit,35)
	var chain_ms:float=(Time.get_ticks_usec()-started)/1000.0
	driver.label="test_validation"
	check(ignited,"normal durability ignites the first barrel")
	check(finished and game.combat.explosions==initial_explosions+3,"each chained barrel detonates exactly once and store/terrain jobs finish")
	var absent:=true
	for identity:int in barrel_ids:absent=absent and game.combat.barrels.get_instance(identity).is_empty()
	check(absent and game.terrain.density_revision>initial_density_revision,"chain removes persistent barrels and edits volumetric terrain")
	# Independent accumulated damage oracle for this empty-before fixture. Do not
	# accept missing cells alone: surviving edge cells must retain exact damage too.
	var mismatches:=0;var expected_destroyed:=0
	for at in range(0,records.size(),4):
		var cell:=Vector3i(records[at],records[at+1],records[at+2]);var damage:=0
		for center:Vector3 in centers:
			var distance:float=(Vector3(cell)+Vector3.ONE*.5).distance_to(center)
			if distance<=5:damage+=maxi(1,roundi(300*(1-distance/5)))
		if damage>=60:
			expected_destroyed+=1
			if game.structures.blocks.get_cell(cell)!=0:mismatches+=1
		elif game.structures.blocks.get_cell(cell)!=word or game.world_attack.durability.damage(game.world_attack.block_key(cell),60)!=damage:mismatches+=1
	check(mismatches==0,"all shell cells retain exact three-blast destruction and edge durability")
	check(expected_destroyed>=96 and game.combat.destroyed_blocks-initial_destroyed>=expected_destroyed,"chain exercises at least the full debris population")
	check(peak_bodies==96,"physical debris reaches and preserves the existing 96-body limit")
	check(game.combat.effects.convex_builds==initial_convex_builds,"dense chain does not decompose collision meshes at runtime")
	await picture(output,"destruction_after")
	driver.label="destruction_recovery"
	check(await driver.wait_for(func():return game.combat.effects.fragments.is_empty() and game.combat.effects.flashes.is_empty(),12),"temporary bodies and flashes retire through their normal lifetime")
	await driver.wait_for(func():return false,3)
	check(game.structures.blocks.is_collision_region_ready(AABB(Vector3(base)-Vector3.ONE,Vector3.ONE*14)),"settled destruction fixture has completed building collision")
	await picture(output,"destruction_settled")
	RenderingServer.frame_post_draw.disconnect(sample)
	if game.combat.effects.block_profiled.is_connected(debris_profile):game.combat.effects.block_profiled.disconnect(debris_profile)
	restore_publication()
	game.combat.set_integrity(original_integrity)
	return {"ok":failures.is_empty(),"failures":failures,"base":base,"fixture_cells":records.size()/4,"expected_destroyed":expected_destroyed,"damage_mismatches":mismatches,"peak_bodies":peak_bodies,"peak_jobs":peak_jobs,"chain_ms":chain_ms,"observer_setup_us":setup_us,"ignition_us":ignition_us,"samples":samples,"debris_profiles":debris_profiles,"publication_profiles":publication_profiles,"scope":"Real three-barrel chain, terrain edits, exact shell damage, full unchanged debris population and normal retirement in an owned default-world clone; observer setup drains before gameplay; nested synchronous publication timings overlap, not additive; not collapse, boundary, interrupted-recovery or endurance acceptance"}
