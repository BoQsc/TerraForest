extends SceneTree
const Zombie=preload("res://addons/characters/runtime/zombie.gd")
var stage:Node3D
var checks:=0
var failures:=0
var timings:Array[Dictionary]=[]
func _initialize()->void:run.call_deferred()
func check(condition:bool,label:String)->void:
 checks+=1
 if not condition:failures+=1
 print("PASS " if condition else "FAIL ",label)
func fresh(template:RefCounted=null,position:Vector3=Vector3.ZERO)->Node3D:
 var zombie:=Zombie.new();zombie.geometry_template=template;zombie.position=position;zombie.process_mode=Node.PROCESS_MODE_DISABLED
 stage.add_child(zombie);timings.append(zombie.initialization_us.duplicate());return zombie
func compare_pose(zombie:Node3D,label:String)->void:
 var worst:=0.0;var matched:=true
 var local:=Transform3D(Basis(Vector3.UP,0.35),Vector3(2,0.6,-3))
 for part:String in Zombie.PARTS:
  var expected:=PackedVector3Array()
  var baked:ArrayMesh=zombie._bake_cpu(zombie.part_meshes[part],local)
  for surface in baked.get_surface_count():expected.append_array(baked.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX])
  var actual:PackedVector3Array=zombie.anatomy.sample_vertices(part,local)
  if actual.size()!=expected.size():matched=false;continue
  for vertex in actual.size():worst=maxf(worst,actual[vertex].distance_to(expected[vertex]))
 check(matched and worst<0.0005,"native points match independent skin/morph reference: "+label+" error="+str(worst))
func compare_contact(zombie:Node3D,part:String,shapes:Array,use_point:bool)->void:
 var target:=Vector3(0.25,1.5,0.8);var mouth:=AABB(Vector3(-0.027,1.597,0.098),Vector3(0.054,0.027,0.024))
 var source:MeshInstance3D=zombie.part_meshes[part];var baked:ArrayMesh=zombie._bake_cpu(source,Transform3D.IDENTITY)
 var distance:=INF;var expected:=Vector3.ZERO
 for surface in baked.get_surface_count():
  var vertices:PackedVector3Array=baked.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
  var binds:PackedVector3Array=source.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
  for vertex in vertices.size():
   if part=="head" and not (binds[vertex].x>=mouth.position.x and binds[vertex].y>=mouth.position.y and binds[vertex].z>=mouth.position.z and binds[vertex].x<=mouth.end.x and binds[vertex].y<=mouth.end.y and binds[vertex].z<=mouth.end.z):continue
   var point:=vertices[vertex]
   var targets:Array[Vector3]=[]
   if shapes.is_empty():targets.append(target if use_point else Vector3(target.x,clampf(point.y,target.y+0.20,target.y+1.65),target.z))
   for shape in shapes:
    if not shape is Dictionary:continue
    var closest:Dictionary=zombie._closest_target_surface(shape,point)
    if not closest.is_empty():targets.append(closest.point)
   for closest:Vector3 in targets:
    if point.distance_to(closest)<distance:distance=point.distance_to(closest);expected=point
 var actual:Dictionary=zombie.anatomy.closest_contact(part,target,use_point,shapes,mouth)
 check((actual.is_empty() and not is_finite(distance)) or (not actual.is_empty() and absf(actual.distance-distance)<0.0005 and actual.point.distance_to(expected)<0.0005),"native contact preserves nearest visible surface and mouth mask: "+part+" shapes="+str(shapes.size())+" point="+str(use_point))
func compare_hand(zombie:Node3D,part:String)->void:
 var source:MeshInstance3D=zombie.part_meshes[part];var baked:ArrayMesh=zombie._bake_cpu(source,Transform3D.IDENTITY)
 var groups:Dictionary={};var prefix:="LeftHand" if part=="hand_l" else "RightHand"
 for surface in baked.get_surface_count():
  var raw:Array=source.mesh.surface_get_arrays(surface);var points:PackedVector3Array=baked.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
  var bones:PackedInt32Array=raw[Mesh.ARRAY_BONES];var weights:PackedFloat32Array=raw[Mesh.ARRAY_WEIGHTS];var influences:int=bones.size()/points.size()
  for vertex in points.size():
   var group:="Palm";var maximum:=0.0
   for influence in influences:
    var slot:int=vertex*influences+influence
    if weights[slot]<=maximum:continue
    maximum=weights[slot];var bone_name:String=source.skin.get_bind_name(bones[slot])
    if bone_name.is_empty():bone_name=zombie.skeleton.get_bone_name(source.skin.get_bind_bone(bones[slot]))
    group=bone_name.trim_prefix(prefix) if bone_name.begins_with(prefix) and bone_name!=prefix else "Palm"
   if not groups.has(group):groups[group]=PackedVector3Array()
   groups[group].append(points[vertex])
 var palm:PackedVector3Array=groups.get("Palm",PackedVector3Array())
 for group:String in groups.keys():
  if group!="Palm" and groups[group].size()<4:palm.append_array(groups[group]);groups.erase(group)
 groups.Palm=palm
 var actual:Dictionary=zombie.anatomy.hand_groups(part,Transform3D.IDENTITY);var matched:bool=actual.keys()==groups.keys()
 for group:String in groups:
  if not actual.has(group) or actual[group].size()!=groups[group].size():matched=false;continue
  for vertex in groups[group].size():matched=matched and actual[group][vertex].distance_to(groups[group][vertex])<0.0005
 check(matched and actual.size()>3,"native compound preserves palm, finger groups and seam vertices: "+part)
