# SPDX-License-Identifier: 0BSD
extends SceneTree
var game:Node
var failures:=0
var evidence:String
func check(ok:bool,label:String)->bool:
 print("PASS " if ok else "FAIL ",label)
 if not ok:failures+=1
 return ok
func wait_for(predicate:Callable,seconds:int=20)->bool:
 var deadline:=Time.get_ticks_msec()+seconds*1000
 while not predicate.call() and Time.get_ticks_msec()<deadline:await process_frame
 return predicate.call()
func amount(item:int)->int:
 var n:=0
 for row:Dictionary in game.player_hud.inventory.snapshot().slots:
  if row.item==item:n+=row.count
 return n
func slot_of(item:int)->int:
 var rows:Array=game.player_hud.inventory.snapshot().slots
 for i in rows.size():
  if rows[i].item==item:return i
 return -1
func use()->void:
 var event:=InputEventKey.new();event.pressed=true;event.physical_keycode=KEY_E
 game._unhandled_input(event)
func aim(feet:Vector3,point:Vector3)->void:
 game.player.position=feet;game.camera.position=Vector3(0,1.62,0);game.camera.look_at(point)
 game.app_focused=true;game.fly=false;game.needs_floor_spawn=false
 Input.mouse_mode=Input.MOUSE_MODE_CAPTURED
