# SPDX-License-Identifier: 0BSD
extends SceneTree
const Catalog=preload("res://addons/structures/grand_buildings/catalog.gd")
var failures:=0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	if not ok: failures+=1
	print("PASS " if ok else "FAIL ",label)
func run() -> void:
	var source:="user://worlds/Hidden_Meadow.trw"
	var before:=FileAccess.get_sha256(source)
	if before.is_empty():
		check(false,"read-only player-world fixture exists"); quit(1); return
	preload("res://addons/world_runtime/session_options.gd").set_arguments(PackedStringArray(["--world-slot=Hidden_Meadow","--snapshot-readonly","--temporary","--no-derived-cache"]),true)
	var game: Node=load("res://demo/world.tscn").instantiate()
	game.temporary_world=true; game.model_region_paging=false; game.background_fps=60; root.add_child(game)
	var deadline:=Time.get_ticks_msec()+120000
	while game.loading_active and Time.get_ticks_msec()<deadline:
		game.app_focused=true; await process_frame
	if check_ready(game):
		for id: String in Catalog.IDS:
			var found:=false
			for asset: Resource in game.structure_prefabs:
				if asset.get_meta("grand_building_id","")==id: found=true
			check(found,"normal construction catalog exposes "+id)
		for title: String in Catalog.TITLES:
			var found:=false
			for index in game.construction_palette.prefab.item_count:
				if game.construction_palette.prefab.get_item_text(index).contains(title): found=true
			check(found,"ordinary Building / Prefab selector lists "+title)
	game.free(); await process_frame
	check(FileAccess.get_sha256(source)==before,"canonical player save stays byte-identical")
	print("GRAND_BUILDINGS_WORLD failures=",failures); quit(1 if failures else 0)
func check_ready(game: Node) -> bool:
	var ready: bool=game.startup_complete and not game.loading_active
	check(ready,"ordinary read-only world opens without developer-content switches")
	return ready
