// SPDX-License-Identifier: 0BSD
#include "block_region_io.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <limits>

namespace terraforest {
static constexpr int64_t READ_RESERVATION=2*1024*1024;
static constexpr int64_t INDEX_RESERVATION=65536*3*sizeof(int32_t);
const char *NativeBlockRegionIO::operation_name(Operation operation) {
    switch(operation){case OPEN:return "open";case READ:return "read";case PUBLISH:return "publish";
        case REMOVE:return "remove";case COLLECT:return "collect";case INDEX:return "index";
        case PIN:return "pin";case PINS:return "pins";case PIN_INDEX:return "checkpoint_index";
        case PIN_READ:return "checkpoint_read";case PIN_ACTIVATE:return "checkpoint_activate";case PIN_RELEASE:return "checkpoint_release";}
    return "unknown";
}
void NativeBlockRegionIO::_bind_methods() {
    ClassDB::bind_method(D_METHOD("start","absolute_directory","request_limit","byte_limit","recover_backup"),&NativeBlockRegionIO::start,DEFVAL(false));
    ClassDB::bind_method(D_METHOD("read_region","region"),&NativeBlockRegionIO::read_region);
    ClassDB::bind_method(D_METHOD("publish_regions","packets","expected_checksums"),&NativeBlockRegionIO::publish_regions);
    ClassDB::bind_method(D_METHOD("remove_region","region","expected_checksum"),&NativeBlockRegionIO::remove_region);
    ClassDB::bind_method(D_METHOD("collect_garbage","max_inspected"),&NativeBlockRegionIO::collect_garbage);
    ClassDB::bind_method(D_METHOD("list_regions"),&NativeBlockRegionIO::list_regions);
    ClassDB::bind_method(D_METHOD("pin_checkpoint"),&NativeBlockRegionIO::pin_checkpoint);
    ClassDB::bind_method(D_METHOD("list_checkpoints"),&NativeBlockRegionIO::list_checkpoints);
    ClassDB::bind_method(D_METHOD("checkpoint_regions","checkpoint"),&NativeBlockRegionIO::checkpoint_regions);
    ClassDB::bind_method(D_METHOD("read_checkpoint_region","checkpoint","region"),&NativeBlockRegionIO::read_checkpoint_region);
    ClassDB::bind_method(D_METHOD("activate_checkpoint","checkpoint"),&NativeBlockRegionIO::activate_checkpoint);
    ClassDB::bind_method(D_METHOD("release_checkpoint","checkpoint"),&NativeBlockRegionIO::release_checkpoint);
    ClassDB::bind_method(D_METHOD("poll","max_results"),&NativeBlockRegionIO::poll,DEFVAL(16));
    ClassDB::bind_method(D_METHOD("request_stop"),&NativeBlockRegionIO::request_stop);
    ClassDB::bind_method(D_METHOD("join"),&NativeBlockRegionIO::join);
    ClassDB::bind_method(D_METHOD("stats"),&NativeBlockRegionIO::stats);
}
NativeBlockRegionIO::~NativeBlockRegionIO(){join();}
int64_t NativeBlockRegionIO::start(const String &path,int request_limit,int64_t byte_limit,bool recover) {
    if(!path.is_absolute_path()||path.begins_with("res://")||path.begins_with("user://")||
       request_limit<1||request_limit>256||byte_limit<READ_RESERVATION||byte_limit>256*1024*1024)return 0;
    // Lifecycle calls belong to the scene owner, not concurrent producers.
    {std::lock_guard<std::mutex> lock(mutex_);if(running_||outstanding_||next_ticket_==INT64_MAX)return 0;}
    if(worker_.joinable())worker_.join();
    Request opening;opening.operation=OPEN;opening.reserved=INDEX_RESERVATION;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        request_limit_=request_limit;byte_limit_=byte_limit;running_=active_=true;ready_=stopping_=false;
        opening.ticket=next_ticket_++;outstanding_=1;reserved_=opening.reserved;
        high_requests_=1;high_bytes_=reserved_;++accepted_;++starts_;
    }
    worker_=std::thread(&NativeBlockRegionIO::run,this,path,recover,opening);
    return opening.ticket;
}
int64_t NativeBlockRegionIO::enqueue(Request request) {
    std::lock_guard<std::mutex> lock(mutex_);
    if(!running_||!ready_||stopping_||outstanding_>=request_limit_||
       request.reserved>byte_limit_-reserved_||next_ticket_==INT64_MAX){++rejected_;return 0;}
    request.ticket=next_ticket_++;const int64_t ticket=request.ticket;
    reserved_+=request.reserved;++outstanding_;++accepted_;
    high_requests_=std::max(high_requests_,outstanding_);high_bytes_=std::max(high_bytes_,reserved_);
    pending_.push_back(std::move(request));wake_.notify_one();return ticket;
}
int64_t NativeBlockRegionIO::read_region(Vector3i region) {
    Request request;request.operation=READ;request.region=region;request.reserved=READ_RESERVATION;return enqueue(std::move(request));
}
int64_t NativeBlockRegionIO::publish_regions(const Array &packets,const Array &expected) {
    if(packets.is_empty()||packets.size()>64||packets.size()!=expected.size())return 0;
    Request request;request.operation=PUBLISH;
    for(int64_t i=0;i<packets.size();++i) {
        if(packets[i].get_type()!=Variant::PACKED_BYTE_ARRAY||expected[i].get_type()!=Variant::PACKED_BYTE_ARRAY)return 0;
        PackedByteArray bytes=packets[i],checksum=expected[i];
        if(bytes.size()>READ_RESERVATION||(checksum.size()!=0&&checksum.size()!=32))return 0;
        request.reserved+=bytes.size()+checksum.size();
        if(request.reserved>64*1024*1024)return 0;
        // Independent Array containers pin COW byte values without retaining
        // the caller's mutable Array. Packet validation stays on the worker.
        request.packets.push_back(bytes);request.expected.push_back(checksum);
    }
    return enqueue(std::move(request));
}
int64_t NativeBlockRegionIO::remove_region(Vector3i region,const PackedByteArray &expected) {
    if(expected.size()!=32)return 0;
    Request request;request.operation=REMOVE;request.region=region;request.checksum=expected;request.reserved=32;return enqueue(std::move(request));
}
int64_t NativeBlockRegionIO::collect_garbage(int max_inspected) {
    if(max_inspected<1||max_inspected>256)return 0;
    Request request;request.operation=COLLECT;request.budget=max_inspected;return enqueue(std::move(request));
}
int64_t NativeBlockRegionIO::list_regions() {
    Request request;request.operation=INDEX;request.reserved=INDEX_RESERVATION;return enqueue(std::move(request));
}
int64_t NativeBlockRegionIO::pin_checkpoint() {
    Request request;request.operation=PIN;request.reserved=32;return enqueue(std::move(request));
}
int64_t NativeBlockRegionIO::list_checkpoints() {
    Request request;request.operation=PINS;request.reserved=512;return enqueue(std::move(request));
}
int64_t NativeBlockRegionIO::checkpoint_regions(const PackedByteArray &checkpoint) {
    if(checkpoint.size()!=32)return 0;
    Request request;request.operation=PIN_INDEX;request.checksum=checkpoint;request.reserved=INDEX_RESERVATION+65536*32+32;return enqueue(std::move(request));
}
int64_t NativeBlockRegionIO::read_checkpoint_region(const PackedByteArray &checkpoint,Vector3i region) {
    if(checkpoint.size()!=32)return 0;
    Request request;request.operation=PIN_READ;request.checksum=checkpoint;request.region=region;request.reserved=READ_RESERVATION+32;return enqueue(std::move(request));
}
int64_t NativeBlockRegionIO::activate_checkpoint(const PackedByteArray &checkpoint) {
    if(checkpoint.size()!=32)return 0;
    Request request;request.operation=PIN_ACTIVATE;request.checksum=checkpoint;request.reserved=32;return enqueue(std::move(request));
}
int64_t NativeBlockRegionIO::release_checkpoint(const PackedByteArray &checkpoint) {
    if(checkpoint.size()!=32)return 0;
    Request request;request.operation=PIN_RELEASE;request.checksum=checkpoint;request.reserved=32;return enqueue(std::move(request));
}
void NativeBlockRegionIO::run(String path,bool recover,Request opening) {
    Ref<NativeBlockRegionStore> store;store.instantiate();
    Dictionary opened=store->open_store(path,recover);
    bool ok=opened["ok"];
    if(ok)opened["keys"]=store->list_regions();
    opened["ticket"]=opening.ticket;opened["operation"]="open";
    {
        std::lock_guard<std::mutex> lock(mutex_);
        completed_.push_back({opened,opening.reserved});++finished_;active_=false;
        ready_=ok&&!stopping_;if(!ok)stopping_=true;
    }
    while(ok) {
        Request request;
        {
            std::unique_lock<std::mutex> lock(mutex_);
            wake_.wait(lock,[this]{return stopping_||!pending_.empty();});
            if(pending_.empty())break;
            request=std::move(pending_.front());pending_.pop_front();active_=true;
        }
        Dictionary result;
        switch(request.operation) {
            case READ:result=store->read_region(request.region);break;
            case PUBLISH:result=store->publish_regions(request.packets,request.expected);break;
            case REMOVE:result=store->remove_region(request.region,request.checksum);break;
            case COLLECT:result=store->collect_garbage(request.budget);break;
            case INDEX:result["ok"]=true;result["error"]=int(OK);result["message"]=String();result["keys"]=store->list_regions();break;
            case PIN:result=store->pin_checkpoint();break;
            case PINS:result["ok"]=true;result["error"]=int(OK);result["message"]=String();result["checkpoints"]=store->list_checkpoints();break;
            case PIN_INDEX:result=store->checkpoint_regions(request.checksum);break;
            case PIN_READ:result=store->read_checkpoint_region(request.checksum,request.region);break;
            case PIN_ACTIVATE:result=store->activate_checkpoint(request.checksum);break;
            case PIN_RELEASE:result=store->release_checkpoint(request.checksum);break;
            case OPEN:break;
        }
        result["ticket"]=request.ticket;result["operation"]=operation_name(request.operation);
        if(request.operation==READ||request.operation==REMOVE||request.operation==PIN_READ)result["region"]=request.region;
        // Release input handles before exposing completion; reservation remains
        // charged until poll, even for failures and small successful replies.
        request.packets.clear();request.expected.clear();request.checksum=PackedByteArray();
        {
            std::lock_guard<std::mutex> lock(mutex_);
            completed_.push_back({result,request.reserved});++finished_;active_=false;
        }
    }
    store->close();store.unref();
    {std::lock_guard<std::mutex> lock(mutex_);running_=ready_=active_=false;}
}
Array NativeBlockRegionIO::poll(int max_results) {
    Array out;if(max_results<1||max_results>64)return out;
    std::lock_guard<std::mutex> lock(mutex_);
    while(!completed_.empty()&&out.size()<max_results) {
        out.push_back(completed_.front().value);reserved_-=completed_.front().reserved;
        --outstanding_;completed_.pop_front();
    }
    return out;
}
void NativeBlockRegionIO::request_stop() {
    std::lock_guard<std::mutex> lock(mutex_);stopping_=true;ready_=false;wake_.notify_one();
}
void NativeBlockRegionIO::join() {
    request_stop();if(worker_.joinable())worker_.join();
}
Dictionary NativeBlockRegionIO::stats() const {
    std::lock_guard<std::mutex> lock(mutex_);Dictionary out;
    out["running"]=running_;out["ready"]=ready_;out["stopping"]=stopping_;out["active"]=active_;
    out["pending"]=int(pending_.size());out["completed"]=int(completed_.size());out["outstanding"]=outstanding_;
    out["reserved_bytes"]=reserved_;out["request_limit"]=request_limit_;out["byte_limit"]=byte_limit_;
    out["high_requests"]=high_requests_;out["high_bytes"]=high_bytes_;out["accepted"]=accepted_;
    out["finished"]=finished_;out["backpressure_rejections"]=rejected_;out["worker_starts"]=starts_;return out;
}
}
