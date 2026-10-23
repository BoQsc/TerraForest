// SPDX-License-Identifier: 0BSD
#include "generated_lake_bake.hpp"
#include "regional_water.hpp"
#include "lake_catalog.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/classes/time.hpp>
#include <algorithm>

using namespace godot;
namespace terraforest {
void NativeGeneratedLakeBake::_bind_methods(){
    ClassDB::bind_method(D_METHOD("run","core","catalog","revision","epoch","timeout_ms"),&NativeGeneratedLakeBake::run,DEFVAL(30000));
    ClassDB::bind_method(D_METHOD("cancel"),&NativeGeneratedLakeBake::cancel);
    ClassDB::bind_method(D_METHOD("progress"),&NativeGeneratedLakeBake::progress);
}
Dictionary NativeGeneratedLakeBake::progress() const {
    Dictionary out;out["status"]=state.load(std::memory_order_relaxed);out["completed"]=completed.load(std::memory_order_relaxed);out["regions"]=regions.load(std::memory_order_relaxed);return out;
}
Dictionary NativeGeneratedLakeBake::run(Object *core,const PackedByteArray &catalog,int64_t revision,int64_t epoch,int64_t timeout_ms){
    Dictionary result;result["ok"]=false;
    if(started.exchange(true)){result["reason"]="Offline lake jobs cannot be reused";return result;}
    const uint64_t began=Time::get_singleton()->get_ticks_usec();
    int64_t patches=0,slices=0,steps=0;uint64_t peak_bytes=0;
    auto failed=[&](int code,const String &reason){
        state.store(code,std::memory_order_relaxed);result["status"]=code;result["reason"]=reason;result["milliseconds"]=double(Time::get_singleton()->get_ticks_usec()-began)/1000;return result;
    };
    if(!core||core->get_class()!=StringName("TerrainCore")||revision<0||revision>0xffffffffll||epoch<0||epoch>0xffffffffll||timeout_ms<1||timeout_ms>60000||catalog.size()>1100000)return failed(-1,"Invalid offline lake job");
    auto current=[&](uint32_t command,int64_t expected){
        PackedByteArray query;query.resize(4);query.encode_u32(0,command);PackedByteArray reply=core->call("execute",query);
        return reply.size()>=16&&reply.decode_u32(0)==0x32505254&&!reply.decode_u32(8)&&reply.decode_u32(12)==uint64_t(expected);
    };
    auto interrupted=[&](){return cancelled.load(std::memory_order_relaxed)||!current(13,epoch)||!current(0,revision);};
    if(interrupted())return failed(-4,"Offline lake job cancelled or terrain changed");
    Ref<NativeLakeCatalog> codec;codec.instantiate();Dictionary decoded=codec->decode(catalog);
    if(!bool(decoded.get("ok",false)))return failed(-1,"Invalid generated lake catalog");
    Array records=decoded["records"];
    for(int i=0;i<records.size();++i){Dictionary record=records[i];PackedByteArray old=record.get("water_state",PackedByteArray());if(!old.is_empty())return failed(-1,"Offline generated lakes require new definitions");}
    Ref<NativeRegionalWater> water;water.instantiate();state.store(1,std::memory_order_relaxed);
    for(int i=0;i<records.size();++i){
        Dictionary record=records[i];Vector3 origin=record["origin"],seed=record["seed"];Vector3i cells=record["cells"];double spacing=record["spacing"],level=record["level"];
        if(!water->begin_fill(AABB(origin,Vector3(cells)*spacing),level,seed,-1))return failed(-2,"Generated lake bounds rejected");
        // The same native authoring, connectivity and contact patch functions as
        // live creation. No mesher, flow, or different volume approximation.
        while(water->fill.running||!water->requests.empty()){
            if(interrupted())return failed(-4,"Offline lake job cancelled or terrain changed");
            if(Time::get_singleton()->get_ticks_usec()-began>=uint64_t(timeout_ms)*1000)return failed(-3,"Offline lake bake exceeded its time budget");
            water->advance(2048,1.0/60.0);++steps;
            Dictionary request=water->next_request();
            if(!request.is_empty()){
                Ref<NativeWaterTerrainPatch> patch;patch.instantiate();Vector3i coordinate=request["coordinate"];
                if(!patch->configure(coordinate))return failed(-2,"Generated lake terrain request rejected");
                int status=0;
                while(status==0){
                    if(interrupted())return failed(-4,"Offline lake job cancelled or terrain changed");
                    if(Time::get_singleton()->get_ticks_usec()-began>=uint64_t(timeout_ms)*1000)return failed(-3,"Offline lake bake exceeded its time budget");
                    status=int(patch->sample_terrain(core,2048,revision,epoch));++slices;
                }
                if(status!=1||!water->accept_patch(patch))return failed(status==-4?-4:-2,"Generated lake terrain sampling rejected");
                ++patches;
            }
            // Include native region/contact storage and conservative frontier
            // node overhead. Reject this detached job before publishing anything.
            uint64_t bytes=water->regions.size()*sizeof(NativeRegionalWater::Region)+water->fill.seen.size()*64+water->fill.queue.size()*16;
            for(const auto &[key,region]:water->regions)if(region.contacts)bytes+=region.contacts->bytes;
            peak_bytes=std::max(peak_bytes,bytes);regions.store(water->regions.size(),std::memory_order_relaxed);
            if(water->limit||bytes>128*1024*1024)return failed(-5,"Generated lake bake exceeded its storage budget");
        }
        completed.store(i+1,std::memory_order_relaxed);
    }
    if(interrupted())return failed(-4,"Offline lake job cancelled or terrain changed");
    PackedByteArray snapshot=water->capture_streaming_snapshot(catalog);
    if(snapshot.is_empty()||snapshot.size()>64*1024*1024)return failed(-5,"Generated lake snapshot exceeded its budget");
    if(interrupted())return failed(-4,"Offline lake job cancelled before publication");
    result["ok"]=true;result["status"]=2;result["snapshot"]=snapshot;result["lakes"]=records.size();result["regions"]=int64_t(water->regions.size());result["water_ml"]=int64_t(water->total);result["patches"]=patches;result["slices"]=slices;result["steps"]=steps;result["peak_native_state_bytes"]=int64_t(peak_bytes);result["snapshot_bytes"]=snapshot.size();result["milliseconds"]=double(Time::get_singleton()->get_ticks_usec()-began)/1000;
    state.store(2,std::memory_order_relaxed);return result;
}
}
