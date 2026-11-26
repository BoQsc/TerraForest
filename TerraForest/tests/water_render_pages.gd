# SPDX-License-Identifier: 0BSD
extends SceneTree
const Pages=preload("res://addons/volumetric_water/water_render_pages.gd")
var failures:=0
func check(value:bool,label:String)->void:
	print("PASS " if value else "FAIL ",label)
	if not value:failures+=1
func arrays(height:float=0.0)->Array:
	var a:Array=[];a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3(0,height,0),Vector3(4,height,0),Vector3(0,height,4)])
	a[Mesh.ARRAY_NORMAL]=PackedVector3Array([Vector3.UP,Vector3.UP,Vector3.UP])
	a[Mesh.ARRAY_TEX_UV]=PackedVector2Array([Vector2(1,2),Vector2(5,2),Vector2(1,6)])
	a[Mesh.ARRAY_COLOR]=PackedColorArray([Color(1,0,0,1),Color(1,0,0,1),Color(1,0,0,1)])
	a[Mesh.ARRAY_INDEX]=PackedInt32Array([0,1,2])
	return a
func owner(parent:Node3D,coordinate:Vector3i,a:Array)->MeshInstance3D:
	var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,a)
	var node:=MeshInstance3D.new();node.mesh=mesh;node.position=Vector3(coordinate)*4;parent.add_child(node);return node
func settle(pages:Node3D)->void:
	var deadline:=Time.get_ticks_msec()+10000
	while Time.get_ticks_msec()<deadline:
		pages.step()
		if pages.task<0 and pages.dirty.is_empty():return
		await process_frame
	check(false,"Render worker completes")
func _initialize()->void:run.call_deferred()
func run()->void:
	var first:=arrays();var second:=arrays(.375)
	var native:RefCounted=ClassDB.instantiate("NativeWaterRenderPages")
	check(native.configure([[{"arrays":first,"offset":Vector3.ZERO},{"arrays":second,"offset":Vector3(4,0,0)}]]),"Two exact owners form a bounded page")
	native.prepare();var result:Array=native.result()
	check(result.size()==1 and result[0].get_surface_count()==1,"One surface replaces two draw submissions")
	var merged:Array=result[0].surface_get_arrays(0)
	# Compare the same renderer packing on both paths (octahedral normals and
	# vertex colors are quantized even for the original unbatched meshes).
	var original:=ArrayMesh.new();original.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,first)
	var original_second:=ArrayMesh.new();original_second.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,second)
	var first_packed:=original.surface_get_arrays(0);var second_packed:=original_second.surface_get_arrays(0)
	var exact:bool=merged[Mesh.ARRAY_INDEX]==PackedInt32Array([0,1,2,3,4,5])
	for i in 3:
		exact=exact and merged[Mesh.ARRAY_VERTEX][i].is_equal_approx(first[Mesh.ARRAY_VERTEX][i]) and merged[Mesh.ARRAY_VERTEX][i+3].is_equal_approx(second[Mesh.ARRAY_VERTEX][i]+Vector3(4,0,0))
		for attribute in [Mesh.ARRAY_NORMAL,Mesh.ARRAY_TEX_UV,Mesh.ARRAY_COLOR]:
			exact=exact and merged[attribute][i].is_equal_approx(first_packed[attribute][i]) and merged[attribute][i+3].is_equal_approx(second_packed[attribute][i])
	check(exact,"Triangle winding, positions, normals, UVs and contact colors are preserved")
	var unsupported:=first.duplicate();unsupported[Mesh.ARRAY_TEX_UV2]=first[Mesh.ARRAY_TEX_UV]
	var rejected:RefCounted=ClassDB.instantiate("NativeWaterRenderPages")
	check(not rejected.configure([[{"arrays":unsupported,"offset":Vector3.ZERO},{"arrays":second,"offset":Vector3.ZERO}]]),"Unknown vertex streams fail closed")
	var invalid:=arrays();invalid[Mesh.ARRAY_INDEX]=PackedInt32Array([0,1,99])
	var bad:RefCounted=ClassDB.instantiate("NativeWaterRenderPages")
	check(bad.configure([[{"arrays":invalid,"offset":Vector3.ZERO},{"arrays":second,"offset":Vector3.ZERO}]]),"Packet validation owns its immutable inputs")
	bad.prepare();check(bad.result()[0]==null,"Invalid indices never reach the renderer")
	check(Pages.page_key(Vector3i(-1,-4,7))==Vector3i(-1,-1,1),"Page coordinates use floor division")
	var stage:=Node3D.new();root.add_child(stage)
	var pages:=Pages.new();stage.add_child(pages)
	var a:=owner(stage,Vector3i.ZERO,first);var b:=owner(stage,Vector3i(1,0,0),second)
	pages.commit({Vector3i.ZERO:{"node":a,"arrays":first},Vector3i(1,0,0):{"node":b,"arrays":second}})
	await settle(pages)
	check(pages.statistics().active==1 and not a.visible and not b.visible,"Published page replaces exactly its current owners")
	pages.set_draw_pages(false)
	check(a.visible and b.visible and pages.statistics().active==0,"Same-scene comparison restores exact individual draws")
	pages.set_draw_pages(true)
	check(not a.visible and not b.visible and pages.statistics().active==1,"Same-scene comparison restores the prepared page without rebuilding")
	var replacement:=owner(stage,Vector3i.ZERO,arrays(.75));a.hide()
	pages.commit({Vector3i.ZERO:{"node":replacement,"arrays":arrays(.75)}})
	check(pages.statistics().active==0 and replacement.visible and b.visible and not a.visible,"Edit exposes current owners immediately without reviving the old mesh")
	pages.step() # A snapshot is in flight when the same owner changes again.
	var latest:=owner(stage,Vector3i.ZERO,arrays(1.0));replacement.hide()
	pages.commit({Vector3i.ZERO:{"node":latest,"arrays":arrays(1.0)}})
	await settle(pages)
	check(pages.statistics().stale==1 and pages.statistics().active==1,"Late render result is rejected by revision and rebuilt")
	check(not latest.visible and not b.visible and not replacement.visible,"Replacement page has no duplicate old owner")
	latest.hide();pages.commit({Vector3i.ZERO:{}})
	check(b.visible and not latest.visible and pages.statistics().active==0,"Removal restores the remaining owner in the same commit")
	await settle(pages)
	check(pages.statistics().owners==1 and pages.statistics().active==0,"A single owner stays unbatched")
	pages.commit({Vector3i.ZERO:{"node":latest,"arrays":arrays(1.0)}});pages.step();pages.clear()
	await settle(pages)
	check(pages.statistics().retained_bytes==0 and pages.statistics().active==0 and latest.visible and b.visible,"Reload invalidates pending work and restores individual visibility")
	pages.commit({Vector3i.ZERO:{"node":latest,"arrays":arrays(1.0)},Vector3i(1,0,0):{"node":b,"arrays":second}})
	await settle(pages);pages.enabled=false
	check(pages.statistics().active==0 and pages.statistics().retained_bytes==0 and latest.visible and b.visible,"Disabling consolidation safely restores current individual owners")
	stage.free();await process_frame
	print("WATER_RENDER_PAGES failures=",failures);quit(failures)
