# SPDX-License-Identifier: 0BSD
extends SceneTree
const Packs=preload("res://addons/structures/pack_registry.gd")
const Items=preload("res://addons/player_runtime/item_catalog.gd")
var failures:=0
var checks:=0
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures+=1
	print("PASS " if ok else "FAIL ",label)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	check(Packs.discover(),"all dropped pack manifests validate")
	check(Packs.packs.size()>=10 and Packs.objects.size()>=100,"all ten Homestead packs discovered")
	var world:=preload("res://addons/structures/structures_world.gd").new(); root.add_child(world)
	var entries:=Packs.register(world)
	check(entries.size()==Packs.objects.size(),"one native collection for every discovered model")
	var recipes:=preload("res://addons/structures/construction_catalog.gd").recipes()
	for entry: Dictionary in entries:
		check(Items.item_name(entry.item)==Packs.by_item[entry.item].name and Items.Objects.TITLES[entry.item]==entry.title and recipes[entry.id]==entry.costs,"shared identity: "+entry.id)
		check(preload("res://addons/player_runtime/item_icons.gd").texture(entry.item)!=null,"discovered icon: "+entry.id)
	var original: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(Packs.ROOT+"/homestead_10/pack.json"))
	var sample:=original.duplicate(true); sample.id="terraforest.example_pack"; sample.name="Example Pack"
	for i in sample.objects.size(): sample.objects[i].item=9000+i
	check(Packs.validate(sample,"example_pack",Packs.by_item,Packs.objects).is_empty(),"new folder requires no per-item host code")
	sample.objects[1].item=sample.objects[0].item
	check(not Packs.validate(sample,"example_pack").is_empty(),"duplicate ids fail closed")
	sample=original.duplicate(true); sample.objects[0].id="../escape"
	check(not Packs.validate(sample,"homestead_10").is_empty(),"model path traversal rejected")
	sample=original.duplicate(true); sample.objects[0].item=1
	check(not Packs.validate(sample,"homestead_10").is_empty(),"base inventory identities protected")
	sample=original.duplicate(true); sample.objects[0].salvage=[102,9999]
	check(not Packs.validate(sample,"homestead_10").is_empty(),"inflated salvage rejected")
	sample=original.duplicate(true); sample.objects[0].recipe=[150,1]
	check(not Packs.validate(sample,"homestead_10").is_empty(),"undefined recipe ingredient rejected")
	check(load("res://demo/world.gd")!=null,"ordinary game compiles")
	world.free(); await process_frame
	print("OBJECT_PACK_REGISTRY checks=",checks," failures=",failures); quit(1 if failures else 0)