func _initialize()->void:run.call_deferred()
func run()->void:
 var slot:String=""
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--route-evidence="):evidence=arg.trim_prefix("--route-evidence=")
  if arg.begins_with("--world-slot="):slot=arg.trim_prefix("--world-slot=")
 if evidence.is_empty() or not slot.begins_with("combined_route_") or not slot.is_valid_identifier():quit(2);return
 game=load("res://demo/world.tscn").instantiate();root.add_child(game)
 if not check(await wait_for(func():return not game.loading_active,45),"copied settlement opens"):await finish();return
 game.set_physics_process(false);game._clear_motion();game.app_focused=true
 check(game.construction_inventory.gameplay and not game.session_menu.developer,"normal paid gameplay active")
 var reopening:bool="--reopen-route" in OS.get_cmdline_user_args()
 var expected:Dictionary={}
 if reopening:
  expected=FileAccess.open(evidence,FileAccess.READ).get_var()
  check(game.player_hud.inventory.capture_storage_snapshot()==expected.inventory,"earned inventory restored exactly")
  check(game.storage.store.capture_storage_snapshot()==expected.storage,"earned chest contents restored exactly")
  check(game.ground_cover.removed.capture_storage_snapshot()==expected.removed,"gathered identities restored exactly")
  check(game.structures.blocks.get_cell(expected.cell)==1,"paid brick restored")
  if expected.has("hinges"):
   check(game.doors.state.capture_storage_snapshot()==expected.hinges and game.doors.collection.capture_snapshot()==expected.doors,"door state after travel restores exactly")
 else:
  if not check(amount(201)==0 and amount(101)==0,"no starting stone or bricks fund this route"):await finish();return
  var cover:Node=game.ground_cover
  if not check(await wait_for(func():return cover.resident.size()==49),"nearby natural ground cover loaded"):await finish();return
  var candidates:Array=[]
  for key in cover.resident:
   var row:Dictionary=cover.resident[key][0]
   for i in row.ids.size():
    var t:PackedFloat32Array=row.transforms
    candidates.append({"id":row.ids[i],"point":Vector3(t[i*12+3],t[i*12+7],t[i*12+11])})
  candidates.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return a.point.distance_squared_to(game.player.position)<b.point.distance_squared_to(game.player.position))
  var gathered:=PackedInt64Array();var last:=Vector3.ZERO
  for row:Dictionary in candidates:
   if row.point.distance_to(game.terrain.focus)>25:continue
   aim(row.point+Vector3(0,0.05,0.8),row.point)
   use()
   if cover.removed.contains(row.id):gathered.append(row.id);last=row.point
   if gathered.size()==5:break
  if gathered.size()!=5:
   print("GATHER_CANDIDATES count=",candidates.size()," player=",game.player.position," focus=",game.terrain.focus," nearest=",candidates[0].point if not candidates.is_empty() else Vector3.INF)
   for row: Dictionary in candidates.slice(0,3):
    var ray_from: Vector3=row.point+Vector3.UP*64
    var ray_to: Vector3=row.point-Vector3.UP*4
    await wait_for(func():return not game._terrain_pick(ray_from,ray_to).is_empty(),5)
    print("GATHER_SURFACE point=",row.point," terrain=",game._terrain_pick(ray_from,ray_to))
  if not check(gathered.size()==5 and amount(201)==5,"E gathers five actual natural stones without free grants"):await finish();return
  game.player_hud.set_open(true);game.player_hud.recipe_buttons[0].pressed.emit()
  if not check(amount(201)==3 and amount(101)==1,"crafting button spends two earned stones for one brick"):await finish();return
  var source:int=slot_of(101)
  game.player_hud.drop_stack("player",5,game.player_hud.drag_data("player",source))
  game.player_hud.set_open(false);game.player_hud.equip(5)
  aim(last+Vector3(0,0.1,2.2),last)
  var hit:Dictionary=game._structure_target(false)
  if not check(not hit.is_empty(),"held brick targets nearby supporting ground"):await finish();return
  expected.cell=hit.target
  var click:=InputEventMouseButton.new();click.pressed=true;click.button_index=MOUSE_BUTTON_RIGHT
  game._unhandled_input(click)
  if not check(amount(101)==0 and game.structures.blocks.get_cell(expected.cell)==1,"right click places and consumes earned brick"):await finish();return
  expected.ids=gathered
 var chest:Node3D=game.storage.collection
 var chest_id:int=chest.get_ids()[0] if not reopening else expected.chest
 var t:PackedFloat32Array=chest.get_instance(chest_id)
 var point:=Vector3(t[3],t[7],t[11])
 # Approach the front in the authored object's local frame, including rotated cottages.
 var front:=Vector3(t[2],t[6],t[10]).normalized()
 aim(point+front*1.6+Vector3.UP*0.05,point+Vector3.UP*0.4)
 for frame in 10:await physics_frame
 use()
 if not check(game.storage.opened and game.storage.identity==chest_id,"E opens the existing furnished cottage chest"):await finish();return
 if not reopening:
  game.storage.player_list.select(slot_of(201));game.storage.quantity.get_line_edit().text="2"
  check(game.storage.move_selected(true) and amount(201)==1,"chest UI deposits two earned stones")
  game.storage.storage_list.select(0);game.storage.quantity.get_line_edit().text="1"
  check(game.storage.move_selected(false) and amount(201)==2,"chest UI withdraws one stone")
  expected.chest=chest_id
 check(game.storage.store.snapshot(chest_id).slots[0].count==1 and chest.is_removal_protected(chest_id),"one stored stone protects its chest from deletion")
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png(evidence+(".reopen.png" if reopening else ".route.png"))
 game.storage.close()
 if not reopening:
  expected.inventory=game.player_hud.inventory.capture_storage_snapshot()
  expected.storage=game.storage.store.capture_storage_snapshot()
  expected.removed=game.ground_cover.removed.capture_storage_snapshot()
  var file:=FileAccess.open(evidence,FileAccess.WRITE);file.store_var(expected);file.close()
 check(preload("res://addons/presentation/fullscreen_policy.gd").measurement(root).fair_graphical_sample,"1920x1080 fullscreen full render scale")
 await finish()
func finish()->void:
 game.shutdown_requested=true
 check(await game.terrain.shutdown_after_edits(),"ordinary compound save completes")
 game.free();await process_frame
 print("COMBINED_RESOURCE_ROUTE failures=",failures)
 quit(1 if failures else 0)
