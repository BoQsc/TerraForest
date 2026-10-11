// SPDX-License-Identifier: 0BSD
#include "water_regions.hpp"
#include "water_geometry.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/classes/time.hpp>
#include <algorithm>
using namespace godot;
namespace terraforest {
NativeWaterRegions::RegionKey NativeWaterRegions::key(const Vector3i &v){return {v.x,v.y,v.z};}
NativeWaterRegions::PortKey NativeWaterRegions::port_key(const int32_t *row,int &side){
    const std::array<int32_t,4> a={row[0],row[1],row[2],row[3]},b={row[4],row[5],row[6],row[7]};
    side=a<b?0:1;PortKey result;for(int i=0;i<4;++i){result[i]=side?b[i]:a[i];result[i+4]=side?a[i]:b[i];}return result;
}
void NativeWaterRegions::_bind_methods(){
    ClassDB::bind_method(D_METHOD("configure","world_id","spacing"),&NativeWaterRegions::configure);
    ClassDB::bind_method(D_METHOD("reserve_region","coordinate","revision","epoch","expected_generation"),&NativeWaterRegions::reserve_region);
    ClassDB::bind_method(D_METHOD("begin_publish","graph","generation"),&NativeWaterRegions::begin_publish);
    ClassDB::bind_method(D_METHOD("begin_release","coordinate","generation"),&NativeWaterRegions::begin_release);
    ClassDB::bind_method(D_METHOD("advance","work_budget"),&NativeWaterRegions::advance);
    ClassDB::bind_method(D_METHOD("inspect_port","coordinate","generation","port_index"),&NativeWaterRegions::inspect_port);
    ClassDB::bind_method(D_METHOD("statistics"),&NativeWaterRegions::statistics);
}
bool NativeWaterRegions::configure(int64_t id,int64_t scale){if(world||id<1||scale<1||scale>8)return false;world=id;spacing=scale;return true;}
void NativeWaterRegions::unready(Region &region){if(region.ready){region.ready=false;--ready_count;}}
Dictionary NativeWaterRegions::reserve_region(const Vector3i &coordinate,int64_t rev,int64_t epoch,int64_t expected){
    Dictionary out;out["ok"]=false;
    if(!world||rev<0||epoch<0||expected<0||next_generation>9007199254740991LL)return out;
    for(int a=0;a<3;++a)if(coordinate[a]<-6250||coordinate[a]>6249)return out;
    const auto k=key(coordinate);auto it=regions.find(k);
    if(it==regions.end()){if(expected||regions.size()>=64)return out;it=regions.emplace(k,Region{}).first;}
    else if(it->second.generation!=expected||rev<it->second.revision||epoch<it->second.epoch||(mode==2&&active==k))return out;
    if(mode==1&&active==k){mode=0;incoming.unref();}
    auto &r=it->second;unready(r);r.generation=next_generation++;r.revision=rev;r.epoch=epoch;
    out["ok"]=true;out["generation"]=r.generation;return out;
}
bool NativeWaterRegions::begin_publish(const Ref<NativeWaterTopology> &graph,int64_t generation){
    if(mode||!world||graph.is_null()||graph->status!=1||graph->field.is_null()||graph->extent!=Vector3i(16,16,16))return false;
    const auto &field=*graph->field.ptr();const auto origin=field.origin+graph->first;
    if(field.world!=world||field.spacing!=spacing||origin.x%16||origin.y%16||origin.z%16)return false;
    const auto k=key(origin/16);auto it=regions.find(k);if(it==regions.end())return false;
    auto &r=it->second;
    if(r.ready||r.generation!=generation||r.revision!=field.revision||r.epoch!=field.epoch||endpoint_count-int(r.keys.size())+int(graph->portals)>65536)return false;
    r.keys.reserve(graph->portals);incoming=graph;active=k;port_cursor=0;mode=1;return true;
}
bool NativeWaterRegions::begin_release(const Vector3i &coordinate,int64_t generation){
    const auto k=key(coordinate);auto it=regions.find(k);
    if(it==regions.end()||it->second.generation!=generation||(mode&&active!=k))return false;
    unready(it->second);incoming.unref();active=k;mode=2;return true;
}
void NativeWaterRegions::retire_one(Region &region){
    const auto k=region.keys.back();region.keys.pop_back();auto it=ports.find(k);
    if(it==ports.end())return;
    for(auto &e:it->second)if(e.generation&&e.region==active){e.generation=0;--endpoint_count;}
    if(!it->second[0].generation&&!it->second[1].generation)ports.erase(it);
}
bool NativeWaterRegions::publish_one(Region &region){
    const auto &g=*incoming.ptr();const auto &f=*g.field.ptr();const int32_t *row=g.world_ports.ptr()+port_cursor*9;
    int side=0;const auto k=port_key(row,side);
    Endpoint e;e.region=active;e.generation=region.generation;e.ceiling=f.ceiling;e.height=row[8];
    const Vector3i local=Vector3i(row[0],row[1],row[2])-f.origin,delta(row[4]-row[0],row[5]-row[1],row[6]-row[2]);
    int face=-1;for(int a=0;a<4;++a){const auto link=lake_links()[row[3]][a];if(Vector3i(link.x,link.y,link.z)==delta&&link.t==row[7])face=a;}
    if(face<0)return false;
    std::array<std::pair<RegionKey,float>,3> samples;int n=0;const auto view=g.view();
    for(int a=0;a<4;++a)if(a!=face){const auto corner=lake_corner(lake_tets[row[3]][a]),p=local+corner;samples[n++]={key(p+f.origin),view.density[view.node(p.x,p.y,p.z)]};}
    std::sort(samples.begin(),samples.end(),[](const auto &a,const auto &b){return a.first<b.first;});
    for(int a=0;a<3;++a)e.density[a]=samples[a].second;
    auto &pair=ports[k];if(pair[side].generation)return false;
    pair[side]=e;region.keys.push_back(k);++endpoint_count;++port_cursor;return true;
}
Dictionary NativeWaterRegions::advance(int64_t budget){
    int64_t work=0;bool ok=true;
    if(budget<1||budget>2048){Dictionary out=statistics();out["ok"]=false;out["work_units"]=work;return out;}
    const uint64_t begun=Time::get_singleton()->get_ticks_usec();
    while(mode&&work<budget){
        ++work;++work_total;auto it=regions.find(active);auto &r=it->second;
        // Retirement precedes insertion, keeping endpoint memory within its cap.
        if(mode==2){
            if(!r.keys.empty())retire_one(r);
            else if(mode==2){regions.erase(it);mode=0;}
        }else if(port_cursor==0&&!r.keys.empty()){
            retire_one(r);
        }else if(port_cursor<int(incoming->portals)){
            if(!publish_one(r)){ok=false;incoming.unref();mode=0;}
        }else{
            r.graph=incoming;r.ready=true;++ready_count;incoming.unref();mode=0;
        }
        if(work%32==0&&Time::get_singleton()->get_ticks_usec()-begun>=2000)break;
    }
    Dictionary out=statistics();out["ok"]=ok;out["work_units"]=work;return out;
}
Dictionary NativeWaterRegions::inspect_port(const Vector3i &coordinate,int64_t generation,int64_t index) const {
    Dictionary out;out["ok"]=false;out["connected"]=false;out["reason"]="region_not_ready";
    const auto k=key(coordinate);auto it=regions.find(k);
    if(it==regions.end()||!it->second.ready)return out;
    const auto &r=it->second;if(r.generation!=generation){out["reason"]="stale_generation";return out;}
    if(index<0||index>=int64_t(r.keys.size())){out["reason"]="invalid_port";return out;}
    out["ok"]=true;const auto &pair=ports.at(r.keys[index]);
    const int side=pair[0].region==k&&pair[0].generation==generation?0:1;
    const Endpoint &own=pair[side],&other=pair[1-side];
    out["opening_mm"]=own.height;
    if(!other.generation){
        RegionKey expected;const auto &address=r.keys[index];
        for(int a=0;a<3;++a){const int cell=address[(1-side)*4+a];expected[a]=cell>=0?cell/16:-int((-(int64_t)cell+15)/16);}
        const auto peer=regions.find(expected);
        out["reason"]=peer==regions.end()?"missing_neighbour":peer->second.ready?"unmatched_face":"stale_neighbour";return out;
    }
    const auto peer=regions.find(other.region);
    if(peer==regions.end()||!peer->second.ready||peer->second.generation!=other.generation){out["reason"]="stale_neighbour";return out;}
    if(own.ceiling!=other.ceiling){out["reason"]="ceiling_mismatch";return out;}
    if(own.height!=other.height||own.density!=other.density){out["reason"]="geometry_mismatch";return out;}
    out["connected"]=true;out["reason"]="ready";out["neighbour"]=Vector3i(other.region[0],other.region[1],other.region[2]);out["neighbour_generation"]=other.generation;return out;
}
Dictionary NativeWaterRegions::statistics() const {
    Dictionary out;out["world_id"]=world;out["regions"]=int64_t(regions.size());out["ready_regions"]=ready_count;out["endpoints"]=endpoint_count;
    out["port_keys"]=int64_t(ports.size());out["busy"]=mode!=0;out["work_total"]=work_total;out["next_generation"]=next_generation;return out;
}
}
