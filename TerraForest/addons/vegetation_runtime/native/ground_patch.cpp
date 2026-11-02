// SPDX-License-Identifier: 0BSD
#include "ground_state.hpp"
#include "patch_bytes.hpp"
#include <godot_cpp/variant/aabb.hpp>
namespace terraforest {
namespace {
constexpr uint32_t magic=0x50474654;
constexpr int header=64,natural_record=16,plant_record=64,natural_limit=32768,plant_limit=8192;
bool valid_bounds(const AABB &bounds){
    if(!bounds.position.is_finite()||!bounds.size.is_finite())return false;
    const Vector3 end=bounds.position+bounds.size;
    for(int axis=0;axis<3;++axis)if(bounds.size[axis]<=0||bounds.size[axis]>128)return false;
    return bounds.position.x>=2&&bounds.position.z>=2&&end.x<=1998&&end.z<=1998&&bounds.position.y>=-1&&end.y<=257;
}
bool inside(const AABB &bounds,Vector3 point){
    for(int axis=0;axis<3;++axis)if(point[axis]<bounds.position[axis]||point[axis]>=bounds.position[axis]+bounds.size[axis])return false;
    return true;
}
bool overlaps_cell(const AABB &bounds,int key){
    const int column=key%63,row=key/63;
    return (column+1)*32>bounds.position.x&&column*32<bounds.position.x+bounds.size.x&&(row+1)*32>bounds.position.z&&row*32<bounds.position.z+bounds.size.z;
}
bool valid_natural(int64_t identity,const AABB &bounds){
    if(identity<1||identity>63*63*1024)return false;
    const int key=identity<=63*63*64?int((identity-1)/64):int((identity-1-63*63*64)/960);
    return overlaps_cell(bounds,key);
}
std::vector<int> region_cells(const AABB &bounds){
    std::vector<int> result;
    for(int row=int(bounds.position.z/32);row<=int((bounds.position.z+bounds.size.z)/32);++row)
        for(int column=int(bounds.position.x/32);column<=int((bounds.position.x+bounds.size.x)/32);++column)
            if(overlaps_cell(bounds,row*63+column))result.push_back(row*63+column);
    return result;
}
}
Dictionary NativeGroundCoverState::ground_patch_state() const {
    Dictionary result;result["revision"]=revision;result["owner"]=int64_t(get_instance_id());result["seed"]=seed;result["generator"]=generator;return result;
}
PackedByteArray NativeGroundCoverState::capture_ground_patch(AABB bounds,const PackedInt64Array &natural_ids,int64_t expected_revision,int64_t expected_owner) const {
    if(seed<0||expected_revision!=revision||expected_owner!=int64_t(get_instance_id())||!valid_bounds(bounds)||natural_ids.size()>natural_limit)return {};
    std::set<int64_t> natural;for(int64_t identity:natural_ids)if(!valid_natural(identity,bounds)||!natural.insert(identity).second)return {};
    std::set<int64_t> plants;
    for(int key:region_cells(bounds)){
        const auto found=cells.find(key);if(found==cells.end())continue;
        for(int64_t identity:found->second){const auto &pose=placed.at(identity).t;if(inside(bounds,Vector3(pose[3],pose[7],pose[11])))plants.insert(identity);}
    }
    if(plants.size()>plant_limit)return {};
    PackedByteArray data;if(data.resize(header+natural.size()*natural_record+plants.size()*plant_record+vegetation_patch::trailer)!=OK)return {};data.fill(0);
    data.encode_u32(0,magic);data.encode_u32(4,1);data.encode_s64(8,seed);data.encode_s64(16,generator);
    for(int axis=0;axis<3;++axis){data.encode_float(24+axis*4,bounds.position[axis]);data.encode_float(36+axis*4,bounds.size[axis]);}
    data.encode_u32(48,natural.size());data.encode_u32(52,plants.size());int offset=header;
    for(int64_t identity:natural){data.encode_s64(offset,identity);data.encode_u64(offset+8,removed.count(identity));offset+=natural_record;}
    for(int64_t identity:plants){
        const auto &plant=placed.at(identity);data.encode_s64(offset,identity);data.encode_u64(offset+8,plant.species);
        for(int index=0;index<12;++index)data.encode_float(offset+16+index*4,plant.t[index]);offset+=plant_record;
    }
    return vegetation_patch::seal(data)?data:PackedByteArray();
}
bool NativeGroundCoverState::decode_ground_patch(const PackedByteArray &data,AABB &bounds,int64_t &world_seed,int64_t &world_generator,std::map<int64_t,bool> &natural,std::map<int64_t,Placement> &plants){
    if(data.size()<header+vegetation_patch::trailer||data.size()>header+natural_limit*natural_record+plant_limit*plant_record+vegetation_patch::trailer||data.decode_u32(0)!=magic||data.decode_u32(4)!=1||data.decode_u64(56)!=0)return false;
    const uint32_t natural_count=data.decode_u32(48),plant_count=data.decode_u32(52);
    if(natural_count>natural_limit||plant_count>plant_limit||data.size()!=header+natural_count*natural_record+plant_count*plant_record+vegetation_patch::trailer||!vegetation_patch::verified(data))return false;
    world_seed=data.decode_s64(8);world_generator=data.decode_s64(16);
    if(world_seed<0||world_seed>INT32_MAX||world_generator!=1)return false;
    for(int axis=0;axis<3;++axis){bounds.position[axis]=data.decode_float(24+axis*4);bounds.size[axis]=data.decode_float(36+axis*4);}
    if(!valid_bounds(bounds))return false;
    int offset=header;int64_t previous=0;
    for(uint32_t index=0;index<natural_count;++index){
        const int64_t identity=data.decode_s64(offset);const uint64_t flag=data.decode_u64(offset+8);
        if(identity<=previous||flag>1||!valid_natural(identity,bounds))return false;
        natural.emplace(identity,flag==1);previous=identity;offset+=natural_record;
    }
    previous=AUTHORED_FIRST-1;std::map<int,size_t> counts;
    for(uint32_t index=0;index<plant_count;++index){
        const int64_t identity=data.decode_s64(offset);const uint64_t species=data.decode_u64(offset+8);
        if(identity<=previous||identity==INT64_MAX||species>8)return false;
        Placement plant;plant.species=int(species);for(int axis=0;axis<12;++axis)plant.t[axis]=data.decode_float(offset+16+axis*4);
        if(!valid(plant)||!inside(bounds,Vector3(plant.t[3],plant.t[7],plant.t[11]))||++counts[cell(plant)]>CELL_LIMIT)return false;
        plants.emplace(identity,plant);previous=identity;offset+=plant_record;
    }
    return true;
}
bool NativeGroundCoverState::validate_ground_patch(const PackedByteArray &data) const {
    AABB bounds;int64_t world_seed,world_generator;std::map<int64_t,bool> natural;std::map<int64_t,Placement> plants;
    return decode_ground_patch(data,bounds,world_seed,world_generator,natural,plants);
}
Dictionary NativeGroundCoverState::restore_ground_patch(const PackedByteArray &data,int64_t expected_revision,int64_t expected_owner){
    Dictionary result;result["ok"]=false;result["changes"]=0;result["revision"]=revision;result["reason"]="invalid_or_stale";
    if(expected_revision!=revision||expected_owner!=int64_t(get_instance_id())||revision==INT64_MAX)return result;
    AABB bounds;int64_t world_seed,world_generator;std::map<int64_t,bool> natural;std::map<int64_t,Placement> plants;
    if(!decode_ground_patch(data,bounds,world_seed,world_generator,natural,plants)||seed!=world_seed||generator!=world_generator)return result;
    std::set<int64_t> additions,deletions,current;std::map<int,std::set<int64_t>> staged_cells;
    for(const auto &[identity,was_removed]:natural){
        const bool is_removed=removed.count(identity)!=0;
        if(was_removed&&!is_removed)additions.insert(identity);else if(!was_removed&&is_removed)deletions.insert(identity);
    }
    for(int key:region_cells(bounds)){
        auto &staged=staged_cells[key];const auto found=cells.find(key);if(found==cells.end())continue;
        staged=found->second;
        for(int64_t identity:found->second){const auto &pose=placed.at(identity).t;if(inside(bounds,Vector3(pose[3],pose[7],pose[11]))){current.insert(identity);staged.erase(identity);}}
    }
    if(placed.size()-current.size()+plants.size()>PLACED_LIMIT){result["reason"]="capacity";return result;}
    size_t changes=additions.size()+deletions.size();int64_t next=next_id;
    for(int64_t identity:current)if(!plants.count(identity))++changes;
    for(const auto &[identity,plant]:plants){
        const auto found=placed.find(identity);
        if(found!=placed.end()&&!current.count(identity)){result["reason"]="identity_outside_region";return result;}
        if(found==placed.end()||found->second.species!=plant.species||std::memcmp(found->second.t.data(),plant.t.data(),sizeof(float)*12)!=0)++changes;
        auto &owner=staged_cells[cell(plant)];owner.insert(identity);
        if(owner.size()>CELL_LIMIT){result["reason"]="cell_capacity";return result;}
        next=std::max(next,identity+1);
    }
    if(changes){
        for(int64_t identity:deletions)removed.erase(identity);removed.merge(additions);
        for(int64_t identity:current)placed.erase(identity);placed.merge(plants);
        for(auto owner=staged_cells.begin();owner!=staged_cells.end();){cells.erase(owner->first);if(owner->second.empty())owner=staged_cells.erase(owner);else ++owner;}
        cells.merge(staged_cells);next_id=next;dirty=true;++revision;
    }
    result["ok"]=true;result["changes"]=int64_t(changes);result["revision"]=revision;result["reason"]="";result["bounds"]=bounds;return result;
}
}
