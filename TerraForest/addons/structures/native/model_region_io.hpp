// SPDX-License-Identifier: 0BSD
#pragma once
#include "block_region_io.hpp"
namespace terraforest {
class NativeModelRegionIO : public RefCounted {
    GDCLASS(NativeModelRegionIO,RefCounted)
    Ref<NativeBlockRegionIO> queue_;
protected:
    static void _bind_methods();
public:
    NativeModelRegionIO(){queue_.instantiate();}
    int64_t start(const String &path,const String &asset,int requests,int64_t bytes,bool recover=false){return asset.is_empty()?0:queue_->start_impl(path,requests,bytes,recover,asset);}
    int64_t read_region(Vector3i key){return queue_->read_region(key);}
    int64_t publish_regions(const Array &packets,const Array &expected){return queue_->publish_regions(packets,expected);}
    int64_t publish_storage_state(const PackedByteArray &resident,const PackedInt32Array &keys,const PackedByteArray &checksums,const PackedByteArray &checkpoint=PackedByteArray()){return queue_->publish_model_state(resident,keys,checksums,checkpoint);}
    int64_t read_checkpoint(const PackedByteArray &checkpoint){return queue_->read_model_snapshot(checkpoint);}
    int64_t pin_checkpoint(){return queue_->pin_checkpoint();}
    int64_t checkpoint_regions(const PackedByteArray &checkpoint){return queue_->checkpoint_regions(checkpoint);}
    int64_t read_checkpoint_region(const PackedByteArray &checkpoint,Vector3i key){return queue_->read_checkpoint_region(checkpoint,key);}
    int64_t activate_checkpoint(const PackedByteArray &checkpoint){return queue_->activate_checkpoint(checkpoint);}
    int64_t release_checkpoint(const PackedByteArray &checkpoint){return queue_->release_checkpoint(checkpoint);}
    int64_t collect_garbage(int budget){return queue_->collect_garbage(budget);}
    int64_t list_regions(){return queue_->list_regions();}
    int64_t list_checkpoints(){return queue_->list_checkpoints();}
    int64_t remove_region(Vector3i key,const PackedByteArray &expected){return queue_->remove_region(key,expected);}
    Array poll(int count=16){return queue_->poll(count);}
    void request_stop(){queue_->request_stop();}
    void join(){queue_->join();}
    Dictionary stats() const{return queue_->stats();}
};
}
