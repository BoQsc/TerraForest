// SPDX-License-Identifier: 0BSD
#include "region_world_archive.hpp"
#include <atomic>
#include <godot_cpp/classes/time.hpp>
#include <godot_cpp/classes/dir_access.hpp>
#include <godot_cpp/classes/file_access.hpp>
#include <godot_cpp/classes/hashing_context.hpp>
#include <godot_cpp/core/class_db.hpp>

namespace terraforest {
void NativeRegionWorldArchive::_bind_methods() {
    ClassDB::bind_method(D_METHOD("publication_profile"),&NativeRegionWorldArchive::publication_profile);
    ClassDB::bind_method(D_METHOD("configure_checkpoint_retention","lease_limit"),&NativeRegionWorldArchive::configure_checkpoint_retention);
    ClassDB::bind_method(D_METHOD("retain_read_checkpoint","asset","checkpoint"),&NativeRegionWorldArchive::retain_read_checkpoint);
    ClassDB::bind_method(D_METHOD("release_read_checkpoint","lease"),&NativeRegionWorldArchive::release_read_checkpoint);
    ClassDB::bind_method(D_METHOD("configure","archive","structures_codec","metadata_first","model_metadata_first","compact_initial"),&NativeRegionWorldArchive::configure,DEFVAL(false),DEFVAL(false),DEFVAL(false));
    ClassDB::bind_method(D_METHOD("acquire","absolute_path"),&NativeRegionWorldArchive::acquire);
    ClassDB::bind_method(D_METHOD("release"),&NativeRegionWorldArchive::release);
    ClassDB::bind_method(D_METHOD("encode","sections"),&NativeRegionWorldArchive::encode);
    ClassDB::bind_method(D_METHOD("decode","bytes"),&NativeRegionWorldArchive::decode);
    ClassDB::bind_method(D_METHOD("read","absolute_path"),&NativeRegionWorldArchive::read);
    ClassDB::bind_method(D_METHOD("publish","absolute_path","bytes"),&NativeRegionWorldArchive::publish);
    ClassDB::bind_method(D_METHOD("publish_sections","absolute_path","sections"),&NativeRegionWorldArchive::publish_sections);
    ClassDB::bind_method(D_METHOD("map_certificates"),&NativeRegionWorldArchive::map_certificates);
    ClassDB::bind_method(D_METHOD("validate_snapshot","bytes"),&NativeRegionWorldArchive::validate_snapshot);
    ClassDB::bind_method(D_METHOD("read_storage_region","region","expected","checkpoint"),&NativeRegionWorldArchive::read_storage_region,DEFVAL(PackedByteArray()));
    ClassDB::bind_method(D_METHOD("start_region_reads","request_limit","byte_limit"),&NativeRegionWorldArchive::start_region_reads,DEFVAL(8),DEFVAL(int64_t(8)*(2*1024*1024+96)));
    ClassDB::bind_method(D_METHOD("request_region_read","region","expected","checkpoint","epoch"),&NativeRegionWorldArchive::request_region_read);
    ClassDB::bind_method(D_METHOD("request_model_region_read","asset","region","expected","checkpoint","epoch"),&NativeRegionWorldArchive::request_model_region_read);
    ClassDB::bind_method(D_METHOD("request_checkpoint_region_read","region","expected","checkpoint","epoch"),&NativeRegionWorldArchive::request_checkpoint_region_read);
    ClassDB::bind_method(D_METHOD("request_model_checkpoint_region_read","asset","region","expected","checkpoint","epoch"),&NativeRegionWorldArchive::request_model_checkpoint_region_read);
    ClassDB::bind_method(D_METHOD("request_model_metadata","asset","checkpoint","epoch"),&NativeRegionWorldArchive::request_model_metadata);
    ClassDB::bind_method(D_METHOD("take_model_region_read","ticket"),&NativeRegionWorldArchive::take_model_region_read);
    ClassDB::bind_method(D_METHOD("request_model_survey_read","asset","region","expected","checkpoint","epoch","bounds"),&NativeRegionWorldArchive::request_model_survey_read);
    ClassDB::bind_method(D_METHOD("request_survey_region_read","region","expected","checkpoint","epoch"),&NativeRegionWorldArchive::request_survey_region_read);
    ClassDB::bind_method(D_METHOD("take_survey_region_read","ticket"),&NativeRegionWorldArchive::take_survey_region_read);
    ClassDB::bind_method(D_METHOD("request_model_render_read","asset","region","expected","checkpoint","epoch"),&NativeRegionWorldArchive::request_model_render_read);
    ClassDB::bind_method(D_METHOD("take_model_render_region_read","ticket"),&NativeRegionWorldArchive::take_model_render_region_read);
    ClassDB::bind_method(D_METHOD("discard_survey_region_read","ticket"),&NativeRegionWorldArchive::discard_survey_region_read);
    ClassDB::bind_method(D_METHOD("discard_model_region_read","ticket"),&NativeRegionWorldArchive::discard_model_region_read);
    ClassDB::bind_method(D_METHOD("poll_model_region_reads","max_results"),&NativeRegionWorldArchive::poll_model_region_reads,DEFVAL(4));
    ClassDB::bind_method(D_METHOD("poll_region_reads","max_results"),&NativeRegionWorldArchive::poll_region_reads,DEFVAL(4));
    ClassDB::bind_method(D_METHOD("stop_region_reads"),&NativeRegionWorldArchive::stop_region_reads);
    ClassDB::bind_method(D_METHOD("join_region_reads"),&NativeRegionWorldArchive::join_region_reads);
    ClassDB::bind_method(D_METHOD("region_read_stats"),&NativeRegionWorldArchive::region_read_stats);
    ClassDB::bind_method(D_METHOD("published_region_index","after_revision"),&NativeRegionWorldArchive::published_region_index,DEFVAL(0));
    ClassDB::bind_method(D_METHOD("published_model_index","asset","after_revision","retain"),&NativeRegionWorldArchive::published_model_index,DEFVAL(0),DEFVAL(false));
    ClassDB::bind_method(D_METHOD("storage_stats"),&NativeRegionWorldArchive::storage_stats);
}
NativeRegionWorldArchive::~NativeRegionWorldArchive(){release();}
bool NativeRegionWorldArchive::configure(const Ref<RefCounted> &archive,const Ref<NativeStructuresSnapshot> &codec,bool metadata_first,bool model_metadata_first,bool compact_initial) {
    if(archive_.is_valid()||archive.is_null()||codec.is_null()||archive->get_class()!=StringName("NativeWorldArchive"))return false;
    if(model_metadata_first&&!metadata_first)return false;
    archive_=archive;codec_=codec;metadata_first_=metadata_first;model_metadata_first_=model_metadata_first;compact_initial_=compact_initial;return true;
}
bool NativeRegionWorldArchive::acquire(const String &path) {
    if(archive_.is_null()||!path_.is_empty()||!path.is_absolute_path()||path.begins_with("res://")||path.begins_with("user://"))return false;
    {std::lock_guard<std::mutex> lock(read_mutex_);if(read_running_||read_outstanding_)return false;}
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
    join_region_reads();
    {std::lock_guard<std::mutex> lock(read_mutex_);published_keys_=PackedInt32Array();published_checksums_=PackedByteArray();published_checkpoint_=PackedByteArray();published_models_.clear();read_checkpoint_leases_.clear();read_checkpoint_refs_.clear();}
    if(store_.is_valid()){store_->close();store_.unref();}
    {std::lock_guard<std::mutex> lock(model_mutex_);for(auto &entry:model_stores_)entry.second->close();model_stores_.clear();model_open_mutexes_.clear();}
    if(!path_.is_empty()&&archive_.is_valid())archive_->call("release");path_=String();
}
Ref<NativeModelRegionStore> NativeRegionWorldArchive::model_store(const String &asset,bool create) const {
    // A save owns lifecycle and drains every job before release. Serialize opens
    // for the same asset, but never hold the directory-map lock during disk I/O.
    std::shared_ptr<std::mutex> asset_mutex;String root;
    {
        std::lock_guard<std::mutex> lock(model_mutex_);
        auto found=model_stores_.find(asset);if(found!=model_stores_.end())return found->second;
        if(path_.is_empty())return {};root=path_;
        auto &entry=model_open_mutexes_[asset];if(!entry)entry=std::make_shared<std::mutex>();asset_mutex=entry;
    }
    std::lock_guard<std::mutex> open(*asset_mutex);
    {std::lock_guard<std::mutex> lock(model_mutex_);auto found=model_stores_.find(asset);if(found!=model_stores_.end())return found->second;}
    Ref<HashingContext> hash;hash.instantiate();hash->start(HashingContext::HASH_SHA256);hash->update(asset.to_utf8_buffer());
    const String folder=(root+String(".models")).path_join(hash->finish().hex_encode());
    if(!create&&!FileAccess::file_exists(folder.path_join("catalog.tfrc")))return {};
    if(create&&DirAccess::make_dir_recursive_absolute(folder)!=OK)return {};
    Ref<NativeModelRegionStore> model;model.instantiate();
    if(!bool(model->open_store(folder,asset)["ok"]))return {};
    {std::lock_guard<std::mutex> lock(model_mutex_);model_stores_.emplace(asset,model);}return model;
}
PackedByteArray NativeRegionWorldArchive::encode(const Dictionary &sections) const {
    if(archive_.is_null())return {};return archive_->call("encode",sections);
}
PackedByteArray NativeRegionWorldArchive::read(const String &path) const {
    if(archive_.is_null())return {};return archive_->call("read",path);
}
Dictionary NativeRegionWorldArchive::decode(const PackedByteArray &bytes) const {
    return decode_mode(bytes,metadata_first_,model_metadata_first_);
}
Dictionary NativeRegionWorldArchive::decode_mode(const PackedByteArray &bytes,bool metadata_first,bool model_metadata_first) const {
    Dictionary failed;failed["ok"]=false;if(archive_.is_null())return failed;
    Dictionary root=archive_->call("decode",bytes);if(!bool(root.get("ok",false)))return root;
    Dictionary sections=root["sections"];if(!sections.has("structures"))return root;
    PackedByteArray structure=sections["structures"];
    Dictionary reference=codec_->decode_reference(structure);
    if(!bool(reference["ok"]))return codec_->validate_snapshot(structure)?root:failed;
    if(store_.is_null())return failed;
    Dictionary restored=metadata_first?store_->checkpoint_regions(reference["checkpoint"]):store_->read_block_checkpoint(reference["checkpoint"]);
    if(!bool(restored["ok"]))return failed;
    // Older saved bundles may omit newly registered model assets. Preserve that
    // schema behavior using the reference's own registered subset codec.
    Dictionary models=reference["models"];PackedStringArray ids;Array keys=models.keys();
    bool bootstrap=model_metadata_first;
    int64_t metadata_reads=0,metadata_hits=0,metadata_bytes=0;
    // Legacy inline model payloads retain the existing resident decode path.
    for(int64_t i=0;i<keys.size();++i) {String asset;PackedByteArray pin;if(!NativeStructuresSnapshot::parse_model_reference(models[keys[i]],asset,pin))bootstrap=false;}
    for(int64_t i=0;i<keys.size();++i) {
        String asset;PackedByteArray checkpoint;
        if(!NativeStructuresSnapshot::parse_model_reference(models[keys[i]],asset,checkpoint))continue;
        auto model=model_store(asset,false);if(model.is_null())return failed;
        Dictionary restored_model=bootstrap?model->read_metadata(checkpoint):model->read_checkpoint(checkpoint);if(!bool(restored_model["ok"]))return failed;
        models[keys[i]]=restored_model[bootstrap?"metadata":"snapshot"];
        if(bootstrap){metadata_reads+=int64_t(restored_model.get("regions_read",0));metadata_hits+=bool(restored_model.get("cache_hit",false));metadata_bytes+=PackedByteArray(restored_model["metadata"]).size();}
    }
    for(int64_t i=0;i<keys.size();++i)ids.push_back(keys[i]);
    Ref<NativeStructuresSnapshot> subset;subset.instantiate();if(!subset->configure_assets(ids))return failed;
    PackedByteArray resident=bootstrap?subset->encode_bootstrap(reference["checkpoint"],restored["keys"],restored["checksums"],models):metadata_first?subset->encode_metadata(reference["checkpoint"],restored["keys"],restored["checksums"],models):subset->encode(restored["blocks"],models);
    if(resident.is_empty()||!(bootstrap?codec_->validate_bootstrap(resident):codec_->validate_storage_snapshot(resident)))return failed;
    sections["structures"]=resident;root["sections"]=sections;
    if(bootstrap){Dictionary stats;stats["assets"]=keys.size();stats["regions_read"]=metadata_reads;stats["cache_hits"]=metadata_hits;stats["metadata_bytes"]=metadata_bytes;root["model_bootstrap"]=stats;}
    return root;
}
Dictionary NativeRegionWorldArchive::map_certificates() const {
 Dictionary out;out["ok"]=false;if(path_.is_empty()||archive_.is_null()||codec_.is_null())return out;
 PackedByteArray canonical=archive_->call("read",path_);Dictionary root=decode_mode(canonical,true,true);
 if(!bool(root.get("ok",false)))return out;Dictionary sections=root["sections"];
 if(!sections.has("structures"))return out;PackedByteArray bytes=sections["structures"];
 Dictionary bootstrap=codec_->decode_bootstrap(bytes);
 const bool resident=!bool(bootstrap.get("ok",false));
 if(resident)bootstrap=codec_->decode(bytes);
 if(!bool(bootstrap.get("ok",false)))return out;
 Dictionary models=bootstrap["models"],identities;Array keys=models.keys();
 for(int64_t i=0;i<keys.size();i++){PackedByteArray metadata=models[keys[i]];identities[keys[i]]=String(resident?"snapshot-v1|":"metadata-v1|")+metadata.slice(metadata.size()-32).hex_encode();}
 // This is the exact startup representation's identity, without constructing
 // scene nodes or changing current residency. Derived cache work can run offline.
 if(PackedByteArray(archive_->call("read",path_))!=canonical)return out;
 const PackedByteArray block_identity_bytes=resident?PackedByteArray(bootstrap["blocks"]):bytes;
 out["ok"]=true;out["blocks_identity"]=String(resident?"snapshot-v1|":"bootstrap-v1|")+block_identity_bytes.slice(block_identity_bytes.size()-32).hex_encode();out["models"]=identities;return out;
}
bool NativeRegionWorldArchive::reference_in_file(const String &path,std::set<String> &keep,std::map<String,std::set<String>> &model_keep) const {
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
    keep.insert(id.hex_encode());
    Dictionary models=reference["models"];Array keys=models.keys();
    for(int64_t i=0;i<keys.size();++i) {
        String asset;PackedByteArray checkpoint;
        if(!NativeStructuresSnapshot::parse_model_reference(models[keys[i]],asset,checkpoint))continue;
        auto model=model_store(asset,false);
        if(model.is_null()||!bool(model->checkpoint_regions(checkpoint)["ok"]))return false;
        model_keep[asset].insert(checkpoint.hex_encode());
    }
    return true;
}
bool NativeRegionWorldArchive::retire_unreferenced() {
    std::set<String> keep;
    std::map<String,std::set<String>> model_keep;
    {
        std::lock_guard<std::mutex> lock(read_mutex_);
        if(checkpoint_sweep_active_)return false;
        checkpoint_sweep_active_=true;
        for(const auto &entry:read_checkpoint_refs_) {
            if(entry.first.first.is_empty())keep.insert(entry.first.second);
            else model_keep[entry.first.first].insert(entry.first.second);
        }
    }
    // Never hold the queue lock over disk work. A checkpoint request/lease
    // arriving during this decision returns backpressure, closing the gap
    // between sampling retention references and releasing durable pins.
    struct SweepGuard {
        std::mutex &mutex;bool &active;
        ~SweepGuard(){std::lock_guard<std::mutex> lock(mutex);active=false;}
    } guard{read_mutex_,checkpoint_sweep_active_};
    if(!reference_in_file(path_,keep,model_keep)||!reference_in_file(path_+String(".bak"),keep,model_keep))return false;
    // Both checkpoint types are collected from the same validated root read.
    const PackedByteArray pins=store_->list_checkpoints();
    for(int64_t i=0;i<pins.size();i+=32) {
        auto id=pins.slice(i,i+32);if(!keep.count(id.hex_encode())&&!bool(store_->release_checkpoint(id)["ok"]))return false;
    }
    std::lock_guard<std::mutex> model_lock(model_mutex_);
    for(auto &entry:model_stores_) {
        const auto pins=entry.second->list_checkpoints();
        for(int64_t i=0;i<pins.size();i+=32){auto id=pins.slice(i,i+32);if(!model_keep[entry.first].count(id.hex_encode())&&!bool(entry.second->release_checkpoint(id)["ok"]))return false;}
    }
    return true;
}
int64_t NativeRegionWorldArchive::publish(const String &path,const PackedByteArray &bytes) {
    if(path_!=path||path_.is_empty()||store_.is_null())return ERR_UNCONFIGURED;
    Dictionary root=archive_->call("decode",bytes);if(!bool(root.get("ok",false)))return ERR_INVALID_DATA;
    return publish_sections(path,root["sections"]);
}
int64_t NativeRegionWorldArchive::publish_sections(const String &path,const Dictionary &input) {
    publication_profile_.clear();uint64_t phase=Time::get_singleton()->get_ticks_usec();
    auto mark=[&](const char *name){uint64_t now=Time::get_singleton()->get_ticks_usec();publication_profile_[name]=int64_t(now-phase);phase=now;};
    if(path_!=path||path_.is_empty()||store_.is_null())return ERR_UNCONFIGURED;
    // Check the exact same section contract as encoding before touching stores.
    // This worker-owned in-memory input does not need a temporary archive/hash.
    if(!bool(archive_->call("validate_sections",input)))return ERR_INVALID_DATA;
    Dictionary sections=input.duplicate();
    if(!sections.has("structures"))return ERR_INVALID_DATA;
    Dictionary structure=codec_->decode(sections["structures"]);
    const bool partial=!bool(structure["ok"]);
    if(partial)structure=codec_->decode_storage(sections["structures"]);
    if(!bool(structure["ok"]))return ERR_INVALID_DATA;
    mark("validate_sections_us");
    if(compact_initial_&&!FileAccess::file_exists(path_)) {
        // A fresh generation already owns a complete bounded TFSB record batch.
        // Publish that established binary representation directly, avoiding
        // thousands of small regional files and a second copy at publication.
        // Later saves use the regional path below, including backup retention.
        if(partial)return ERR_INVALID_DATA;
        const PackedByteArray bytes=archive_->call("encode",sections);if(bytes.is_empty())return ERR_INVALID_DATA;
        const int64_t error=archive_->call("publish",path,bytes);
        publication_profile_["compact_initial"]=true;publication_profile_["structure_bytes"]=PackedByteArray(sections["structures"]).size();
        mark("root_publish_us");return error;
    }
    // Failed previous saves can leave extra pins. Retire only after validating
    // both published roots, before allocating another pin.
    if(!retire_unreferenced())return ERR_FILE_CORRUPT;
    mark("retire_before_us");
    Dictionary published=partial?store_->publish_storage_state(structure["resident"],structure["unavailable_keys"],structure["unavailable_checksums"],structure["checkpoint"]):store_->publish_block_snapshot(structure["blocks"]);if(!bool(published["ok"]))return published["error"];
    Dictionary pin=store_->pin_checkpoint();if(!bool(pin["ok"]))return pin["error"];
    mark("blocks_us");
    Dictionary models=structure["models"];PackedStringArray ids;Array keys=models.keys();for(int64_t i=0;i<keys.size();++i)ids.push_back(keys[i]);
    std::map<String,PublishedModelIndex> model_indexes;
    // Each job owns one asset store and its result. No worker mutates the shared
    // Godot dictionaries or publishes the root. Drain every job before returning
    // an error so current/backup checkpoint retention remains authoritative.
    struct ModelJob {
        String asset;Ref<NativeModelRegionStore> store;PackedByteArray snapshot;
        PublishedModelIndex index;int64_t error=OK;uint64_t open_us=0;
    };
    std::vector<ModelJob> jobs; jobs.reserve(keys.size());
    for(int64_t i=0;i<keys.size();++i) {
        String asset=keys[i];jobs.push_back({asset,{},models[asset],{},OK});
    }
    mark("models_open_us");
    auto publish_model=[this](ModelJob &job)->int64_t {
        const auto began=Time::get_singleton()->get_ticks_usec();
        job.store=model_store(job.asset,true);job.open_us=Time::get_singleton()->get_ticks_usec()-began;
        auto &model=job.store;if(model.is_null())return ERR_CANT_OPEN;
        String parsed_asset;Dictionary state;
        Dictionary stored=NativeStructuresSnapshot::parse_model_storage(job.snapshot,parsed_asset,&state)?
            model->publish_storage_state(state["resident"],state["unavailable_keys"],state["unavailable_checksums"]):model->publish_snapshot(job.snapshot);
        if(!bool(stored["ok"]))return stored["error"];
        Dictionary model_pin=model->pin_checkpoint();if(!bool(model_pin["ok"]))return model_pin["error"];
        // Bake derived metadata only at explicit save publication. Read-only
        // startup may rebuild in memory but never writes checkpoint sidecars.
        Dictionary metadata=model->bake_metadata(model_pin["checkpoint"]);if(!bool(metadata["ok"]))return metadata["error"];
        Dictionary model_index=model->checkpoint_regions(model_pin["checkpoint"]);if(!bool(model_index["ok"]))return model_index["error"];
        job.index={model_index["keys"],model_index["checksums"],model_pin["checkpoint"]};
        return OK;
    };
    const bool initial_publication=!FileAccess::file_exists(path_);
    const size_t concurrency=initial_publication?std::min<size_t>(12,std::max<size_t>(1,std::thread::hardware_concurrency())):std::min<size_t>(4,std::max<size_t>(1,std::thread::hardware_concurrency()/2));
    const size_t worker_count=std::min<size_t>(jobs.size(),concurrency);
    publication_profile_["model_workers"]=int64_t(worker_count);
    publication_profile_["model_jobs"]=int64_t(jobs.size());
    std::atomic<size_t> next{0};std::vector<std::thread> workers;
    auto run=[&](){for(;;){size_t i=next.fetch_add(1);if(i>=jobs.size())return;jobs[i].error=publish_model(jobs[i]);}};
    // The save worker participates. Fresh creation may use up to eleven more
    // independent I/O workers; ordinary gameplay retains its four-worker limit.
    for(size_t i=1;i<worker_count;++i)workers.emplace_back(run);
    run();for(auto &worker:workers)worker.join();
    uint64_t open_total=0,open_max=0;for(const auto &job:jobs){open_total+=job.open_us;open_max=std::max(open_max,job.open_us);}
    publication_profile_["models_open_worker_us"]=int64_t(open_total);publication_profile_["models_open_max_us"]=int64_t(open_max);
    for(auto &job:jobs) {
        if(job.error!=OK)return job.error;
        model_indexes.emplace(job.asset,job.index);
        models[job.asset]=NativeStructuresSnapshot::model_reference(job.asset,job.index.checkpoint);
    }
    mark("models_us");
    Ref<NativeStructuresSnapshot> subset;subset.instantiate();if(!subset->configure_assets(ids))return ERR_INVALID_DATA;
    PackedByteArray reference=subset->encode_reference(pin["checkpoint"],models);if(reference.is_empty())return ERR_INVALID_DATA;
    sections["structures"]=reference;PackedByteArray compact=archive_->call("encode",sections);if(compact.is_empty())return ERR_INVALID_DATA;
    Dictionary index=store_->checkpoint_regions(pin["checkpoint"]);
    if(!bool(index["ok"]))return index["error"];
    mark("compact_encode_us");
    int64_t error=archive_->call("publish",path,compact);if(error!=OK)return error;
    mark("root_publish_us");
    if(bool(index["ok"])) {
        std::lock_guard<std::mutex> lock(read_mutex_);
        published_keys_=index["keys"];published_checksums_=index["checksums"];published_checkpoint_=pin["checkpoint"];
        published_models_=std::move(model_indexes);
        ++published_index_revision_;
    }
    // Publication already succeeded. Cleanup failure must never masquerade as a
    // failed commit; retain safe excess data and retry on the next save.
    if(retire_unreferenced()) {
        store_->collect_garbage(32);
        std::lock_guard<std::mutex> lock(model_mutex_);
        for(auto &entry:model_stores_)entry.second->collect_garbage(32);
    }
    mark("retire_after_us");
    return OK;
}
Dictionary NativeRegionWorldArchive::read_storage_region(Vector3i region,const PackedByteArray &expected,const PackedByteArray &checkpoint) const {
    if(store_.is_valid())return store_->read_storage_region(region,expected,checkpoint);
    Dictionary failed;failed["ok"]=false;failed["error"]=int(ERR_UNCONFIGURED);return failed;
}
Dictionary NativeRegionWorldArchive::storage_stats() const {
    Dictionary out;if(store_.is_valid())out=store_->stats();else out["open"]=false;
    std::lock_guard<std::mutex> lock(model_mutex_);
    int64_t pins=0;for(const auto &entry:model_stores_)pins+=int64_t(entry.second->stats()["checkpoints"]);
    out["model_stores"]=int(model_stores_.size());out["model_checkpoints"]=pins;return out;
}
}
