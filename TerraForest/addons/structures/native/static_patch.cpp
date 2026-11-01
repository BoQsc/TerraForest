// SPDX-License-Identifier: 0BSD
#include "static_batch.hpp"
#include <climits>
#include <cstring>

namespace terraforest {
namespace {
constexpr int patch_header=68,patch_trailer=32,patch_limit=4096,patch_work_limit=16384;
constexpr int patch_max_bytes=patch_header+patch_trailer+16+128+patch_limit*56+32;
constexpr uint32_t patch_magic=0x504d4654;
bool patch_bounds(Vector3i origin,Vector3i size){
    for(int axis=0;axis<3;++axis)
        if(size[axis]<1||size[axis]>128||origin[axis]<-1048575||int64_t(origin[axis])+size[axis]>1048575)return false;
    return true;
}
PackedByteArray digest(const PackedByteArray &bytes){
    Ref<HashingContext> hash;hash.instantiate();
    if(hash.is_null()||hash->start(HashingContext::HASH_SHA256)!=OK||hash->update(bytes)!=OK)return {};
    return hash->finish();
}
bool contains(const AABB &outer,const AABB &inner){
    for(int axis=0;axis<3;++axis)
        if(inner.position[axis]<outer.position[axis]||inner.get_end()[axis]>outer.get_end()[axis])return false;
    return true;
}
bool same_placement(const std::array<float,12> &left,const std::array<float,12> &right){
    return std::memcmp(left.data(),right.data(),sizeof(float)*12)==0;
}
}
PackedByteArray NativeStaticBatch::placement_patch_prototype() const {
    if(source_mesh.is_null())return {};
    PackedByteArray bytes;
    if(bytes.resize(4+24*(1+proxy_parts.size()))!=OK)return {};
    bytes.encode_u32(0,proxy_parts.size());
    for(size_t index=0;index<=proxy_parts.size();++index){
        const AABB box=index?proxy_parts[index-1]:source_mesh->get_aabb();
        if(!box.position.is_finite()||!box.size.is_finite()||!box.get_end().is_finite())return {};
        for(int axis=0;axis<3;++axis){
            if(box.size[axis]<0)return {};
            bytes.encode_float(4+index*24+axis*4,box.position[axis]);
            bytes.encode_float(16+index*24+axis*4,box.size[axis]);
        }
    }
    return digest(bytes);
}
bool NativeStaticBatch::select_placement_patch(const AABB &bounds,std::map<int64_t,Placement> &selected,String &reason) const {
    if(source_mesh.is_null()||admission||collection_retirement||defer_change_signal){reason="busy";return false;}
    if(unloaded_bounds.any_intersection(bounds,[](BlockKey){return true;})){reason="unavailable";return false;}
    const AABB prototype=proxy_parts.empty()?source_mesh->get_aabb():source_mesh->get_aabb().merge(proxy_box);
    int visited=0;
    for(const auto &entry:render_bounds){
        if(!entry.second.merge(collision_bounds.at(entry.first)).intersects(bounds))continue;
        const auto &members=groups.at(entry.first);
        if(members.size()>size_t(patch_work_limit-visited)){reason="work_limit";return false;}
        visited+=members.size();
        for(auto id:members){
            const auto &placement=placements.at(id);
            const AABB box=placement_transform(placement).xform(prototype);
            if(!box.intersects(bounds))continue;
            if(!contains(bounds,box)){reason="boundary";return false;}
            if(selected.size()>=patch_limit){reason="capacity";return false;}
            selected.emplace(id,placement);
        }
    }
    return true;
}
Dictionary NativeStaticBatch::placement_patch_state() const {
    Dictionary result;result["revision"]=int64_t(edit_revision);result["owner"]=int64_t(get_instance_id());return result;
}
PackedByteArray NativeStaticBatch::capture_placement_patch(Vector3i origin,Vector3i size,int64_t expected_revision,int64_t expected_owner) const {
    if(expected_revision<0||uint64_t(expected_revision)!=edit_revision||uint64_t(expected_owner)!=get_instance_id()||
        !patch_bounds(origin,size)||!valid_asset(asset_id))return {};
    const PackedByteArray prototype=placement_patch_prototype();if(prototype.size()!=32)return {};
    std::map<int64_t,Placement> selected;String reason;
    if(!select_placement_patch(AABB(Vector3(origin),Vector3(size)),selected,reason))return {};
    const PackedByteArray payload=encode_placements(asset_id,selected);if(payload.is_empty())return {};
    PackedByteArray result;if(result.resize(patch_header)!=OK)return {};
    result.encode_u32(0,patch_magic);result.encode_u32(4,1);
    for(int axis=0;axis<3;++axis){result.encode_s32(8+axis*4,origin[axis]);result.encode_s32(20+axis*4,size[axis]);}
    result.encode_u32(32,payload.size());
    for(int index=0;index<32;++index)result.set(36+index,prototype[index]);
    result.append_array(payload);const PackedByteArray checksum=digest(result);
    if(checksum.size()!=32)return {};result.append_array(checksum);return result;
}
bool NativeStaticBatch::decode_placement_patch(const PackedByteArray &bytes,AABB &bounds,std::map<int64_t,Placement> &selected) const {
    if(source_mesh.is_null()||bytes.size()<patch_header+patch_trailer+49||bytes.size()>patch_max_bytes||
        bytes.decode_u32(0)!=patch_magic||bytes.decode_u32(4)!=1||bytes.decode_u32(32)!=uint64_t(bytes.size()-patch_header-patch_trailer))return false;
    Vector3i origin,size;
    for(int axis=0;axis<3;++axis){origin[axis]=bytes.decode_s32(8+axis*4);size[axis]=bytes.decode_s32(20+axis*4);}
    if(!patch_bounds(origin,size)||bytes.decode_u32(patch_header+12)>patch_limit||
        digest(bytes.slice(0,bytes.size()-patch_trailer))!=bytes.slice(bytes.size()-patch_trailer)||
        placement_patch_prototype()!=bytes.slice(36,68))return false;
    String asset;
    if(!parse(bytes.slice(patch_header,bytes.size()-patch_trailer),asset,&selected)||asset!=asset_id)return false;
    bounds=AABB(Vector3(origin),Vector3(size));
    const AABB prototype=proxy_parts.empty()?source_mesh->get_aabb():source_mesh->get_aabb().merge(proxy_box);
    for(const auto &entry:selected)if(!contains(bounds,placement_transform(entry.second).xform(prototype)))return false;
    return true;
}
bool NativeStaticBatch::validate_placement_patch(const PackedByteArray &bytes) const {
    AABB bounds;std::map<int64_t,Placement> selected;return decode_placement_patch(bytes,bounds,selected);
}
Dictionary NativeStaticBatch::restore_placement_patch(const PackedByteArray &bytes,int64_t expected_revision,int64_t expected_owner){
    Dictionary result;result["ok"]=false;result["changes"]=0;result["revision"]=int64_t(edit_revision);
    result["owner"]=int64_t(get_instance_id());result["reason"]="stale";
    if(expected_revision<0||uint64_t(expected_revision)!=edit_revision||uint64_t(expected_owner)!=get_instance_id()||edit_revision>=uint64_t(INT64_MAX))return result;
    AABB bounds;std::map<int64_t,Placement> desired,current;
    result["reason"]="invalid";if(!decode_placement_patch(bytes,bounds,desired))return result;
    String reason;
    if(!select_placement_patch(bounds,current,reason)){result["reason"]=reason;return result;}
    result["reason"]="outside_identity";
    for(const auto &entry:desired)
        if(unloaded_ids.count(entry.first)||(placements.count(entry.first)&&!current.count(entry.first)))return result;
    result["reason"]="capacity";
    if(placements.size()+unloaded_ids.size()-current.size()+desired.size()>100000)return result;
    std::map<int64_t,Placement> replacements;
    std::set<int64_t> removed,changed;
    std::set<BlockKey> touched;
    for(const auto &entry:current){
        auto found=desired.find(entry.first);
        if(found!=desired.end()&&same_placement(found->second,entry.second))continue;
        if(removal_protected.count(entry.first)||visual_hidden.count(entry.first)){result["reason"]="protected";return result;}
        changed.insert(entry.first);touched.insert(group_for(entry.second));
        if(found==desired.end())removed.insert(entry.first);
    }
    for(const auto &entry:desired){
        auto found=current.find(entry.first);if(found!=current.end()&&same_placement(found->second,entry.second))continue;
        const auto key=group_for(entry.second);
        if(unloaded_regions.count(key)){result["reason"]="unavailable";return result;}
        if(removal_protected.count(entry.first)||visual_hidden.count(entry.first)){result["reason"]="protected";return result;}
        replacements.emplace(entry);changed.insert(entry.first);touched.insert(key);
    }
    std::map<BlockKey,std::set<int64_t>> staged_groups;size_t copied=0;
    for(const auto key:touched){
        auto found=groups.find(key);
        if(found!=groups.end()){
            copied+=found->second.size();if(copied>patch_work_limit){result["reason"]="work_limit";return result;}
            staged_groups.emplace(key,found->second);
        }else staged_groups.emplace(key,std::set<int64_t>());
    }
    for(auto id:changed){auto found=current.find(id);if(found!=current.end())staged_groups.at(group_for(found->second)).erase(id);}
    for(const auto &entry:replacements)staged_groups.at(group_for(entry.second)).insert(entry.first);
    int64_t group_count=groups.size()+unloaded_regions.size();
    for(const auto &entry:staged_groups)group_count+=int(!entry.second.empty())-int(groups.count(entry.first));
    if(group_count>4096)return result;
    for(auto id:changed)invalidate_proxy(id);
    for(auto id:removed){placements.erase(id);slots.erase(id);appearance_birth.erase(id);}
    for(auto entry=replacements.begin();entry!=replacements.end();){
        auto found=placements.find(entry->first);
        if(found==placements.end()){++entry;continue;}
        found->second=entry->second;entry=replacements.erase(entry);
    }
    placements.merge(replacements);
    for(auto entry=staged_groups.begin();entry!=staged_groups.end();){
        auto found=groups.find(entry->first);
        if(entry->second.empty()){if(found!=groups.end())groups.erase(found);entry=staged_groups.erase(entry);}
        else if(found!=groups.end()){found->second.swap(entry->second);entry=staged_groups.erase(entry);}
        else ++entry;
    }
    groups.merge(staged_groups);
    if(!changed.empty()){rebuild(touched,true);for(auto id:changed)change_world_render(id);}
    result["ok"]=true;result["reason"]="";result["changes"]=int64_t(changed.size());result["bounds"]=bounds;
    result["revision"]=int64_t(edit_revision+(!changed.empty()));
    if(!changed.empty())publish_change();return result;
}
}
