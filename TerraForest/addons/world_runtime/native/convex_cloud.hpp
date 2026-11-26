// SPDX-License-Identifier: 0BSD
#pragma once
#include <godot_cpp/variant/packed_vector3_array.hpp>
#include <algorithm>
#include <array>
#include <cmath>
#include <vector>

namespace terraforest {
// Removing a point strictly inside a tetrahedron of retained source points
// cannot change their convex hull. The common center is a convex combination
// of retained support points. These cells need not tile or form a valid hull:
// gaps merely keep more points. No boundary approximation or vertex snapping.
struct ConvexCloudWitness {int point,a,b,c;double u,v,w;};
struct ConvexCloudResult {
    godot::PackedVector3Array points;
    std::vector<int> supports;
    std::vector<ConvexCloudWitness> witnesses;
    int cells=0;
};
namespace convex_cloud_detail {
struct D3 {
    double x=0,y=0,z=0;
    D3 operator-(D3 b) const{return {x-b.x,y-b.y,z-b.z};}
    D3 operator/(double n) const{return {x/n,y/n,z/n};}
    double dot(D3 b) const{return x*b.x+y*b.y+z*b.z;}
    D3 cross(D3 b) const{return {y*b.z-z*b.y,z*b.x-x*b.z,x*b.y-y*b.x};}
};
inline D3 wide(godot::Vector3 p){return {p.x,p.y,p.z};}
struct Cell {int a,b,c;D3 u,v,w;};
}
inline ConvexCloudResult prepare_convex_cloud(const godot::PackedVector3Array &input,bool witnesses=false){
    using namespace convex_cloud_detail;
    ConvexCloudResult result;result.points=input;
    // Paired construction on the saved-world corpus found search overhead
    // outweighed hull savings on the 256–532 point clouds. Keep their original
    // fast path; this threshold changes no geometry or simulation policy.
    const int count=input.size();if(count<1024)return result;
    const auto *points=input.ptr();
    D3 lo=wide(points[0]),hi=lo;
    for(int i=0;i<count;i++){
        if(!points[i].is_finite())return result;
        lo.x=std::min(lo.x,double(points[i].x));lo.y=std::min(lo.y,double(points[i].y));lo.z=std::min(lo.z,double(points[i].z));
        hi.x=std::max(hi.x,double(points[i].x));hi.y=std::max(hi.y,double(points[i].y));hi.z=std::max(hi.z,double(points[i].z));
    }
    const D3 extent=hi-lo;const double scale=std::max({extent.x,extent.y,extent.z});
    if(scale<1e-12)return result;
    // Sample support directions on the six faces of a cube. Neighboring
    // samples form small inscribed cells even on unfamiliar deformed poses.
    std::array<int,54> grid{};
    std::array<int,27> directional;directional.fill(-1);
    std::vector<bool> keep_support(count,false);
    for(int face=0;face<6;face++)for(int y=0;y<3;y++)for(int x=0;x<3;x++){
        int d[3]={};d[face/2]=face%2?1:-1;d[(face/2+1)%3]=x-1;d[(face/2+2)%3]=y-1;
        int key=d[0]+1+3*(d[1]+1)+9*(d[2]+1),best=directional[key];
        if(best<0){
            const D3 direction{double(d[0]),double(d[1]),double(d[2])};best=0;double support=wide(points[0]).dot(direction);
            for(int i=1;i<count;i++){double value=wide(points[i]).dot(direction);if(value>support){best=i;support=value;}}
            directional[key]=best;
        }
        grid[face*9+y*3+x]=best;
        if(!keep_support[best]){keep_support[best]=true;result.supports.push_back(best);}
    }
    if(result.supports.size()<4)return result;
    D3 center;
    for(int index:result.supports){center.x+=points[index].x;center.y+=points[index].y;center.z+=points[index].z;}
    center=center/double(result.supports.size());
    std::vector<Cell> cells;cells.reserve(48);
    auto add_cell=[&](int a,int b,int c){
        if(a==b||a==c||b==c)return;
        D3 av=(wide(points[a])-center)/scale,bv=(wide(points[b])-center)/scale,cv=(wide(points[c])-center)/scale;
        double determinant=av.dot(bv.cross(cv));
        // Normalize before inversion; reject thin/degenerate cells. An ample
        // barycentric interior margin below guards against roundoff.
        if(std::abs(determinant)<1e-8)return;
        cells.push_back({a,b,c,bv.cross(cv)/determinant,cv.cross(av)/determinant,av.cross(bv)/determinant});
    };
    for(int face=0;face<6;face++)for(int y=0;y<2;y++)for(int x=0;x<2;x++){
        int base=face*9+y*3+x;
        add_cell(grid[base],grid[base+1],grid[base+3]);
        add_cell(grid[base+1],grid[base+4],grid[base+3]);
    }
    result.cells=cells.size();if(cells.empty())return result;
    // Broad-phase the certificate search. Only cells whose bounds cover a
    // point's bin can possibly certify it. Missed/degenerate cells merely
    // retain points; the positive barycentric test remains authoritative.
    std::array<std::vector<int>,512> bins;
    auto bin=[&](D3 p){return std::array<int,3>{
        std::clamp(int((p.x-lo.x)/scale*8),0,7),std::clamp(int((p.y-lo.y)/scale*8),0,7),std::clamp(int((p.z-lo.z)/scale*8),0,7)};};
    for(int index=0;index<int(cells.size());index++){
        const auto &cell=cells[index];D3 low=center,high=center;
        for(int vertex:{cell.a,cell.b,cell.c}){
            D3 p=wide(points[vertex]);low.x=std::min(low.x,p.x);low.y=std::min(low.y,p.y);low.z=std::min(low.z,p.z);
            high.x=std::max(high.x,p.x);high.y=std::max(high.y,p.y);high.z=std::max(high.z,p.z);
        }
        auto first=bin(low),last=bin(high);
        for(int z=first[2];z<=last[2];z++)for(int y=first[1];y<=last[1];y++)for(int x=first[0];x<=last[0];x++)bins[x+8*y+64*z].push_back(index);
    }
    godot::PackedVector3Array reduced;reduced.resize(count);auto *out=reduced.ptrw();int retained=0;
    for(int i=0;i<count;i++){
        bool inside=false;
        if(!keep_support[i]){
            D3 point=(wide(points[i])-center)/scale;
            auto location=bin(wide(points[i]));
            for(int cell_index:bins[location[0]+8*location[1]+64*location[2]]){
                const auto &cell=cells[cell_index];
                double u=cell.u.dot(point);if(u<=1e-5||u>=1-1e-5)continue;
                double v=cell.v.dot(point);if(v<=1e-5||u+v>=1-1e-5)continue;
                double w=cell.w.dot(point);
                if(w>1e-5&&u+v+w<1-1e-5){
                    inside=true;
                    if(witnesses)result.witnesses.push_back({i,cell.a,cell.b,cell.c,u,v,w});
                    break;
                }
            }
        }
        if(!inside)out[retained++]=points[i];
    }
    reduced.resize(retained);result.points=reduced;return result;
}
}
