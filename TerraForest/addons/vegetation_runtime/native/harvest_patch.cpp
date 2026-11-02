// SPDX-License-Identifier: 0BSD
#include "harvest_state.hpp"
#include "patch_bytes.hpp"
#include <map>
namespace terraforest {
namespace {
constexpr uint32_t magic=0x50484654;
constexpr int header=16,record=16,limit=4096;
bool decode(const PackedByteArray &data,std::map<int64_t,bool> &selected){
    if(data.size()<header+record+vegetation_patch::trailer||data.size()>header+limit*record+vegetation_patch::trailer||data.decode_u32(0)!=magic||data.decode_u32(4)!=1||data.decode_u32(12)!=0)return false;
    const uint32_t count=data.decode_u32(8);
    if(count<1||count>limit||data.size()!=header+count*record+vegetation_patch::trailer||!vegetation_patch::verified(data))return false;
    int64_t previous=0;
    for(uint32_t index=0;index<count;++index){
        const int offset=header+index*record;const int64_t identity=data.decode_s64(offset);const uint64_t removed=data.decode_u64(offset+8);
        if(identity<=previous||removed>1)return false;
        previous=identity;selected.emplace(identity,removed==1);
    }
    return true;
}
}
Dictionary NativeHarvestState::harvest_patch_state() const {
    Dictionary result;result["revision"]=revision;result["owner"]=int64_t(get_instance_id());return result;
}
PackedByteArray NativeHarvestState::capture_harvest_patch(const PackedInt64Array &ids,int64_t expected_revision,int64_t expected_owner) const {
    if(expected_revision!=revision||expected_owner!=int64_t(get_instance_id())||ids.size()<1||ids.size()>limit)return {};
    std::set<int64_t> selected;for(int64_t identity:ids)if(identity<=0||!selected.insert(identity).second)return {};
    PackedByteArray data;if(data.resize(header+selected.size()*record+vegetation_patch::trailer)!=OK)return {};data.fill(0);
    data.encode_u32(0,magic);data.encode_u32(4,1);data.encode_u32(8,selected.size());int offset=header;
    for(int64_t identity:selected){data.encode_s64(offset,identity);data.encode_u64(offset+8,removed.count(identity));offset+=record;}
    return vegetation_patch::seal(data)?data:PackedByteArray();
}
bool NativeHarvestState::validate_harvest_patch(const PackedByteArray &data) const {
    std::map<int64_t,bool> selected;return decode(data,selected);
}
Dictionary NativeHarvestState::restore_harvest_patch(const PackedByteArray &data,int64_t expected_revision,int64_t expected_owner){
    Dictionary result;result["ok"]=false;result["changes"]=0;result["revision"]=revision;result["reason"]="invalid_or_stale";
    if(expected_revision!=revision||expected_owner!=int64_t(get_instance_id())||revision==INT64_MAX)return result;
    std::map<int64_t,bool> selected;if(!decode(data,selected))return result;
    std::set<int64_t> additions,deletions;
    for(const auto &[identity,was_removed]:selected){
        const bool is_removed=removed.count(identity)!=0;
        if(was_removed&&!is_removed)additions.insert(identity);
        else if(!was_removed&&is_removed)deletions.insert(identity);
    }
    if(removed.size()+additions.size()-deletions.size()>LIMIT){result["reason"]="capacity";return result;}
    const size_t changes=additions.size()+deletions.size();
    if(changes){for(int64_t identity:deletions)removed.erase(identity);removed.merge(additions);snapshot_dirty=true;++revision;}
    result["ok"]=true;result["changes"]=int64_t(changes);result["revision"]=revision;result["reason"]="";return result;
}
}
