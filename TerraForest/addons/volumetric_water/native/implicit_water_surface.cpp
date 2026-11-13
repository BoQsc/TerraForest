// SPDX-License-Identifier: 0BSD
#include "implicit_water_surface.hpp"
#include "../../volumetric_terrain/native/density_surface.hpp"
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/classes/mesh.hpp>
#include <godot_cpp/classes/time.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <vector>
#include <map>
#include <cmath>
using namespace godot;
namespace terraforest {
void NativeImplicitWaterSurface::_bind_methods(){ClassDB::bind_method(D_METHOD("extract","samples","cells","spacing"),&NativeImplicitWaterSurface::extract);}
Dictionary NativeImplicitWaterSurface::extract(const PackedFloat32Array &samples,int64_t cells,double spacing) const {
    Dictionary result;result["ok"]=false;
    if(cells<1||cells>64||!std::isfinite(spacing)||spacing<=0||spacing>4){result["reason"]="Invalid bounded field dimensions";return result;}
    const int n=int(cells),s=n+2,v=n+1;
    if(samples.size()!=s*s*s){result["reason"]="Field requires one negative halo sample and its positive endpoint";return result;}
    for(float sample:samples)if(!std::isfinite(sample)){result["reason"]="Non-finite field";return result;}
    const uint64_t started=Time::get_singleton()->get_ticks_usec();
    struct Vertex{int cx,cy,cz;unsigned mask;Vector3 position,normal;};
    std::vector<Vertex> vertices;vertices.reserve(4096);
    std::vector<int> ids(v*v*v,-1);
    auto node=[&](int x,int y,int z){return samples[(x+1)+s*((y+1)+s*(z+1))];};
    auto index=[&](int x,int y,int z){return x+1+v*(y+1+v*(z+1));};
    constexpr size_t MAX_VERTICES=262144,MAX_TRIANGLES=524288;
    bool failed=false;
    for(int z=-1;z<n;++z)for(int y=-1;y<n;++y)for(int x=-1;x<n;++x){
        float density[8];unsigned signs=0;
        for(int i=0;i<8;++i){density[i]=node(x+(i&1),y+((i>>1)&1),z+((i>>2)&1));if(density[i]<0)signs|=1u<<i;}
        extract_density_components(density,signs,true,[&](DensitySurfaceVertex point,unsigned mask){
            if(vertices.size()>=MAX_VERTICES){failed=true;return;}
            if(ids[index(x,y,z)]<0)ids[index(x,y,z)]=int(vertices.size());
            vertices.push_back({x,y,z,mask,Vector3(x+point.position.x,y+point.position.y,z+point.position.z)*spacing,Vector3(point.normal.x,point.normal.y,point.normal.z)});
        });
        if(failed){result["reason"]="Implicit surface vertex budget exceeded";return result;}
    }
    std::map<int,int> arcs;
    std::vector<Vector3> positions,normals;positions.reserve(12288);normals.reserve(12288);
    const int component_count=int(vertices.size());
    connect_material_surface(component_count,{0,n,0,n,0,n},[&](int i){return vertices[i];},
        [&](int x,int y,int z,int ax,int ay,int az,int axis){
            if(x< -1||x>=n||y< -1||y>=n||z< -1||z>=n)return -1;
            const unsigned edge=1u<<(8+density_edge_index((ax-x)+2*(ay-y)+4*(az-z),axis));
            for(int i=ids[index(x,y,z)];i>=0&&i<component_count;++i){const auto &point=vertices[i];
                if(point.cx!=x||point.cy!=y||point.cz!=z)break;if(point.mask&edge)return i;}
            return -1;
        },[&](int,int,int,int){return true;},
        [&](int x,int y,int z,int axis,int ex,int ey,int ez,int edge_axis,int left,int right){
            unsigned arc=0;auto point=density_face_arc(x,y,z,axis,ex,ey,ez,edge_axis,node,arc);
            const int key=(index(x,y,z)*3+axis)*4+int(arc);auto found=arcs.find(key);if(found!=arcs.end())return found->second;
            if(vertices.size()>=MAX_VERTICES){failed=true;return left;}
            int id=int(vertices.size());vertices.push_back({x,y,z,0,Vector3(point.x,point.y,point.z)*spacing,(vertices[left].normal+vertices[right].normal).normalized()});arcs[key]=id;return id;
        },[&](int a,int b,int c,int d,bool reverse,const int *middle){
            if(failed)return;
            surface_split_quad(a,b,c,d,reverse,middle,[&](int i){return vertices[i].position;},
                [&](int a,int b,int c,int d){
                    if(vertices.size()>=MAX_VERTICES){failed=true;return a;}
                    const Vector3 point=(vertices[a].position+vertices[b].position+vertices[c].position+vertices[d].position)*.25f;
                    const Vector3 normal=(vertices[a].normal+vertices[b].normal+vertices[c].normal+vertices[d].normal).normalized();
                    int id=int(vertices.size());vertices.push_back({0,0,0,0,point,normal});return id;
                },[&](int a,int b,int c){
                    if(failed)return;if(positions.size()/3>=MAX_TRIANGLES){failed=true;return;}
                    const Vector3 normal=(vertices[c].position-vertices[a].position).cross(vertices[b].position-vertices[a].position).normalized();
                    if(normal.length_squared()<.5)return;
                    for(int i:{a,b,c}){positions.push_back(vertices[i].position);normals.push_back(vertices[i].normal.length_squared()>.5?vertices[i].normal:normal);}
                });
        });
    if(failed){result["reason"]="Implicit surface output budget exceeded";return result;}
    PackedVector3Array packed_positions,packed_normals;packed_positions.resize(positions.size());packed_normals.resize(normals.size());
    for(size_t i=0;i<positions.size();++i){packed_positions.set(i,positions[i]);packed_normals.set(i,normals[i]);}
    Array arrays;arrays.resize(Mesh::ARRAY_MAX);arrays[Mesh::ARRAY_VERTEX]=packed_positions;arrays[Mesh::ARRAY_NORMAL]=packed_normals;
    result["ok"]=true;result["arrays"]=arrays;result["triangles"]=int64_t(positions.size()/3);
    result["extract_us"]=int64_t(Time::get_singleton()->get_ticks_usec()-started);
    result["sample_bytes"]=samples.size()*4;result["mesh_bytes"]=int64_t(positions.size()*sizeof(Vector3)*2);
    result["extractor"]="shared terrain implicit surface";return result;
}
}
