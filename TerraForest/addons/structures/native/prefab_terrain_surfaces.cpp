// SPDX-License-Identifier: 0BSD
#include "block_prefab.hpp"
#include "block_shapes.hpp"
#include <algorithm>
#include <map>
#include <tuple>

namespace terraforest {
namespace {
// Same oriented convex geometry as collision/picking. These are conservative
// surface probes, not a second shape catalogue or a terrain-rendering offset.
using Hulls=std::vector<std::vector<ShapePlane>>;
Hulls hulls(int word) {
    Hulls result;
    visit_shape_hulls(block_shape(word),[&](){result.emplace_back();},[&](Vector3 normal,double offset){
        Vector3 rotated=orient_block_vector(normal,block_rotation(word)),center(.5,.5,.5);
        result.back().push_back({rotated,offset+rotated.dot(center)-normal.dot(center)});
    },[](){});
    return result;
}
bool contains(const Hulls &shapes,Vector3 point) {
    for(const auto &shape:shapes){bool inside=true;for(const auto &plane:shape)if(plane.normal.dot(point)>plane.offset+1e-6){inside=false;break;}if(inside)return true;}
    return false;
}
const std::vector<Vector3> &surface_template(int word) {
    static thread_local std::map<int,std::vector<Vector3>> cache;
    word=block_word(block_shape(word),block_rotation(word),0);
    auto found=cache.find(word);if(found!=cache.end())return found->second;
    auto &points=cache[word];const auto shapes=hulls(word);
    // Full footprint flat slabs need nine probes. Other shapes include eighths
    // to exercise stair treads, thin trims and all supported mount orientations.
    std::vector<float> grid=block_shape(word)==1||block_shape(word)==2||block_shape(word)==8?
        std::vector<float>{.001f,.5f,.999f}:std::vector<float>{.001f,.125f,.25f,.375f,.5f,.625f,.75f,.875f,.999f};
    for(float x:grid)for(float z:grid){
        double top=-1;
        for(const auto &shape:shapes){
            double low=0,high=1;bool hit=true;
            for(const auto &plane:shape){
                double remainder=plane.offset-plane.normal.x*x-plane.normal.z*z;
                if(std::abs(plane.normal.y)<1e-8){if(remainder<-1e-7){hit=false;break;}}
                else if(plane.normal.y>0)high=std::min(high,remainder/plane.normal.y);
                else low=std::max(low,remainder/plane.normal.y);
            }
            if(hit&&high-low>1e-5)top=std::max(top,high);
        }
        if(top>=0)points.emplace_back(x,float(top),z);
    }
    return points;
}
}
void NativeBlockPrefab::cache_terrain_surfaces(int band) const {
    if(terrain_surface_revision==definition_revision&&terrain_surface_band==band)return;
    terrain_surface_revision=definition_revision;terrain_surface_band=band;
    terrain_surface_probes.clear();terrain_surface_overflow=false;
    if(band<0||band>4095){terrain_surface_overflow=true;return;}
    auto less=[](const PrefabCell &a,const PrefabCell &b){return std::tie(a.x,a.y,a.z)<std::tie(b.x,b.y,b.z);};
    std::map<int,Hulls> shape_cache;
    for(const auto &cell:cells){
        if(cell.y>band)continue;
        for(Vector3 surface:surface_template(cell.word)){
            Vector3 point=Vector3(cell.x,cell.y,cell.z)+surface;
            Vector3 above=point+Vector3(0,.001,0);
            PrefabCell key{int(std::floor(above.x)),int(std::floor(above.y)),int(std::floor(above.z)),0};
            auto other=std::lower_bound(cells.begin(),cells.end(),key,less);
            if(other!=cells.end()&&other->x==key.x&&other->y==key.y&&other->z==key.z){
                auto found=shape_cache.find(other->word);
                if(found==shape_cache.end())found=shape_cache.emplace(other->word,hulls(other->word)).first;
                if(contains(found->second,above-Vector3(key.x,key.y,key.z)))continue;
            }
            // Positive air 2 cm below the visible surface establishes separation;
            // testing half a metre above the slab cannot detect coplanar soil.
            point.y-=.02f;terrain_surface_probes.push_back(point);
            if(terrain_surface_probes.size()>1048576){terrain_surface_probes.clear();terrain_surface_overflow=true;return;}
        }
    }
}
int64_t NativeBlockPrefab::terrain_surface_sample_count(int band) const {
    cache_terrain_surfaces(band);return terrain_surface_overflow?-1:int64_t(terrain_surface_probes.size());
}
PackedVector3Array NativeBlockPrefab::terrain_surface_samples(Vector3i origin,int turns,int64_t offset,int limit,int band) const {
    PackedVector3Array result;
    if(turns<0||turns>3||offset<0||limit<1||limit>512)return result;
    for(int axis=0;axis<3;++axis)if(origin[axis]<-1044480||origin[axis]>1044480)return result;
    int64_t total=terrain_surface_sample_count(band);if(total<0||offset>=total)return result;
    int count=int(std::min(int64_t(limit),total-offset));result.resize(count);
    for(int i=0;i<count;++i){Vector3 point=terrain_surface_probes[offset+i];for(int turn=0;turn<turns;++turn)point=Vector3(1-point.z,point.y,point.x);result.set(i,Vector3(origin)+point);}
    return result;
}
Dictionary NativeBlockPrefab::terrain_surface_clearance(Vector3i origin,int turns,int band) const {
    Dictionary result;result["ok"]=false;
    for(int axis=0;axis<3;++axis)if(origin[axis]<-1044480||origin[axis]>1044480){result["reason"]="Surface clearance origin outside limits";return result;}
    if(turns<0||turns>3||terrain_surface_sample_count(band)<0){result["reason"]="Invalid or excessive surface clearance geometry";return result;}
    // Compile the lowest visible surface per cell column into horizontal runs.
    // Subtraction only: never fill an intentionally hollow/unsupported volume.
    std::map<std::pair<int,int>,float> columns;
    for(Vector3 point:terrain_surface_probes){
        for(int turn=0;turn<turns;++turn)point=Vector3(1-point.z,point.y,point.x);
        point+=Vector3(origin);auto key=std::make_pair(int(std::floor(point.z)),int(std::floor(point.x)));
        float height=point.y+.02f-.125f;auto found=columns.find(key);
        if(found==columns.end()||height<found->second)columns[key]=height;
    }
    Array segments;
    for(auto it=columns.begin();it!=columns.end();){
        int z=it->first.first,first=it->first.second,last=first;float y=it->second;++it;
        while(it!=columns.end()&&it->first.first==z&&it->first.second==last+1&&std::abs(it->second-y)<1e-5&&last-first<118){last=it->first.second;++it;}
        Vector3 start(first-.125f,y,z+.5f),finish(last+1.125f,y,z+.5f);
        if(first<7||last>1992||z<7||z>1992||y<5||y>246||segments.size()>=4096){result["reason"]="Surface clearance exceeds world or segment limits";return result;}
        Dictionary segment;segment["start"]=start;segment["finish"]=finish;segment["half_width"]=.625;
        segment["depth"]=1.;segment["clearance"]=4.;segment["shoulder"]=0.;segment["material"]=1;
        segment["rectangular"]=true;segment["cut_only"]=true;segment["phase"]="surface_clearance";
        segment["bounds"]=AABB(start-Vector3(.625,1,.625),finish-start+Vector3(1.25,5,1.25));segments.append(segment);
    }
    result["ok"]=true;result["segments"]=segments;return result;
}
}