func run()->void:
 stage=Node3D.new();root.add_child(stage)
 var first:=fresh()
 check(first.initialized and first._shape_cache.size()==15 and not first.anatomy.geometry_stats().mesh_reused,"cold initialization builds all fourteen limb proxies plus pelvis")
 var second:=fresh(first.anatomy,Vector3(120,4,-70))
 check(second.initialized and second.anatomy.geometry_stats().mesh_reused and second.anatomy.geometry_stats().shapes_reused,"translated resident reuses validated geometry and fitted collision")
 var same:=true
 for part:String in first._shape_cache:
  same=same and first._shape_cache[part].shape==second._shape_cache[part].shape and first._shape_cache[part].offset==second._shape_cache[part].offset
 check(same,"residents share identical immutable shape resources")
 first.anatomy.hit("forearm_l",30,false,"heavy");first.anatomy.detach("hand_l")
 check(second.anatomy.snapshot().health==180 and not second.anatomy.snapshot().missing.hand_l,"geometry reuse never copies wounds or missing limbs")
 var geometry:RefCounted=second.anatomy
 first.free();second.free()
 var third:=fresh(geometry)
 check(third.initialized and third.anatomy.geometry_stats().mesh_reused and third.anatomy.geometry_stats().shapes_reused,"cache survives retirement without retaining scene nodes")
 compare_pose(third,"idle")
 for clip:String in ["Zombie_Attack_Left","Zombie_Attack_Bite","Zombie_Crawl_Bite"]:
  var key:String=third._animation_key(clip)
  third.animation_player.play(key);third.animation_player.seek(0.65,true);third.skeleton.force_update_all_bone_transforms()
  compare_pose(third,clip)
 var shapes:Array=[{"type":"box","half_extents":Vector3(0.3,0.5,0.2),"transform":Transform3D(Basis(Vector3.UP,0.25),Vector3(0.2,1.4,0.8))},{"type":"sphere","radius":0.3,"transform":Transform3D(Basis.IDENTITY,Vector3(-0.4,1.6,0.6))}]
 for part:String in ["hand_l","hand_r","head"]:
  compare_contact(third,part,[],true);compare_contact(third,part,[],false);compare_contact(third,part,shapes,false);compare_contact(third,part,[{},"invalid"],false)
 compare_hand(third,"hand_l");compare_hand(third,"hand_r")
 var invalid:=Transform3D.IDENTITY;invalid.origin.x=NAN
 check(third.anatomy.sample_vertices("unknown",Transform3D.IDENTITY).is_empty() and third.anatomy.sample_vertices("head",invalid).is_empty(),"invalid sample requests fail without returning malformed geometry")
 var asset:Mesh=third.part_meshes.head.mesh
 asset.emit_changed()
 check(not geometry.geometry_stats().valid and not third.anatomy.geometry_stats().valid,"resource changes invalidate every cached geometry owner")
 var fourth:=fresh(geometry)
 check(fourth.initialized and not fourth.anatomy.geometry_stats().mesh_reused and not fourth.anatomy.geometry_stats().shapes_reused,"changed asset is revalidated and refitted instead of reusing stale geometry")
 var fifth:=fresh(fourth.anatomy)
 check(fifth.anatomy.geometry_stats().mesh_reused and fifth.anatomy.geometry_stats().shapes_reused,"subsequent admissions reuse the newly validated asset")
 var duplicate:Mesh=asset.duplicate()
 fifth.part_meshes.head.mesh=duplicate
 var different:RefCounted=ClassDB.instantiate("NativeZombieAnatomy");different.configure(Zombie.PARTS)
 check(different.set_hit_meshes(fifth.skeleton,fifth.part_meshes,fourth.anatomy) and not different.geometry_stats().mesh_reused,"a replacement mesh cannot borrow another asset's collision data")
 var altered:RefCounted=ClassDB.instantiate("NativeZombieAnatomy");altered.configure(Zombie.PARTS)
 var bone:int=fourth.skeleton.find_bone("Head");var rest:Transform3D=fourth.skeleton.get_bone_rest(bone)
 var changed:=rest;changed.origin.x+=0.01;fourth.skeleton.set_bone_rest(bone,changed)
 check(altered.set_hit_meshes(fourth.skeleton,fourth.part_meshes,fourth.anatomy) and not altered.geometry_stats().mesh_reused,"a changed skeleton rest cannot reuse another rig's bind mapping")
 fourth.skeleton.set_bone_rest(bone,rest)
 var retry:RefCounted=ClassDB.instantiate("NativeZombieAnatomy");retry.configure(Zombie.PARTS)
 var incomplete:Dictionary=fourth.part_meshes.duplicate();incomplete.hand_r=null
 check(not retry.set_hit_meshes(fourth.skeleton,incomplete,fourth.anatomy) and retry.set_hit_meshes(fourth.skeleton,fourth.part_meshes,fourth.anatomy) and retry.geometry_stats().mesh_reused,"a rejected partial mesh set can be retried without poisoning the cache signature")
 var folder:="res://reports/zombie_geometry_cache";DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
 FileAccess.open(folder.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures,"initialization_us":timings},"  "))
 geometry=null;different=null;altered=null;retry=null;stage.free();await process_frame;await process_frame
 print("ZOMBIE_GEOMETRY_CACHE checks=",checks," failures=",failures);quit(1 if failures else 0)
