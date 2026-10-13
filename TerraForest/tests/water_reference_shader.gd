# SPDX-License-Identifier: 0BSD
extends SceneTree
# Read-only execution of the user's earlier project's real compute shaders.
# This is a reference behavior check, not a replacement water runtime.
var rd:RenderingDevice
var resources:Array[RID]=[]
var failures:=0
var results:Dictionary={}
var source_root:=""
func _initialize():call_deferred("run")
func check(ok:bool,label:String):
 print("PASS " if ok else "FAIL ",label)
 if not ok:failures+=1
func keep(rid:RID)->RID:
 resources.append(rid);return rid
func compile_shader(name:String)->RID:
 var text:=FileAccess.get_file_as_string(source_root+name).replace("#[compute]","")
 if name=="marching_cubes.glsl":text=text.replace('#include "res://world_marching_cubes/marching_cubes_lookup_table.glslinc"',FileAccess.get_file_as_string(source_root+"marching_cubes_lookup_table.glslinc"))
 var source:=RDShaderSource.new();source.source_compute=text
 var spirv:=rd.shader_compile_spirv_from_source(source)
 var error:=spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
 if not error.is_empty():push_error(error);failures+=1;return RID()
 return keep(rd.shader_create_from_spirv(spirv))
func buffer(data:PackedByteArray)->RID:return keep(rd.storage_buffer_create(data.size(),data))
func zeros(size:int)->PackedByteArray:
 var data:=PackedByteArray();data.resize(size);data.fill(0);return data
func dispatch(shader:RID,buffers:Array[RID],push:PackedByteArray,groups:int):
 var uniforms:Array[RDUniform]=[]
 for i in buffers.size():
  var uniform:=RDUniform.new();uniform.uniform_type=RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER;uniform.binding=i;uniform.add_id(buffers[i]);uniforms.append(uniform)
 var set_id:=rd.uniform_set_create(uniforms,shader,0)
 var pipeline:=rd.compute_pipeline_create(shader)
 var list:=rd.compute_list_begin();rd.compute_list_bind_compute_pipeline(list,pipeline);rd.compute_list_bind_uniform_set(list,set_id,0)
 rd.compute_list_set_push_constant(list,push,push.size());rd.compute_list_dispatch(list,groups,groups,groups);rd.compute_list_end();rd.submit();rd.sync()
 rd.free_rid(set_id);rd.free_rid(pipeline)
func edit(shader:RID,density:RID,materials:RID,value:float):
 var push:=zeros(48)
 push.encode_float(16,16.5);push.encode_float(20,8.5);push.encode_float(24,16.5);push.encode_float(28,0.6)
 push.encode_float(32,value);push.encode_s32(36,1);push.encode_s32(40,-1)
 dispatch(shader,[density,materials],push,9)
func mesh(shader:RID,density:RID,materials:RID)->Dictionary:
 var output:=rd.storage_buffer_create(32*32*32*12*24)
 var counter:=rd.storage_buffer_create(12,zeros(12))
 var indices:=rd.storage_buffer_create(32*32*32*15*4)
 var push:=zeros(32);push.encode_float(28,32)
 dispatch(shader,[output,counter,density,materials,indices],push,4)
 var counts:=rd.buffer_get_data(counter);var triangles:=counts.decode_u32(0);var vertex_count:=counts.decode_u32(8)
 var vertices:=rd.buffer_get_data(output,0,maxi(24,vertex_count*24));var topology:=rd.buffer_get_data(indices,0,maxi(12,triangles*12))
 var volume:=0.0;var depth_volume:=0.0;var low:=Vector3.INF;var high:=-Vector3.INF;var edges:Dictionary={}
 for i in triangles:
  var points:Array[Vector3]=[]
  for j in 3:
   var offset:=topology.decode_u32((i*3+j)*4)*24
   var point:=Vector3(vertices.decode_float(offset),vertices.decode_float(offset+4),vertices.decode_float(offset+8))
   points.append(point);low=low.min(point);high=high.max(point)
  volume+=points[0].dot(points[1].cross(points[2]))/6.0
  depth_volume+=absf((points[1]-points[0]).cross(points[2]-points[0]).y)*0.5*(8.5-(points[0].y+points[1].y+points[2].y)/3.0)
  for j in 3:
   var a:=str(Vector3i((points[j]*100000).round()));var b:=str(Vector3i((points[(j+1)%3]*100000).round()))
   var key:=a+"/"+b if a<b else b+"/"+a;edges[key]=int(edges.get(key,0))+1
 var boundary:=0
 for count:int in edges.values():
  if count!=2:boundary+=1
 rd.free_rid(indices);rd.free_rid(counter);rd.free_rid(output)
 return {"triangles":triangles,"vertices":vertex_count,"closed_mesh_volume_m3":absf(volume) if boundary==0 else null,"depth_integral_below_y_8_5":depth_volume,"low":low,"high":high,"unpaired_edges":boundary}
