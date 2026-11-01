# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
var checks:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print(("PASS " if ok else "FAIL ")+label)
func _initialize()->void:run.call_deferred()
func run()->void:
	GDExtensionManager.load_extension("res://addons/player_runtime/player_runtime.gdextension")
	var state=ClassDB.instantiate("NativeCombatState")
	check(state!=null,"native combat extension available")
	if state==null:quit(1);return
	check(not state.integrity_enabled() and state.get_rounds()==0 and not state.take_round(),"new worlds start with optional integrity off and an empty magazine")
	check(state.load_rounds(30) and not state.load_rounds(1),"magazine capacity enforced")
	for i in 30:check(state.take_round(),"round consumed once "+str(i))
	check(not state.take_round(),"empty magazine rejects firing")
	state.load_rounds(17);state.set_integrity_enabled(true)
	var saved:PackedByteArray=state.capture_storage_snapshot();var restored=ClassDB.instantiate("NativeCombatState")
	check(restored.restore_storage_snapshot(saved) and restored.get_rounds()==17 and restored.integrity_enabled(),"magazine and optional integrity survive snapshot restore")
	var corrupt:=saved.duplicate();corrupt.encode_u32(8,31)
	check(not restored.restore_storage_snapshot(corrupt) and restored.get_rounds()==17,"invalid snapshot is rejected without mutation")
	var pending:=[{"center":Vector3(100,20,100),"records":PackedInt32Array([100,21,100,33,101,21,100,33]),"offset":4}]
	check(state.set_blast_jobs(pending),"pending blast records enter bounded native persistence")
	check(restored.restore_storage_snapshot(state.capture_storage_snapshot()) and restored.get_blast_jobs()==pending,"save restores exact destruction cursor without reapplying processed cells")
	var invalid:=pending.duplicate(true);invalid[0].offset=3
	check(not state.set_blast_jobs(invalid) and state.get_blast_jobs()==pending,"unaligned destruction cursor rejected without replacing valid work")
	check(not restored.validate_snapshot(state.capture_storage_snapshot().slice(0,-1)),"truncated destruction snapshot rejected")
	check(state.load_rounds(30,8) and state.get_rounds(8)==30 and state.get_rounds()==17,"assault rifle has an independent magazine")
	check(state.take_round(8) and state.get_rounds(8)==29 and state.get_rounds()==17,"automatic rifle shot leaves carbine ammunition unchanged")
	check(not state.load_rounds(2,8) and not state.load_rounds(0,8) and not state.load_rounds(1,9) and not state.take_round(9),"new magazine rejects overflow and unknown weapon identities")
	check(restored.restore_storage_snapshot(state.capture_storage_snapshot()) and restored.get_rounds(8)==29 and restored.get_rounds()==17 and restored.get_blast_jobs()==pending,"v3 restores both magazines with pending destruction")
	corrupt=state.capture_storage_snapshot();corrupt.encode_u32(20,31)
	check(not restored.restore_storage_snapshot(corrupt) and restored.get_rounds(8)==29,"invalid assault magazine rejects entire snapshot atomically")
	var legacy:PackedByteArray=state.capture_storage_snapshot().slice(0,20);legacy.encode_u32(4,2);legacy.append_array(state.capture_storage_snapshot().slice(24))
	check(restored.restore_storage_snapshot(legacy) and restored.get_rounds()==17 and restored.get_rounds(8)==0 and restored.get_blast_jobs()==pending,"v2 migration preserves carbine and cursor while initializing assault magazine empty")
	legacy=legacy.slice(0,16);legacy.encode_u32(4,1)
	check(restored.restore_storage_snapshot(legacy) and restored.get_rounds()==17 and restored.get_rounds(8)==0 and restored.get_blast_jobs().is_empty(),"v1 migration remains supported")
	var records:=PackedInt32Array([4,2,4,33,4,3,4,33,5,3,4,33,10,5,10,1])
	var origin:=Vector3i(100,20,100);var size:=Vector3i(32,32,32)
	var probes:PackedVector3Array=state.support_probes(records,origin)
	check(probes.size()==4 and probes[0].is_equal_approx(Vector3(104.5,21.92,104.5)),"support probes sample terrain beneath each block")
	var missing:PackedInt32Array=state.unsupported(records,origin,size,PackedFloat32Array([-1,1,1,1]))
	check(missing==PackedInt32Array([110,25,110,1]),"grounded tower carries a short beam; detached block falls")
	missing=state.unsupported(records,origin,size,PackedFloat32Array([1,1,1,1]))
	check(missing.size()==16,"mining away foundation destabilizes every disconnected block")
	check(state.unsupported(records,origin,size,PackedFloat32Array([NAN,1,1,1])).is_empty(),"unavailable support cannot authorize collapse")
	var beam:=PackedInt32Array();var density:=PackedFloat32Array()
	for x in range(2,20):beam.append_array(PackedInt32Array([x,4,4,33]));density.append(-1 if x==2 else 1)
	check(not state.unsupported(beam,origin,size,density).is_empty(),"long unsupported cantilever exceeds material span")
	check(state.blast_cells(records,origin,Vector3(104.5,22.5,104.5),1.1).size()==8,"spherical blast selects only nearby building cells")
	if "--native-only" in OS.get_cmdline_user_args():
		print("COMBAT_STATE checks=",checks," failures=",failures);quit(1 if failures else 0);return
	var tools=load("res://addons/player_runtime/tool_view.gd").new();root.add_child(tools);tools.set_process(false);tools.human.set_process(false)
	var human=tools.human;var reloaded:Array=[];human.rifle_reload_finished.connect(func():reloaded.append(true))
	tools.equip(7)
	for clip in ["Idle","Walk","Run","Jump","Aim","Fire","HipFire","Reload","Equip","Holster"]:check(human.clips.has("FP_Rifle_"+clip),"existing authored rifle clip "+clip)
	check(human.active_clip=="FP_Rifle_Equip","rifle equip plays")
	human._process(1);check(human.rifle_action("HipFire"),"hip fire starts after equip")
	human._process(1);human.rifle_aiming=true;human._process(.1)
	check(human.active_clip=="FP_Rifle_Aim" and human.rifle_action("Fire"),"aim and aimed fire are wired")
	human._process(1);check(human.rifle_action("Reload"),"reload starts")
	human._process(1);check(reloaded.is_empty(),"reload does not complete during windup")
	human.cancel_rifle_reload();human._process(3);check(reloaded.is_empty(),"cancelled reload never completes")
	check(human.rifle_action("Reload"),"fresh reload starts");human._process(3)
	check(reloaded.size()==1,"full animation completes reload exactly once")
	tools.equip(1);check(human.active_clip=="FP_Rifle_Holster","switching tools plays rifle holster")
	human._process(1);check(human.current==1,"holster completes queued tool change")
	tools.equip(8);human._process(1)
	check(human.current==8 and human.rifle_action("HipFire"),"new assault rifle equips and starts automatic recoil")
	check(human.active_clip=="FP_Ranger_HipFire" and is_equal_approx(human.action_remaining,.08),"automatic recoil fits inside 100ms firing interval")
	human._process(.12);check(human.rifle_action("Fire"),"next automatic shot has no leftover animation lock")
	human._process(.12);check(human.rifle_action("Reload"),"assault rifle uses authored detachable-magazine reload")
	human._process(3);check(reloaded.size()==2,"assault reload completes once")
	var visible_ranger:=0;var visible_carbine:=0
	for mesh:MeshInstance3D in human.meshes:
		if mesh.visible and "Ranger" in mesh.name and "Flash" not in mesh.name:visible_ranger+=1
		if mesh.visible and "Equipment.Carbine" in mesh.name:visible_carbine+=1
	check(visible_ranger==2 and visible_carbine==0,"new body and independent magazine replace the carbine presentation")
	tools.free();await process_frame
	print("COMBAT_STATE checks=",checks," failures=",failures);quit(1 if failures else 0)
