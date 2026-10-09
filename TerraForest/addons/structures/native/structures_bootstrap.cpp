// SPDX-License-Identifier: 0BSD
#include "structures_snapshot.hpp"
#include "static_batch.hpp"
#include "block_world.hpp"

namespace terraforest {
using namespace godot;
bool NativeStructuresSnapshot::parse_model_metadata(const PackedByteArray &bytes,String &asset) const {
    PackedByteArray checkpoint;std::map<BlockKey,NativeStaticBatch::MetadataRegion> regions;std::set<int64_t> ids;
    return NativeStaticBatch::parse_metadata(bytes,asset,checkpoint,regions,ids);
}
PackedByteArray NativeStructuresSnapshot::encode_bootstrap(const PackedByteArray &checkpoint,const PackedInt32Array &keys,const PackedByteArray &checksums,const Dictionary &models) const {
    // Reuse the canonical block-storage encoding without accepting startup
    // metadata as an ordinary save envelope. TFSU is scene bootstrap only.
    Ref<NativeStructuresSnapshot> blocks;blocks.instantiate();blocks->configure_assets(PackedStringArray());
    PackedByteArray encoded=blocks->encode_metadata(checkpoint,keys,checksums,Dictionary());
    if(encoded.is_empty())return {};
    return encode_payload(encoded.slice(16,16+encoded.decode_u32(12)),models,BOOTSTRAP);
}
Dictionary NativeStructuresSnapshot::decode_bootstrap(const PackedByteArray &bytes) const {
    Dictionary result;result["ok"]=false;parse(bytes,&result,BOOTSTRAP);return result;
}
bool NativeStructuresSnapshot::restore_bootstrap(const PackedByteArray &bytes,NativeBlockWorld *blocks,const Dictionary &collections) {
    if(restore_busy||!blocks||collections.size()!=int64_t(assets.size()))return false;
    Dictionary decoded=decode_bootstrap(bytes);if(!bool(decoded["ok"]))return false;
    Dictionary models=decoded["models"];
    struct Prepared {
        NativeStaticBatch *batch=nullptr;
        std::map<BlockKey,NativeStaticBatch::UnloadedRegion> regions;
        std::set<int64_t> ids;
        uint64_t object_id=0;
        bool blocked=false;
    };
    std::vector<Prepared> prepared;prepared.reserve(assets.size());
    for(const auto &asset:assets) {
        if(!collections.has(asset))return false;
        Object *object=collections[asset];auto *batch=Object::cast_to<NativeStaticBatch>(object);
        if(!batch||batch->asset_id!=asset||batch->source_mesh.is_null()||batch->admission||batch->defer_change_signal||
           (batch->paging_owner&&ObjectDB::get_instance(batch->paging_owner)))return false;
        Prepared stage;stage.batch=batch;stage.object_id=batch->get_instance_id();stage.blocked=batch->is_blocking_signals();
        if(models.has(asset)&&!batch->prepare_metadata(models[asset],stage.regions,stage.ids))return false;
        prepared.push_back(std::move(stage));
    }
    std::map<BlockKey,BlockChunk> resident;
    if(!NativeBlockWorld::parse(decoded["resident"],&resident))return false;
    PackedInt32Array keys=decoded["unavailable_keys"];PackedByteArray checksums=decoded["unavailable_checksums"];
    std::map<BlockKey,PackedByteArray> unavailable;
    for(int64_t i=0;i<keys.size()/3;++i)unavailable.emplace(BlockKey{keys[i*3],keys[i*3+1],keys[i*3+2]},checksums.slice(i*32,(i+1)*32));
    // All bytes, identities, activity guards and prototype-dependent bounds are
    // validated before either blocks or models change. Suppress change observers
    // until every collection has installed its prepared residency map.
    restore_busy=true;
    const bool block_signals=blocks->is_blocking_signals();const uint64_t block_id=blocks->get_instance_id();
    blocks->set_block_signals(true);
    for(auto &stage:prepared)stage.batch->set_block_signals(true);
    blocks->replace_storage(std::move(resident),std::move(unavailable));
    for(auto &stage:prepared) {
        stage.batch->install_metadata(std::move(stage.regions),std::move(stage.ids));
        stage.batch->paging_checkpoint.reset();
    }
    blocks->set_block_signals(block_signals);
    for(auto &stage:prepared)stage.batch->set_block_signals(stage.blocked);
    // Publication observers may destroy nodes; resolve weak identities afresh.
    if(auto *world=ObjectDB::get_instance(block_id))world->emit_signal("changed");
    for(auto &stage:prepared)if(auto *batch=ObjectDB::get_instance(stage.object_id))batch->emit_signal("changed");
    restore_busy=false;return true;
}
}
