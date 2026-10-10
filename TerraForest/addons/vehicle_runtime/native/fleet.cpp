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
    ClassDB::bind_method(D_METHOD("spawn","pose"),&NativeVehicleFleet::spawn);
    ClassDB::bind_method(D_METHOD("remove","identity"),&NativeVehicleFleet::remove);
    ClassDB::bind_method(D_METHOD("set_pose","identity","pose"),&NativeVehicleFleet::set_pose);
    ClassDB::bind_method(D_METHOD("get_record","identity"),&NativeVehicleFleet::get_record);
    ClassDB::bind_method(D_METHOD("query_near","center","radius","limit","budget"),&NativeVehicleFleet::query_near);
    ClassDB::bind_method(D_METHOD("statistics"),&NativeVehicleFleet::statistics);
    ClassDB::bind_method(D_METHOD("capture_storage_snapshot"),&NativeVehicleFleet::capture_storage_snapshot);
    ClassDB::bind_method(D_METHOD("validate_snapshot","data"),&NativeVehicleFleet::validate_snapshot);
    ClassDB::bind_method(D_METHOD("restore_storage_snapshot","data"),&NativeVehicleFleet::restore_storage_snapshot);
}
int NativeVehicleFleet::cell(const Vector3 &p){return int(p.x/32)|(int(p.y/32)<<8)|(int(p.z/32)<<16);}
void NativeVehicleFleet::remove_cell(int64_t id,const Vector3 &p){auto it=cells_.find(cell(p));if(it==cells_.end())return;it->second.erase(id);if(it->second.empty())cells_.erase(it);}
int64_t NativeVehicleFleet::spawn(const Transform3D &pose){
    if(records_.size()>=65536 || next_==INT64_MAX || !NativeVehicleStorage::valid_pose(pose))return 0;
    const int64_t id=next_++;records_.emplace(id,pose);cells_[cell(pose.origin)].insert(id);return id;
}
bool NativeVehicleFleet::remove(int64_t id){auto it=records_.find(id);if(it==records_.end())return false;remove_cell(id,it->second.origin);records_.erase(it);return true;}
bool NativeVehicleFleet::set_pose(int64_t id,const Transform3D &pose){
    auto it=records_.find(id);if(it==records_.end())return false;
    if(!NativeVehicleStorage::valid_pose(pose))return false;
    if(cell(it->second.origin)!=cell(pose.origin)){remove_cell(id,it->second.origin);cells_[cell(pose.origin)].insert(id);}
    it->second=pose;return true;
}
Dictionary NativeVehicleFleet::get_record(int64_t id) const {Dictionary out;auto it=records_.find(id);out["present"]=it!=records_.end();if(it!=records_.end()){out["identity"]=id;out["pose"]=it->second;}return out;}
Dictionary NativeVehicleFleet::statistics() const {Dictionary out;out["records"]=int64_t(records_.size());out["cells"]=int64_t(cells_.size());out["next_identity"]=next_;return out;}
Dictionary NativeVehicleFleet::query_near(const Vector3 &center,double radius,int limit,int budget) const {
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
        for(auto id:it->second){if(visited==budget){exhausted=true;break;}++visited;double distance=records_.at(id).origin.distance_squared_to(center);if(distance<=radius*radius)candidates.emplace_back(distance,id);}
    }
    out["visited"]=visited;out["complete"]=!exhausted;
    if(exhausted){out["reason"]="candidate_budget";return out;}
    std::sort(candidates.begin(),candidates.end());out["truncated"]=candidates.size()>size_t(limit);
    for(size_t i=0;i<candidates.size()&&i<size_t(limit);++i)ids.push_back(candidates[i].second);
    out["ids"]=ids;return out;
}
PackedByteArray NativeVehicleFleet::capture_storage_snapshot() const {
    Array rows;for(const auto &entry:records_){Dictionary row;row["identity"]=entry.first;row["pose"]=entry.second;rows.push_back(row);}
    Ref<NativeVehicleStorage> codec;codec.instantiate();return codec->encode_fleet(rows,next_);
}
bool NativeVehicleFleet::validate_snapshot(const PackedByteArray &data) const {Ref<NativeVehicleStorage> codec;codec.instantiate();return codec->validate_fleet_snapshot(data);}
bool NativeVehicleFleet::restore_storage_snapshot(const PackedByteArray &data){
    Ref<NativeVehicleStorage> codec;codec.instantiate();Dictionary decoded=codec->decode_fleet(data);if(!bool(decoded["ok"]))return false;
    std::map<int64_t,Transform3D> records;std::unordered_map<int,std::set<int64_t>> cells;
    Array rows=decoded["records"];for(int i=0;i<rows.size();++i){Dictionary row=rows[i];int64_t id=row["identity"];Transform3D pose=row["pose"];records.emplace(id,pose);cells[cell(pose.origin)].insert(id);}
    records_.swap(records);cells_.swap(cells);next_=decoded["next_identity"];return true;
}
}