func run():
 for argument:String in OS.get_cmdline_user_args():
  if argument.begins_with("--reference-project="):source_root=argument.trim_prefix("--reference-project=").path_join("world_marching_cubes/")
 if source_root.is_empty():push_error("Pass --reference-project=<path to the earlier project>");quit(1);return
 for name:String in ["modify_density.glsl","marching_cubes.glsl","marching_cubes_lookup_table.glslinc"]:
  if not FileAccess.file_exists(source_root+name):push_error("Missing reference source: "+name);quit(1);return
 rd=RenderingServer.create_local_rendering_device()
 if rd==null:push_error("A Vulkan rendering device is required");quit(1);return
 var modifier:=compile_shader("modify_density.glsl");var mesher:=compile_shader("marching_cubes.glsl")
 if failures:finish();return
 var lake:=PackedFloat32Array();lake.resize(33*33*33)
 for z in 33:
  for y in 33:
   for x in 33:lake[x+33*y+1089*z]=y-8.5
 var density:=buffer(lake.to_byte_array());var materials:=buffer(zeros(lake.size()*4))
 results.lake_before=mesh(mesher,density,materials)
 edit(modifier,density,materials,0.5)
 var scooped:=rd.buffer_get_data(density).to_float32_array();var changed:=0;var removed_samples:=0
 for i in lake.size():
  if lake[i]!=scooped[i]:changed+=1
  if lake[i]<0 and scooped[i]>=0:removed_samples+=1
 check(changed==4 and removed_samples==4,"Actual reference box shader removes four submerged corner samples at the lake surface")
 results.lake_scooped=mesh(mesher,density,materials)
 results.lake_surface_removed_m3=results.lake_scooped.depth_integral_below_y_8_5-results.lake_before.depth_integral_below_y_8_5
 check(results.lake_scooped.triangles!=results.lake_before.triangles,"The shared marching-cubes shader rebuilds the sculpted water surface")
 # Generated dry areas use +100, not an assumed symmetric +/-0.5 field.
 var dry:=PackedFloat32Array();dry.resize(lake.size());dry.fill(100)
 rd.buffer_update(density,0,dry.size()*4,dry.to_byte_array());edit(modifier,density,materials,-0.5)
 var placed:=rd.buffer_get_data(density).to_float32_array();var added:=0
 for value:float in placed:
  if value<0:added+=1
 check(added==8,"Actual bucket placement creates eight negative density corners in dry space")
 results.placed=mesh(mesher,density,materials)
 check(results.placed.triangles>0 and results.placed.unpaired_edges==0,"The reference's placed water is a closed volumetric mesh")
 edit(modifier,density,materials,0.5)
 results.removed=mesh(mesher,density,materials)
 check(results.removed.triangles==0,"The same water-layer box removal removes the placed volume")
 results.scope="Unmodified reference GPU shaders, lake density matching its water-level generator, and dry density +100. No whole-world performance, flow, bucket conservation or gameplay acceptance claim."
 results.changed_lake_samples=changed;results.removed_negative_samples=removed_samples;results.placed_negative_samples=added
 finish()
func finish():
 for i in range(resources.size()-1,-1,-1):rd.free_rid(resources[i])
 rd.free();results.failures=failures
 DirAccess.make_dir_recursive_absolute("res://reports")
 var file:=FileAccess.open("res://reports/water_reference_shader.json",FileAccess.WRITE);file.store_string(JSON.stringify(results,"  "));file.close()
 print("WATER_REFERENCE_SHADER failures=",failures);quit(failures)
