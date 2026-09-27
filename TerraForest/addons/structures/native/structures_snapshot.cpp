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
void NativeStructuresSnapshot::_bind_methods() {
    ClassDB::bind_method(D_METHOD("configure_assets","asset_ids"),&NativeStructuresSnapshot::configure_assets);
    ClassDB::bind_method(D_METHOD("encode","blocks","models"),&NativeStructuresSnapshot::encode);
    ClassDB::bind_method(D_METHOD("decode","bytes"),&NativeStructuresSnapshot::decode);
    ClassDB::bind_method(D_METHOD("validate_snapshot","bytes"),&NativeStructuresSnapshot::validate_snapshot);
}
bool NativeStructuresSnapshot::configure_assets(const PackedStringArray &ids) {
    if(configured||ids.size()>256)return false;
    std::set<String> selected;
    for(auto id:ids)if(!NativeStaticBatch::valid_asset(id)||!selected.insert(id).second)return false;
    assets=std::move(selected);configured=true;return true;
}
PackedByteArray NativeStructuresSnapshot::encode(const PackedByteArray &blocks,const Dictionary &models) const {
    if(!configured||models.size()!=int64_t(assets.size())||!NativeBlockWorld::parse(blocks,nullptr))return {};
    int64_t size=16+blocks.size()+32;
    for(auto asset:assets) {
        if(!models.has(asset)||models[asset].get_type()!=Variant::PACKED_BYTE_ARRAY)return {};
        PackedByteArray value=models[asset];String parsed;
        if(!NativeStaticBatch::parse(value,parsed,nullptr)||parsed!=asset)return {};
        size+=4+value.size();if(size>LIMIT)return {};
    }
    if(size>LIMIT)return {};
    PackedByteArray result;result.resize(size-32);uint8_t *out=result.ptrw();std::memcpy(out,"TFSB\1\0\0\0",8);
    int64_t cursor=8;
    auto u32=[&](uint32_t n){for(int i=0;i<4;i++)out[cursor++]=uint8_t(n>>(8*i));};
    auto copy=[&](const PackedByteArray &bytes){std::memcpy(out+cursor,bytes.ptr(),bytes.size());cursor+=bytes.size();};
    u32(uint32_t(assets.size()));u32(uint32_t(blocks.size()));copy(blocks);
    for(auto asset:assets){PackedByteArray bytes=models[asset];u32(uint32_t(bytes.size()));copy(bytes);}
    result.append_array(digest(result));return result;
}
bool NativeStructuresSnapshot::parse(const PackedByteArray &bytes,Dictionary *result) const {
    if(!configured||bytes.size()<48||bytes.size()>LIMIT||std::memcmp(bytes.ptr(),"TFSB\1\0\0\0",8))return false;
    auto payload=bytes.slice(0,bytes.size()-32);if(digest(payload)!=bytes.slice(bytes.size()-32))return false;
    const uint8_t *data=payload.ptr();int64_t p=8,n=payload.size();
    auto u32=[&](){uint32_t v=uint32_t(data[p])|uint32_t(data[p+1])<<8|uint32_t(data[p+2])<<16|uint32_t(data[p+3])<<24;p+=4;return v;};
    uint32_t count=u32(),length=u32();if(count>256||length>n-p)return false;
    auto blocks=payload.slice(p,p+length);p+=length;if(!NativeBlockWorld::parse(blocks,nullptr))return false;
    Dictionary models;String previous;
    for(uint32_t i=0;i<count;i++) {
        if(p+4>n)return false;length=u32();if(length>n-p)return false;
        auto model=payload.slice(p,p+length);p+=length;String asset;
        if(!NativeStaticBatch::parse(model,asset,nullptr)||!assets.count(asset)||(i&&!(previous<asset)))return false;
        previous=asset;if(result)models[asset]=model;
    }
    if(p!=n)return false;
    if(result){(*result)["ok"]=true;(*result)["blocks"]=blocks;(*result)["models"]=models;}
    return true;
}
Dictionary NativeStructuresSnapshot::decode(const PackedByteArray &bytes) const {
    Dictionary result;result["ok"]=false;parse(bytes,&result);return result;
}
}
