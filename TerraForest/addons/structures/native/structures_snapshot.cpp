#include "structures_snapshot.hpp"
#include "block_world.hpp"
#include "static_batch.hpp"
#include <godot_cpp/classes/hashing_context.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <cstring>
namespace terraforest {
using namespace godot;
static constexpr int64_t LIMIT=64*1024*1024;
static PackedByteArray digest(const PackedByteArray &bytes) {Ref<HashingContext> h;h.instantiate();h->start(HashingContext::HASH_SHA256);h->update(bytes);return h->finish();}
PackedByteArray NativeStructuresSnapshot::model_reference(const String &asset,const PackedByteArray &checkpoint) {
    if(!NativeStaticBatch::valid_asset(asset)||checkpoint.size()!=32)return {};
    auto name=asset.to_utf8_buffer();PackedByteArray out;out.resize(12);std::memcpy(out.ptrw(),"TFMK\1\0\0\0",8);
    out.encode_u32(8,name.size());out.append_array(name);out.append_array(checkpoint);out.append_array(digest(out));return out;
}
bool NativeStructuresSnapshot::parse_model_reference(const PackedByteArray &bytes,String &asset,PackedByteArray &checkpoint) {
    if(bytes.size()<77||bytes.size()>204||std::memcmp(bytes.ptr(),"TFMK\1\0\0\0",8))return false;
    const int64_t length=bytes.decode_u32(8);if(length<1||length>128||bytes.size()!=76+length)return false;
    if(digest(bytes.slice(0,bytes.size()-32))!=bytes.slice(bytes.size()-32))return false;
    for(int64_t i=0;i<length;++i)if(bytes[12+i]<33||bytes[12+i]>126)return false;
    asset=String::utf8(reinterpret_cast<const char*>(bytes.ptr()+12),length);
    checkpoint=bytes.slice(12+length,44+length);return true;
}
void NativeStructuresSnapshot::_bind_methods() {
    ClassDB::bind_method(D_METHOD("encode_model_storage","resident","unavailable_keys","unavailable_checksums"),&NativeStructuresSnapshot::encode_model_storage);
    ClassDB::bind_method(D_METHOD("configure_assets","asset_ids"),&NativeStructuresSnapshot::configure_assets);
    ClassDB::bind_method(D_METHOD("encode","blocks","models"),&NativeStructuresSnapshot::encode);
    ClassDB::bind_method(D_METHOD("decode","bytes"),&NativeStructuresSnapshot::decode);
    ClassDB::bind_method(D_METHOD("validate_snapshot","bytes"),&NativeStructuresSnapshot::validate_snapshot);
    ClassDB::bind_method(D_METHOD("encode_reference","checkpoint","models"),&NativeStructuresSnapshot::encode_reference);
    ClassDB::bind_method(D_METHOD("decode_reference","bytes"),&NativeStructuresSnapshot::decode_reference);
    ClassDB::bind_method(D_METHOD("encode_storage","resident","keys","checksums","models","checkpoint"),&NativeStructuresSnapshot::encode_storage,DEFVAL(PackedByteArray()));
    ClassDB::bind_method(D_METHOD("encode_metadata","checkpoint","keys","checksums","models"),&NativeStructuresSnapshot::encode_metadata);
    ClassDB::bind_method(D_METHOD("decode_storage","bytes"),&NativeStructuresSnapshot::decode_storage);
    ClassDB::bind_method(D_METHOD("validate_storage_snapshot","bytes"),&NativeStructuresSnapshot::validate_storage_snapshot);
}
bool NativeStructuresSnapshot::configure_assets(const PackedStringArray &ids) {
    if(configured||ids.size()>256)return false;
    std::set<String> selected;
    for(auto id:ids)if(!NativeStaticBatch::valid_asset(id)||!selected.insert(id).second)return false;
    assets=std::move(selected);configured=true;return true;
}
PackedByteArray NativeStructuresSnapshot::encode_model_storage(const PackedByteArray &resident,const PackedInt32Array &keys,const PackedByteArray &checksums) const {
    if(keys.size()%3||keys.size()/3>4096||checksums.size()!=keys.size()/3*32||resident.size()>5600176)return {};
    PackedByteArray out;out.resize(16);std::memcpy(out.ptrw(),"TFMP\1\0\0\0",8);
    out.encode_u32(8,resident.size());out.encode_u32(12,keys.size()/3);out.append_array(resident);
    for(int64_t i=0;i<keys.size()/3;++i){int64_t at=out.size();out.resize(at+44);for(int j=0;j<3;++j)out.encode_s32(at+j*4,keys[i*3+j]);std::memcpy(out.ptrw()+at+12,checksums.ptr()+i*32,32);}
    out.append_array(digest(out));String asset;
    return configured&&parse_model_storage(out,asset)&&assets.count(asset)?out:PackedByteArray();
}
bool NativeStructuresSnapshot::parse_model_storage(const PackedByteArray &bytes,String &asset,Dictionary *state) {
    if(bytes.size()<97||bytes.size()>5780448||std::memcmp(bytes.ptr(),"TFMP\1\0\0\0",8))return false;
    int64_t length=bytes.decode_u32(8),count=bytes.decode_u32(12);
    if(count>4096||length>5600176||48+length+count*44!=bytes.size()||digest(bytes.slice(0,bytes.size()-32))!=bytes.slice(bytes.size()-32))return false;
    auto resident=bytes.slice(16,16+length);std::map<int64_t,NativeStaticBatch::Placement> values;
    if(!NativeStaticBatch::parse(resident,asset,&values))return false;
    std::set<BlockKey> occupied;for(const auto &value:values)occupied.insert(NativeStaticBatch::group_for(value.second));
    if(occupied.size()+count>4096)return false;
    PackedInt32Array keys;PackedByteArray checksums;if(state){keys.resize(count*3);checksums.resize(count*32);}
    BlockKey previous;
    for(int64_t i=0;i<count;++i){int64_t at=16+length+i*44;BlockKey key{int(bytes.decode_s32(at)),int(bytes.decode_s32(at+4)),int(bytes.decode_s32(at+8))};
        if(!NativeStaticBatch::valid_model_region(key)||(i&&!(previous<key))||occupied.count(key))return false;
        previous=key;if(state){keys.set(i*3,key.x);keys.set(i*3+1,key.y);keys.set(i*3+2,key.z);std::memcpy(checksums.ptrw()+i*32,bytes.ptr()+at+12,32);}}
    if(state){(*state)["resident"]=resident;(*state)["unavailable_keys"]=keys;(*state)["unavailable_checksums"]=checksums;}return true;
}
PackedByteArray NativeStructuresSnapshot::encode(const PackedByteArray &blocks,const Dictionary &models) const {
    return encode_payload(blocks,models,RESIDENT);
}
PackedByteArray NativeStructuresSnapshot::encode_reference(const PackedByteArray &checkpoint,const Dictionary &models) const {
    return encode_payload(checkpoint,models,REFERENCE);
}
PackedByteArray NativeStructuresSnapshot::encode_payload(const PackedByteArray &blocks,const Dictionary &models,Mode mode) const {
    if(!configured||models.size()!=int64_t(assets.size())||!parse_block_payload(blocks,nullptr,mode))return {};
    int64_t size=16+blocks.size()+32;
    for(auto asset:assets) {
        if(!models.has(asset)||models[asset].get_type()!=Variant::PACKED_BYTE_ARRAY)return {};
        PackedByteArray value=models[asset];String parsed;
        PackedByteArray checkpoint;
        if((!NativeStaticBatch::parse(value,parsed,nullptr)&&!(mode==REFERENCE&&parse_model_reference(value,parsed,checkpoint))&& !((mode==STORAGE||mode==CHECKPOINT_STORAGE)&&parse_model_storage(value,parsed)))||parsed!=asset)return {};
        size+=4+value.size();if(size>LIMIT)return {};
    }
    if(size>LIMIT)return {};
    PackedByteArray result;result.resize(size-32);uint8_t *out=result.ptrw();std::memcpy(out,magic(mode),8);
    int64_t cursor=8;
    auto u32=[&](uint32_t n){for(int i=0;i<4;i++)out[cursor++]=uint8_t(n>>(8*i));};
    auto copy=[&](const PackedByteArray &bytes){std::memcpy(out+cursor,bytes.ptr(),bytes.size());cursor+=bytes.size();};
    u32(uint32_t(assets.size()));u32(uint32_t(blocks.size()));copy(blocks);
    for(auto asset:assets){PackedByteArray bytes=models[asset];u32(uint32_t(bytes.size()));copy(bytes);}
    result.append_array(digest(result));return result;
}
bool NativeStructuresSnapshot::parse(const PackedByteArray &bytes,Dictionary *result,Mode mode) const {
    if(!configured||bytes.size()<48||bytes.size()>LIMIT||std::memcmp(bytes.ptr(),magic(mode),8))return false;
    auto payload=bytes.slice(0,bytes.size()-32);if(digest(payload)!=bytes.slice(bytes.size()-32))return false;
    const uint8_t *data=payload.ptr();int64_t p=8,n=payload.size();
    auto u32=[&](){uint32_t v=uint32_t(data[p])|uint32_t(data[p+1])<<8|uint32_t(data[p+2])<<16|uint32_t(data[p+3])<<24;p+=4;return v;};
    uint32_t count=u32(),length=u32();if(count>256||length>n-p)return false;
    Dictionary storage;auto blocks=payload.slice(p,p+length);p+=length;if(!parse_block_payload(blocks,result?&storage:nullptr,mode))return false;
    Dictionary models;String previous;
    for(uint32_t i=0;i<count;i++) {
        if(p+4>n)return false;length=u32();if(length>n-p)return false;
        auto model=payload.slice(p,p+length);p+=length;String asset;
        PackedByteArray checkpoint;
        if((!NativeStaticBatch::parse(model,asset,nullptr)&&!(mode==REFERENCE&&parse_model_reference(model,asset,checkpoint))&&!((mode==STORAGE||mode==CHECKPOINT_STORAGE)&&parse_model_storage(model,asset)))||!assets.count(asset)||(i&&!(previous<asset)))return false;
        previous=asset;if(result)models[asset]=model;
    }
    if(p!=n)return false;
    if(result){if(mode==STORAGE||mode==CHECKPOINT_STORAGE)*result=storage;else (*result)[mode==REFERENCE?"checkpoint":"blocks"]=blocks;(*result)["ok"]=true;(*result)["models"]=models;}
    return true;
}
const char *NativeStructuresSnapshot::magic(Mode mode) {
    switch(mode){case RESIDENT:return "TFSB\1\0\0\0";case REFERENCE:return "TFSR\1\0\0\0";case STORAGE:return "TFSP\1\0\0\0";case CHECKPOINT_STORAGE:return "TFSQ\1\0\0\0";}
    return "";
}
bool NativeStructuresSnapshot::parse_block_payload(const PackedByteArray &bytes,Dictionary *result,Mode mode) const {
    if(mode==RESIDENT)return NativeBlockWorld::parse(bytes,nullptr);
    if(mode==REFERENCE)return bytes.size()==32;
    const bool based=mode==CHECKPOINT_STORAGE;
    if(based&&bytes.size()<32)return false;
    if(!parse_storage(based?bytes.slice(32):bytes,result))return false;
    if(result)(*result)["checkpoint"]=based?bytes.slice(0,32):PackedByteArray();
    return true;
}
// TFSP is an in-memory save envelope, never a standalone published world.
// The inner payload is length/count, resident TFBL, then sorted xyz/digest records.
bool NativeStructuresSnapshot::parse_storage(const PackedByteArray &payload,Dictionary *result) const {
    if(payload.size()<8||payload.size()>LIMIT)return false;
    const int64_t length=payload.decode_u32(0),count=payload.decode_u32(4);
    if(count>65536||8+length+count*44!=payload.size())return false;
    auto resident=payload.slice(8,8+length);
    std::map<BlockKey,BlockChunk> chunks;
    if(!NativeBlockWorld::parse(resident,&chunks))return false;
    std::set<BlockKey> occupied;
    for(const auto &entry:chunks)occupied.insert(NativeBlockWorld::region_for(entry.first));
    if(occupied.size()+count>65536)return false;
    PackedInt32Array keys;PackedByteArray checksums;
    if(result){keys.resize(count*3);checksums.resize(count*32);}
    BlockKey previous;
    for(int64_t i=0;i<count;++i) {
        const int64_t offset=8+length+i*44;
        BlockKey key{int(payload.decode_s32(offset)),int(payload.decode_s32(offset+4)),int(payload.decode_s32(offset+8))};
        if(!NativeBlockWorld::valid_region(key)||(i&&!(previous<key))||occupied.count(key))return false;
        previous=key;
        if(result){keys.set(i*3,key.x);keys.set(i*3+1,key.y);keys.set(i*3+2,key.z);std::memcpy(checksums.ptrw()+i*32,payload.ptr()+offset+12,32);}
    }
    if(result){(*result)["resident"]=resident;(*result)["unavailable_keys"]=keys;(*result)["unavailable_checksums"]=checksums;}
    return true;
}
PackedByteArray NativeStructuresSnapshot::encode_storage(const PackedByteArray &resident,const PackedInt32Array &keys,const PackedByteArray &checksums,const Dictionary &models,const PackedByteArray &checkpoint) const {
    if((checkpoint.size()!=0&&checkpoint.size()!=32)||keys.size()%3||keys.size()/3>65536||checksums.size()!=keys.size()/3*32)return {};
    const int64_t count=keys.size()/3,size=8+resident.size()+count*44;
    if(size+checkpoint.size()>LIMIT-48)return {};
    PackedByteArray payload;payload.resize(size);payload.encode_u32(0,resident.size());payload.encode_u32(4,count);
    if(resident.size())std::memcpy(payload.ptrw()+8,resident.ptr(),resident.size());
    for(int64_t i=0;i<count;++i){const int64_t offset=8+resident.size()+i*44;for(int j=0;j<3;++j)payload.encode_s32(offset+j*4,keys[i*3+j]);std::memcpy(payload.ptrw()+offset+12,checksums.ptr()+i*32,32);}
    if(checkpoint.is_empty())return encode_payload(payload,models,STORAGE);
    PackedByteArray based=checkpoint;based.append_array(payload);return encode_payload(based,models,CHECKPOINT_STORAGE);
}
PackedByteArray NativeStructuresSnapshot::encode_metadata(const PackedByteArray &checkpoint,const PackedInt32Array &keys,const PackedByteArray &checksums,const Dictionary &models) const {
    if(checkpoint.size()!=32)return {};
    return encode_storage(NativeBlockWorld::encode_chunks({}),keys,checksums,models,checkpoint);
}
Dictionary NativeStructuresSnapshot::decode_storage(const PackedByteArray &bytes) const {
    Dictionary result;result["ok"]=false;if(!parse(bytes,&result,STORAGE))parse(bytes,&result,CHECKPOINT_STORAGE);return result;
}
Dictionary NativeStructuresSnapshot::decode(const PackedByteArray &bytes) const {
    Dictionary result;result["ok"]=false;parse(bytes,&result);return result;
}
Dictionary NativeStructuresSnapshot::decode_reference(const PackedByteArray &bytes) const {
    Dictionary result;result["ok"]=false;parse(bytes,&result,REFERENCE);return result;
}
}
