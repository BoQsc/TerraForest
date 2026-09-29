// SPDX-License-Identifier: 0BSD
#include "region_world_archive.hpp"
#include <algorithm>
#include <limits>

namespace terraforest {
// Worst-case encoded region plus the request and result digests. Containers,
// store catalogs, parser scratch and caller-owned polled results are separate.
static constexpr int64_t READ_BYTES=2*1024*1024+96;

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
    // The worker owns its own store Ref. It never reads the adapter's mutable
    // lifecycle fields and never accesses a scene node or the world archive.
    read_worker_=std::thread(&NativeRegionWorldArchive::run_region_reads,this,store_);
    return true;
}

int64_t NativeRegionWorldArchive::request_region_read(Vector3i region,const PackedByteArray &expected,const PackedByteArray &checkpoint,int64_t epoch) {
    std::lock_guard<std::mutex> lock(read_mutex_);
    const bool valid_region=region.x>=-16384&&region.x<16384&&region.y>=-16384&&region.y<16384&&region.z>=-16384&&region.z<16384;
    if(!valid_region||expected.size()!=32||(checkpoint.size()!=0&&checkpoint.size()!=32)||epoch<0||
       !read_running_||read_stopping_||read_outstanding_>=read_request_limit_||
       READ_BYTES>read_byte_limit_-read_reserved_||read_next_ticket_==INT64_MAX) {
        ++read_rejected_;return 0;
    }
    RegionRead request;request.ticket=read_next_ticket_++;request.epoch=epoch;
    request.region=region;request.expected=expected;request.checkpoint=checkpoint;
    const int64_t ticket=request.ticket;
    read_pending_.push_back(std::move(request));++read_outstanding_;++read_accepted_;
    read_reserved_+=READ_BYTES;read_high_requests_=std::max(read_high_requests_,read_outstanding_);
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
        }
        // Store locking serializes exact-version reads with catalog mutation and
        // garbage collection. Do not hold the queue mutex across any disk work.
        Dictionary result=store->read_storage_region(request.region,request.expected,request.checkpoint);
        result["ticket"]=request.ticket;result["epoch"]=request.epoch;result["region"]=request.region;
        result["expected_checksum"]=request.expected;result["checkpoint"]=request.checkpoint;
        request.expected=PackedByteArray();request.checkpoint=PackedByteArray();
        {
            std::lock_guard<std::mutex> lock(read_mutex_);
            read_completed_.push_back(std::move(result));++read_finished_;read_active_=false;
        }
    }
    store.unref();
    std::lock_guard<std::mutex> lock(read_mutex_);read_running_=read_active_=false;
}

Array NativeRegionWorldArchive::poll_region_reads(int max_results) {
    Array results;if(max_results<1||max_results>64)return results;
    std::lock_guard<std::mutex> lock(read_mutex_);
    while(!read_completed_.empty()&&results.size()<max_results) {
        results.push_back(read_completed_.front());read_completed_.pop_front();
        --read_outstanding_;read_reserved_-=READ_BYTES;
    }
    return results;
}

void NativeRegionWorldArchive::stop_region_reads() {
    std::lock_guard<std::mutex> lock(read_mutex_);read_stopping_=true;read_wake_.notify_one();
}
void NativeRegionWorldArchive::join_region_reads() {
    stop_region_reads();if(read_worker_.joinable())read_worker_.join();
}
Dictionary NativeRegionWorldArchive::region_read_stats() const {
    std::lock_guard<std::mutex> lock(read_mutex_);Dictionary out;
    out["running"]=read_running_;out["stopping"]=read_stopping_;out["active"]=read_active_;
    out["pending"]=int(read_pending_.size());out["completed"]=int(read_completed_.size());
    out["outstanding"]=read_outstanding_;out["reserved_bytes"]=read_reserved_;
    out["request_limit"]=read_request_limit_;out["byte_limit"]=read_byte_limit_;
    out["reservation_per_request"]=READ_BYTES;out["high_requests"]=read_high_requests_;out["high_bytes"]=read_high_bytes_;
    out["accepted"]=read_accepted_;out["finished"]=read_finished_;out["rejected"]=read_rejected_;out["worker_starts"]=read_starts_;
    return out;
}
}
