// SPDX-License-Identifier: 0BSD
#include "model_region_store.hpp"
#include <godot_cpp/core/class_db.hpp>
namespace terraforest {
void NativeModelRegionStore::_bind_methods() {
    ClassDB::bind_method(D_METHOD("publish_snapshot","snapshot"),&NativeModelRegionStore::publish_snapshot);
    ClassDB::bind_method(D_METHOD("read_checkpoint","checkpoint"),&NativeModelRegionStore::read_checkpoint);
    ClassDB::bind_method(D_METHOD("open_store","absolute_directory","asset_id","recover_backup"),&NativeModelRegionStore::open_store,DEFVAL(false));
    ClassDB::bind_method(D_METHOD("close"),&NativeModelRegionStore::close);
    ClassDB::bind_method(D_METHOD("stats"),&NativeModelRegionStore::stats);
    ClassDB::bind_method(D_METHOD("list_regions"),&NativeModelRegionStore::list_regions);
    ClassDB::bind_method(D_METHOD("checksum","region"),&NativeModelRegionStore::checksum);
    ClassDB::bind_method(D_METHOD("read_region","region"),&NativeModelRegionStore::read_region);
    ClassDB::bind_method(D_METHOD("publish_region","packet","expected_checksum"),&NativeModelRegionStore::publish_region);
    ClassDB::bind_method(D_METHOD("publish_regions","packets","expected_checksums"),&NativeModelRegionStore::publish_regions);
    ClassDB::bind_method(D_METHOD("remove_region","region","expected_checksum"),&NativeModelRegionStore::remove_region);
    ClassDB::bind_method(D_METHOD("collect_garbage","max_inspected"),&NativeModelRegionStore::collect_garbage);
    ClassDB::bind_method(D_METHOD("pin_checkpoint"),&NativeModelRegionStore::pin_checkpoint);
    ClassDB::bind_method(D_METHOD("list_checkpoints"),&NativeModelRegionStore::list_checkpoints);
    ClassDB::bind_method(D_METHOD("checkpoint_regions","checkpoint"),&NativeModelRegionStore::checkpoint_regions);
    ClassDB::bind_method(D_METHOD("read_checkpoint_region","checkpoint","region"),&NativeModelRegionStore::read_checkpoint_region);
    ClassDB::bind_method(D_METHOD("activate_checkpoint","checkpoint"),&NativeModelRegionStore::activate_checkpoint);
    ClassDB::bind_method(D_METHOD("release_checkpoint","checkpoint"),&NativeModelRegionStore::release_checkpoint);
}
Dictionary NativeModelRegionStore::open_store(const String &path,const String &asset,bool recover_backup) {
    std::lock_guard<std::mutex> lock(lifecycle_);
    if(!store_->set_model_asset(asset)) {
        Dictionary out;out["ok"]=false;out["error"]=int(ERR_INVALID_PARAMETER);
        out["message"]="Use a closed store and a valid model asset identity.";return out;
    }
    return store_->open_store(path,recover_backup);
}
}
