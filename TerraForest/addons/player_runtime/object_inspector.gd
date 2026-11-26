# SPDX-License-Identifier: 0BSD
extends CanvasLayer
## Presentation only. Native bounded spatial query; no object-owned label nodes.
const Profiles=preload("res://addons/player_runtime/durability_catalog.gd")
const MAX_LABELS:=24
const RANGE:=24.0
var game: Node
var enabled:=false
var nearby_names:=false
var clock:=0.0
var view: Control
var candidates: Array=[]
var labels: Array[Dictionary]=[]
var target: Dictionary={}
var title_by_collection: Dictionary={}
var collections: Array=[]
var queries: RefCounted
var stats: Dictionary={}
class Overlay extends Control:
	var owner_inspector: CanvasLayer
	func _draw() -> void: owner_inspector.paint(self)

func _ready() -> void:
	layer=24; queries=ClassDB.instantiate("NativeStructureQueries")
	view=Overlay.new(); view.owner_inspector=self; view.mouse_filter=Control.MOUSE_FILTER_IGNORE; add_child(view)
	collections=game.structures.model_collections().values()
	for key: String in game.structures.model_collections():
		var batch: Node3D=game.structures.model(key)
		title_by_collection[batch]=Profiles.model_profile(key,game.structures.object_definitions).name

func available() -> bool:
	return enabled and game.app_focused and not game.loading_active and not game.shutdown_requested and not game.session_menu.visible_ui() and not game.player_hud.inventory_open and game.terrain.world_ready

func _process(delta: float) -> void:
	view.visible=available()
	if not view.visible: labels.clear(); target.clear(); clock=0.0; return
	clock-=delta
	if clock<=0:
		clock=.15
		var start:=Time.get_ticks_usec()
		stats=queries.nearby_models(collections,game.camera.global_position,RANGE,128) if nearby_names else {"objects":[],"scanned":0,"nearby":0,"truncated":false}
		candidates=stats.objects; choose_labels(); stats.query_layout_us=Time.get_ticks_usec()-start
	view.queue_redraw()

func choose_labels() -> void:
	labels.clear(); target.clear()
	stats["occlusion_queries"]=0
	var camera: Camera3D=game.camera; var start: Vector3=camera.global_position
	var hit: Dictionary=game.structures.blocks.raycast_scene(start,start-camera.global_basis.z*RANGE,7,[game.player.get_rid()])
	if not hit.is_empty() and title_by_collection.has(hit.collider):
		var id: int=hit.collider.placement_for_body(hit.rid)
		if id>0: target={"collection":hit.collider,"id":id,"name":title_by_collection[hit.collider],"point":hit.position,"distance":start.distance_to(hit.position)}
	var occupied: Array[Rect2]=[]
	var size:=get_viewport().get_visible_rect().size
	# Reserve crosshair/target card, top status and right-hand developer controls.
	occupied.append(Rect2(size*.5-Vector2(250,45),Vector2(500,130)))
	occupied.append(Rect2(Vector2.ZERO,Vector2(550,280)))
	occupied.append(Rect2(Vector2(size.x-360,170),Vector2(360,650)))
	for row: Dictionary in candidates:
		if labels.size()>=MAX_LABELS: break
		if not target.is_empty() and row.collection==target.collection and row.id==target.id: continue
		var bounds: AABB=row.bounds; var point:=bounds.get_center()
		if camera.is_position_behind(point): continue
		var pixel:=camera.unproject_position(point)
		if not Rect2(Vector2(30,80),size-Vector2(60,160)).has_point(pixel): continue
		var text: String=title_by_collection.get(row.collection,"Object").trim_prefix("Homestead ").trim_prefix("Outdoor ")
		text=text.left(45)+" · %.1f m"%float(row.distance)
		var width:=ThemeDB.fallback_font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,16).x+18
		for offset: Vector2 in [Vector2(12,-24),Vector2(12,10),Vector2(-width-12,-24),Vector2(-width-12,10),Vector2(12,-58)]:
			var rect:=Rect2(pixel+offset,Vector2(width,27)); var free:=Rect2(Vector2(8,90),size-Vector2(16,260)).encloses(rect)
			for other: Rect2 in occupied:
				if rect.grow(4).intersects(other): free=false; break
			if not free: continue
			# Occlusion matters only when a label has space. Crowded labels formerly
			# spent physics queries before being rejected by this same layout.
			stats.occlusion_queries+=1
			var blocking: Dictionary=game.structures.blocks.raycast_scene(start,point,7,[game.player.get_rid()])
			if not blocking.is_empty() and (blocking.collider!=row.collection or row.collection.placement_for_body(blocking.rid)!=row.id) and start.distance_to(blocking.position)<start.distance_to(point)-.08: break
			occupied.append(rect); labels.append({"text":text,"rect":rect,"point":point}); break
	stats["shown"]=labels.size()

func paint(canvas: Control) -> void:
	if not available(): return
	var font:=ThemeDB.fallback_font; var size:=get_viewport().get_visible_rect().size
	canvas.draw_rect(Rect2(18,210,525,65),Color(.025,.045,.045,.92))
	canvas.draw_string(font,Vector2(28,234),"OBJECT INSPECTION"+(" · Nearby names (%d shown)"%labels.size() if nearby_names else " · Aim to inspect"),HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color("bfead9"))
	for row: Dictionary in labels:
		var pixel: Vector2=game.camera.unproject_position(row.point)
		canvas.draw_line(pixel,row.rect.get_center(),Color(.65,.83,.75,.6),1,true)
		canvas.draw_circle(pixel,3,Color("a6d9c2")); canvas.draw_rect(row.rect,Color(.025,.045,.045,.92))
		canvas.draw_string(font,row.rect.position+Vector2(9,19),row.text,HORIZONTAL_ALIGNMENT_LEFT,-1,16,Color("e5efeb"))
	if not target.is_empty():
		var text: String=target.name+" · %.1f m"%float(target.distance)
		var width:=font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,20).x+28
		var rect:=Rect2(size*.5+Vector2(-width*.5,42),Vector2(width,36))
		canvas.draw_rect(rect,Color(.03,.12,.10,.96)); canvas.draw_rect(rect,Color("a0e5bd"),false,2)
		canvas.draw_string(font,rect.position+Vector2(14,25),text,HORIZONTAL_ALIGNMENT_LEFT,-1,20,Color("ecfff0"))
	if stats.get("truncated",false) or labels.size()>=MAX_LABELS:
		canvas.draw_string(font,Vector2(28,260),"Dense view · turn or move closer to reveal more names",HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("cad5cf"))
