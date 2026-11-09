// SPDX-License-Identifier: 0BSD
#include "structures_capture.hpp"
#include <godot_cpp/classes/os.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <chrono>
#include <cstring>
using namespace godot;
namespace terraforest {
std::atomic<uint64_t> NativeStructuresCapture::pending_bytes{0};
void NativeStructuresCapture::_bind_methods(){
    ClassDB::bind_method(D_METHOD("serialize_snapshot"),&NativeStructuresCapture::serialize_snapshot);
    ClassDB::bind_method(D_METHOD("stats"),&NativeStructuresCapture::stats);
}
NativeStructuresCapture::~NativeStructuresCapture(){release_frozen();}
void NativeStructuresCapture::release_frozen(){
    // Return the reservation only after releasing its actual frozen buffers.
    std::vector<Chunk>().swap(chunks);std::vector<Region>().swap(missing);std::vector<Model>().swap(models);
    checkpoint=PackedByteArray();codec.unref();
    const uint64_t bytes=reserved_bytes.exchange(0);if(bytes)pending_bytes.fetch_sub(bytes);
}
void NativeStructuresCapture::region_arrays(const std::vector<Region> &regions,PackedInt32Array &keys,PackedByteArray &checksums){
    keys.resize(regions.size()*3);checksums.resize(regions.size()*32);
    auto *out=keys.ptrw();auto *digest=checksums.ptrw();
    for(size_t i=0;i<regions.size();++i){
        const auto &r=regions[i];out[i*3]=r.key.x;out[i*3+1]=r.key.y;out[i*3+2]=r.key.z;
        std::memcpy(digest+i*32,r.checksum.data(),32);
    }
}
PackedByteArray NativeStructuresCapture::serialize_snapshot(){
    if(!complete)return {};
    std::lock_guard<std::mutex> lock(serialization_mutex);
    if(!serialized_ready.load()){
        serialized_bytes=encode_frozen();serialized_bytes_count.store(serialized_bytes.size());
        release_frozen();serialized_ready.store(true);
    }
    return serialized_bytes;
}
PackedByteArray NativeStructuresCapture::encode_frozen() const {
    if(!complete||codec.is_null())return {};
    // Rebuild encoder inputs from frozen values on the worker. Existing codecs
    // remain the one authority for canonical formats, limits and validation.
    std::map<BlockKey,BlockChunk> blocks;
    for(const auto &chunk:chunks)blocks[chunk.key].cells=chunk.cells;
    const auto resident=NativeBlockWorld::encode_chunks(blocks);
    Dictionary encoded;bool fully_resident=missing.empty();
    for(const auto &model:models){
        std::map<int64_t,NativeStaticBatch::Placement> placements;
        for(const auto &record:model.records)placements.emplace_hint(placements.end(),record.id,record.transform);
        auto bytes=NativeStaticBatch::encode_placements(model.asset,placements);
        if(!model.missing.empty()){
            fully_resident=false;PackedInt32Array keys;PackedByteArray checksums;
            region_arrays(model.missing,keys,checksums);
            bytes=codec->encode_model_storage(bytes,keys,checksums);
        }
        if(bytes.is_empty())return {};
        encoded[model.asset]=bytes;
    }
    if(fully_resident)return codec->encode(resident,encoded);
    PackedInt32Array keys;PackedByteArray checksums;region_arrays(missing,keys,checksums);
    return codec->encode_storage(resident,keys,checksums,encoded,checkpoint);
}
Dictionary NativeStructuresCapture::stats() const {
    Dictionary out;out["complete"]=complete;out["capture_us"]=int64_t(capture_us);
    out["chunks"]=int64_t(captured_chunks);out["model_collections"]=int64_t(captured_models);
    out["model_records"]=int64_t(model_records);out["missing_regions"]=int64_t(missing_regions);
    out["capture_bytes"]=int64_t(capture_bytes);out["reserved_bytes"]=int64_t(reserved_bytes.load());out["pending_bytes"]=int64_t(pending_bytes.load());
    out["serialized"]=serialized_ready.load();out["serialized_bytes"]=int64_t(serialized_bytes_count.load());
    out["pending_limit_bytes"]=int64_t(LIMIT);return out;
}
Ref<NativeStructuresCapture> NativeStructuresSnapshot::capture_save_snapshot(NativeBlockWorld *blocks,const Dictionary &collections,const PackedByteArray &checkpoint) const {
    const auto began=std::chrono::steady_clock::now();
    auto os=OS::get_singleton();
    if(!os||os->get_thread_caller_id()!=os->get_main_thread_id()||!configured||!blocks||
       collections.size()!=int64_t(assets.size())||(checkpoint.size()!=0&&checkpoint.size()!=32))return {};
    // Conservative payload accounting includes container/asset overhead. It is
    // a bound for retained captures, not for temporary encoder allocations.
    uint64_t bytes=sizeof(NativeStructuresCapture)+checkpoint.size()+
        blocks->chunks.size()*sizeof(NativeStructuresCapture::Chunk)+
        blocks->unloaded_regions.size()*sizeof(NativeStructuresCapture::Region);
    std::vector<NativeStaticBatch*> owners;owners.reserve(assets.size());
    for(const auto &asset:assets){
        if(!collections.has(asset)||collections[asset].get_type()!=Variant::OBJECT)return {};
        auto owner=Object::cast_to<NativeStaticBatch>(collections[asset]);
        if(!owner||owner->asset_id!=asset)return {};
        bytes+=sizeof(NativeStructuresCapture::Model)+1024+
            owner->placements.size()*sizeof(ModelPlacementRecord)+
            owner->unloaded_regions.size()*sizeof(NativeStructuresCapture::Region);
        owners.push_back(owner);
    }
    uint64_t previous=NativeStructuresCapture::pending_bytes.load();
    do{if(bytes>NativeStructuresCapture::LIMIT||previous>NativeStructuresCapture::LIMIT-bytes)return {};}
    while(!NativeStructuresCapture::pending_bytes.compare_exchange_weak(previous,previous+bytes));
    Ref<NativeStructuresCapture> frozen;frozen.instantiate();frozen->reserved_bytes=bytes;frozen->capture_bytes=bytes;
    frozen->captured_chunks=blocks->chunks.size();frozen->captured_models=owners.size();
    frozen->codec=Ref<NativeStructuresSnapshot>(const_cast<NativeStructuresSnapshot*>(this));
    frozen->checkpoint=checkpoint;frozen->chunks.reserve(blocks->chunks.size());
    for(const auto &[key,chunk]:blocks->chunks)frozen->chunks.push_back({key,chunk.cells});
    frozen->missing.reserve(blocks->unloaded_regions.size());
    for(const auto &[key,digest]:blocks->unloaded_regions){
        if(digest.size()!=32)return {};
        NativeStructuresCapture::Region record;record.key=key;std::memcpy(record.checksum.data(),digest.ptr(),32);
        frozen->missing.push_back(record);
    }
    frozen->missing_regions=frozen->missing.size();frozen->models.reserve(owners.size());
    for(const auto *owner:owners){
        NativeStructuresCapture::Model model;model.asset=owner->asset_id;
        model.records.reserve(owner->placements.size());model.missing.reserve(owner->unloaded_regions.size());
        for(const auto &[id,pose]:owner->placements){
            // In-flight admission/retirement is represented by the complete
            // unavailable disk region, never a partly installed record prefix.
            if(owner->admission&&owner->unloaded_regions.count(NativeStaticBatch::group_for(pose)))continue;
            model.records.push_back({id,pose});
        }
        for(const auto &[key,metadata]:owner->unloaded_regions){
            if(metadata.checksum.size()!=32)return {};
            NativeStructuresCapture::Region record;record.key=key;std::memcpy(record.checksum.data(),metadata.checksum.ptr(),32);
            model.missing.push_back(record);
        }
        frozen->model_records+=model.records.size();frozen->missing_regions+=model.missing.size();
        frozen->models.push_back(std::move(model));
    }
    frozen->complete=true;
    frozen->capture_us=std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now()-began).count();
    return frozen;
}
}
