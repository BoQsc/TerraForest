// SPDX-License-Identifier: 0BSD
#include "selection.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/classes/time.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/transform3d.hpp>
#include <godot_cpp/variant/vector2i.hpp>
#include <cmath>
#include <algorithm>
using namespace godot;
namespace terraforest {
void NativeVegetationSelection::_bind_methods(){
 ClassDB::bind_method(D_METHOD("flush","renderer"),&NativeVegetationSelection::flush);
 ClassDB::bind_method(D_METHOD("select","renderer","eye","projection","time","instant"),&NativeVegetationSelection::select);
 ClassDB::bind_method(D_METHOD("clear"),&NativeVegetationSelection::clear);
 ClassDB::bind_method(D_METHOD("erase","id"),&NativeVegetationSelection::erase);
 ClassDB::bind_method(D_METHOD("queue_stats"),&NativeVegetationSelection::queue_stats);
}
void NativeVegetationSelection::clear(){events={};live.clear();travel=0;}
void NativeVegetationSelection::erase(int64_t id){live.erase(id);}
void NativeVegetationSelection::schedule(int64_t id,double slack){Event e{travel+std::max(0.0,slack-0.02),id,++serial};live[id]=e;events.push(e);}
Dictionary NativeVegetationSelection::queue_stats()const{Dictionary d;d["records"]=int64_t(events.size());d["live"]=int64_t(live.size());return d;}
static int desired(double px,int current,bool reference){
 if(reference)return current==0?(px>=75?0:1):(px>95?0:1);
 if(current==0)return px>=180?0:(px<70?2:1);
 if(current==1)return px>220?0:(px<70?2:1);
 return px>220?0:(px>90?1:2);
}
static int mask(int a,int b){return (a>=0?1<<a:0)|(b>=0?1<<b:0);}
void NativeVegetationSelection::select(Object *f,Vector3 eye,double projection,double time,bool instant){
 if(!f||!eye.is_finite()||!std::isfinite(projection)||projection<=0||!std::isfinite(time))return;
 const uint64_t started=Time::get_singleton()->get_ticks_usec();
 Dictionary roots=f->get("roots"),cells=f->get("cells"),moving=f->get("moving"),dirty=f->get("dirty"),dirty_rows=f->get("dirty_rows"),invalid=f->get("_invalid_decisions"),audit_pending=f->get("_audit_pending"),stats=f->get("stats"),previous=f->get("previous_neighborhood");
 const bool reference=f->get("reference"),audit=f->get("audit_enabled");
 const double reach_base=f->get("shadow_reach"),scale_max=f->get("max_scale"),guard=f->get("membership_guard_m");
 const Vector3 last_eye=f->get("last_eye");
 const bool reset=bool(f->get("changed"))||instant||projection!=double(f->get("last_projection"));
 if(reset){clear();invalid.clear();}else travel+=last_eye.distance_to(eye);
 const double height=18.4712715;
 const double radius=std::max(reach_base+30.0,height*scale_max*projection/70.0)+guard+6.0;
 // Match the script's single-precision Vector3 arithmetic before binning.
 const Vector3 low=eye-Vector3(radius,0,radius),high=eye+Vector3(radius,0,radius);
 const Vector2i lo(std::floor(low.x/128.0),std::floor(low.z/128.0)),hi(std::floor(high.x/128.0),std::floor(high.z/128.0));
 Dictionary current,due;
 for(int z=lo.y;z<=hi.y;++z)for(int x=lo.x;x<=hi.x;++x){Vector2i k(x,z);if(cells.has(k))current[k]=true;}
 int64_t popped=0;
 while(!events.empty()&&events.top().distance<=travel){
  const Event e=events.top();events.pop();++popped;
  auto it=live.find(e.id);if(it==live.end()||it->second.token!=e.token)continue;
  live.erase(it);
  if(roots.has(e.id)){Dictionary row=roots[e.id];if(current.has(row["key"]))due[e.id]=true;}
 }
 Array invalid_ids=invalid.keys();
 for(int i=0;i<invalid_ids.size();++i){Variant id=invalid_ids[i];if(roots.has(id)){Dictionary row=roots[id];if(current.has(row["key"]))due[id]=true;}}
 invalid.clear();Dictionary visit=current.duplicate();Array old_keys=previous.keys();
 for(int i=0;i<old_keys.size();++i)visit[old_keys[i]]=true;
 int64_t reused=0;Array keys=visit.keys();
 for(int i=0;i<keys.size();++i){Variant k=keys[i];if(!cells.has(k))continue;
  if(reset||current.has(k)!=previous.has(k)){
   Array rows=f->call("_members",cells[k]);for(int j=0;j<rows.size();++j){Dictionary row=rows[j];due[row["id"]]=true;}
  }else ++reused;
 }
 auto mark=[&](Dictionary row,int bits){
  Variant id=row["id"],key=row["key"];
  invalid[id]=true;if(audit)audit_pending[id]=true;
  if(cells.has(key)){Dictionary cell=cells[key];cell["certificate_valid"]=false;}
  dirty[key]=int64_t(dirty.get(key,0))|bits;
  if(!dirty_rows.has(key))dirty_rows[key]=Dictionary();
  Dictionary changes=dirty_rows[key];changes[id]=int64_t(changes.get(id,0))|bits;
 };
 Array ids=due.keys();
 for(int i=0;i<ids.size();++i){
  const int64_t id=ids[i];Dictionary row=roots[id];
  const bool nearby=current.has(row["key"]);
  const double scale=row["scale"],dist=eye.distance_to(Vector3(row["center"])),root_dist=eye.distance_to(Transform3D(row["t"]).origin),size_factor=height*scale*projection;
  int lod=int64_t(row["lod"]),next=int64_t(row["next"]),shadow=int64_t(row["shadow"]),shadow_next=int64_t(row["shadow_next"]);
  if(next==-1){
   int want=desired(size_factor/std::max(dist,0.1),lod,reference);if(!nearby)want=reference?1:2;
   if(want!=lod){mark(row,mask(lod,want));if(instant){row["lod"]=want;lod=want;}else{row["next"]=want;next=want;row["time"]=time;moving[id]=true;}}
  }
  const double reach=reach_base+20.0*scale,band=reference?58.0:32.0,threshold=shadow==3?band+3:band-3;
  int want=dist<reach?4:-1;if(root_dist<threshold)want=3;
  if(shadow_next==-2&&want!=shadow){mark(row,mask(shadow,want));if(instant){row["shadow"]=want;shadow=want;}else{row["shadow_next"]=want;shadow_next=want;row["shadow_time"]=time;moving[id]=true;}}
  invalid.erase(id);
  if(!nearby){erase(id);continue;}
  double slack=0;
  if(next==-1&&shadow_next==-2){
   if(reference)slack=std::abs(dist-size_factor/(lod==0?75.0:95.0));
   else if(lod==0)slack=std::abs(dist-size_factor/180.0);
   else if(lod==1)slack=std::min(std::abs(dist-size_factor/220.0),std::abs(dist-size_factor/70.0));
   else slack=std::abs(dist-size_factor/90.0);
   slack=std::min(slack,std::abs(dist-reach));slack=std::min(slack,std::abs(root_dist-(shadow==3?band+3:band-3)));
  }
  schedule(id,slack);
 }
 if(events.size()>4*live.size()+1024){events={};for(const auto &entry:live)events.push(entry.second);}
 stats["selection_checked"]=int64_t(stats["selection_checked"])+due.size();
 stats["selection_skipped_cells"]=int64_t(stats["selection_skipped_cells"])+reused;
 stats["event_pops"]=int64_t(stats.get("event_pops",0))+popped;
 stats["event_queue_records"]=int64_t(events.size());stats["live_certificates"]=int64_t(live.size());
 stats["selection_jobs"]=int64_t(stats["selection_jobs"])+1;stats["tested_rows"]=due.size();
 stats["selection_us"]=int64_t(Time::get_singleton()->get_ticks_usec()-started);
 f->set("previous_neighborhood",current);f->set("last_eye",eye);f->set("last_projection",projection);f->set("changed",false);f->set("membership_changed",false);
}
}
