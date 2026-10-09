// SPDX-License-Identifier: 0BSD
#include "model_region_io.hpp"
#include <godot_cpp/core/class_db.hpp>
namespace terraforest {
void NativeModelRegionIO::_bind_methods() {
    ClassDB::bind_method(D_METHOD("start","absolute_directory","asset_id","request_limit","byte_limit","recover_backup"),&NativeModelRegionIO::start,DEFVAL(false));
    ClassDB::bind_method(D_METHOD("read_region","region"),&NativeModelRegionIO::read_region);
    ClassDB::bind_method(D_METHOD("publish_regions","packets","expected_checksums"),&NativeModelRegionIO::publish_regions);
    ClassDB::bind_method(D_METHOD("publish_storage_state","resident","unavailable_keys","unavailable_checksums","checkpoint"),&NativeModelRegionIO::publish_storage_state,DEFVAL(PackedByteArray()));
    ClassDB::bind_method(D_METHOD("read_checkpoint","checkpoint"),&NativeModelRegionIO::read_checkpoint);
    ClassDB::bind_method(D_METHOD("pin_checkpoint"),&NativeModelRegionIO::pin_checkpoint);
    ClassDB::bind_method(D_METHOD("checkpoint_regions","checkpoint"),&NativeModelRegionIO::checkpoint_regions);
    ClassDB::bind_method(D_METHOD("read_checkpoint_region","checkpoint","region"),&NativeModelRegionIO::read_checkpoint_region);
    ClassDB::bind_method(D_METHOD("activate_checkpoint","checkpoint"),&NativeModelRegionIO::activate_checkpoint);
    ClassDB::bind_method(D_METHOD("release_checkpoint","checkpoint"),&NativeModelRegionIO::release_checkpoint);
    ClassDB::bind_method(D_METHOD("collect_garbage","max_inspected"),&NativeModelRegionIO::collect_garbage);
    ClassDB::bind_method(D_METHOD("list_regions"),&NativeModelRegionIO::list_regions);
    ClassDB::bind_method(D_METHOD("list_checkpoints"),&NativeModelRegionIO::list_checkpoints);
    ClassDB::bind_method(D_METHOD("remove_region","region","expected_checksum"),&NativeModelRegionIO::remove_region);
    ClassDB::bind_method(D_METHOD("poll","max_results"),&NativeModelRegionIO::poll,DEFVAL(16));
    ClassDB::bind_method(D_METHOD("request_stop"),&NativeModelRegionIO::request_stop);
    ClassDB::bind_method(D_METHOD("join"),&NativeModelRegionIO::join);
    ClassDB::bind_method(D_METHOD("stats"),&NativeModelRegionIO::stats);
}
}
