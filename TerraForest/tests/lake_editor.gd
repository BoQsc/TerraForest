# SPDX-License-Identifier: 0BSD
extends SceneTree
var failures:=0
func check(ok: bool,label: String):
 if not ok:failures+=1
 print(("PASS " if ok else "FAIL ")+label)
func _initialize():run.call_deferred()
func run():
 var game=load("res://demo/world.tscn").instantiate();root.add_child(game);game.background_fps=60
 var begun=Time.get_ticks_msec()
 var readiness_events: Array=[]
 game.lakes.lake_ready.connect(func(id: int):readiness_events.append({"id":id,"ms":Time.get_ticks_msec()-begun}))
 var deadline=Time.get_ticks_msec()+30000
 while (game.loading_active or game.lakes.statistics().ready!=4) and Time.get_ticks_msec()<deadline:await process_frame
 game.set_physics_process(false);game._clear_motion()
 print("LAKE_STARTUP ",JSON.stringify({"events":readiness_events,"state":game.lakes.statistics(),"worker":game.terrain.backend.status(),"queued":game.terrain.backend.queued()}))
 check(not game.loading_active and game.lakes.statistics().ready==4,"four generated lakes ready in main world")
 if not game.session_menu.developer:game.session_menu.toggle_developer()
 game.session_menu.show_page("Water")
 var editor=game.session_menu.pages.Water.get_child(0)
 for i in 4:await process_frame
 check(editor.rows.get_child_count()==4 and game.session_menu.pages.Water.visible,"Water page lists four lakes")
 var entries: Array[Dictionary]=game.lakes.descriptions();var first: Dictionary=entries[0]
 check(first.state=="Ready" and not game.lakes.retry_lake(first.id),"ready water reports usable state and cannot queue redundant bake")
 var saved: PackedByteArray=game.lakes.capture_snapshot();var revision: int=game.terrain.published_revision
 var record: Dictionary=game.lakes._lakes[first.id];var seed: Vector3=record.seed
 check(game.lakes.depth_at(seed)>0,"selected lake seed is occupied before removal")
 editor.rows.get_child(0).get_child(1).pressed.emit()
 for i in 4:await process_frame
 check(game.lakes.statistics().lakes==3 and editor.rows.get_child_count()==3 and game.lakes.depth_at(seed)==0,"Remove water button removes occupancy and updates list")
 check(game.terrain.published_revision==revision and not game.terrain.pending_edit,"removing water does not sculpt terrain")
 check(game.lakes.restore_snapshot(saved),"existing persistence restores removed definition")
 deadline=Time.get_ticks_msec()+20000
 while game.lakes.statistics().ready!=4 and Time.get_ticks_msec()<deadline:await process_frame
 for i in 4:await process_frame
 check(game.lakes.statistics().ready==4 and editor.rows.get_child_count()==4 and game.lakes.capture_snapshot()==saved,"restored water republishes and UI retains stable identities")
 DirAccess.make_dir_recursive_absolute("res://reports/lake_editor")
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png("res://reports/lake_editor/water.png")
 game.session_menu.toggle_developer();editor.remove(first.id)
 check(game.lakes.capture_snapshot()==saved and not game.session_menu.navigation.Water.visible,"gameplay hides water editor and rejects its actions")
 game.shutdown_requested=true;await game.terrain.shutdown_after_edits();game.free();await process_frame
 print("LAKE_EDITOR failures=",failures);quit(1 if failures else 0)
