// SPDX-License-Identifier: 0BSD
#include "block_pager.hpp"
#include <godot_cpp/classes/time.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <algorithm>
#include <cmath>
#include <limits>

namespace terraforest {
static constexpr int REQUESTS=4,SCAN_BUDGET=128,RETRY_TICKS=120;
void NativeBlockPager::_bind_methods() {
    ClassDB::bind_method(D_METHOD("configure","blocks","archive","load_radius","unload_radius","chunk_limit"),&NativeBlockPager::configure,DEFVAL(384.0),DEFVAL(512.0),DEFVAL(1536));
    ClassDB::bind_method(D_METHOD("step","world_focus","restore_checkpoint"),&NativeBlockPager::step,DEFVAL(PackedByteArray()));
    ClassDB::bind_method(D_METHOD("get_checkpoint"),&NativeBlockPager::get_checkpoint);
    ClassDB::bind_method(D_METHOD("stop"),&NativeBlockPager::stop);
    ClassDB::bind_method(D_METHOD("stats"),&NativeBlockPager::stats);
}
NativeBlockPager::~NativeBlockPager(){stop();}
NativeBlockWorld *NativeBlockPager::world() const {return Object::cast_to<NativeBlockWorld>(ObjectDB::get_instance(world_id_));}
double NativeBlockPager::distance_squared(BlockKey key,Vector3 point) {
    double sum=0;const int axes[3]={key.x,key.y,key.z};
    for(int i=0;i<3;++i){double low=axes[i]*64.0,delta=std::max({low-double(point[i]),0.0,double(point[i])-low-64.0});sum+=delta*delta;}
    return sum;
}
bool NativeBlockPager::configure(NativeBlockWorld *blocks,const Ref<NativeRegionWorldArchive> &archive,double load,double unload,int limit) {
    if(archive_.is_valid()||!blocks||archive.is_null()||!std::isfinite(load)||!std::isfinite(unload)||load<64||load>512||unload<load+64||unload>768||limit<64||limit>2048)return false;
    owns_read_service_=!bool(archive->region_read_stats()["running"]);
    if(owns_read_service_&&!archive->start_region_reads(REQUESTS,int64_t(REQUESTS)*(2*1024*1024+96)))return false;
    world_id_=blocks->get_instance_id();archive_=archive;load_radius_=load;unload_radius_=unload;chunk_limit_=limit;
    const int reach=int(std::ceil(load/64))+1;
    for(int x=-reach;x<=reach;++x)for(int y=-reach;y<=reach;++y)for(int z=-reach;z<=reach;++z)offsets_.push_back({x,y,z});
    std::sort(offsets_.begin(),offsets_.end(),[](BlockKey a,BlockKey b){int da=a.x*a.x+a.y*a.y+a.z*a.z,db=b.x*b.x+b.y*b.y+b.z*b.z;return da==db?a<b:da<db;});
    initialized_=false;return true;
}
void NativeBlockPager::reset(NativeBlockWorld *blocks,const PackedByteArray &checkpoint) {
    world_epoch_=blocks->storage_epoch;++epoch_;initialized_=true;grid_valid_=false;cursor_=0;pressure_distance_=1e100;
    pending_.clear();pending_keys_.clear();admitted_versions_.clear();blocked_.clear();retry_after_.clear();
    committed_keys_=PackedInt32Array();committed_digests_=PackedByteArray();indexed_=false;checkpoint_=checkpoint;
    // A prior scene's publication notice is not proof of this restored scene's
    // committed versions. Newly admitted packets establish provenance instead.
    Dictionary previous=archive_->published_region_index();index_revision_=previous.is_empty()?0:int64_t(previous["revision"]);
}
PackedByteArray NativeBlockPager::committed_digest(BlockKey key) const {
    if(!indexed_){auto found=admitted_versions_.find(key);return found==admitted_versions_.end()?PackedByteArray():found->second;}
    int64_t low=0,high=committed_keys_.size()/3;
    while(low<high){int64_t mid=(low+high)/2;BlockKey selected{committed_keys_[mid*3],committed_keys_[mid*3+1],committed_keys_[mid*3+2]};if(selected<key)low=mid+1;else high=mid;}
    if(low>=committed_keys_.size()/3)return {};
    BlockKey selected{committed_keys_[low*3],committed_keys_[low*3+1],committed_keys_[low*3+2]};
    return key<selected||selected<key?PackedByteArray():committed_digests_.slice(low*32,(low+1)*32);
}
bool NativeBlockPager::evict_one(NativeBlockWorld *blocks,Vector3 focus) {
    std::set<BlockKey> regions;for(const auto &entry:blocks->chunks)regions.insert(NativeBlockWorld::region_for(entry.first));
    for(auto it=blocked_.begin();it!=blocked_.end();)if(!regions.count(it->first))it=blocked_.erase(it);else ++it;
    for(auto it=admitted_versions_.begin();it!=admitted_versions_.end();)if(!regions.count(it->first))it=admitted_versions_.erase(it);else ++it;
    const double protected_radius=std::min(128.0,load_radius_/2);
    double threshold=unload_radius_*unload_radius_;
    if(blocks->chunks.size()+64>size_t(chunk_limit_))threshold=std::min(threshold,std::max(protected_radius*protected_radius,pressure_distance_+0.01));
    bool found=false;BlockKey selected;double farthest=threshold;
    const auto revision=std::make_pair(blocks->revision,blocks->history_revision);
    for(auto key:regions) {
        auto skipped=blocked_.find(key);if(skipped!=blocked_.end()&&skipped->second==revision)continue;
        const double distance=distance_squared(key,focus);
        if(distance>farthest){farthest=distance;selected=key;found=true;}
    }
    if(!found)return false;
    auto digest=committed_digest(selected);
    if(digest.is_empty()||blocks->region_has_history(selected)){blocked_[selected]=revision;return false;}
    PackedByteArray packet=blocks->capture_region(Vector3i(selected.x,selected.y,selected.z));
    if(packet.size()<32||packet.slice(packet.size()-32)!=digest){blocked_[selected]=revision;return false;}
    if(blocks->unloaded_regions.size()>=65536)return false;
    // This packet was captured from the current scene, not supplied externally.
    // Exact committed digest plus history protection authorize the transfer.
    blocks->unloaded_regions.emplace(selected,digest);
    blocks->replace_region_chunks(selected,{},false);
    admitted_versions_.erase(selected);blocked_.erase(selected);++evicted_;
    blocks->emit_signal("changed");return true;
}
bool NativeBlockPager::step(Vector3 world_focus,const PackedByteArray &restore_checkpoint) {
    NativeBlockWorld *blocks=world();
    if(archive_.is_null()||!blocks||!world_focus.is_finite()||(restore_checkpoint.size()!=0&&restore_checkpoint.size()!=32))return false;
    const Transform3D transform=blocks->is_inside_tree()?blocks->get_global_transform():blocks->get_transform();
    if(!transform.is_finite()||std::abs(transform.basis.determinant())<1e-12)return false;
    const Vector3 focus=transform.affine_inverse().xform(world_focus);
    if(!focus.is_finite())return false;
    for(int i=0;i<3;++i)if(std::abs(double(focus[i]))>1048576.0+768)return false;
    if(!bool(archive_->region_read_stats()["running"]))return false;
    const uint64_t begin=Time::get_singleton()->get_ticks_usec();scanned_=operations_=0;++ticks_;
    if(!initialized_||world_epoch_!=blocks->storage_epoch) {
        if(epoch_==INT64_MAX)return false;
        reset(blocks,restore_checkpoint);
    }
    BlockKey grid{int(std::floor(focus.x/64)),int(std::floor(focus.y/64)),int(std::floor(focus.z/64))};
    if(!grid_valid_||grid<grid_||grid_<grid){grid_=grid;grid_valid_=true;cursor_=0;pressure_distance_=1e100;}
    Dictionary index=archive_->published_region_index(index_revision_);
    if(!index.is_empty()) {
        index_revision_=index["revision"];committed_keys_=index["keys"];committed_digests_=index["checksums"];checkpoint_=index["checkpoint"];
        indexed_=true;admitted_versions_.clear();blocked_.clear();retry_after_.clear();
    }
    Array results=archive_->poll_region_reads(1);
    for(int i=0;i<results.size();++i) {
        Dictionary result=results[i];const int64_t ticket=result["ticket"];
        auto request=pending_.find(ticket);
        if(int64_t(result["epoch"])!=epoch_||request==pending_.end()){++stale_;continue;}
        const Pending captured=request->second;pending_keys_.erase(captured.key);pending_.erase(request);
        auto missing=blocks->unloaded_regions.find(captured.key);
        if(missing==blocks->unloaded_regions.end()||missing->second!=captured.checksum||distance_squared(captured.key,focus)>load_radius_*load_radius_){++stale_;continue;}
        if(!bool(result["ok"])){++failed_;retry_after_[captured.key]=ticks_+RETRY_TICKS;continue;}
        PackedByteArray packet=result["bytes"];
        const int64_t chunks=packet.size()>=36?packet.decode_u32(32):65;
        if(chunks>64||int64_t(blocks->chunks.size())+chunks>chunk_limit_){++budget_deferred_;retry_after_[captured.key]=ticks_+RETRY_TICKS;continue;}
        if(blocks->restore_region_impl(packet,PackedByteArray(),true)) {
            admitted_versions_[captured.key]=captured.checksum;++admitted_;++operations_;
        } else {++failed_;retry_after_[captured.key]=ticks_+RETRY_TICKS;}
    }
    blocks=world();if(!blocks||blocks->storage_epoch!=world_epoch_)return false;
    if(operations_==0&&evict_one(blocks,focus)) {
        ++operations_;
        // The vacancy belongs to the nearest missing region, not whichever
        // farther coordinate follows the old scan cursor. Otherwise pressure
        // can repeatedly refill distant regions and starve the destination.
        cursor_=0;
    }
    blocks=world();if(!blocks||blocks->storage_epoch!=world_epoch_)return false;
    pressure_distance_=1e100;
    int submitted=0;
    while(scanned_<SCAN_BUDGET&&submitted<2&&pending_.size()<REQUESTS) {
        const auto offset=offsets_[cursor_++];if(cursor_==offsets_.size())cursor_=0;++scanned_;
        BlockKey key{grid.x+offset.x,grid.y+offset.y,grid.z+offset.z};
        if(!NativeBlockWorld::valid_region(key)||distance_squared(key,focus)>load_radius_*load_radius_||pending_keys_.count(key))continue;
        auto missing=blocks->unloaded_regions.find(key);if(missing==blocks->unloaded_regions.end())continue;
        auto delayed=retry_after_.find(key);if(delayed!=retry_after_.end()&&delayed->second>ticks_)continue;
        if(int64_t(blocks->chunks.size())+int64_t(pending_.size()+1)*64>chunk_limit_){pressure_distance_=std::min(pressure_distance_,distance_squared(key,focus));++budget_deferred_;continue;}
        const int64_t ticket=archive_->request_region_read(Vector3i(key.x,key.y,key.z),missing->second,checkpoint_,epoch_);
        if(!ticket)break;
        pending_.emplace(ticket,Pending{key,missing->second});pending_keys_.insert(key);++requested_;++submitted;
    }
    if(retry_after_.size()>4096)retry_after_.erase(retry_after_.begin());
    if(admitted_versions_.size()>2048)admitted_versions_.erase(admitted_versions_.begin());
    scan_high_=std::max(scan_high_,scanned_);operation_high_=std::max(operation_high_,operations_);
    last_ms_=(Time::get_singleton()->get_ticks_usec()-begin)/1000.0;max_ms_=std::max(max_ms_,last_ms_);return true;
}
void NativeBlockPager::stop() {
    if(archive_.is_valid()){if(owns_read_service_){archive_->join_region_reads();archive_->poll_region_reads(64);}archive_.unref();}
    owns_read_service_=false;
    world_id_=ObjectID();pending_.clear();pending_keys_.clear();offsets_.clear();initialized_=false;
}
Dictionary NativeBlockPager::stats() const {
    Dictionary out;out["active"]=archive_.is_valid();out["epoch"]=epoch_;out["pending"]=int(pending_.size());
    out["requested"]=requested_;out["admitted"]=admitted_;out["evicted"]=evicted_;out["stale_results"]=stale_;out["failed_reads"]=failed_;
    out["budget_deferred"]=budget_deferred_;out["chunk_limit"]=chunk_limit_;out["blocked_candidates"]=int(blocked_.size());
    out["scan_last"]=scanned_;out["scan_high"]=scan_high_;out["operation_last"]=operations_;out["operation_high"]=operation_high_;
    out["last_ms"]=last_ms_;out["max_ms"]=max_ms_;return out;
}
}
