// SPDX-License-Identifier: 0BSD
#include "selection.hpp"
#include <godot_cpp/classes/multi_mesh.hpp>
#include <godot_cpp/classes/multi_mesh_instance3d.hpp>
#include <godot_cpp/classes/time.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/vector4.hpp>
#include <algorithm>
#include <cmath>
using namespace godot;
namespace terraforest {
static bool has_tier(const Dictionary &row,int kind){
 return kind<3?(kind==int64_t(row["lod"])||kind==int64_t(row["next"])):
 (kind==int64_t(row["shadow"])||kind==int64_t(row["shadow_next"]));
}
static Vector4 packet(const Dictionary &row,int kind,double duration){
 const int from=int64_t(row[kind<3?"lod":"shadow"]),dest=int64_t(row[kind<3?"next":"shadow_next"]);
 if(dest>=(kind<3?0:-1)){
  double t=std::fmod(double(row[kind<3?"time":"shadow_time"]),4096.0);if(t<0)t+=4096.0;
  return Vector4(double(row["seed"]),t,kind==from?-1:1,duration);
 }
 return Vector4(double(row["seed"]),0,0,duration);
}
void NativeVegetationSelection::flush(Object *f){
 if(!f)return;
 const uint64_t started=Time::get_singleton()->get_ticks_usec();
 Dictionary roots=f->get("roots"),cells=f->get("cells"),dirty=f->get("dirty"),dirty_rows=f->get("dirty_rows"),rebuild=f->get("rebuild_cells"),stats=f->get("stats");
 const bool profiling=f->get("profiling_enabled");const double duration=f->get("transition_seconds");
 const char *count_keys[]={"source","middle","far","shadow_source","shadow_proxy"};
 int64_t api_us=0;
 auto put=[&](Dictionary cell,int kind,int slot,int64_t id,Vector4 data,bool transform_changed){
  const uint64_t begin=profiling?Time::get_singleton()->get_ticks_usec():0;
  Array nodes=cell["nodes"];auto *node=Object::cast_to<MultiMeshInstance3D>(nodes[kind]);
  Ref<MultiMesh> mesh=node->get_multimesh();
  if(transform_changed){Dictionary row=roots[id];mesh->set_instance_transform(slot,row["local_t"]);
   stats["row_writes"]=int64_t(stats["row_writes"])+1;stats["uploaded_bytes"]=int64_t(stats["uploaded_bytes"])+48;}
  mesh->set_instance_custom_data(slot,Color(data.x,data.y,data.z,data.w));
  stats["custom_writes"]=int64_t(stats["custom_writes"])+1;stats["uploaded_bytes"]=int64_t(stats["uploaded_bytes"])+16;
  Array all_packets=cell["packets"];Dictionary packets=all_packets[kind];packets[id]=data;
  if(profiling)api_us+=Time::get_singleton()->get_ticks_usec()-begin;
 };
 Array keys=dirty.keys();
 for(int i=0;i<keys.size();++i){
  const Variant key=keys[i];if(!cells.has(key))continue;
  Dictionary cell=cells[key];Array rows=f->call("_members",cell),nodes=cell["nodes"];
  if(rows.is_empty()){
   for(int kind=0;kind<5;++kind){auto *node=Object::cast_to<MultiMeshInstance3D>(nodes[kind]);if(!node)continue;
    Ref<MultiMesh> mesh=node->get_multimesh();stats[count_keys[kind]]=int64_t(stats[count_keys[kind]])-std::max(mesh->get_visible_instance_count(),0);
    stats["instance_cache_live_payload_bytes"]=int64_t(stats.get("instance_cache_live_payload_bytes",0))-int64_t(mesh->get_instance_count())*64;node->queue_free();}
   cells.erase(key);continue;
  }
  if(rebuild.has(key)){f->call("_rebuild",cell,rows);continue;}
  Dictionary changes=dirty_rows.get(key,Dictionary());Array ids=changes.keys();
  Array all_slots=cell["slots"],all_members=cell["slot_ids"],all_packets=cell["packets"],uploads=cell["tier_uploads"];
  for(int kind=0;kind<5;++kind){
   if(!(int64_t(dirty[key])&(1<<kind)))continue;
   Dictionary slots=all_slots[kind],packets=all_packets[kind];Array members=all_members[kind];
   const int64_t old_size=members.size();bool touched=false;
   // Remove before adding: each tier retains its fixed root-count capacity.
   for(int j=0;j<ids.size();++j){const int64_t id=ids[j];
    if(!(int64_t(changes[id])&(1<<kind))||!slots.has(id))continue;
    if(roots.has(id)&&has_tier(roots[id],kind))continue;
    const int index=int64_t(slots[id]);const int64_t last_id=members[members.size()-1];
    if(index!=members.size()-1){members[index]=last_id;slots[last_id]=index;put(cell,kind,index,last_id,packets[last_id],true);}
    members.pop_back();slots.erase(id);packets.erase(id);touched=true;
   }
   for(int j=0;j<ids.size();++j){const int64_t id=ids[j];
    if(!(int64_t(changes[id])&(1<<kind))||!roots.has(id))continue;
    Dictionary row=roots[id];if(!has_tier(row,kind))continue;
    const Vector4 data=packet(row,kind,duration);
    if(slots.has(id)){if(Vector4(packets[id])!=data){put(cell,kind,int64_t(slots[id]),id,data,false);touched=true;}}
    else{
     if(nodes[kind].get_type()==Variant::NIL)f->call("_batch",cell,kind,rows.size(),cell["bounds"]);
     const int index=members.size();members.append(id);slots[id]=index;put(cell,kind,index,id,data,true);touched=true;
    }
   }
   if(touched){auto *node=Object::cast_to<MultiMeshInstance3D>(nodes[kind]);if(node)node->get_multimesh()->set_visible_instance_count(members.size());
    stats[count_keys[kind]]=int64_t(stats[count_keys[kind]])+members.size()-old_size;uploads[kind]=int64_t(uploads[kind])+1;
    stats["uploads"]=int64_t(stats["uploads"])+1;stats["flushed_tiers"]=int64_t(stats["flushed_tiers"])+1;}
  }
 }
 dirty.clear();dirty_rows.clear();rebuild.clear();
 f->set("api_us_this_tick",int64_t(f->get("api_us_this_tick"))+api_us);
 stats["flush_us"]=int64_t(Time::get_singleton()->get_ticks_usec()-started);
}
}
