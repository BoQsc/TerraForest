// SPDX-License-Identifier: 0BSD
#include "fleet.hpp"
#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_int64_array.hpp>
#include <algorithm>
#include <cmath>
#include <vector>
using namespace godot;
namespace terraforest {
void NativeVehicleFleet::_bind_methods(){
    ADD_SIGNAL(MethodInfo("obstacles_changed",PropertyInfo(Variant::AABB,"bounds")));
    ADD_SIGNAL(MethodInfo("presentation_changed",PropertyInfo(Variant::INT,"identity")));
    ADD_SIGNAL(MethodInfo("presentation_reset"));
    ClassDB::bind_method(D_METHOD("spawn","pose"),&NativeVehicleFleet::spawn);
    ClassDB::bind_method(D_METHOD("spawn_module","pose","kind","state"),&NativeVehicleFleet::spawn_module,DEFVAL(PackedByteArray()));
    ClassDB::bind_method(D_METHOD("set_module_state","identity","state"),&NativeVehicleFleet::set_module_state);
    ClassDB::bind_method(D_METHOD("read_records","after","limit"),&NativeVehicleFleet::read_records);
    ClassDB::bind_method(D_METHOD("first_of_kind","kind"),&NativeVehicleFleet::first_of_kind);
    ClassDB::bind_method(D_METHOD("remove","identity"),&NativeVehicleFleet::remove);
    ClassDB::bind_method(D_METHOD("set_pose","identity","pose"),&NativeVehicleFleet::set_pose);
    ClassDB::bind_method(D_METHOD("get_record","identity"),&NativeVehicleFleet::get_record);
    ClassDB::bind_method(D_METHOD("query_near","center","radius","limit","budget"),&NativeVehicleFleet::query_near);
    ClassDB::bind_method(D_METHOD("query_near_kind","center","radius","limit","budget","kind"),&NativeVehicleFleet::query_near_kind);
    ClassDB::bind_method(D_METHOD("statistics"),&NativeVehicleFleet::statistics);
    ClassDB::bind_method(D_METHOD("capture_storage_snapshot"),&NativeVehicleFleet::capture_storage_snapshot);
    ClassDB::bind_method(D_METHOD("validate_snapshot","data"),&NativeVehicleFleet::validate_snapshot);
    ClassDB::bind_method(D_METHOD("restore_storage_snapshot","data"),&NativeVehicleFleet::restore_storage_snapshot);
}
int NativeVehicleFleet::cell(const Vector3 &p){return int(p.x/32)|(int(p.y/32)<<8)|(int(p.z/32)<<16);}
static AABB obstacle_bounds(const Transform3D &pose){return AABB(pose.origin-Vector3(5,5,5),Vector3(10,10,10));}
void NativeVehicleFleet::remove_cell(int64_t id,const Vector3 &p){auto it=cells_.find(cell(p));if(it==cells_.end())return;it->second.erase(id);if(it->second.empty())cells_.erase(it);}
int64_t NativeVehicleFleet::spawn(const Transform3D &pose){
    return spawn_module(pose,NativeVehicleStorage::default_kind(),PackedByteArray());
}
int64_t NativeVehicleFleet::spawn_module(const Transform3D &pose,const String &kind,const PackedByteArray &state){
    if(!NativeVehicleStorage::valid_kind(kind)||state.size()>4096||records_.size()>=65536||next_==INT64_MAX||!NativeVehicleStorage::valid_pose(pose)||state_bytes_+state.size()+(records_.size()+1)*96>32*1024*1024)return 0;
    const int64_t identity=next_++;records_.emplace(identity,pose);cells_[cell(pose.origin)].insert(identity);kinds_[kind].insert(identity);
    if(kind!=NativeVehicleStorage::default_kind()||!state.is_empty())modules_[identity]={kind,state};
    state_bytes_+=state.size();++revision_;emit_signal("obstacles_changed",obstacle_bounds(pose));emit_signal("presentation_changed",identity);return identity;
}
bool NativeVehicleFleet::set_module_state(int64_t identity,const PackedByteArray &state){
    if(!records_.count(identity)||state.size()>4096)return false;
    auto found=modules_.find(identity);int64_t previous=found==modules_.end()?0:found->second.second.size();
    if((found==modules_.end()&&state.is_empty())||(found!=modules_.end()&&found->second.second==state))return true;
    if(state_bytes_-previous+state.size()+records_.size()*96>32*1024*1024)return false;
    state_bytes_+=state.size()-previous;
    if(found==modules_.end()){if(!state.is_empty())modules_[identity]={NativeVehicleStorage::default_kind(),state};}
    else found->second.second=state;
    ++revision_;return true;
}
Dictionary NativeVehicleFleet::read_records(int64_t after,int limit) const {
    Dictionary result;result["ok"]=false;if(after<0||limit<1||limit>512)return result;
    Array rows;auto iterator=records_.upper_bound(after);int64_t cursor=after;
    for(;iterator!=records_.end()&&rows.size()<limit;++iterator){cursor=iterator->first;rows.push_back(get_record(cursor));}
    result["ok"]=true;result["records"]=rows;result["cursor"]=cursor;result["complete"]=iterator==records_.end();result["revision"]=int64_t(revision_);return result;
}
int64_t NativeVehicleFleet::first_of_kind(const String &kind) const {auto found=kinds_.find(kind);return found==kinds_.end()||found->second.empty()?0:*found->second.begin();}
bool NativeVehicleFleet::remove(int64_t id){auto it=records_.find(id);if(it==records_.end())return false;const AABB bounds=obstacle_bounds(it->second);remove_cell(id,it->second.origin);records_.erase(it);auto module=modules_.find(id);String kind=module==modules_.end()?NativeVehicleStorage::default_kind():module->second.first;kinds_[kind].erase(id);if(kinds_[kind].empty())kinds_.erase(kind);if(module!=modules_.end()){state_bytes_-=module->second.second.size();modules_.erase(module);}++revision_;emit_signal("obstacles_changed",bounds);emit_signal("presentation_changed",id);return true;}
bool NativeVehicleFleet::set_pose(int64_t id,const Transform3D &pose){
    auto it=records_.find(id);if(it==records_.end())return false;
    if(!NativeVehicleStorage::valid_pose(pose))return false;
    if(it->second==pose)return true;
    const AABB bounds=obstacle_bounds(it->second).merge(obstacle_bounds(pose));
    if(cell(it->second.origin)!=cell(pose.origin)){remove_cell(id,it->second.origin);cells_[cell(pose.origin)].insert(id);}
    it->second=pose;++revision_;emit_signal("obstacles_changed",bounds);emit_signal("presentation_changed",id);return true;
}
Dictionary NativeVehicleFleet::get_record(int64_t id) const {Dictionary out;auto it=records_.find(id);out["present"]=it!=records_.end();if(it!=records_.end()){out["identity"]=id;out["pose"]=it->second;auto module=modules_.find(id);out["kind"]=module==modules_.end()?NativeVehicleStorage::default_kind():module->second.first;out["state"]=module==modules_.end()?PackedByteArray():module->second.second;}return out;}
Dictionary NativeVehicleFleet::statistics() const {Dictionary out;out["records"]=int64_t(records_.size());out["cells"]=int64_t(cells_.size());out["next_identity"]=next_;out["revision"]=int64_t(revision_);return out;}
Dictionary NativeVehicleFleet::query_near(const Vector3 &center,double radius,int limit,int budget) const {
    return query_near_kind(center,radius,limit,budget,String());
}
Dictionary NativeVehicleFleet::query_near_kind(const Vector3 &center,double radius,int limit,int budget,const String &kind) const {
    Dictionary out;PackedInt64Array ids;out["ok"]=false;out["complete"]=false;out["ids"]=ids;out["visited"]=0;
    if(!center.is_finite()||!std::isfinite(radius)||radius<0||radius>128||limit<1||limit>256||budget<1||budget>65536)return out;
    out["ok"]=true;
    // Clamp before integer conversion even for finite, extremely distant input.
    Vector3 lo=center-Vector3(radius,radius,radius),hi=center+Vector3(radius,radius,radius);
    if(hi.x<2||lo.x>1998||hi.y<0||lo.y>600||hi.z<2||lo.z>1998){out["complete"]=true;return out;}
    int x0=int(std::max(0.0,double(lo.x))/32),x1=int(std::min(1998.0,double(hi.x))/32);
    int y0=int(std::max(0.0,double(lo.y))/32),y1=int(std::min(600.0,double(hi.y))/32);
    int z0=int(std::max(0.0,double(lo.z))/32),z1=int(std::min(1998.0,double(hi.z))/32);
    std::vector<std::pair<double,int64_t>> candidates;int visited=0;bool exhausted=false;
    for(int z=z0;z<=z1&&!exhausted;++z)for(int y=y0;y<=y1&&!exhausted;++y)for(int x=x0;x<=x1&&!exhausted;++x){
        auto it=cells_.find(x|(y<<8)|(z<<16));if(it==cells_.end())continue;
        for(auto id:it->second){if(visited==budget){exhausted=true;break;}++visited;auto module=modules_.find(id);if(!kind.is_empty()&&kind!=(module==modules_.end()?NativeVehicleStorage::default_kind():module->second.first))continue;double distance=records_.at(id).origin.distance_squared_to(center);if(distance<=radius*radius)candidates.emplace_back(distance,id);}
    }
    out["visited"]=visited;out["complete"]=!exhausted;
    if(exhausted){out["reason"]="candidate_budget";return out;}
    std::sort(candidates.begin(),candidates.end());out["truncated"]=candidates.size()>size_t(limit);
    for(size_t i=0;i<candidates.size()&&i<size_t(limit);++i)ids.push_back(candidates[i].second);
    out["ids"]=ids;return out;
}
PackedByteArray NativeVehicleFleet::capture_storage_snapshot() const {
    Array rows;for(const auto &entry:records_)rows.push_back(get_record(entry.first));
    Ref<NativeVehicleStorage> codec;codec.instantiate();return codec->encode_fleet(rows,next_);
}
bool NativeVehicleFleet::validate_snapshot(const PackedByteArray &data) const {Ref<NativeVehicleStorage> codec;codec.instantiate();return codec->validate_fleet_snapshot(data);}
bool NativeVehicleFleet::restore_storage_snapshot(const PackedByteArray &data){
    Ref<NativeVehicleStorage> codec;codec.instantiate();Dictionary decoded=codec->decode_fleet(data);if(!bool(decoded["ok"]))return false;
    std::map<int64_t,Transform3D> records;std::unordered_map<int,std::set<int64_t>> cells;
    std::map<int64_t,std::pair<String,PackedByteArray>> modules;
    Array rows=decoded["records"];for(int i=0;i<rows.size();++i){Dictionary row=rows[i];int64_t id=row["identity"];Transform3D pose=row["pose"];records.emplace(id,pose);cells[cell(pose.origin)].insert(id);String kind=row.get("kind",NativeVehicleStorage::default_kind());PackedByteArray state=row.get("state",PackedByteArray());if(kind!=NativeVehicleStorage::default_kind()||!state.is_empty())modules[id]={kind,state};}
    int64_t state_bytes=0;for(const auto &module:modules)state_bytes+=module.second.second.size();
    if(state_bytes+records.size()*96>32*1024*1024)return false;
    std::map<String,std::set<int64_t>> kinds;for(const auto &entry:records){auto module=modules.find(entry.first);kinds[module==modules.end()?NativeVehicleStorage::default_kind():module->second.first].insert(entry.first);}
    records_.swap(records);cells_.swap(cells);modules_.swap(modules);kinds_.swap(kinds);state_bytes_=state_bytes;next_=decoded["next_identity"];++revision_;emit_signal("obstacles_changed",AABB());emit_signal("presentation_reset");return true;
}
}
