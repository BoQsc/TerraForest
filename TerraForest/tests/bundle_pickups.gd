# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
var checks:=0
func check(ok:bool,label:String)->bool:
 checks+=1
 if not ok:failures+=1
 print("PASS " if ok else "FAIL ",label)
 return ok
func _initialize()->void:run.call_deferred()
func run()->void:
 Engine.max_fps=60
 var scene:=Node3D.new();root.add_child(scene)
 var provider=preload("res://addons/world_runtime/world_persistence.gd").new()
 var pickups=preload("res://addons/world_runtime/material_pickups.gd").new();scene.add_child(pickups)
 var hud=preload("res://addons/player_runtime/player_hud.gd").new()
 if not check(hud.prepare() and pickups.prepare(provider),"bundled inventory, pickup schemas and every dropped model initialize"):
  hud.free();scene.free();quit(1);return
 check(provider.register_component("player_loadout",hud.capture_snapshot,hud.restore_snapshot,hud.inventory,hud.default_loadout),"inventory and pickups share snapshot registration")
 var index:=0;var ids:Dictionary={};var points:Dictionary={}
 for item:int in pickups.ITEMS:
  var slot:=-1
  for i in hud.inventory.snapshot().slots.size():
   if hud.inventory.snapshot().slots[i].item==item:slot=i;break
  if slot<0:
   check(hud.inventory.grant(item,1,hud.inventory.snapshot().revision).ok,"grant fixture item %d"%item)
   for i in hud.inventory.snapshot().slots.size():
    if hud.inventory.snapshot().slots[i].item==item:slot=i;break
  if item==1:hud.inventory.wear_tool(slot,7,hud.inventory.snapshot().revision)
  var point:=Vector3((index%6)*4,0,(index/6)*4);points[item]=point
  var dropped:Dictionary=pickups.drop_one(hud.inventory,slot,hud.inventory.snapshot().revision,point)
  check(dropped.ok,"drop item %d through native stack transfer"%item)
  if dropped.ok:ids[item]=dropped.id
  var label:=Label3D.new();label.text=pickups.ITEMS[item];label.position=point+Vector3(0,0.8,0);label.billboard=BaseMaterial3D.BILLBOARD_ENABLED;label.font_size=32;scene.add_child(label)
  index+=1
 pickups.update_view(0,Vector3(10,0,6),true)
 for item:int in pickups.ITEMS:
  check(pickups.render_status[item].rendered==1 and pickups.renderers[item].multimesh.mesh.get_aabb().size.length()>0,"batched item %d has actual visible geometry"%item)
 var before:Dictionary=provider._capture().sections
 check(not pickups.collect_near(points[202],hud.inventory,func(_p):return false).ok,"occluded ore cannot be collected")
 for item:int in ids:
  check(pickups.collect_near(points[item],hud.inventory,func(_p):return true).ok and pickups.stores[item].resolve_identity(ids[item])==0,"collect item %d without respawn"%item)
 var after:Dictionary=provider._capture().sections
 provider._restore(before,1)
 check(provider._capture().sections==before,"compound restore exactly recovers uncollected items and inventory")
 provider._restore(after,2)
 check(provider._capture().sections==after,"compound restore exactly recovers collected items and tool wear")
 provider._restore(before,3);pickups.update_view(0,Vector3(10,0,6),true)
 var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-55,-20,0);scene.add_child(light)
 var camera:=Camera3D.new();scene.add_child(camera);camera.position=Vector3(10,21,25);camera.look_at(Vector3(10,0,6));camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=27;camera.make_current()
 for frame in 3:await RenderingServer.frame_post_draw
 DirAccess.make_dir_recursive_absolute("res://reports/bundle_pickups")
 root.get_texture().get_image().save_png("res://reports/bundle_pickups/route.png")
 var file:=FileAccess.open("res://reports/bundle_pickups/result.json",FileAccess.WRITE);file.store_string(JSON.stringify({"checks":checks,"failures":failures,"items":ids.size()},"  "));file.close()
 hud.free();scene.free();await process_frame
 print("BUNDLE_PICKUPS failures=",failures);quit(1 if failures else 0)
