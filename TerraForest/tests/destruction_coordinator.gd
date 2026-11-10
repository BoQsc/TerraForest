# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
func check(ok:bool,label:String)->void:
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func _initialize()->void:run.call_deferred()
func key(cell:Vector3i)->String:return "block:%d:%d:%d"%[cell.x,cell.y,cell.z]
func legacy(blocks:Node,durability:RefCounted,records:PackedInt32Array,offset:int,center:Vector3)->Dictionary:
	var removed:=PackedInt32Array();var forces:=PackedFloat64Array();var hits:Array[Dictionary]=[]
	var end:=mini(offset+96,records.size());var revision:int=blocks.survey_revision_id()
	for at in range(offset,end,4):
		var cell:=Vector3i(records[at],records[at+1],records[at+2]);var word:=records[at+3]
		if word==0 or blocks.get_cell(cell)!=word:continue
		var distance:float=(Vector3(cell)+Vector3.ONE*.5).distance_to(center)
		var damage:=maxi(1,roundi(300*(1-distance/5)))
		var maximum:int=[90,60,120,180][blocks.decode_block(word).material]
		var quote:Dictionary=durability.quote_hit(key(cell),maximum,damage)
		if not quote.ok:continue
		if quote.destroyed:
			removed.append_array(PackedInt32Array([cell.x,cell.y,cell.z,word]));forces.append(9*(1-distance/6))
		else:hits.append({"key":key(cell),"maximum":maximum,"damage":damage})
	if not removed.is_empty() and not blocks.erase_cells(removed,revision):return {"ok":false}
	for hit:Dictionary in hits:durability.hit(hit.key,hit.maximum,hit.damage)
	for at in range(0,removed.size(),4):durability.forget(key(Vector3i(removed[at],removed[at+1],removed[at+2])))
	return {"ok":true,"offset":end,"removed":removed,"forces":forces}
func run()->void:
	GDExtensionManager.load_extension("res://addons/structures/structures.gdextension")
	GDExtensionManager.load_extension("res://addons/player_runtime/player_runtime.gdextension")
	var coordinator=ClassDB.instantiate("NativeDestructionCoordinator")
	var actual=ClassDB.instantiate("NativeBlockWorld");var control=ClassDB.instantiate("NativeBlockWorld")
	var damage=ClassDB.instantiate("NativeWorldDurability");var reference=ClassDB.instantiate("NativeWorldDurability")
	var records:=PackedInt32Array()
	for z in range(-5,6):
		for x in range(-5,6):
			var word:int=actual.encode_block(1,0,posmod(x+z,4))
			records.append_array(PackedInt32Array([x,0,z,word]))
	check(actual.set_cells(records) and control.set_cells(records),"mixed-material fixture admitted")
	for center:Vector3 in [Vector3(0,.5,0),Vector3(3,.5,2),Vector3(-3,.5,-2)]:
		for offset in range(0,records.size(),96):
			var expected:=legacy(control,reference,records,offset,center)
			var result:Dictionary=coordinator.execute(actual,damage,records,offset,center,24)
			check(result.ok and result.offset==expected.offset and result.removed==expected.removed and result.forces==expected.forces,"ordered damage and exact debris impulse parity")
		check(actual.capture_snapshot()==control.capture_snapshot() and damage.capture_storage_snapshot()==reference.capture_storage_snapshot(),"overlapping blast stores match legacy byte for byte")
	var duplicate:=PackedInt32Array([54,0,50,97,54,0,50,97])
	actual.set_cells(duplicate);control.set_cells(duplicate)
	var repeated:=legacy(control,reference,duplicate,0,Vector3(50,.5,50))
	check(coordinator.execute(actual,damage,duplicate,0,Vector3(50,.5,50),24).ok and repeated.ok and damage.capture_storage_snapshot()==reference.capture_storage_snapshot(),"legacy repeated survivor records retain cumulative damage")
	var fixture:=PackedInt32Array([20,0,20,1,24,0,20,97])
	actual.set_cells(fixture)
	var before:PackedByteArray=actual.capture_snapshot();var prior:PackedByteArray=damage.capture_storage_snapshot()
	var premature:Array[bool]=[]
	actual.set_edit_admission(func(_bounds:AABB)->bool:
		premature.append(coordinator.commit_damage());return false)
	check(not coordinator.execute(actual,damage,fixture,0,Vector3(20,.5,20),24).ok,"rejected admission rejects native transaction")
	check(actual.capture_snapshot()==before and damage.capture_storage_snapshot()==prior,"rejected admission preserves both stores and cursor")
	check(premature==[false],"admission callbacks cannot invoke the commit hook prematurely")
	actual.set_edit_admission(func(_bounds:AABB)->bool:
		damage.hit("external",100,1);return true)
	check(not coordinator.execute(actual,damage,fixture,0,Vector3(20,.5,20),24).ok and actual.capture_snapshot()==before,"durability revision changed during admission cannot erase blocks")
	prior=damage.capture_storage_snapshot()
	actual.set_edit_admission(func(_bounds:AABB)->bool:
		actual.set_edit_admission(Callable())
		actual.set_cells(PackedInt32Array([30,0,20,1]));return true)
	check(not coordinator.execute(actual,damage,fixture,0,Vector3(20,.5,20),24).ok and actual.get_cell(Vector3i(20,0,20))==1 and damage.capture_storage_snapshot()==prior,"reentrant block edit cannot consume staged damage")
	actual.set_edit_admission(Callable())
	var observed:Array[bool]=[]
	actual.cells_changed.connect(func(_bounds:AABB):observed.append(damage.damage("block:24:0:20",180)>0))
	check(coordinator.execute(actual,damage,fixture,0,Vector3(20,.5,20),24).ok and observed==[true],"block observers see matching survivor damage at store publication")
	check(not coordinator.commit_damage(),"completed transaction cannot replay damage")
	check(not coordinator.execute(actual,damage,fixture,0,Vector3.ZERO,65).ok,"native batch capacity is enforced")
	var combat=load("res://addons/player_runtime/combat_world.gd").new()
	combat.state=ClassDB.instantiate("NativeCombatState")
	combat.destruction_commit_active=true
	check(combat.capture().is_empty(),"reentrant save cannot capture new damage with an old cursor")
	combat.step_blasts()
	combat.destruction_commit_active=false
	check(not combat.capture().is_empty(),"combat capture resumes outside the commit boundary")
	combat.effects.free();combat.free()
	actual.free();control.free()
	print("DESTRUCTION_COORDINATOR failures=",failures);quit(1 if failures else 0)
