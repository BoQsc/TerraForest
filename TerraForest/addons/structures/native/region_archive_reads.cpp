// SPDX-License-Identifier: 0BSD
#include "region_world_archive.hpp"
#include <algorithm>
#include <limits>

namespace terraforest {
// Worst-case encoded region plus the request and result digests. Containers,
// store catalogs, parser scratch and caller-owned polled results are separate.
static constexpr int64_t READ_BYTES=2*1024*1024+96;
static constexpr int64_t MODEL_READ_BYTES=5600232+96;

bool NativeRegionWorldArchive::start_region_reads(int request_limit,int64_t byte_limit) {
    // Lifecycle calls have one owner and must not race acquire/release/join.
    if(store_.is_null()||path_.is_empty()||request_limit<1||request_limit>64||
       byte_limit<READ_BYTES||byte_limit>128*1024*1024)return false;
    {
        std::lock_guard<std::mutex> lock(read_mutex_);
        if(read_running_||read_outstanding_||read_next_ticket_==INT64_MAX)return false;
    }
    if(read_worker_.joinable())read_worker_.join();
    {
        std::lock_guard<std::mutex> lock(read_mutex_);
        read_request_limit_=request_limit;read_byte_limit_=byte_limit;
        read_running_=true;read_stopping_=read_active_=false;
        read_high_requests_=0;read_high_bytes_=0;++read_starts_;
    }
    // release joins the worker before changing path or closing either store.
    // The worker never accesses a scene node or the world archive.
    read_worker_=std::thread(&NativeRegionWorldArchive::run_region_reads,this,store_);
    return true;
}

int64_t NativeRegionWorldArchive::request_region_read(Vector3i region,const PackedByteArray &expected,const PackedByteArray &checkpoint,int64_t epoch) {
    return request_read(String(),region,expected,checkpoint,epoch);
}
int64_t NativeRegionWorldArchive::request_model_region_read(const String &asset,Vector3i region,const PackedByteArray &expected,const PackedByteArray &checkpoint,int64_t epoch) {
    if(asset.is_empty()){std::lock_guard<std::mutex> lock(read_mutex_);++read_rejected_;return 0;}
    return request_read(asset,region,expected,checkpoint,epoch);
}
int64_t NativeRegionWorldArchive::request_checkpoint_region_read(Vector3i region,const PackedByteArray &expected,const PackedByteArray &checkpoint,int64_t epoch) {
    return request_read(String(),region,expected,checkpoint,epoch,false,true);
}
int64_t NativeRegionWorldArchive::request_model_checkpoint_region_read(const String &asset,Vector3i region,const PackedByteArray &expected,const PackedByteArray &checkpoint,int64_t epoch) {
    if(asset.is_empty()){std::lock_guard<std::mutex> lock(read_mutex_);++read_rejected_;return 0;}
    return request_read(asset,region,expected,checkpoint,epoch,false,true);
}
int64_t NativeRegionWorldArchive::request_model_metadata(const String &asset,const PackedByteArray &checkpoint,int64_t epoch) {
    return request_read(asset,Vector3i(),PackedByteArray(),checkpoint,epoch,true);
}
int64_t NativeRegionWorldArchive::request_read(const String &asset,Vector3i region,const PackedByteArray &expected,const PackedByteArray &checkpoint,int64_t epoch,bool metadata,bool strict_checkpoint) {
    std::lock_guard<std::mutex> lock(read_mutex_);
    if(checkpoint.size()==32&&checkpoint_sweep_active_) {++read_rejected_;++read_checkpoint_busy_rejections_;return 0;}
    const bool model=!asset.is_empty();
    const int bound=model?32768:16384;
    const int64_t reservation=model?MODEL_READ_BYTES:READ_BYTES;
    const bool valid_region=region.x>=-bound&&region.x<bound&&region.y>=-bound&&region.y<bound&&region.z>=-bound&&region.z<bound;
    if((strict_checkpoint&&checkpoint.size()!=32)||(metadata&&(!model||checkpoint.size()!=32))||(model&&(codec_.is_null()||!codec_->has_asset(asset)))||!valid_region||(!metadata&&expected.size()!=32)||(checkpoint.size()!=0&&checkpoint.size()!=32)||epoch<0||
       !read_running_||read_stopping_||read_outstanding_>=read_request_limit_||
       reservation>read_byte_limit_-read_reserved_||read_next_ticket_==INT64_MAX) {
        ++read_rejected_;return 0;
    }
    RegionRead request;request.ticket=read_next_ticket_++;request.epoch=epoch;request.asset=asset;request.metadata=metadata;request.strict_checkpoint=strict_checkpoint;
    request.region=region;request.expected=expected;request.checkpoint=checkpoint;
    const int64_t ticket=request.ticket;
    if(checkpoint.size()==32)++read_checkpoint_refs_[{asset,checkpoint.hex_encode()}];
    read_pending_.push_back(std::move(request));++read_outstanding_;++read_accepted_;
    read_reserved_+=reservation;read_high_requests_=std::max(read_high_requests_,read_outstanding_);
    read_high_bytes_=std::max(read_high_bytes_,read_reserved_);
    read_wake_.notify_one();return ticket;
}

void NativeRegionWorldArchive::run_region_reads(Ref<NativeBlockRegionStore> store) {
    for(;;) {
        RegionRead request;
        {
            std::unique_lock<std::mutex> lock(read_mutex_);
            read_wake_.wait(lock,[this]{return read_stopping_||!read_pending_.empty();});
            if(read_pending_.empty())break;
            request=std::move(read_pending_.front());read_pending_.pop_front();read_active_=true;
            read_active_model_ticket_=request.asset.is_empty()?0:request.ticket;read_discard_active_=false;
        }
        // Store locking serializes exact-version reads with catalog mutation and
        // garbage collection. Do not hold the queue mutex across any disk work.
        Dictionary result;
        if(request.asset.is_empty())result=request.strict_checkpoint?store->read_checkpoint_region(request.checkpoint,request.region):store->read_storage_region(request.region,request.expected,request.checkpoint);
        else {
            // Lazy opening happens only on this worker, never under read_mutex_.
            auto model=model_store(request.asset,false);
            if(model.is_valid())result=request.metadata?model->read_metadata(request.checkpoint):(request.strict_checkpoint?model->read_checkpoint_region(request.checkpoint,request.region):model->read_storage_region(request.region,request.expected,request.checkpoint));
            else {result["ok"]=false;result["error"]=int(ERR_CANT_OPEN);}
        }
        if(request.strict_checkpoint&&bool(result.get("ok",false))&&PackedByteArray(result.get("checksum",PackedByteArray()))!=request.expected) {
            // Never expose a valid but unwanted checkpoint packet on failure.
            result.clear();result["ok"]=false;result["error"]=int(ERR_BUSY);
        }
        result["checkpoint_verified"]=(request.strict_checkpoint||request.metadata)&&bool(result.get("ok",false));
        if(!request.asset.is_empty()) {
            result["asset"]=request.asset;
            result["operation"]=request.metadata?"metadata":"region";
        }
        result["ticket"]=request.ticket;result["epoch"]=request.epoch;result["region"]=request.region;
        result["expected_checksum"]=request.expected;result["checkpoint"]=request.checkpoint;
        request.expected=PackedByteArray();request.checkpoint=PackedByteArray();
        {
            std::lock_guard<std::mutex> lock(read_mutex_);
            if(read_discard_active_) {
                PackedByteArray pin=result["checkpoint"];
                if(pin.size()==32)release_checkpoint_ref_locked({request.asset,pin.hex_encode()});
                --read_outstanding_;read_reserved_-=MODEL_READ_BYTES;
            } else (request.asset.is_empty()?read_completed_:model_read_completed_).push_back(std::move(result));
            ++read_finished_;read_active_=false;read_active_model_ticket_=0;read_discard_active_=false;
        }
    }
    store.unref();
    std::lock_guard<std::mutex> lock(read_mutex_);read_running_=read_active_=false;
}

Array NativeRegionWorldArchive::poll_region_reads(int max_results) {
    return poll_reads(max_results,false);
}
Array NativeRegionWorldArchive::poll_model_region_reads(int max_results) {
    return poll_reads(max_results,true);
}
Array NativeRegionWorldArchive::poll_reads(int max_results,bool models) {
    Array results;if(max_results<1||max_results>64)return results;
    std::lock_guard<std::mutex> lock(read_mutex_);
    auto &completed=models?model_read_completed_:read_completed_;
    while(!completed.empty()&&results.size()<max_results) {
        const Dictionary &result=completed.front();PackedByteArray checkpoint=result["checkpoint"];
        if(checkpoint.size()==32)release_checkpoint_ref_locked({String(result.get("asset",String())),checkpoint.hex_encode()});
        results.push_back(result);completed.pop_front();
        --read_outstanding_;read_reserved_-=models?MODEL_READ_BYTES:READ_BYTES;
    }
    return results;
}

// Ticket-specific consumption shares the existing queue accounting and never
// removes a metadata/region completion owned by a different consumer.
Dictionary NativeRegionWorldArchive::take_model_region_read(int64_t ticket) {
    std::lock_guard<std::mutex> lock(read_mutex_);
    for(auto it=model_read_completed_.begin();it!=model_read_completed_.end();++it)if(int64_t((*it)["ticket"])==ticket) {
        Dictionary result=*it;PackedByteArray pin=result["checkpoint"];
        if(pin.size()==32)release_checkpoint_ref_locked({String(result["asset"]),pin.hex_encode()});
        model_read_completed_.erase(it);--read_outstanding_;read_reserved_-=MODEL_READ_BYTES;return result;
    }
    return {};
}
bool NativeRegionWorldArchive::discard_model_region_read(int64_t ticket) {
    if(ticket<=0)return false;
    std::lock_guard<std::mutex> lock(read_mutex_);
    for(auto it=read_pending_.begin();it!=read_pending_.end();++it)if(it->ticket==ticket&&!it->asset.is_empty()) {
        if(it->checkpoint.size()==32)release_checkpoint_ref_locked({it->asset,it->checkpoint.hex_encode()});
        read_pending_.erase(it);--read_outstanding_;read_reserved_-=MODEL_READ_BYTES;return true;
    }
    for(auto it=model_read_completed_.begin();it!=model_read_completed_.end();++it)if(int64_t((*it)["ticket"])==ticket) {
        PackedByteArray pin=(*it)["checkpoint"];
        if(pin.size()==32)release_checkpoint_ref_locked({String((*it)["asset"]),pin.hex_encode()});
        model_read_completed_.erase(it);--read_outstanding_;read_reserved_-=MODEL_READ_BYTES;return true;
    }
    if(read_active_model_ticket_==ticket) {read_discard_active_=true;return true;}
    return false;
}

void NativeRegionWorldArchive::release_checkpoint_ref_locked(const ReadCheckpointKey &key) {
    auto found=read_checkpoint_refs_.find(key);
    // release() invalidates disk retention before unread completions are polled.
    if(found!=read_checkpoint_refs_.end()&&!--found->second)read_checkpoint_refs_.erase(found);
}
bool NativeRegionWorldArchive::configure_checkpoint_retention(int limit) {
    std::lock_guard<std::mutex> lock(read_mutex_);
    if(limit<1||limit>4096||read_checkpoint_leases_.size()>size_t(limit))return false;
    read_checkpoint_lease_limit_=limit;return true;
}
int64_t NativeRegionWorldArchive::retain_read_checkpoint(const String &asset,const PackedByteArray &checkpoint) {
    std::lock_guard<std::mutex> lock(read_mutex_);
    if(checkpoint_sweep_active_) {++read_checkpoint_busy_rejections_;return 0;}
    if(path_.is_empty()||store_.is_null()||checkpoint.size()!=32||
       (!asset.is_empty()&&(codec_.is_null()||!codec_->has_asset(asset)))||
       read_checkpoint_leases_.size()>=size_t(read_checkpoint_lease_limit_)||read_next_lease_==INT64_MAX)return 0;
    const ReadCheckpointKey key{asset,checkpoint.hex_encode()};
    const int64_t lease=read_next_lease_++;read_checkpoint_leases_.emplace(lease,key);
    ++read_checkpoint_refs_[key];return lease;
}
bool NativeRegionWorldArchive::release_read_checkpoint(int64_t lease) {
    std::lock_guard<std::mutex> lock(read_mutex_);
    auto found=read_checkpoint_leases_.find(lease);if(found==read_checkpoint_leases_.end())return false;
    release_checkpoint_ref_locked(found->second);read_checkpoint_leases_.erase(found);return true;
}

void NativeRegionWorldArchive::stop_region_reads() {
    std::lock_guard<std::mutex> lock(read_mutex_);read_stopping_=true;read_wake_.notify_one();
}
void NativeRegionWorldArchive::join_region_reads() {
    stop_region_reads();if(read_worker_.joinable())read_worker_.join();
}
Dictionary NativeRegionWorldArchive::published_region_index(int64_t after_revision) const {
    std::lock_guard<std::mutex> lock(read_mutex_);Dictionary out;
    if(published_checkpoint_.is_empty()||published_index_revision_<=after_revision)return out;
    out["revision"]=published_index_revision_;out["keys"]=published_keys_;
    out["checksums"]=published_checksums_;out["checkpoint"]=published_checkpoint_;return out;
}
Dictionary NativeRegionWorldArchive::published_model_index(const String &asset,int64_t after_revision,bool retain) {
    std::lock_guard<std::mutex> lock(read_mutex_);Dictionary out;
    auto found=published_models_.find(asset);
    if(found==published_models_.end()||published_index_revision_<=after_revision)return out;
    if(retain) {
        if(checkpoint_sweep_active_){++read_checkpoint_busy_rejections_;return out;}
        if(read_checkpoint_leases_.size()>=size_t(read_checkpoint_lease_limit_)||read_next_lease_==INT64_MAX)return out;
        const ReadCheckpointKey key{asset,found->second.checkpoint.hex_encode()};
        const int64_t lease=read_next_lease_++;read_checkpoint_leases_.emplace(lease,key);
        ++read_checkpoint_refs_[key];out["lease"]=lease;
    }
    out["revision"]=published_index_revision_;out["keys"]=found->second.keys;
    out["checksums"]=found->second.checksums;out["checkpoint"]=found->second.checkpoint;
    return out;
}
Dictionary NativeRegionWorldArchive::region_read_stats() const {
    std::lock_guard<std::mutex> lock(read_mutex_);Dictionary out;
    out["running"]=read_running_;out["stopping"]=read_stopping_;out["active"]=read_active_;
    out["pending"]=int(read_pending_.size());out["completed"]=int(read_completed_.size()+model_read_completed_.size());
    out["block_completed"]=int(read_completed_.size());out["model_completed"]=int(model_read_completed_.size());
    out["outstanding"]=read_outstanding_;out["reserved_bytes"]=read_reserved_;
    out["request_limit"]=read_request_limit_;out["byte_limit"]=read_byte_limit_;
    out["reservation_per_request"]=READ_BYTES;out["high_requests"]=read_high_requests_;out["high_bytes"]=read_high_bytes_;
    out["model_reservation_per_request"]=MODEL_READ_BYTES;
    out["checkpoint_leases"]=int(read_checkpoint_leases_.size());out["checkpoint_lease_limit"]=read_checkpoint_lease_limit_;
    out["retained_checkpoint_keys"]=int(read_checkpoint_refs_.size());out["checkpoint_sweep_active"]=checkpoint_sweep_active_;
    out["checkpoint_busy_rejections"]=read_checkpoint_busy_rejections_;
    out["accepted"]=read_accepted_;out["finished"]=read_finished_;out["rejected"]=read_rejected_;out["worker_starts"]=read_starts_;
    return out;
}
}
