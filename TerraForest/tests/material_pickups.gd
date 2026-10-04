# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
var changes:=0
var captured: Dictionary={}
func check(ok: bool,label: String) -> void:
	print(("PASS " if ok else "FAIL ")+label)
	if not ok: failures+=1
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var provider:=preload("res://addons/world_runtime/world_persistence.gd").new()
	var pickups:=preload("res://addons/world_runtime/material_pickups.gd").new()
	root.add_child(pickups)
	var hud:=preload("res://addons/player_runtime/player_hud.gd").new()
	root.add_child(hud)
	check(pickups.prepare(provider),"four material stores register for world saving")
	provider.register_component("player_loadout",hud.capture_snapshot,hud.restore_snapshot,hud.inventory,hud.default_loadout)
	pickups.changed.connect(func(): changes+=1;captured=provider._capture().sections)
	var id: int=pickups.spawn(101,Vector3(1,0,0))
	check(id>0 and pickups.spawn(999,Vector3.ZERO)==0,"valid material spawn returns persistent identity")
	check(changes==1,"only accepted spawn announces a save-relevant mutation")
	pickups.update_view(0,Vector3.ZERO,true)
	check(pickups.render_status[101].rendered==1,"native renderer displays authored supply")
	var before: Dictionary=provider._capture().sections
	var denied: Dictionary=pickups.collect_near(Vector3.ZERO,hud.inventory,func(_p: Vector3): return false)
	check(not denied.ok and pickups.stores[101].resolve_identity(id)>0,"occluded pickup remains in world")
	check(changes==1,"occluded pickup does not announce a mutation")
	var result: Dictionary=pickups.collect_near(Vector3.ZERO,hud.inventory,func(_p: Vector3): return true)
	hud.refresh()
	check(result.ok and pickups.stores[101].resolve_identity(id)==0,"collection removes entity after successful inventory grant")
	check(hud.state.slots[4].item==101 and hud.state.slots[4].count==1 and hud.belt[4].disabled,"collected material appears in inventory without becoming a tool")
	check(hud.slots[4].text.contains("×1"),"inventory displays material quantity")
	var after: Dictionary=provider._capture().sections
	check(changes==2 and captured==after,"collection announces both inventory and entity changes after commit")
	provider._restore(before,1)
	check(pickups.stores[101].resolve_identity(id)>0 and hud.inventory.snapshot().slots[4].item==0,"compound reload restores both uncollected supply and prior inventory")
	provider._restore(after,2)
	check(changes==2,"snapshot restoration does not dirty the loaded world")
	check(pickups.stores[101].resolve_identity(id)==0 and hud.inventory.snapshot().slots[4].count==1,"collected snapshot does not respawn supply")
	var full: Dictionary=hud.inventory.grant(101,28*999-1,hud.inventory.snapshot().revision)
	id=pickups.spawn(102,Vector3.ZERO)
	result=pickups.collect_near(Vector3.ZERO,hud.inventory,func(_p: Vector3): return true)
	check(full.ok and not result.ok and pickups.stores[102].resolve_identity(id)>0,"full inventory leaves pickup intact")
	check(changes==3,"rejected full-inventory collection does not announce a mutation")
	pickups.update_view(0,Vector3.ZERO,false)
	check(not pickups.visible,"loading gate hides pickup rendering")
	pickups.free();hud.free()
	DirAccess.make_dir_recursive_absolute("res://reports")
	var file:=FileAccess.open("res://reports/material_pickups.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"failures":failures,"scope":"pickup inventory renderer and compound provider lifecycle"}));file.close()
	quit(1 if failures else 0)
