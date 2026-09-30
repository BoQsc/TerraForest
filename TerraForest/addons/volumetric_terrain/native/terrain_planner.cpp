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
void collect(Vector3i key,Vector3 focus,bool collision,State &state,Dictionary &split,Dictionary &wanted,std::vector<Request> &requests) {
    if(key.x>=2000||key.y>=2000)return;
    wanted[key]=true;int index=index_for(key);auto flag=state.flags[index];
    double d=distance(key,focus,collision);bool divide=false;
    if(key.z>16) {
        double radius=key.z==32?48:(key.z==64?100:key.z*1.4);
        divide=d<radius*((flag&SPLIT)?1.30:1.0);split[key]=divide;
    }
    if(!(flag&PRESENT)||(flag&RETAINED_COARSE)||((flag&DIRTY)&&(!divide||(flag&VISIBLE)))) {
        double priority=d+(key.z==256?0:(key.z<=32?20:200));
        if(key.z<=32&&d<25)priority-=5000;
        requests.push_back({key,priority});
    }
    if(divide)for(auto child:children(key))collect(child,focus,collision,state,split,wanted,requests);
}
bool cover(Vector3i key,const State &state,std::vector<Vector3i> &out) {
    if(key.x>=2000||key.y>=2000)return true;
    auto flag=state.flags[index_for(key)];size_t start=out.size();
    bool attempted=(flag&SPLIT)&&key.z>16;
    if(attempted) {
        bool complete=true;
        for(auto child:children(key))if(!cover(child,state,out)){complete=false;break;}
        if(complete)return true;
        out.resize(start);
    }
    // Keep dirty live collision/visuals until their edit transaction publishes;
    // never resurrect a dirty hidden parent while its replacement is pending.
    if((flag&PRESENT)&&(!(flag&DIRTY)||(flag&VISIBLE))) {out.push_back(key);return true;}
    if(!attempted&&key.z>16) {
        for(auto child:children(key))if(!cover(child,state,out)){out.resize(start);return false;}
        return true;
    }
    return false;
}
}
void NativeTerrainPlanner::_bind_methods() {
    ClassDB::bind_method(D_METHOD("requests","focus","require_collision","tiles","split_state","visible_cut"),&NativeTerrainPlanner::requests);
    ClassDB::bind_method(D_METHOD("coverage","tiles","split_state","visible_cut"),&NativeTerrainPlanner::coverage);
    ClassDB::bind_method(D_METHOD("eviction_candidates","tiles","visible_cut","requested_keys"),&NativeTerrainPlanner::eviction_candidates);
}
Dictionary NativeTerrainPlanner::requests(Vector3 focus,bool collision,const Dictionary &tiles,const Dictionary &previous,const Array &visible) const {
    State state;if(!focus.is_finite()||!state.load(tiles,previous,visible))return failure();
    Dictionary split=previous.duplicate(),wanted;
    std::vector<Request> pending;pending.reserve(512);
    for(int z=0;z<2048;z+=256)for(int x=0;x<2048;x+=256)collect(Vector3i(x,z,256),focus,collision,state,split,wanted,pending);
    std::stable_sort(pending.begin(),pending.end(),[](const Request &a,const Request &b){return a.priority<b.priority;});
    TypedArray<Vector3i> keys;keys.resize(pending.size());
    for(size_t i=0;i<pending.size();i++)keys[i]=pending[i].key;
    Dictionary result;result["ok"]=true;result["requests"]=keys;result["requested_keys"]=wanted;result["split_state"]=split;return result;
}
Dictionary NativeTerrainPlanner::coverage(const Dictionary &tiles,const Dictionary &split,const Array &visible) const {
    State state;if(!state.load(tiles,split,visible))return failure();
    std::vector<Vector3i> covered;covered.reserve(512);int roots=0;Dictionary covered_roots;
    for(int z=0;z<2048;z+=256)for(int x=0;x<2048;x+=256) {
        Vector3i root(x,z,256);
        if(cover(root,state,covered)) {++roots;covered_roots[root]=true;}
    }
    TypedArray<Vector3i> keys,hidden;keys.resize(covered.size());
    for(size_t i=0;i<covered.size();i++) {keys[i]=covered[i];state.flags[index_for(covered[i])]|=CHOSEN;}
    for(int i=0;i<visible.size();i++)if(!(state.flags[index_for(visible[i])]&CHOSEN))hidden.push_back(visible[i]);
    Dictionary result;result["ok"]=true;result["keys"]=keys;result["hidden"]=hidden;result["root_coverage"]=roots;result["covered_roots"]=covered_roots;return result;
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
