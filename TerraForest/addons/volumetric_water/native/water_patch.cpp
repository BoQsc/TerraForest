// SPDX-License-Identifier: 0BSD
#include "regional_water.hpp"
#include <godot_cpp/classes/hashing_context.hpp>
#include <algorithm>
#include <cstring>
#include <set>
using namespace godot;
namespace terraforest {
namespace {
constexpr uint32_t patch_magic=0x50574654;
constexpr int header_bytes=64,record_bytes=16,digest_bytes=32,cell_limit=262144,region_limit=1024;
constexpr uint64_t quantity_limit=uint64_t(1)<<52;
struct Patch {
    Vector3i origin,size;
    uint32_t flags=0,count=0;
    uint64_t total=0;
};
struct Sample {uint32_t index,vacancy;uint64_t amount;};
uint32_t read32(const uint8_t *bytes){uint32_t value=0;for(int index=0;index<4;++index)value|=uint32_t(bytes[index])<<(8*index);return value;}
uint64_t read64(const uint8_t *bytes){uint64_t value=0;for(int index=0;index<8;++index)value|=uint64_t(bytes[index])<<(8*index);return value;}
void write32(uint8_t *bytes,uint32_t value){for(int index=0;index<4;++index)bytes[index]=uint8_t(value>>(8*index));}
void write64(uint8_t *bytes,uint64_t value){for(int index=0;index<8;++index)bytes[index]=uint8_t(value>>(8*index));}
bool valid_box(const Vector3i &origin,const Vector3i &size){
    if(origin.x<0||origin.x>=4000||origin.z<0||origin.z>=4000||origin.y<2||origin.y>=509)return false;
    for(int axis=0;axis<3;++axis)if(size[axis]<1||size[axis]>256)return false;
    const auto end=origin+size;
    if(end.x>4000||end.z>4000||end.y>509||int64_t(size.x)*size.y*size.z>cell_limit)return false;
    const auto first=origin/8,last=(end-Vector3i(1,1,1))/8;
    return (last.x-first.x+1)*(last.y-first.y+1)*(last.z-first.z+1)<=region_limit;
}
PackedByteArray digest(const PackedByteArray &data){
    Ref<HashingContext> hash;hash.instantiate();
    if(hash.is_null()||hash->start(HashingContext::HASH_SHA256)!=OK||hash->update(data.slice(0,data.size()-digest_bytes))!=OK)return {};
    return hash->finish();
}
bool decode_patch(const PackedByteArray &data,Patch &patch){
    if(data.size()<header_bytes+digest_bytes||data.size()>header_bytes+cell_limit*record_bytes+digest_bytes)return false;
    const auto *bytes=data.ptr();
    if(read32(bytes)!=patch_magic||read32(bytes+4)!=1||read64(bytes+48)||read64(bytes+56))return false;
    patch.flags=read32(bytes+8);patch.count=read32(bytes+12);
    if(patch.flags>3||patch.count>cell_limit||data.size()!=header_bytes+int64_t(patch.count)*record_bytes+digest_bytes)return false;
    for(int axis=0;axis<3;++axis){patch.origin[axis]=int32_t(read32(bytes+16+axis*4));patch.size[axis]=int32_t(read32(bytes+28+axis*4));}
    if(!valid_box(patch.origin,patch.size))return false;
    const uint32_t volume=patch.size.x*patch.size.y*patch.size.z;
    if(patch.count>volume)return false;
    patch.total=read64(bytes+40);if(patch.total>quantity_limit)return false;
    uint64_t total=0;uint32_t previous=0;
    for(uint32_t index=0;index<patch.count;++index){
        const auto *record=bytes+header_bytes+index*record_bytes;const auto amount=read64(record+8);const uint32_t sample=read32(record),vacancy=read32(record+4);
        if(sample>=volume||(index&&sample<=previous)||amount>quantity_limit-total||vacancy>125000||(!amount&&!vacancy))return false;
        previous=sample;
        total+=amount;
    }
    return total==patch.total&&digest(data)==data.slice(data.size()-digest_bytes);
}
bool implicit_ocean(const Vector3i &coordinate,bool western,bool surrounding){
    if(coordinate.y<7||coordinate.y>=10)return false;
    return (western&&coordinate.x<35)||(surrounding&&std::min({coordinate.x,coordinate.z,499-coordinate.x,499-coordinate.z})<35);
}
}
Dictionary NativeRegionalWater::water_patch_state() const {
    Dictionary result;result["revision"]=int64_t(survey_revision);result["owner"]=int64_t(get_instance_id());
    result["filling"]=fill.running;result["publishing"]=batch_active||publish_pending;
    result["ocean_flags"]=int(western_ocean)|(int(surrounding_ocean)<<1);return result;
}
PackedByteArray NativeRegionalWater::capture_water_patch(const Vector3i &origin,const Vector3i &size,int64_t revision,int64_t owner) const {
    if(revision<0||uint64_t(revision)!=survey_revision||owner!=int64_t(get_instance_id())||fill.running||!valid_box(origin,size))return {};
    const auto first=origin/8,last=(origin+size-Vector3i(1,1,1))/8;
    std::map<Key,const Region *> selected;bool has_regions=false;
    for(int column=first.x;column<=last.x;++column)for(int height=first.y;height<=last.y;++height)for(int row=first.z;row<=last.z;++row){
        const Vector3i coordinate(column,height,row);const Key identity=key(coordinate);
        if(deferred_regions.count(identity)||ocean_cache.count(identity))return {};
        const auto found=regions.find(identity);
        if(found==regions.end()){
            if(implicit_ocean(coordinate,western_ocean,surrounding_ocean))return {};
            selected.emplace(identity,nullptr);
        }else{
            if(!found->second.valid||!found->second.has_density||found->second.replace_water||found->second.limited_building_edit)return {};
            selected.emplace(identity,&found->second);
            has_regions=true;
        }
    }
    std::vector<Sample> samples;samples.reserve(std::min(4096,size.x*size.y*size.z));uint64_t total=0;uint32_t cursor=0;
    if(has_regions)for(int row=origin.z;row<origin.z+size.z;++row)for(int height=origin.y;height<origin.y+size.y;++height)for(int column=origin.x;column<origin.x+size.x;++column){
        const Vector3i point(column,height,row);const auto *region=selected.at(region_key(point));const int sample=index(point);
        const uint64_t amount=region?region->water[sample]:0;const uint32_t vacancy=region&&!region->vacancies.empty()?region->vacancies[sample]:0;
        if(amount>quantity_limit-total||vacancy>125000)return {};total+=amount;
        if(amount||vacancy)samples.push_back({cursor,vacancy,amount});++cursor;
    }
    PackedByteArray data;if(data.resize(header_bytes+samples.size()*record_bytes+digest_bytes)!=OK)return {};data.fill(0);
    auto *bytes=data.ptrw();write32(bytes,patch_magic);write32(bytes+4,1);write32(bytes+8,uint32_t(western_ocean)|(uint32_t(surrounding_ocean)<<1));write32(bytes+12,samples.size());
    for(int axis=0;axis<3;++axis){write32(bytes+16+axis*4,origin[axis]);write32(bytes+28+axis*4,size[axis]);}
    int offset=header_bytes;
    for(const auto &sample:samples){write32(bytes+offset,sample.index);write32(bytes+offset+4,sample.vacancy);write64(bytes+offset+8,sample.amount);offset+=record_bytes;}
    write64(bytes+40,total);const auto checksum=digest(data);if(checksum.size()!=digest_bytes)return {};
    std::memcpy(data.ptrw()+offset,checksum.ptr(),digest_bytes);return data;
}
bool NativeRegionalWater::validate_water_patch(const PackedByteArray &data) const {Patch patch;return decode_patch(data,patch);}
Dictionary NativeRegionalWater::restore_water_patch(const PackedByteArray &data,int64_t revision,int64_t owner){
    Dictionary result;result["ok"]=false;result["changes"]=0;result["revision"]=int64_t(survey_revision);result["reason"]="invalid_or_stale";
    if(revision<0||uint64_t(revision)!=survey_revision||survey_revision>=INT64_MAX||owner!=int64_t(get_instance_id()))return result;
    Patch patch;if(!decode_patch(data,patch)||patch.flags!=(uint32_t(western_ocean)|(uint32_t(surrounding_ocean)<<1)))return result;
    if(fill.running||batch_active||publish_pending){result["reason"]="busy";return result;}
    const auto first=patch.origin/8,last=(patch.origin+patch.size-Vector3i(1,1,1))/8;
    std::map<Key,const Region *> selected;bool has_regions=false;
    for(int column=first.x;column<=last.x;++column)for(int height=first.y;height<=last.y;++height)for(int row=first.z;row<=last.z;++row){
        const Vector3i coordinate(column,height,row);const Key identity=key(coordinate);const auto found=regions.find(identity);
        if(deferred_regions.count(identity)||ocean_cache.count(identity)||(found==regions.end()&&implicit_ocean(coordinate,western_ocean,surrounding_ocean))){result["reason"]="unavailable";return result;}
        if(found!=regions.end()&&(!found->second.valid||!found->second.has_density||found->second.replace_water||found->second.limited_building_edit)){result["reason"]="unavailable";return result;}
        selected.emplace(identity,found==regions.end()?nullptr:&found->second);
        has_regions|=found!=regions.end();
    }
    std::map<Key,Region> staged;uint64_t old_total=0;size_t additions=0,changed_cells=0;uint32_t record=0;const auto *bytes=data.ptr();
    const uint32_t steps=has_regions?patch.size.x*patch.size.y*patch.size.z:patch.count;
    for(uint32_t step=0;step<steps;++step){
        const uint32_t cursor=has_regions?step:read32(bytes+header_bytes+step*record_bytes);
        const Vector3i point=patch.origin+Vector3i(cursor%patch.size.x,(cursor/patch.size.x)%patch.size.y,cursor/(patch.size.x*patch.size.y));
        const Key identity=region_key(point);const auto *region=selected.at(identity);const int sample=index(point);
        const auto *encoded=bytes+header_bytes+record*record_bytes;const bool present=record<patch.count&&read32(encoded)==cursor;
        const uint64_t previous=region?region->water[sample]:0,amount=present?read64(encoded+8):0;
        const uint32_t previous_vacancy=region&&!region->vacancies.empty()?region->vacancies[sample]:0,vacancy=present?read32(encoded+4):0;
        if(present)++record;
        old_total+=previous;if(previous==amount&&previous_vacancy==vacancy)continue;
        auto found=staged.find(identity);
        if(found==staged.end()){found=staged.emplace(identity,region?*region:Region{}).first;if(!region)++additions;}
        auto &next=found->second;next.water[sample]=amount;
        if(vacancy&&next.vacancies.empty())next.vacancies.resize(512,0);
        if(!next.vacancies.empty())next.vacancies[sample]=vacancy;
        if(next.ocean_state==1)next.ocean_state=2;
        ++changed_cells;
    }
    if(old_total>total||patch.total>MAX_TOTAL-(total-old_total)){result["reason"]="quantity_capacity";return result;}
    if(regions.size()+ocean_cache.size()+additions>MAX_REGIONS){result["reason"]="region_capacity";return result;}
    std::set<Key> dirty;
    for(auto &[identity,region]:staged){
        if(std::all_of(region.vacancies.begin(),region.vacancies.end(),[](uint32_t vacancy){return vacancy==0;}))region.vacancies.clear();
        const auto coordinate=position(identity);
        for(int row=-1;row<=1;++row)for(int height=-1;height<=1;++height)for(int column=-1;column<=1;++column){
            const auto neighbor=coordinate+Vector3i(column,height,row);
            if(neighbor.x>=0&&neighbor.x<500&&neighbor.z>=0&&neighbor.z<500&&neighbor.y>=0&&neighbor.y<64)dirty.insert(key(neighbor));
        }
    }
    const size_t changed_regions=staged.size();PackedInt32Array coordinates;coordinates.resize(changed_regions*3);int coordinate_cursor=0;
    for(const auto &[identity,region]:staged){const auto coordinate=position(identity);for(int axis=0;axis<3;++axis)coordinates.set(coordinate_cursor++,coordinate[axis]);}
    if(changed_cells){
        for(const auto &[identity,region]:staged){regions.erase(identity);restored_cache.erase(identity);if(!region.valid)request(identity);}
        regions.merge(staged);total=total-old_total+patch.total;invalidate_snapshot();changes+=changed_cells;
        for(Key identity:dirty)if(mesh_set.insert(identity).second)meshes.push_back(identity);
    }
    result["ok"]=true;result["changes"]=int64_t(changed_cells);result["revision"]=int64_t(survey_revision);result["reason"]="";
    result["bounds"]=AABB(Vector3(patch.origin)*.5,Vector3(patch.size)*.5);result["coordinates"]=coordinates;result["regions"]=int64_t(changed_regions);return result;
}
}
