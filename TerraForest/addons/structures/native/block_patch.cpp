// SPDX-License-Identifier: 0BSD
#include "block_world.hpp"
#include <godot_cpp/classes/hashing_context.hpp>
#include <climits>

namespace terraforest {
namespace {
constexpr int patch_header=36,patch_trailer=32,patch_sample_limit=262144;
constexpr uint32_t patch_magic=0x31504254;
bool patch_bounds(Vector3i origin,Vector3i size){
    int64_t samples=1;
    for(int axis=0;axis<3;++axis){
        if(size[axis]<1||size[axis]>128||origin[axis]<-1048575||int64_t(origin[axis])+size[axis]-1>1048575)return false;
        samples*=size[axis];
    }
    return samples<=patch_sample_limit;
}
PackedByteArray patch_digest(const PackedByteArray &bytes){
    Ref<HashingContext> hash;hash.instantiate();
    if(hash.is_null()||hash->start(HashingContext::HASH_SHA256)!=OK||hash->update(bytes.slice(0,bytes.size()-patch_trailer))!=OK)return {};
    return hash->finish();
}
bool decode_patch(const PackedByteArray &bytes,Vector3i &origin,Vector3i &size){
    if(bytes.size()<patch_header+patch_trailer+2||bytes.size()>patch_header+patch_trailer+patch_sample_limit*2||
        bytes.decode_u32(0)!=patch_magic||bytes.decode_u32(4)!=1)return false;
    for(int axis=0;axis<3;++axis){origin[axis]=bytes.decode_s32(8+axis*4);size[axis]=bytes.decode_s32(20+axis*4);}
    if(!patch_bounds(origin,size))return false;
    const int count=size.x*size.y*size.z;
    if(bytes.decode_u32(32)!=uint32_t(count)||bytes.size()!=patch_header+patch_trailer+count*2)return false;
    if(patch_digest(bytes)!=bytes.slice(bytes.size()-patch_trailer))return false;
    for(int index=0;index<count;++index)if(!valid_block_word(bytes.decode_u16(patch_header+index*2)))return false;
    return true;
}
}
Dictionary NativeBlockWorld::cell_patch_state() const {
    Dictionary result;result["epoch"]=int64_t(storage_epoch);result["revision"]=int64_t(content_revision);return result;
}
bool NativeBlockWorld::validate_cell_patch(const PackedByteArray &bytes) const {
    Vector3i origin,size;return decode_patch(bytes,origin,size);
}
PackedByteArray NativeBlockWorld::capture_cell_patch(Vector3i origin,Vector3i size,int64_t expected_revision,int64_t expected_epoch) const {
    if(expected_revision<0||uint64_t(expected_revision)!=content_revision||expected_epoch<0||uint64_t(expected_epoch)!=storage_epoch||
        !patch_bounds(origin,size)||unavailable_region(AABB(Vector3(origin),Vector3(size))))return {};
    const int count=size.x*size.y*size.z;PackedByteArray result;
    if(result.resize(patch_header+patch_trailer+count*2)!=OK)return {};
    result.encode_u32(0,patch_magic);result.encode_u32(4,1);
    for(int axis=0;axis<3;++axis){result.encode_s32(8+axis*4,origin[axis]);result.encode_s32(20+axis*4,size[axis]);}
    result.encode_u32(32,count);int index=0;
    for(int z=0;z<size.z;++z)for(int y=0;y<size.y;++y)for(int x=0;x<size.x;++x)
        result.encode_u16(patch_header+2*index++,cell(origin.x+x,origin.y+y,origin.z+z));
    const PackedByteArray digest=patch_digest(result);if(digest.size()!=patch_trailer)return {};
    for(int offset=0;offset<patch_trailer;++offset)result.set(result.size()-patch_trailer+offset,digest[offset]);
    return result;
}
Dictionary NativeBlockWorld::restore_cell_patch(const PackedByteArray &bytes,int64_t expected_revision,int64_t expected_epoch){
    Dictionary result;result["ok"]=false;result["changes"]=0;result["epoch"]=int64_t(storage_epoch);result["revision"]=int64_t(content_revision);
    result["bounds"]=AABB();
    Vector3i origin,size;
    if(expected_revision<0||uint64_t(expected_revision)!=content_revision||expected_epoch<0||uint64_t(expected_epoch)!=storage_epoch||
        content_revision>=uint64_t(INT64_MAX)||!decode_patch(bytes,origin,size)||unavailable_region(AABB(Vector3(origin),Vector3(size))))return result;
    const int count=size.x*size.y*size.z;PackedInt32Array records;
    if(records.resize(count*4)!=OK)return result;
    int index=0,changes=0;
    for(int z=0;z<size.z;++z)for(int y=0;y<size.y;++y)for(int x=0;x<size.x;++x){
        const int word=bytes.decode_u16(patch_header+2*index++);
        if(word==cell(origin.x+x,origin.y+y,origin.z+z))continue;
        const int offset=changes++*4;
        records.set(offset,origin.x+x);records.set(offset+1,origin.y+y);records.set(offset+2,origin.z+z);records.set(offset+3,word);
    }
    if(records.resize(changes*4)!=OK)return result;
    bool changed=false;AABB changed_bounds;
    if(changes&&!apply_cells(records,false,changed,&changed_bounds))return result;
    result["ok"]=true;result["changes"]=changes;result["revision"]=int64_t(content_revision);result["bounds"]=changed_bounds;
    if(changed){emit_signal("cells_changed",changed_bounds);emit_signal("changed");}
    return result;
}
}
