// SPDX-License-Identifier: 0BSD
#pragma once
#include "block_region_store.hpp"
namespace terraforest {
// Asset-specific facade over the shared leased, checksummed catalog engine.
// Deliberately does not expose block snapshot encoding or reconstruction APIs.
class NativeModelRegionStore : public RefCounted {
    GDCLASS(NativeModelRegionStore,RefCounted)
    Ref<NativeBlockRegionStore> store_;
    std::mutex lifecycle_;
protected:
    static void _bind_methods();
public:
    NativeModelRegionStore(){store_.instantiate();}
    Dictionary open_store(const String &path,const String &asset,bool recover_backup=false);
    void close(){std::lock_guard<std::mutex> lock(lifecycle_);store_->close();}
    Dictionary stats() const{return store_->stats();}
    Dictionary publish_snapshot(const PackedByteArray &snapshot){return store_->publish_model_snapshot(snapshot);}
    Dictionary read_checkpoint(const PackedByteArray &checkpoint) const{return store_->read_model_checkpoint(checkpoint);}
    PackedInt32Array list_regions() const{return store_->list_regions();}
    PackedByteArray checksum(Vector3i region) const{return store_->checksum(region);}
    Dictionary read_region(Vector3i region) const{return store_->read_region(region);}
    Dictionary publish_region(const PackedByteArray &bytes,const PackedByteArray &expected){return store_->publish_region(bytes,expected);}
    Dictionary publish_regions(const Array &bytes,const Array &expected){return store_->publish_regions(bytes,expected);}
    Dictionary remove_region(Vector3i region,const PackedByteArray &expected){return store_->remove_region(region,expected);}
    Dictionary collect_garbage(int budget){return store_->collect_garbage(budget);}
    Dictionary pin_checkpoint(){return store_->pin_checkpoint();}
    PackedByteArray list_checkpoints() const{return store_->list_checkpoints();}
    Dictionary checkpoint_regions(const PackedByteArray &checkpoint) const{return store_->checkpoint_regions(checkpoint);}
    Dictionary read_checkpoint_region(const PackedByteArray &checkpoint,Vector3i region) const{return store_->read_checkpoint_region(checkpoint,region);}
    Dictionary activate_checkpoint(const PackedByteArray &checkpoint){return store_->activate_checkpoint(checkpoint);}
    Dictionary release_checkpoint(const PackedByteArray &checkpoint){return store_->release_checkpoint(checkpoint);}
};
}
