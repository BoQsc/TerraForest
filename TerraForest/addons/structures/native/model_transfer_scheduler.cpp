// SPDX-License-Identifier: 0BSD
#include "model_transfer_scheduler.hpp"
#include <chrono>
#include <algorithm>
#include <vector>

namespace terraforest {
void NativeModelTransferScheduler::_bind_methods() {
    ClassDB::bind_method(D_METHOD("configure","archive","history","max_jobs","max_bytes"),&NativeModelTransferScheduler::configure);
    ClassDB::bind_method(D_METHOD("register_collection","asset","collection","checkpoint"),&NativeModelTransferScheduler::register_collection);
    ClassDB::bind_method(D_METHOD("unregister_collection","asset"),&NativeModelTransferScheduler::unregister_collection);
    ClassDB::bind_method(D_METHOD("request","asset","region","expected","retire","priority","epoch"),&NativeModelTransferScheduler::request);
    ClassDB::bind_method(D_METHOD("cancel","ticket"),&NativeModelTransferScheduler::cancel);
    ClassDB::bind_method(D_METHOD("set_epoch","epoch"),&NativeModelTransferScheduler::set_epoch);
    ClassDB::bind_method(D_METHOD("stop"),&NativeModelTransferScheduler::stop);
    ClassDB::bind_method(D_METHOD("tick","max_records","max_hash_bytes","max_usec","max_operations"),&NativeModelTransferScheduler::tick,DEFVAL(256),DEFVAL(65536),DEFVAL(500),DEFVAL(8));
    ClassDB::bind_method(D_METHOD("poll","max_results"),&NativeModelTransferScheduler::poll,DEFVAL(8));
    ClassDB::bind_method(D_METHOD("stats"),&NativeModelTransferScheduler::stats);
}
NativeStaticBatch *NativeModelTransferScheduler::resolve(uint64_t id) {return Object::cast_to<NativeStaticBatch>(ObjectDB::get_instance(id));}
bool NativeModelTransferScheduler::configure(const Ref<NativeRegionWorldArchive> &source,const Ref<NativeStaticHistory> &journal,int limit,int64_t bytes) {
    if(busy||!jobs.empty()||!collections.empty()||source.is_null()||journal.is_null()||limit<1||limit>64||bytes<PACKET_RESERVATION||bytes>128*1024*1024)return false;
    archive=source;history=journal;job_limit=limit;byte_limit=bytes;stopping=false;return true;
}
bool NativeModelTransferScheduler::register_collection(const String &asset,NativeStaticBatch *collection,const PackedByteArray &checkpoint) {
    if(busy||stopping||archive.is_null()||history.is_null()||!collection||asset.is_empty()||collection->asset_id!=asset||checkpoint.size()!=32||collections.count(asset)||collections.size()>=256||collection->admission)return false;
    if(collection->paging_owner&&ObjectDB::get_instance(collection->paging_owner))return false;
    auto previous=collection->paging_checkpoint;
    if(previous&&!collection->unloaded_regions.empty()&&
       (previous->archive!=archive||previous->checkpoint!=checkpoint))return false;
    // Acquire a fresh handle even on adoption: explicit archive release can
    // invalidate an old handle. Strict reads still establish disk provenance.
    const int64_t handle=archive->retain_read_checkpoint(asset,checkpoint);if(!handle)return false;
    auto lease=std::make_shared<ModelCheckpointLease>();lease->archive=archive;lease->checkpoint=checkpoint;lease->handle=handle;
    collection->paging_checkpoint=lease;collection->paging_owner=get_instance_id();
    collections.emplace(asset,Collection{collection->get_instance_id(),std::move(lease)});return true;
}
bool NativeModelTransferScheduler::unregister_collection(const String &asset) {
    if(busy)return false;
    auto found=collections.find(asset);if(found==collections.end())return false;
    for(const auto &entry:jobs)if(entry.second.asset==asset)return false;
    if(auto *collection=resolve(found->second.id)) {
        collection->paging_owner=0;
        // Unavailable records keep their lease independently of the scheduler.
        if(collection->unloaded_regions.empty())collection->paging_checkpoint.reset();
    }
    collections.erase(found);return true;
}
int64_t NativeModelTransferScheduler::request(const String &asset,Vector3i region,const PackedByteArray &expected,bool retire,int priority,int64_t request_epoch) {
    if(busy||stopping||archive.is_null()||request_epoch!=epoch||expected.size()!=32||priority<0||priority>255||
       !NativeStaticBatch::valid_model_region({region.x,region.y,region.z})||!collections.count(asset)||jobs.size()>=size_t(job_limit)||
       (int64_t(jobs.size())+1)*PACKET_RESERVATION>byte_limit||next_ticket==INT64_MAX)return 0;
    if(!resolve(collections.at(asset).id))return 0;
    for(const auto &entry:jobs)if(entry.second.asset==asset&&entry.second.region==region&&entry.second.stage!=DONE)return 0;
    Job job;job.ticket=next_ticket++;job.epoch=epoch;job.asset=asset;job.region=region;job.expected=expected;job.retiring=retire;job.priority=priority;
    const auto ticket=job.ticket;jobs.emplace(ticket,std::move(job));return ticket;
}
void NativeModelTransferScheduler::finish(Job &job,const String &result,const String &error) {
    job.stage=DONE;job.result=result;job.error=error;job.packet=PackedByteArray();
}
void NativeModelTransferScheduler::cancel_job(Job &job) {
    if(job.stage==DONE)return;job.cancelled=true;
    if(job.stage==TRANSFERRING) {
        auto *collection=resolve(collections.at(job.asset).id);
        if(!collection){finish(job,"cancelled","collection_destroyed");return;}
        if(job.retiring)history->cancel_region_retirement(collection,job.transfer_ticket);
        else history->cancel_region_admission(collection,job.transfer_ticket);
        // A committed retirement cannot roll back. Bounded cleanup must finish.
    } else {
        if(job.read_ticket)archive->discard_model_region_read(job.read_ticket);
        job.read_ticket=0;finish(job,"cancelled");
    }
}
bool NativeModelTransferScheduler::cancel(int64_t ticket) {
    if(busy)return false;auto found=jobs.find(ticket);if(found==jobs.end()||found->second.stage==DONE)return false;
    cancel_job(found->second);return true;
}
bool NativeModelTransferScheduler::set_epoch(int64_t value) {
    if(busy||value<epoch||value<0)return false;if(value==epoch)return true;
    epoch=value;for(auto &entry:jobs)if(entry.second.epoch<epoch)cancel_job(entry.second);return true;
}
bool NativeModelTransferScheduler::stop() {
    if(busy)return false;stopping=true;for(auto &entry:jobs)cancel_job(entry.second);return true;
}
bool NativeModelTransferScheduler::collection_busy(const Job &job) const {
    for(const auto &entry:jobs)if(entry.first!=job.ticket&&entry.second.asset==job.asset&&entry.second.stage==TRANSFERRING)return true;
    return false;
}
Dictionary NativeModelTransferScheduler::tick(int records,int bytes,int usec,int operations) {
    if(busy||archive.is_null()||history.is_null()||records<1||records>1024||bytes<1||bytes>262144||usec<1||usec>2000||operations<1||operations>64)return stats();
    busy=true;const auto start=std::chrono::steady_clock::now();
    const auto deadline=start+std::chrono::microseconds(usec);
    last_records=last_bytes=last_operations=0;++ticks;
    std::vector<int64_t> order;order.reserve(jobs.size());
    for(const auto &entry:jobs)if(entry.second.stage!=DONE)order.push_back(entry.first);
    std::sort(order.begin(),order.end(),[&](int64_t a,int64_t b){const auto &x=jobs.at(a),&y=jobs.at(b);
        if(x.cancelled!=y.cancelled)return x.cancelled;
        if(x.priority!=y.priority)return x.priority>y.priority;
        return x.last_served!=y.last_served?x.last_served<y.last_served:x.ticket<y.ticket;});
    for(int64_t ticket:order) {
        if(last_operations>=operations||std::chrono::steady_clock::now()>=deadline)break;
        auto &job=jobs.at(ticket);auto &binding=collections.at(job.asset);
        auto *collection=resolve(binding.id);
        if(!collection){++last_operations;if(job.read_ticket)archive->discard_model_region_read(job.read_ticket);finish(job,"failed","collection_destroyed");continue;}
        if(job.stage==QUEUED) {
            ++last_operations;job.last_served=++serial;
            job.read_ticket=archive->request_model_checkpoint_region_read(job.asset,job.region,job.expected,binding.lease->checkpoint,job.epoch);
            if(job.read_ticket)job.stage=READING;
            continue;
        }
        if(job.stage==READING) {
            ++last_operations;job.last_served=++serial;
            Dictionary result=archive->take_model_region_read(job.read_ticket);if(result.is_empty())continue;
            job.read_ticket=0;
            if(!bool(result.get("ok",false))||!bool(result.get("checkpoint_verified",false))||int64_t(result.get("epoch",-1))!=job.epoch||
               PackedByteArray(result.get("checkpoint",PackedByteArray()))!=binding.lease->checkpoint) {finish(job,"failed","checkpoint_read");continue;}
            job.packet=result["bytes"];job.stage=READY;continue;
        }
        if(job.stage==READY) {
            if(collection_busy(job))continue;
            ++last_operations;job.last_served=++serial;
            job.transfer_ticket=job.retiring?history->begin_region_retirement(collection,job.packet):history->begin_region_admission(collection,job.packet);
            if(!job.transfer_ticket)finish(job,"failed","transfer_rejected");
            else {job.stage=TRANSFERRING;job.packet=PackedByteArray();}
            continue;
        }
        if(job.stage==TRANSFERRING) {
            if(last_records>=records||last_bytes>=bytes)continue;
            const auto remaining=std::chrono::duration_cast<std::chrono::microseconds>(deadline-std::chrono::steady_clock::now()).count();
            if(remaining<1)break;
            ++last_operations;job.last_served=++serial;
            Dictionary result=job.retiring?history->advance_region_retirement(collection,job.transfer_ticket,records-last_records,bytes-last_bytes,remaining):
                history->advance_region_admission(collection,job.transfer_ticket,records-last_records,bytes-last_bytes,remaining);
            if(!bool(result.get("accepted",false))){finish(job,"failed","transfer_lost");continue;}
            last_records+=int64_t(result.get("step_records",0));last_bytes+=int64_t(result.get("step_hash_bytes",0));
            if(!bool(result.get("active",false)))finish(job,result.get("result","failed"),result.get("error",String()));
        }
    }
    last_usec=std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now()-start).count();peak_usec=std::max(peak_usec,last_usec);
    busy=false;return stats();
}
Array NativeModelTransferScheduler::poll(int count) {
    Array result;if(busy||count<1||count>64)return result;
    for(auto it=jobs.begin();it!=jobs.end()&&result.size()<count;) {
        const auto &job=it->second;if(job.stage!=DONE){++it;continue;}
        Dictionary out;out["ticket"]=job.ticket;out["epoch"]=job.epoch;out["asset"]=job.asset;out["region"]=job.region;
        out["operation"]=job.retiring?"retire":"admit";out["result"]=job.result;out["error"]=job.error;out["cancel_requested"]=job.cancelled;
        result.push_back(out);it=jobs.erase(it);
    }
    return result;
}
Dictionary NativeModelTransferScheduler::stats() const {
    Dictionary out;int active=0,reading=0,completed=0;
    for(const auto &entry:jobs){active+=entry.second.stage==TRANSFERRING;reading+=entry.second.stage==READING;completed+=entry.second.stage==DONE;}
    out["jobs"]=int(jobs.size());out["active"]=active;out["reading"]=reading;out["completed"]=completed;out["collections"]=int(collections.size());
    out["job_limit"]=job_limit;out["byte_limit"]=byte_limit;out["reserved_bytes"]=int64_t(jobs.size())*PACKET_RESERVATION;
    out["packet_reservation"]=PACKET_RESERVATION;out["epoch"]=epoch;out["stopping"]=stopping;out["busy"]=busy;out["ticks"]=ticks;
    out["step_records"]=last_records;out["step_hash_bytes"]=last_bytes;out["step_operations"]=last_operations;out["step_usec"]=last_usec;out["peak_usec"]=peak_usec;return out;
}
NativeModelTransferScheduler::~NativeModelTransferScheduler() {
    // Normal runtime shutdown calls stop() then tick() until active==0. The
    // exceptional destruction path finishes owned rollback/committed cleanup so
    // a surviving collection is never left locked by the still-live journal.
    stop();busy=true;
    for(auto &entry:jobs) {
        auto &job=entry.second;if(job.stage!=TRANSFERRING)continue;
        while(auto *collection=resolve(collections.at(job.asset).id)) {
            Dictionary state=job.retiring?history->advance_region_retirement(collection,job.transfer_ticket,1024,262144,2000):history->advance_region_admission(collection,job.transfer_ticket,1024,262144,2000);
            if(!bool(state.get("accepted",false))||!bool(state.get("active",false)))break;
        }
    }
    for(auto &entry:collections)if(auto *collection=resolve(entry.second.id)) {
        collection->paging_owner=0;
        if(collection->unloaded_regions.empty())collection->paging_checkpoint.reset();
    }
}
}
