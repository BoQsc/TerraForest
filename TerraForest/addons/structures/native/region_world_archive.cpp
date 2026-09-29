// SPDX-License-Identifier: 0BSD
#include "region_world_archive.hpp"
#include <godot_cpp/classes/dir_access.hpp>
#include <godot_cpp/classes/file_access.hpp>
#include <godot_cpp/core/class_db.hpp>

namespace terraforest {
void NativeRegionWorldArchive::_bind_methods() {
    ClassDB::bind_method(D_METHOD("configure","archive","structures_codec"),&NativeRegionWorldArchive::configure);
    ClassDB::bind_method(D_METHOD("acquire","absolute_path"),&NativeRegionWorldArchive::acquire);
    ClassDB::bind_method(D_METHOD("release"),&NativeRegionWorldArchive::release);
    ClassDB::bind_method(D_METHOD("encode","sections"),&NativeRegionWorldArchive::encode);
    ClassDB::bind_method(D_METHOD("decode","bytes"),&NativeRegionWorldArchive::decode);
    ClassDB::bind_method(D_METHOD("read","absolute_path"),&NativeRegionWorldArchive::read);
    ClassDB::bind_method(D_METHOD("publish","absolute_path","bytes"),&NativeRegionWorldArchive::publish);
    ClassDB::bind_method(D_METHOD("storage_stats"),&NativeRegionWorldArchive::storage_stats);
}
NativeRegionWorldArchive::~NativeRegionWorldArchive(){release();}
bool NativeRegionWorldArchive::configure(const Ref<RefCounted> &archive,const Ref<NativeStructuresSnapshot> &codec) {
    if(archive_.is_valid()||archive.is_null()||codec.is_null()||archive->get_class()!=StringName("NativeWorldArchive"))return false;
    archive_=archive;codec_=codec;return true;
}
bool NativeRegionWorldArchive::acquire(const String &path) {
    if(archive_.is_null()||!path_.is_empty()||!path.is_absolute_path()||path.begins_with("res://")||path.begins_with("user://"))return false;
    if(!bool(archive_->call("acquire",path)))return false;
    const String directory=path+String(".regions");
    // Never recreate a missing sidecar for an already checkpoint-based root.
    if(!DirAccess::dir_exists_absolute(directory)&&FileAccess::file_exists(path)) {
        PackedByteArray bytes=archive_->call("read",path);Dictionary root=archive_->call("decode",bytes);
        if(bool(root.get("ok",false))) {
            Dictionary sections=root["sections"];
            if(sections.has("structures")&&bool(codec_->decode_reference(sections["structures"])["ok"])) {archive_->call("release");return false;}
        }
    }
    if(DirAccess::make_dir_recursive_absolute(directory)!=OK){archive_->call("release");return false;}
    store_.instantiate();Dictionary opened=store_->open_store(directory);
    if(!bool(opened["ok"])){store_.unref();archive_->call("release");return false;}
    path_=path;return true;
}
void NativeRegionWorldArchive::release() {
    if(store_.is_valid()){store_->close();store_.unref();}
    if(!path_.is_empty()&&archive_.is_valid())archive_->call("release");path_=String();
}
PackedByteArray NativeRegionWorldArchive::encode(const Dictionary &sections) const {
    if(archive_.is_null())return {};return archive_->call("encode",sections);
}
PackedByteArray NativeRegionWorldArchive::read(const String &path) const {
    if(archive_.is_null())return {};return archive_->call("read",path);
}
Dictionary NativeRegionWorldArchive::decode(const PackedByteArray &bytes) const {
    Dictionary failed;failed["ok"]=false;if(archive_.is_null())return failed;
    Dictionary root=archive_->call("decode",bytes);if(!bool(root.get("ok",false)))return root;
    Dictionary sections=root["sections"];if(!sections.has("structures"))return root;
    PackedByteArray structure=sections["structures"];
    Dictionary reference=codec_->decode_reference(structure);
    if(!bool(reference["ok"]))return codec_->validate_snapshot(structure)?root:failed;
    if(store_.is_null())return failed;
    Dictionary restored=store_->read_block_checkpoint(reference["checkpoint"]);
    if(!bool(restored["ok"]))return failed;
    // Older saved bundles may omit newly registered model assets. Preserve that
    // schema behavior using the reference's own registered subset codec.
    Dictionary models=reference["models"];PackedStringArray ids;Array keys=models.keys();
    for(int64_t i=0;i<keys.size();++i)ids.push_back(keys[i]);
    Ref<NativeStructuresSnapshot> subset;subset.instantiate();if(!subset->configure_assets(ids))return failed;
    PackedByteArray resident=subset->encode(restored["blocks"],models);
    if(resident.is_empty()||!codec_->validate_snapshot(resident))return failed;
    sections["structures"]=resident;root["sections"]=sections;return root;
}
bool NativeRegionWorldArchive::reference_in_file(const String &path,std::set<String> &keep) const {
    if(!FileAccess::file_exists(path))return true;
    PackedByteArray bytes=archive_->call("read",path);
    // Legacy terrain-only save; the terrain decoder remains responsible for its
    // semantic validation. It cannot hold a region checkpoint reference.
    if(bytes.size()>=4&&bytes.decode_u32(0)==0x32575254)return true;
    Dictionary root=archive_->call("decode",bytes);if(!bool(root.get("ok",false)))return false;
    Dictionary sections=root["sections"];if(!sections.has("structures"))return true;
    Dictionary reference=codec_->decode_reference(sections["structures"]);
    if(!bool(reference["ok"]))return codec_->validate_snapshot(sections["structures"]);
    PackedByteArray id=reference["checkpoint"];
    if(!bool(store_->checkpoint_regions(id)["ok"]))return false;
    keep.insert(id.hex_encode());return true;
}
bool NativeRegionWorldArchive::retire_unreferenced() {
    std::set<String> keep;
    if(!reference_in_file(path_,keep)||!reference_in_file(path_+String(".bak"),keep))return false;
    const PackedByteArray pins=store_->list_checkpoints();
    for(int64_t i=0;i<pins.size();i+=32) {
        auto id=pins.slice(i,i+32);if(!keep.count(id.hex_encode())&&!bool(store_->release_checkpoint(id)["ok"]))return false;
    }
    return true;
}
int64_t NativeRegionWorldArchive::publish(const String &path,const PackedByteArray &bytes) {
    if(path_!=path||path_.is_empty()||store_.is_null())return ERR_UNCONFIGURED;
    Dictionary root=archive_->call("decode",bytes);if(!bool(root.get("ok",false)))return ERR_INVALID_DATA;
    Dictionary sections=root["sections"];
    if(!sections.has("structures"))return ERR_INVALID_DATA;
    Dictionary structure=codec_->decode(sections["structures"]);if(!bool(structure["ok"]))return ERR_INVALID_DATA;
    // Failed previous saves can leave extra pins. Retire only after validating
    // both published roots, before allocating another pin.
    if(!retire_unreferenced())return ERR_FILE_CORRUPT;
    Dictionary published=store_->publish_block_snapshot(structure["blocks"]);if(!bool(published["ok"]))return published["error"];
    Dictionary pin=store_->pin_checkpoint();if(!bool(pin["ok"]))return pin["error"];
    Dictionary models=structure["models"];PackedStringArray ids;Array keys=models.keys();for(int64_t i=0;i<keys.size();++i)ids.push_back(keys[i]);
    Ref<NativeStructuresSnapshot> subset;subset.instantiate();if(!subset->configure_assets(ids))return ERR_INVALID_DATA;
    PackedByteArray reference=subset->encode_reference(pin["checkpoint"],models);if(reference.is_empty())return ERR_INVALID_DATA;
    sections["structures"]=reference;PackedByteArray compact=archive_->call("encode",sections);if(compact.is_empty())return ERR_INVALID_DATA;
    int64_t error=archive_->call("publish",path,compact);if(error!=OK)return error;
    // Publication already succeeded. Cleanup failure must never masquerade as a
    // failed commit; retain safe excess data and retry on the next save.
    if(retire_unreferenced())store_->collect_garbage(32);
    return OK;
}
Dictionary NativeRegionWorldArchive::storage_stats() const {
    Dictionary out;if(store_.is_valid())out=store_->stats();else out["open"]=false;return out;
}
}
