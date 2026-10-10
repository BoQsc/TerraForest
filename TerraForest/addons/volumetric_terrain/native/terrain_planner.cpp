#include "terrain_planner.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/typed_array.hpp>
#include <godot_cpp/variant/vector3i.hpp>
#include <array>
#include <vector>
#include <algorithm>
#include <cmath>

namespace terraforest {
using namespace godot;
namespace {
constexpr int COUNT=21824;
enum Flag { PRESENT=1,DIRTY=2,VISIBLE=4,SPLIT=8,CHOSEN=16,RETAINED_COARSE=32 };
int index_for(Vector3i key) {
    if(key.x<0||key.y<0||key.x>=2048||key.y>=2048)return -1;
    int offset=0;
    for(int size=16;size<=256;size*=2) {
        int width=2048/size;
        if(key.z==size)return key.x%size||key.y%size?-1:offset+(key.y/size)*width+key.x/size;
        offset+=width*width;
    }
    return -1;
}
Dictionary failure() {Dictionary out;out["ok"]=false;return out;}
struct State {
    std::array<uint8_t,COUNT> flags{};
    Array tile_keys;
    bool load(const Dictionary &tiles,const Dictionary &split,const Array &visible) {
        if(tiles.size()>COUNT||split.size()>COUNT||visible.size()>COUNT)return false;
        tile_keys=tiles.keys();
        for(int i=0;i<tile_keys.size();i++) {
            Variant key=tile_keys[i],value=tiles[key];
            if(key.get_type()!=Variant::VECTOR3I||value.get_type()!=Variant::DICTIONARY)return false;
            int index=index_for(key);if(index<0)return false;
            Dictionary tile=value;Variant dirty=tile.get("dirty",false);
            if(dirty.get_type()!=Variant::BOOL)return false;
            flags[index]|=PRESENT|(bool(dirty)?DIRTY:0);
            Vector3i tile_key=key;Variant step=tile.get("step",std::max(1,tile_key.z/32));
            if(step.get_type()!=Variant::INT||int64_t(step)<1||int64_t(step)>8)return false;
            if(int64_t(step)>std::max(1,tile_key.z/32))flags[index]|=RETAINED_COARSE;
        }
        Array split_keys=split.keys();
        for(int i=0;i<split_keys.size();i++) {
            Variant key=split_keys[i],value=split[key];
            if(key.get_type()!=Variant::VECTOR3I||value.get_type()!=Variant::BOOL)return false;
            int index=index_for(key);if(index<0)return false;
            if(bool(value))flags[index]|=SPLIT;
        }
        for(int i=0;i<visible.size();i++) {
            Variant key=visible[i];if(key.get_type()!=Variant::VECTOR3I)return false;
            int index=index_for(key);if(index<0)return false;flags[index]|=VISIBLE;
        }
        return true;
    }
};
std::array<Vector3i,4> children(Vector3i key) {
    int half=key.z/2;
    return {Vector3i(key.x,key.y,half),Vector3i(key.x+half,key.y,half),
            Vector3i(key.x,key.y+half,half),Vector3i(key.x+half,key.y+half,half)};
}
double distance(Vector3i key,Vector3 focus,bool collision) {
    double dx=std::max({double(key.x)-focus.x,double(focus.x)-(key.x+key.z),0.0});
    double dz=std::max({double(key.y)-focus.z,double(focus.z)-(key.y+key.z),0.0});
    double dy=collision?0:std::max(0.0,double(focus.y)-256);
    return std::sqrt(dx*dx+dz*dz+dy*dy);
}
struct Request {Vector3i key;double priority;};
void collect(Vector3i key,Vector3 focus,bool collision,State &state,Dictionary &split,Dictionary &wanted,std::vector<Request> &requests,const Vector3 *target=nullptr,const std::vector<Vector3> *travel=nullptr) {
    if(key.x>=2000||key.y>=2000)return;
    wanted[key]=true;int index=index_for(key);auto flag=state.flags[index];
    double d=distance(key,focus,collision);bool divide=false;
    if(target)d=std::min(d,distance(key,*target,true));
    if(travel)for(const auto &point:*travel)d=std::min(d,distance(key,point,collision));
    if(key.z>16) {
        double radius=key.z==32?48:(key.z==64?100:key.z*1.4);
        divide=d<radius*((flag&SPLIT)?1.30:1.0);split[key]=divide;
        state.flags[index]=(state.flags[index]&~SPLIT)|(divide?SPLIT:0);
    }
    if(!(flag&PRESENT)||(flag&RETAINED_COARSE)||((flag&DIRTY)&&(!divide||(flag&VISIBLE)))) {
        double priority=d+(key.z==256?0:(key.z<=32?20:200));
        if(key.z<=32&&d<25)priority-=5000;
        requests.push_back({key,priority});
    }
    if(divide)for(auto child:children(key))collect(child,focus,collision,state,split,wanted,requests,target,travel);
}
bool visible_descendant(Vector3i key,const State &state) {
    if(key.z<=16)return false;
    for(auto child:children(key))
        if((state.flags[index_for(child)]&VISIBLE)||visible_descendant(child,state))return true;
    return false;
}
bool cover(Vector3i key,const State &state,std::vector<Vector3i> &out,bool available=false) {
    if(key.x>=2000||key.y>=2000)return true;
    auto flag=state.flags[index_for(key)];size_t start=out.size();
    bool attempted=(flag&SPLIT)&&key.z>16;
    if(attempted) {
        bool complete=true;
        for(auto child:children(key))if(!cover(child,state,out,available)){complete=false;if(!available)break;}
        if(complete)return true;
        if(!available)out.resize(start);
        // A late coarse arrival must not downgrade an already published fine
        // cut while refinement is still requested. Keep its disjoint partial
        // descendants until complete replacement coverage exists.
        else if(!(flag&VISIBLE)&&visible_descendant(key,state))return false;
    }
    // Keep dirty live collision/visuals until their edit transaction publishes;
    // never resurrect a dirty hidden parent while its replacement is pending.
    if((flag&PRESENT)&&(!(flag&DIRTY)||(flag&VISIBLE))) {out.resize(start);out.push_back(key);return true;}
    if(!attempted&&key.z>16) {
        bool complete=true;
        for(auto child:children(key))if(!cover(child,state,out,available)) {
            complete=false;
            if(!available){out.resize(start);return false;}
        }
        return complete;
    }
    return false;
}
void prioritize_coverage(Vector3 focus,bool collision,const State &state,const Dictionary &wanted,std::vector<Request> &pending,double bias=0) {
    // Finish one nearby activation path before accumulating more hidden detail.
    // Sibling coverage at every ancestor is required by cover(); the old
    // distance-only order deferred those 64/128m bridges behind distant detail.
    if(focus.x<=-25||focus.z<=-25||focus.x>=2025||focus.z>=2025)return;
    Vector3i target(-1,-1,16);
    double best=1e30;
    int x0=std::max(0,int(std::floor((focus.x-25)/16))*16);
    int z0=std::max(0,int(std::floor((focus.z-25)/16))*16);
    int x1=std::min(1999,int(std::floor((focus.x+25)/16))*16);
    int z1=std::min(1999,int(std::floor((focus.z+25)/16))*16);
    for(int z=z0;z<=z1;z+=16)for(int x=x0;x<=x1;x+=16) {
        Vector3i key(x,z,16);
        if(!wanted.has(key)||(state.flags[index_for(key)]&VISIBLE)||distance(key,focus,collision)>=25)continue;
        double dx=x+8-focus.x,dz=z+8-focus.z;
        double rank=dx*dx+dz*dz;
        if(focus.x>=x&&focus.x<x+16&&focus.z>=z&&focus.z<z+16)rank=-1;
        if(rank<best){best=rank;target=key;}
    }
    if(target.x<0)return;
    for(auto &request:pending)if(request.key==target)request.priority=std::min(request.priority,-12000+bias);
    std::vector<Vector3i> covered;
    for(Vector3i child=target;child.z<256;) {
        int size=child.z*2;
        Vector3i parent(child.x/size*size,child.y/size*size,size);
        for(auto sibling:children(parent)) {
            if(sibling==child)continue;
            covered.clear();
            if(cover(sibling,state,covered))continue;
            // Preserve the request set. A dirty hidden sibling may need its
            // descendants instead of a parent rebuild; prioritize those too.
            for(auto &request:pending) {
                auto key=request.key;
                if(key.z<=sibling.z&&key.x>=sibling.x&&key.y>=sibling.y&&
                   key.x+key.z<=sibling.x+sibling.z&&key.y+key.z<=sibling.y+sibling.z)
                    request.priority=std::min(request.priority,-11000-key.z+distance(key,focus,collision)*0.01+bias);
            }
        }
        child=parent;
    }
}
}
void NativeTerrainPlanner::_bind_methods() {
    ClassDB::bind_method(D_METHOD("requests_travel","focus","require_collision","velocity","tiles","split_state","visible_cut"),&NativeTerrainPlanner::requests_travel);
    ClassDB::bind_method(D_METHOD("collision_region_ready","bounds","active_leaves"),&NativeTerrainPlanner::collision_region_ready);
    ClassDB::bind_method(D_METHOD("requests","focus","require_collision","tiles","split_state","visible_cut"),&NativeTerrainPlanner::requests);
    ClassDB::bind_method(D_METHOD("requests_targeted","focus","require_collision","target","tiles","split_state","visible_cut"),&NativeTerrainPlanner::requests_targeted);
    ClassDB::bind_method(D_METHOD("coverage","tiles","split_state","visible_cut"),&NativeTerrainPlanner::coverage);
    ClassDB::bind_method(D_METHOD("coverage_available","tiles","split_state","visible_cut"),&NativeTerrainPlanner::coverage_available);
    ClassDB::bind_method(D_METHOD("eviction_candidates","tiles","visible_cut","requested_keys"),&NativeTerrainPlanner::eviction_candidates);
}
bool NativeTerrainPlanner::collision_region_ready(AABB bounds,const Dictionary &active_leaves) const {
    Vector3 start=bounds.position,end=bounds.position+bounds.size;
    if(!start.is_finite()||!bounds.size.is_finite()||!end.is_finite()||bounds.size.x<0||bounds.size.y<0||bounds.size.z<0)return false;
    // Terrain columns span the vertical domain. Include the far boundary cell:
    // a body touching a streaming seam must not rely on its center cell alone.
    if(start.x<0||start.z<0||end.x>=2000||end.z>=2000)return false;
    int x0=int(std::floor(start.x/16)),z0=int(std::floor(start.z/16));
    int x1=int(std::floor(end.x/16)),z1=int(std::floor(end.z/16));
    for(int z=z0;z<=z1;++z)for(int x=x0;x<=x1;++x){
        Variant ready=active_leaves.get(Vector2i(x,z),false);
        if(ready.get_type()!=Variant::BOOL||!bool(ready))return false;
    }
    return true;
}
static Dictionary plan_requests(Vector3 focus,bool collision,const Dictionary &tiles,const Dictionary &previous,const Array &visible,const Vector3 *target,const std::vector<Vector3> *travel=nullptr) {
    State state;if(!focus.is_finite()||(target&&!target->is_finite())||!state.load(tiles,previous,visible))return failure();
    Dictionary split=previous.duplicate(),wanted;
    std::vector<Request> pending;pending.reserve(512);
    for(int z=0;z<2048;z+=256)for(int x=0;x<2048;x+=256)collect(Vector3i(x,z,256),focus,collision,state,split,wanted,pending,target,travel);
    prioritize_coverage(target?*target:focus,target?true:collision,state,wanted,pending);
    // Ahead detail is unusable until its sibling coverage can replace the
    // visible ancestor. Finish those dependencies before accumulating more
    // hidden fine meshes, with current-position activation always first.
    if(travel)for(size_t i=0;i<travel->size();++i)
        prioritize_coverage((*travel)[i],collision,state,wanted,pending,2000.0+100.0*i);
    std::stable_sort(pending.begin(),pending.end(),[](const Request &a,const Request &b){return a.priority<b.priority;});
    TypedArray<Vector3i> keys;keys.resize(pending.size());Dictionary activation;
    for(size_t i=0;i<pending.size();i++) {
        keys[i]=pending[i].key;
        if(pending[i].priority<-10000)activation[pending[i].key]=true;
    }
    Dictionary result;result["ok"]=true;result["requests"]=keys;result["requested_keys"]=wanted;result["split_state"]=split;result["activation_keys"]=activation;return result;
}
Dictionary NativeTerrainPlanner::requests(Vector3 focus,bool collision,const Dictionary &tiles,const Dictionary &previous,const Array &visible) const {
    return plan_requests(focus,collision,tiles,previous,visible,nullptr);
}
Dictionary NativeTerrainPlanner::requests_travel(Vector3 focus,bool collision,Vector3 velocity,const Dictionary &tiles,const Dictionary &previous,const Array &visible) const {
    if(!velocity.is_finite())return failure();
    // Two seconds of travel, capped at 128 m. Samples at <=32 m retain a
    // continuous refinement corridor while bounding additional planning work.
    velocity.y=0;
    double speed=velocity.length();
    if(!std::isfinite(speed))return failure();
    double length=std::min(speed*2,128.0);
    std::vector<Vector3> samples;
    if(length>0){
        int count=int(std::ceil(length/32));samples.reserve(count);
        Vector3 direction=velocity/real_t(speed);
        for(int i=1;i<=count;++i)samples.push_back(focus+direction*real_t(length*i/count));
    }
    return plan_requests(focus,collision,tiles,previous,visible,nullptr,&samples);
}
Dictionary NativeTerrainPlanner::requests_targeted(Vector3 focus,bool collision,Vector3 target,const Dictionary &tiles,const Dictionary &previous,const Array &visible) const {
    return plan_requests(focus,collision,tiles,previous,visible,&target);
}
static Dictionary plan_coverage(const Dictionary &tiles,const Dictionary &split,const Array &visible,bool available) {
    State state;if(!state.load(tiles,split,visible))return failure();
    std::vector<Vector3i> covered;covered.reserve(512);int roots=0;Dictionary covered_roots;
    for(int z=0;z<2048;z+=256)for(int x=0;x<2048;x+=256) {
        Vector3i root(x,z,256);
        // An absent root is already a coverage hole. Publish valid disjoint
        // descendants there without waiting for siblings across 256 metres.
        // A usable parent remains the fallback until its full replacement is
        // ready: never turn previously covered space into a new hole.
        if(cover(root,state,covered,available)) {++roots;covered_roots[root]=true;}
    }
    TypedArray<Vector3i> keys,hidden;keys.resize(covered.size());
    for(size_t i=0;i<covered.size();i++) {keys[i]=covered[i];state.flags[index_for(covered[i])]|=CHOSEN;}
    for(int i=0;i<visible.size();i++)if(!(state.flags[index_for(visible[i])]&CHOSEN))hidden.push_back(visible[i]);
    Dictionary result;result["ok"]=true;result["keys"]=keys;result["hidden"]=hidden;result["root_coverage"]=roots;result["covered_roots"]=covered_roots;return result;
}
Dictionary NativeTerrainPlanner::coverage(const Dictionary &tiles,const Dictionary &split,const Array &visible) const {
    return plan_coverage(tiles,split,visible,false);
}
Dictionary NativeTerrainPlanner::coverage_available(const Dictionary &tiles,const Dictionary &split,const Array &visible) const {
    return plan_coverage(tiles,split,visible,true);
}
Dictionary NativeTerrainPlanner::eviction_candidates(const Dictionary &tiles,const Array &visible,const Dictionary &requested) const {
    State state;if(!state.load(tiles,requested,visible))return failure();
    struct Victim {int64_t used;Vector3i key;};std::vector<Victim> victims;
    for(int i=0;i<tiles.size();i++) {
        Vector3i key=state.tile_keys[i];auto flag=state.flags[index_for(key)];
        if(key.z==256||(flag&VISIBLE)||requested.has(key))continue;
        Dictionary tile=tiles[key];Variant used=tile.get("used",0);
        if(used.get_type()!=Variant::INT)return failure();
        victims.push_back({int64_t(used),key});
    }
    std::stable_sort(victims.begin(),victims.end(),[](const Victim &a,const Victim &b){return a.used<b.used;});
    TypedArray<Vector3i> keys;keys.resize(victims.size());for(size_t i=0;i<victims.size();i++)keys[i]=victims[i].key;
    Dictionary result;result["ok"]=true;result["keys"]=keys;return result;
}
}
