// SPDX-License-Identifier: 0BSD
#include "water_runtime.hpp"
#include "lake_volume.hpp"
#include "water_geometry.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <cmath>
#include <godot_cpp/classes/time.hpp>
using namespace godot;
namespace terraforest {
void NativeWaterRuntime::_bind_methods(){
 ClassDB::bind_method(D_METHOD("configure","origin","cells","spacing","level","seed","state"),&NativeWaterRuntime::configure);
 ClassDB::bind_method(D_METHOD("sample_terrain","core","budget","revision","epoch"),&NativeWaterRuntime::sample_terrain);
 ClassDB::bind_method(D_METHOD("get_network"),&NativeWaterRuntime::get_network);
 ClassDB::bind_method(D_METHOD("statistics"),&NativeWaterRuntime::statistics);
}
bool NativeWaterRuntime::configure(const Vector3 &o,const Vector3i &c,double spacing,double level,const Vector3 &s,const PackedByteArray &state){
 Ref<NativeLakeVolume> validation;validation.instantiate();
 if(status!=-1||!validation->configure(o,c,spacing,level,s)||spacing!=std::floor(spacing)||state.size()>65552)return false;
 origin=o;cells=c;scale=spacing;seed=s;ceiling=std::llround(level*1000);saved=state;
 first=Vector3i((o/(16.0*scale)).floor());last=Vector3i(((o+Vector3(c)*scale-Vector3(.001,.001,.001))/(16.0*scale)).floor());
 // Nothing above the authored maximum water surface needs sampling.
 last.y=std::min(last.y,int(std::floor(level/(16*scale))));
 const auto extent=last-first+Vector3i(1,1,1);if(extent.x<1||extent.y<1||extent.z<1||int64_t(extent.x)*extent.y*extent.z>64)return false;
 coordinate=first;registry.instantiate();registry->configure(1,scale);
 for(int64_t h=(first.y*16*scale-1)*1000;h<ceiling;h+=1000)anchors.insert(h);anchors.insert(ceiling);
 if(anchors.size()>256)return false;status=0;return true;
}
int64_t NativeWaterRuntime::sample_terrain(Object *core,int64_t budget,int64_t rev,int64_t ep){
 const auto start=Time::get_singleton()->get_ticks_usec();
 for(int i=0;i<64&&status==0;++i){step(core,2048,rev,ep);if(Time::get_singleton()->get_ticks_usec()-start>=2000)break;}return status;
}
int64_t NativeWaterRuntime::step(Object *core,int64_t budget,int64_t rev,int64_t ep){
 if(status!=0)return status;
 if(revision<0){revision=rev;epoch=ep;}if(revision!=rev||epoch!=ep){status=-4;return status;}
 budget=std::max(int64_t(1),std::min(int64_t(2048),budget));
 if(stage==0){field.instantiate();if(!field->begin_terrain(1,rev,ep,coordinate*16-Vector3i(1,1,1),Vector3i(18,18,18),scale,ceiling)){fail("Water sampling bounds unavailable");return status;}stage=1;}
 else if(stage==1){field->sample_terrain(core,budget);const int s=field->statistics()["status"];if(s<0){status=s;return status;}if(s==1){graph.instantiate();if(!graph->begin_field(field,Vector3i(1,1,1),Vector3i(16,16,16))){fail("Water topology rejected");return status;}stage=2;}}
 else if(stage==2){graph->advance(128);const int s=graph->statistics()["status"];if(s<0){fail("Water topology failed");return status;}if(s==1){
  Dictionary g=graph->graph();PackedInt32Array ids=g["ids"];
  if(ids.is_empty()){stage=5;return status;}
  basin.instantiate();if(!basin->begin(g)){fail("Water basin graph exceeds limits");return status;}stage=3;
 }}
 else if(stage==3){basin->advance(budget);const int s=basin->statistics()["status"];if(s<0){fail("Water basin compilation failed");return status;}if(s==1){
  // Keep raw geometry private until seed-component pruning. Unrelated exterior
  // air must neither consume registry portal capacity nor become lake water.
  graphs.push_back(graph);basins.push_back(basin);stage=5;
 }}
 else if(stage==5){field.unref();graph.unref();basin.unref();
  if(++coordinate.x>last.x){coordinate.x=first.x;if(++coordinate.z>last.z){coordinate.z=first.z;++coordinate.y;}}
  if(coordinate.y>last.y){stage=10;index=0;}else stage=0;
 }
 else if(stage==10){
  if(index==int(graphs.size())){
   parents.resize(leaf_offset);for(int i=0;i<leaf_offset;++i)parents[i]=i;
   for(int i=0;i<int(basins.size());++i){const PackedInt32Array merges=basins[i]->hierarchy()["merges"],floors=basins[i]->hierarchy()["leaf_floors_mm"];
    auto entry=[&](int n){return n<floors.size()?n:merges[(n-floors.size())*4+3];};
    for(int j=0;j<merges.size();j+=4)connect(boundaries[i].offset+entry(merges[j]),boundaries[i].offset+entry(merges[j+1]));
   }
   index=0;stage=11;return status;
  }
  const Dictionary g=graphs[index]->graph(),b=basins[index]->hierarchy();BoundaryPiece p;
  p.origin=g["grid_origin"];p.ids=g["ids"];p.ports=g["world_ports"];p.owners=b["owners"];p.offset=leaf_offset;
  const PackedInt32Array floors=b["leaf_floors_mm"];leaf_offset+=floors.size();if(leaf_offset>4096){fail("Water basin leaves exceed 4096");return status;}
  const Vector3i c=(p.origin+Vector3i(1,1,1))/16;boundary_index[{c.x,c.y,c.z}]=index;boundaries.push_back(p);++index;
 }
 else if(stage==11){
  if(index==int(boundaries.size())){
   const Vector3 grid=seed/double(scale);const Vector3i cell(grid.floor()),c((grid/16.0).floor());float weights[4];const int tet=lake_tetra(grid-Vector3(cell),weights);
   const auto it=boundary_index.find({c.x,c.y,c.z});if(it==boundary_index.end()){fail("Water seed has no storage region");return status;}
   const auto &q=boundaries[it->second];const Vector3i local=cell-q.origin;const int id=(local.x+18*(local.y+18*local.z))*6+tet;
   const int32_t *at=std::lower_bound(q.ids.ptr(),q.ids.ptr()+q.ids.size(),id);
   if(at==q.ids.ptr()+q.ids.size()||*at!=id){fail("Water seed is solid");return status;}
   seed_root=root(q.offset+q.owners[at-q.ids.ptr()]);
   for(int node:unresolved)if(root(node)==seed_root){fail("Seed basin opens beyond its sampled regions");return status;}
   stage=12;return status;
  }
  const auto &p=boundaries[index];
  auto owner=[](const BoundaryPiece &q,const int32_t *address){const Vector3i cell=Vector3i(address[0],address[1],address[2])-q.origin;
   if(cell.x<0||cell.y<0||cell.z<0||cell.x>=18||cell.y>=18||cell.z>=18)return -1;
   const int id=(cell.x+18*(cell.y+18*cell.z))*6+address[3];const int32_t *at=std::lower_bound(q.ids.ptr(),q.ids.ptr()+q.ids.size(),id);
   return at==q.ids.ptr()+q.ids.size()||*at!=id?-1:q.offset+q.owners[at-q.ids.ptr()];};
  for(int work=0;work<128&&boundary_cursor<p.ports.size();++work,boundary_cursor+=9){
   const int32_t *row=p.ports.ptr()+boundary_cursor;const std::array<int,3> key={int(std::floor(row[4]/16.0)),int(std::floor(row[5]/16.0)),int(std::floor(row[6]/16.0))};
   const auto it=boundary_index.find(key);const int a=owner(p,row);
   if(a<0){fail("Water boundary lacks owner");return status;}
   if(it==boundary_index.end()){unresolved.push_back(a);continue;}
   const int b=owner(boundaries[it->second],row+4);if(a<0||b<0){fail("Water boundary has no basin owner");return status;}
   connect(a,b);const auto pair=std::make_pair(std::min(a,b),std::max(a,b));auto found=openings.find(pair);
   if(found==openings.end())openings[pair]=row[8];else found->second=std::min(found->second,row[8]);
   if(openings.size()>98304){fail("Water boundary graph exceeds limits");return status;}
  }
  if(boundary_cursor==p.ports.size()){++index;boundary_cursor=0;}
 }
 else if(stage==12){
  // Parallel faces between the same owners have one effective first opening.
  // Higher redundant faces cannot change the connectivity/spill hierarchy.
  for(int work=0;work<128&&!openings.empty();++work){if(root(openings.begin()->first.first)==seed_root)anchors.insert(openings.begin()->second);openings.erase(openings.begin());}
  if(anchors.size()>256){fail("Effective water storage anchors exceed 256");return status;}
  if(openings.empty()){registry.instantiate();registry->configure(1,scale);index=0;filter_phase=0;filter_cursor=0;stage=14;}
 }
 else if(stage==14){
  if(index==int(graphs.size())){
   graphs.swap(kept_graphs);basins.swap(kept_basins);kept_graphs.clear();kept_basins.clear();boundaries.clear();boundary_index.clear();parents.clear();unresolved.clear();
   for(auto h:anchors)levels.append(h);index=0;stage=6;return status;
  }
  const auto &old=*graphs[index].ptr();const auto &p=boundaries[index];
  if(graph.is_null()){graph.instantiate();graph->field=old.field;graph->first=old.first;graph->extent=old.extent;graph->count=old.count;graph->cursor=old.cursor;}
  auto keep=[&](int id){const int32_t *at=std::lower_bound(p.ids.ptr(),p.ids.ptr()+p.ids.size(),id);return at!=p.ids.ptr()+p.ids.size()&&*at==id&&root(p.offset+p.owners[at-p.ids.ptr()])==seed_root;};
  for(int work=0;work<128;++work){
   if(filter_phase==0){
    if(filter_cursor==old.ids.size()){filter_phase=1;filter_cursor=0;continue;}
    if(root(p.offset+p.owners[filter_cursor])==seed_root){graph->ids.append(old.ids[filter_cursor]);graph->floors.append(old.floors[filter_cursor]);}++filter_cursor;
   }else if(filter_phase==1){
    if(filter_cursor==old.edges.size()){filter_phase=2;filter_cursor=0;continue;}
    if(keep(old.edges[filter_cursor])&&keep(old.edges[filter_cursor+1]))for(int k=0;k<3;++k)graph->edges.append(old.edges[filter_cursor+k]);filter_cursor+=3;
   }else{
    if(filter_cursor==old.world_ports.size()){
     graph->node_count=graph->ids.size();graph->edge_count=graph->edges.size()/3;graph->portals=graph->world_ports.size()/9;graph->status=1;filter_phase=filter_cursor=0;
     if(graph->ids.is_empty()){graph.unref();++index;return status;}
     basin.instantiate();if(!basin->begin(graph->graph())){fail("Filtered seed basin rejected");return status;}stage=15;return status;
    }
    const int32_t *row=old.world_ports.ptr()+filter_cursor;const Vector3i cell=Vector3i(row[0],row[1],row[2])-p.origin;const int id=(cell.x+18*(cell.y+18*cell.z))*6+row[3];
    if(keep(id))for(int k=0;k<9;++k)graph->world_ports.append(row[k]);filter_cursor+=9;
   }
  }
 }
 else if(stage==15){
  basin->advance(budget);const int state=basin->statistics()["status"];if(state<0){fail("Filtered basin hierarchy failed");return status;}
  if(state==1){const PackedInt32Array merges=basin->hierarchy()["merges"];for(int i=2;i<merges.size();i+=4)anchors.insert(merges[i]);if(anchors.size()>256){fail("Effective water anchors exceed 256");return status;}
   const Vector3i c=(boundaries[index].origin+Vector3i(1,1,1))/16;const Dictionary ticket=registry->reserve_region(c,rev,ep,0);
   if(!bool(ticket.get("ok",false))||!registry->begin_publish(graph,ticket["generation"])){fail("Filtered basin publication failed");return status;}stage=16;
  }
 }
 else if(stage==16){registry->advance(budget);if(!bool(registry->statistics()["busy"])){kept_graphs.push_back(graph);kept_basins.push_back(basin);graph.unref();basin.unref();++index;stage=14;}}
 else if(stage==6){if(index==int(graphs.size())){if(profiles.is_empty()){fail("No enclosed water basin");return status;}network.instantiate();if(!network->begin(registry,profiles)){fail("Basin is open or exceeds network limits");return status;}stage=8;}
  else {profile.instantiate();if(!profile->begin_region(graphs[index],basins[index],levels)){fail("Water profile rejected");return status;}stage=7;}}
 else if(stage==7){profile->advance(budget);const int s=profile->statistics()["status"];if(s<0){fail("Water profile failed");return status;}if(s==1){profiles.append(profile);profile.unref();++index;stage=6;}}
 else if(stage==8){network->advance(budget);const int s=network->statistics()["status"];if(s<0){error=network->statistics()["error"];status=-2;return status;}if(s==1){
  if(!saved.is_empty()){if(!network->restore_state(saved)){fail("Saved water geometry does not match terrain; quantities retained");return status;}status=1;}
  else if(!network->fill_to_level(seed,ceiling)){fail("Water seed is solid or outside basin");return status;}else stage=9;
 }}
 else if(stage==9){const Dictionary result=network->advance_settling(budget);if(!bool(result["busy"])){if(int64_t(result["pending_ml"])!=0)fail("Initial water exceeds capacity");else status=1;}}
 return status;
}
Dictionary NativeWaterRuntime::statistics() const{Dictionary d;d["status"]=status;d["stage"]=stage;d["regions"]=int64_t(graphs.size());d["error"]=error;return d;}
}
