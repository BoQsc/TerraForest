// SPDX-License-Identifier: 0BSD
#include "model_transfer_scheduler.hpp"
#include <chrono>
#include <algorithm>
#include <vector>
#include <cmath>

namespace terraforest {
void NativeModelTransferScheduler::_bind_methods() {
    ClassDB::bind_method(D_METHOD("configure","archive","history","max_jobs","max_bytes"),&NativeModelTransferScheduler::configure);
    ClassDB::bind_method(D_METHOD("register_collection","asset","collection","checkpoint"),&NativeModelTransferScheduler::register_collection);
    ClassDB::bind_method(D_METHOD("unregister_collection","asset"),&NativeModelTransferScheduler::unregister_collection);
    ClassDB::bind_method(D_METHOD("refresh_checkpoint","asset"),&NativeModelTransferScheduler::refresh_checkpoint);
    ClassDB::bind_method(D_METHOD("get_checkpoint","asset"),&NativeModelTransferScheduler::get_checkpoint);
    ClassDB::bind_method(D_METHOD("select_focus","world_focus","load_radius","unload_radius","max_scans","max_usec"),&NativeModelTransferScheduler::select_focus,DEFVAL(384.0),DEFVAL(512.0),DEFVAL(64),DEFVAL(250));
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
    Collection binding;binding.id=collection->get_instance_id();binding.lease=std::move(lease);
    for(const auto &entry:collection->unloaded_regions)binding.versions.emplace(entry.first,entry.second.checksum);
    Dictionary index=archive->published_model_index(asset);
    if(!index.is_empty()&&PackedByteArray(index["checkpoint"])==checkpoint) {
        PackedInt32Array keys=index["keys"];PackedByteArray checksums=index["checksums"];
        for(int64_t i=0;i<keys.size()/3;++i)binding.versions[{keys[i*3],keys[i*3+1],keys[i*3+2]}]=checksums.slice(i*32,(i+1)*32);
    }
    collections.emplace(asset,std::move(binding));return true;
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
PackedByteArray NativeModelTransferScheduler::get_checkpoint(const String &asset) const {
    auto found=collections.find(asset);return found==collections.end()?PackedByteArray():found->second.lease->checkpoint;
}
bool NativeModelTransferScheduler::refresh_checkpoint(const String &asset) {
    if(busy||stopping||archive.is_null())return false;
    auto found=collections.find(asset);if(found==collections.end())return false;
    // Completed results must also be consumed before changing their provenance.
    for(const auto &entry:jobs)if(entry.second.asset==asset)return false;
    auto *collection=resolve(found->second.id);
    if(!collection||collection->admission||collection->paging_owner!=get_instance_id())return false;
    // Read the publication notice and retain it under one archive queue lock,
    // so concurrent save cleanup cannot remove it between observation and lease.
    Dictionary index=archive->published_model_index(asset,0,true);
    if(index.is_empty())return false;
    PackedByteArray checkpoint=index["checkpoint"],digests=index["checksums"];
    PackedInt32Array keys=index["keys"];
    auto lease=std::make_shared<ModelCheckpointLease>();lease->archive=archive;lease->checkpoint=checkpoint;lease->handle=index["lease"];
    // The notice is produced only after root publication, not from caller bytes.
    // Every unavailable region must survive unchanged in the new saved version.
    int64_t cursor=0;
    for(const auto &entry:collection->unloaded_regions) {
        while(cursor<keys.size()/3) {
            BlockKey key{keys[cursor*3],keys[cursor*3+1],keys[cursor*3+2]};
            if(!(key<entry.first))break;
            ++cursor;
        }
        if(cursor==keys.size()/3)return false;
        BlockKey key{keys[cursor*3],keys[cursor*3+1],keys[cursor*3+2]};
        if(entry.first<key||digests.slice(cursor*32,(cursor+1)*32)!=entry.second.checksum)return false;
    }
    // Hold the new version before releasing either reference to the old lease.
    collection->paging_checkpoint=lease;found->second.lease=std::move(lease);
    found->second.versions.clear();found->second.retry_after.clear();found->second.cursor_valid=false;found->second.query_valid=false;
    for(int64_t i=0;i<keys.size()/3;++i)found->second.versions.emplace(BlockKey{keys[i*3],keys[i*3+1],keys[i*3+2]},digests.slice(i*32,(i+1)*32));
    return true;
}
static double focus_distance(const AABB &box,const Vector3 &focus) {
    const Vector3 end=box.get_end();
    return focus.distance_squared_to(Vector3(std::clamp(focus.x,box.position.x,end.x),
        std::clamp(focus.y,box.position.y,end.y),std::clamp(focus.z,box.position.z,end.z)));
}
Dictionary NativeModelTransferScheduler::select_focus(Vector3 world_focus,double load_radius,double unload_radius,int max_scans,int max_usec) {
    if(busy||stopping||!world_focus.is_finite()||!std::isfinite(load_radius)||!std::isfinite(unload_radius)||
       load_radius<0||unload_radius<=load_radius||unload_radius>32768||max_scans<1||max_scans>1024||max_usec<1||max_usec>2000)return stats();
    const auto begin=std::chrono::steady_clock::now(),deadline=begin+std::chrono::microseconds(max_usec);
    selection_scans=selection_requests=0;++selection_tick;
    // The job set is already bounded by the shared scheduler capacity. Cancel
    // only obsolete work; ordinary sub-region camera motion does not reset I/O.
    for(auto &entry:jobs) {
        auto &job=entry.second;if(job.stage==DONE||job.cancelled)continue;
        auto *collection=resolve(collections.at(job.asset).id);if(!collection)continue;
        const Transform3D transform=collection->is_inside_tree()?collection->get_global_transform():collection->get_transform();
        if(!transform.is_finite()||std::abs(transform.basis.determinant())<1e-12)continue;
        const Vector3 focus=transform.affine_inverse().xform(world_focus);
        BlockKey key{job.region.x,job.region.y,job.region.z};
        auto missing=collection->unloaded_regions.find(key);
        AABB bounds;
        if(missing!=collection->unloaded_regions.end())bounds=missing->second.bounds;
        else {auto rendered=collection->render_bounds.find(key);if(rendered==collection->render_bounds.end())continue;bounds=rendered->second;
            auto collision=collection->collision_bounds.find(key);if(collision!=collection->collision_bounds.end())bounds=bounds.merge(collision->second);}
        const double distance=focus_distance(bounds,focus);
        if((!job.retiring&&distance>unload_radius*unload_radius)||(job.retiring&&distance<=unload_radius*unload_radius))cancel_job(job);
    }
    while(!collections.empty()&&selection_scans<max_scans&&std::chrono::steady_clock::now()<deadline) {
        auto next=collections.upper_bound(selection_asset);if(next==collections.end())next=collections.begin();
        selection_asset=next->first;auto &binding=next->second;++selection_scans;
        auto *collection=resolve(binding.id);if(!collection)continue;
        const Transform3D transform=collection->is_inside_tree()?collection->get_global_transform():collection->get_transform();
        if(!transform.is_finite()||std::abs(transform.basis.determinant())<1e-12)continue;
        const Vector3 focus=transform.affine_inverse().xform(world_focus);if(!focus.is_finite())continue;
        collection->set_render_focus(focus);collection->set_collision_focus(focus);
        BlockKey key;AABB bounds;PackedByteArray expected;
        auto &index=collection->unloaded_bounds;
        if(!binding.query_valid||binding.bounds_revision!=index.revision()||binding.query_radius!=load_radius||binding.query_focus.distance_squared_to(focus)>16) {
            binding.query_valid=true;binding.bounds_revision=index.revision();binding.query_radius=load_radius;binding.query_focus=focus;
            binding.frontier.clear();if(index.root())binding.frontier.push_back(index.root()->code);
            binding.select_resident=false;
        }
        if(!binding.select_resident) {
            bool candidate=false;
            const double padded=(load_radius+4)*(load_radius+4);
            // A small per-asset quantum follows nearby branches promptly without
            // allowing one overlapping collection to monopolize the shared visit budget.
            for(int visited=0;visited<16&&!binding.frontier.empty()&&selection_scans<max_scans&&std::chrono::steady_clock::now()<deadline;++visited) {
                const auto code=binding.frontier.back();binding.frontier.pop_back();++selection_scans;
                const auto *node=index.find(code);if(!node||focus_distance(node->bounds,binding.query_focus)>padded)continue;
                const auto *first=node->left.get(),*second=node->right.get();
                if(first&&second&&focus_distance(first->bounds,binding.query_focus)>focus_distance(second->bounds,binding.query_focus))std::swap(first,second);
                // LIFO: visit the nearer child first, including true extended bounds.
                if(second&&focus_distance(second->bounds,binding.query_focus)<=padded)binding.frontier.push_back(second->code);
                if(first&&focus_distance(first->bounds,binding.query_focus)<=padded)binding.frontier.push_back(first->code);
                if(focus_distance(node->box,focus)>load_radius*load_radius)continue;
                auto item=collection->unloaded_regions.find(node->key);if(item==collection->unloaded_regions.end())continue;
                key=item->first;bounds=item->second.bounds;expected=item->second.checksum;candidate=true;break;
            }
            if(!candidate) {
                if(binding.frontier.empty()){binding.select_resident=true;binding.cursor_valid=false;}
                continue;
            }
        } else {
            auto item=binding.cursor_valid?collection->render_bounds.upper_bound(binding.cursor):collection->render_bounds.begin();
            if(item==collection->render_bounds.end()){binding.select_resident=false;binding.cursor_valid=false;
                binding.frontier.clear();if(index.root())binding.frontier.push_back(index.root()->code);continue;}
            key=item->first;bounds=item->second;
            auto collision=collection->collision_bounds.find(key);if(collision!=collection->collision_bounds.end())bounds=bounds.merge(collision->second);
            auto version=binding.versions.find(key);if(version!=binding.versions.end())expected=version->second;
        }
        if(binding.select_resident){binding.cursor=key;binding.cursor_valid=true;}
        const double distance=focus_distance(bounds,focus);
        const bool retiring=binding.select_resident;
        if(expected.is_empty()||(!retiring&&distance>load_radius*load_radius)||(retiring&&distance<=unload_radius*unload_radius))continue;
        auto retry=binding.retry_after.find(key);if(retry!=binding.retry_after.end()&&retry->second>selection_tick)continue;
        if(retiring) {
            // Skip renderer/history protection without starting disk reads.
            // Proxy protection is independently enforced by the transfer guard.
            auto drawn=collection->batches.lower_bound({key,0});
            if(drawn!=collection->batches.end()&&!(key<drawn->first.first)&&!(drawn->first.first<key))continue;
            if(history->region_has_history(collection,Vector3i(key.x,key.y,key.z)))continue;
        }
        const int priority=retiring?0:128+int(std::max(0.0,127.0-std::sqrt(distance)/32.0));
        if(request(next->first,Vector3i(key.x,key.y,key.z),expected,retiring,priority,epoch)>0)++selection_requests;
    }
    selection_usec=std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now()-begin).count();
    return stats();
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
    if(result=="failed") {
        auto found=collections.find(job.asset);
        if(found!=collections.end()) {
            if(found->second.retry_after.size()>=4096)found->second.retry_after.clear();
            found->second.retry_after[{job.region.x,job.region.y,job.region.z}]=selection_tick+120;
        }
    }
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
    out["selection_scans"]=selection_scans;out["selection_requests"]=selection_requests;out["selection_usec"]=selection_usec;
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
